import asyncio
import sqlite3
from contextlib import asynccontextmanager, contextmanager
import re
import secrets

import aiosqlite
from fastapi import Request

from d3pl0y_frontend import config


async def sqlite_connection() -> aiosqlite.Connection:
    """A factory for creating new connections."""
    conn = await aiosqlite.connect(config.DB_PATH)
    await conn.execute("PRAGMA journal_mode = WAL")
    await conn.execute("PRAGMA busy_timeout = 5000")
    await conn.execute("PRAGMA synchronous = NORMAL")
    await conn.execute("PRAGMA cache_size = 100000000")
    await conn.execute("PRAGMA temp_store = MEMORY")
    await conn.execute("PRAGMA foreign_keys = ON")
    conn.row_factory = aiosqlite.Row
    return conn


@asynccontextmanager
async def get_db_writer(request: Request) -> aiosqlite.Connection:
    """helper to get a connection from the writer pool"""
    db_pool = request.state.db_writer_pool
    async with db_pool.connection() as conn:
        yield conn


@asynccontextmanager
async def get_db_reader(request: Request) -> aiosqlite.Connection:
    """helper to get a connection from the reader pool"""
    db_pool = request.state.db_reader_pool
    async with db_pool.connection() as conn:
        yield conn


async def get_permission(request, requester, owner, objectname, permission):
    async with get_db_reader(request) as conn:
        async with conn.execute("""
            WITH matched AS (
                SELECT effect, length(prefix) AS plen
                FROM shares
                WHERE (receiver = :requester OR receiver = '*public')
                  AND owner = :owner
                  AND permission = :permission
                  AND scope = 'exact'
                  AND prefix = :objectname

                UNION ALL

                SELECT effect, length(prefix) AS plen
                FROM shares
                WHERE (receiver = :requester OR receiver = '*public')
                  AND owner = :owner
                  AND permission = :permission
                  AND scope = 'prefix'
                  AND :objectname GLOB prefix || '*'
            )
            SELECT effect
            FROM matched
            ORDER BY plen DESC,
                     CASE effect WHEN 'deny' THEN 0 ELSE 1 END
            LIMIT 1;
            """,
            {
                "owner": owner,
                "objectname": objectname,
                "requester": requester,
                "permission": permission,
            }
        ) as cur:
            row = await cur.fetchone()
    return row is not None and row["effect"] == "allow"


async def object_exists(request, owner, name) -> bool:
    async with get_db_reader(request) as conn:
        async with conn.execute(
            "SELECT 1 FROM objects WHERE username = ? AND name = ?",
            (owner, name),
        ) as cur:
            row = await cur.fetchone()
    return row is not None


async def verify_credentials(request, username, token) -> bool:
    """Shared by HTTP Basic auth (API) and the web login form."""
    if not re.match(config.USERNAME_RE, username):
        return False
    async with get_db_reader(request) as conn:
        async with conn.execute(
            "SELECT token FROM users WHERE username = ?", (username,)
        ) as cur:
            row = await cur.fetchone()
    return row is not None and secrets.compare_digest(row["token"], token)


async def get_object_uuid(request, owner, name):
    """The on-disk uuid for (owner, name), or None if it doesn't exist."""
    async with get_db_reader(request) as conn:
        async with conn.execute(
            "SELECT uuid FROM objects WHERE username = ? AND name = ?", (owner, name),
        ) as cur:
            row = await cur.fetchone()
    return row["uuid"] if row is not None else None


@contextmanager
def sync_db():
    """Blocking SQLite connection; commits on success, closes always."""
    conn = sqlite3.connect(config.DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        with conn:
            yield conn
    finally:
        conn.close()


def init_storage():
    config.DATA_DIR.mkdir(parents=True, exist_ok=True)
    config.OBJECT_DIR.mkdir(parents=True, exist_ok=True)
    with sync_db() as conn:
        conn.execute("PRAGMA journal_mode = WAL")
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS users (
                username   TEXT PRIMARY KEY,
                token      TEXT NOT NULL UNIQUE,
                created_at INTEGER NOT NULL DEFAULT (unixepoch())
            );
            CREATE TABLE IF NOT EXISTS objects (
                username  TEXT NOT NULL REFERENCES users(username) ON DELETE CASCADE,
                name      TEXT NOT NULL,
                uuid      TEXT NOT NULL UNIQUE,
                PRIMARY KEY (username, name)
            );
            CREATE TABLE IF NOT EXISTS shares (
                owner      TEXT NOT NULL REFERENCES users(username) ON DELETE CASCADE,
                prefix     TEXT NOT NULL,
                scope      TEXT NOT NULL CHECK (scope IN ('exact', 'prefix')),
                receiver   TEXT NOT NULL REFERENCES users(username) ON DELETE CASCADE,
                permission TEXT NOT NULL CHECK (permission IN ('r','w','x','s')),
                effect     TEXT NOT NULL CHECK (effect IN ('allow','deny')) DEFAULT 'allow',
                PRIMARY KEY (owner, prefix, scope, receiver, permission, effect),
                CHECK (owner <> receiver),
                CHECK (
                       (scope = 'prefix' AND (prefix = '' OR prefix LIKE '%/'))
                    OR (scope = 'exact'  AND prefix <> '' AND prefix NOT LIKE '%/')
                )
            );
            INSERT INTO users (username, token) VALUES ('*public', '') ON CONFLICT (username) DO NOTHING;
            CREATE INDEX IF NOT EXISTS idx_objects_by_owner_name ON objects (username, name);
            CREATE INDEX IF NOT EXISTS idx_shares_for_receiver ON shares (receiver, owner, permission);
            """
        )
