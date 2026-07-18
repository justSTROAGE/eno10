import os
import sqlite3
import threading
from datetime import datetime, timezone

_local = threading.local()
_db_path = os.environ.get("PAY_DB_PATH", "./payments.db")


def conn() -> sqlite3.Connection:
    if not hasattr(_local, "c"):
        c = sqlite3.connect(_db_path, isolation_level=None, check_same_thread=False)
        c.execute("PRAGMA journal_mode=WAL")
        c.execute("PRAGMA foreign_keys=ON")
        _local.c = c
    return _local.c


def init() -> None:
    c = conn()
    c.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            handle        TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL,
            balance_cents INTEGER NOT NULL DEFAULT 0,
            created_at    TEXT NOT NULL
        )
    """)
    c.execute("""
        CREATE TABLE IF NOT EXISTS sessions (
            token      TEXT PRIMARY KEY,
            user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            expires_at TEXT NOT NULL,
            created_at TEXT NOT NULL
        )
    """)


def create_user(handle: str, password_hash: str) -> int:
    cur = conn().execute(
        "INSERT INTO users(handle, password_hash, balance_cents, created_at) VALUES (?, ?, 0, ?)",
        (handle, password_hash, datetime.now(timezone.utc).isoformat()),
    )
    return int(cur.lastrowid)


def credit_balance(handle: str, amount: int):
    """Adds `amount` cents to the given handle's wallet. Returns the new balance, or None if unknown handle."""
    c = conn()
    c.execute("BEGIN IMMEDIATE")
    try:
        row = c.execute("SELECT id, balance_cents FROM users WHERE handle = ?", (handle,)).fetchone()
        if not row:
            c.execute("ROLLBACK")
            return None
        user_id, current = row
        new = current + amount
        c.execute("UPDATE users SET balance_cents = ? WHERE id = ?", (new, user_id))
        c.execute("COMMIT")
        return new
    except Exception:
        c.execute("ROLLBACK")
        raise


def find_user_by_handle(handle: str):
    row = conn().execute(
        "SELECT id, handle, password_hash, balance_cents FROM users WHERE handle = ?",
        (handle,),
    ).fetchone()
    return row 


def find_user_by_id(user_id: int):
    row = conn().execute(
        "SELECT id, handle, password_hash, balance_cents FROM users WHERE id = ?",
        (user_id,),
    ).fetchone()
    return row


def create_session(token: str, user_id: int, expires_at_iso: str, created_at_iso: str) -> None:
    conn().execute(
        "INSERT INTO sessions(token, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)",
        (token, user_id, expires_at_iso, created_at_iso),
    )


def lookup_session(token: str):
    row = conn().execute(
        """
        SELECT s.user_id, u.handle FROM sessions s
        JOIN users u ON u.id = s.user_id
        WHERE s.token = ? AND s.expires_at > ?
        """,
        (token, datetime.now(timezone.utc).isoformat()),
    ).fetchone()
    return row


def delete_session(token: str) -> None:
    conn().execute("DELETE FROM sessions WHERE token = ?", (token,))


def debit_balance(user_id: int, amount: int):
    """Returns new balance on success, or None on insufficient funds / missing user."""
    c = conn()
    c.execute("BEGIN IMMEDIATE")
    try:
        row = c.execute("SELECT balance_cents FROM users WHERE id = ?", (user_id,)).fetchone()
        if not row:
            c.execute("ROLLBACK")
            return None
        current = row[0]
        if current < amount:
            c.execute("ROLLBACK")
            return None
        new = current - amount
        c.execute("UPDATE users SET balance_cents = ? WHERE id = ?", (new, user_id))
        c.execute("COMMIT")
        return new
    except Exception:
        c.execute("ROLLBACK")
        raise
