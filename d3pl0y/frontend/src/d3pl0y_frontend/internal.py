import os
import secrets
import uuid
import sqlite3
from pathlib import Path

import asyncio
from fastapi import Request, HTTPException

from d3pl0y_frontend import config, db

"""Implementation of core object storage functionality shared by web and api

Generally it is assumed, that the requester is a authenticated user and
therefore the string contains a valid username. (owner, name) for identifying
objects are also assumed to be valid, as they have to be handled differently
between api and web.

Other arguments are not assumed to be valid and shall be checked in the internal
implementation.

Cases that can be reached via normal interaction with the ui shall not raise
an HTTPException.
"""


async def _is_owner_or_permission(request, requester, owner, name, perm):
    if not ((requester == owner)
            or await db.get_permission(request, requester, owner, name, perm)):
        raise HTTPException(status_code=403)


async def register(request: Request, username: str) -> str:
    username = username.strip()
    if not config.USERNAME_RE.match(username):
        raise HTTPException(status_code=400,
                            detail="Invalid username.")
    token = secrets.token_urlsafe(32)
    try:
        async with db.get_db_writer(request) as conn:
            await conn.execute(
                "INSERT INTO users (username, token) VALUES (?, ?)",
                (username, token),
            )
            await conn.commit()
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=409,
                            detail=f"Username '{username}' is already taken.")
    return token


async def get_object(request: Request, requester: str, owner: str, name: str) -> Path:
    """Checks permissions and reads object path from db, returns the path"""
    await _is_owner_or_permission(request, requester, owner, name, "r")
    obj_uuid = await db.get_object_uuid(request, owner, name)
    if obj_uuid is None:
        raise HTTPException(status_code=404)
    path = config.OBJECT_DIR / obj_uuid
    if not path.is_file():
        raise HTTPException(status_code=500)
    return path


async def put_object(request: Request, requester: str, owner: str, name: str, data: bytes) -> bool:
    await _is_owner_or_permission(request, requester, owner, name, "w")
    if len(data) > config.MAX_OBJECT_BYTES:
        raise HTTPException(detail="File too big", status_code=413)
    new_uuid = uuid.uuid4().hex
    new_file = config.OBJECT_DIR / new_uuid
    with open(new_file, "xb") as f:
        f.write(data)
    async with db.get_db_writer(request) as conn:
        await conn.execute(
            "INSERT INTO objects (username, name, uuid) VALUES (?, ?, ?) "
            "ON CONFLICT(username, name) DO NOTHING",
            (owner, name, new_uuid),
        )
        await conn.commit()
    obj_uuid = await db.get_object_uuid(request, owner, name)
    if obj_uuid is None:
        (config.OBJECT_DIR / new_uuid).unlink()
        raise HTTPException(status_code=500)
    if obj_uuid != new_uuid:
        os.replace(new_file, config.OBJECT_DIR / obj_uuid)
        return False
    return True


async def delete_object(request: Request, requester: str, owner: str, name: str):
    await _is_owner_or_permission(request, requester, owner, name, "w")
    obj_uuid = await db.get_object_uuid(request, owner, name)
    if obj_uuid is None:
        raise HTTPException(status_code=404)
    async with db.get_db_writer(request) as conn:
        await conn.execute(
            "DELETE FROM objects WHERE username = ? AND name = ?",
            (owner, name),
        )
        await conn.commit()
    try:
        (config.OBJECT_DIR / obj_uuid).unlink()
    except FileNotFoundError:
        pass


async def get_owned_objects(request: Request, requester: str) -> [str, str]:
    """list of name, uuid of owned objects, ordered"""
    async with db.get_db_reader(request) as conn:
        rows = await conn.execute_fetchall(
            "SELECT name, uuid FROM objects WHERE username = ? ORDER BY name",
            (requester,)
        )
    return [(row["name"], row["uuid"]) for row in rows]


async def _shared_candidates(request: Request, requester: str,
                             after: (str, str), limit: int) -> [dict]:
    """One batch of objects with a share rule that could apply to `requester`.

    Ordered by (owner, name) and starting after the `after` key, so a caller can
    walk the whole listing by feeding the last key back in. These are candidates
    only: whether a rule actually grants anything is get_permission's call.
    """
    async with db.get_db_reader(request) as conn:
        rows = await conn.execute_fetchall(
            """
            SELECT DISTINCT o.username AS owner, o.name AS name
            FROM objects o
            JOIN shares s ON s.owner = o.username
            WHERE o.username != :me
              AND (s.receiver = :me OR s.receiver = '*public')
              AND (
                       (s.scope = 'exact'  AND s.prefix = o.name)
                    OR (s.scope = 'prefix' AND o.name GLOB s.prefix || '*')
                  )
              AND (:unpaged OR (o.username, o.name) > (:after_owner, :after_name))
            ORDER BY o.username, o.name
            LIMIT :limit
            """,
            {
                "me": requester,
                "unpaged": after is None,
                "after_owner": after[0] if after else "",
                "after_name": after[1] if after else "",
                "limit": limit,
            },
        )
    return rows


async def get_shared_objects(request: Request, requester: str,
                             after: (str, str) = None,
                             limit: int = config.SHARED_PAGE_SIZE
                             ) -> ([(str, str, [str])], (str, str)):
    """One page of objects owned by others that `requester` can access.

    Returns (rows, next_key). Rows are (owner, name, [perms]) ordered by
    (owner, name); next_key is the cursor for the following page, or None once
    the listing is exhausted. Each permission is resolved through get_permission
    so deny-overrides are honored.

    A candidate can still resolve to nothing, so the page cannot be a plain SQL
    LIMIT — that would leave short pages with holes in them. Candidates are
    pulled a batch at a time and resolved until `limit` of them survive, which
    keeps the work proportional to the page rather than to the whole listing.
    """
    shared, cursor = [], after
    while len(shared) < limit:
        rows = await _shared_candidates(request, requester, cursor,
                                        config.SHARED_CANDIDATE_BATCH)
        drained = True
        for i, row in enumerate(rows):
            cursor = (row["owner"], row["name"])
            perms = await get_permissions(request, requester, row["owner"], row["name"])
            if perms:
                shared.append((row["owner"], row["name"], perms))
                if len(shared) == limit:
                    drained = i == len(rows) - 1
                    break
        if drained and len(rows) < config.SHARED_CANDIDATE_BATCH:
            cursor = None
            break
    return shared, cursor


async def get_shared_objects_by_user(request: Request, requester: str, owner: str) -> [(str, str, [str])]:
    """Objects owned by others that `requester` has at least one allowed permission on.

    Returns (owner, name, [perms]). Each permission is resolved through
    get_permission so deny-overrides are honored.
    """
    async with db.get_db_reader(request) as conn:
        rows = await conn.execute_fetchall(
            """
            SELECT DISTINCT o.username AS owner, o.name AS name
            FROM objects o
            JOIN shares s ON s.owner = o.username
            WHERE o.username = :owner
              AND (s.receiver = :me OR s.receiver = '*public')
              AND (
                       (s.scope = 'exact'  AND s.prefix = o.name)
                    OR (s.scope = 'prefix' AND o.name GLOB s.prefix || '*')
                  )
            ORDER BY o.username, o.name
            """,
            {"me": requester, "owner": owner},
        )
    shared = []
    for row in rows:
        perms = await get_permissions(request, requester, row["owner"], row["name"])
        if perms:
            shared.append((row["owner"], row["name"], perms))
    return shared


async def get_shares_for_object(request: Request, owner: str, prefix: str) -> [dict]:
    async with db.get_db_reader(request) as conn:
        rows = await conn.execute_fetchall(
            "SELECT receiver, prefix, scope, permission, effect FROM shares "
            "WHERE owner = :owner "
            "AND ((prefix = :prefix AND scope = 'exact')"
            "     OR (:prefix GLOB prefix || '*' AND scope = 'prefix'))"
            "ORDER BY receiver, permission, effect",
            {"owner": owner, "prefix": prefix}
        )
    return [dict(row) for row in rows]


async def get_permissions(request: Request, requester: str, owner: str, name: str) -> str:
    return [
        p for p in ("r", "w", "x", "s")
        if await db.get_permission(request, requester, owner, name, p)
    ]


async def set_share(request: Request, owner: str, prefix: str,
                    scope: str, receiver: str, permission: str, effect: str):
    if (not config.OBJECTNAME_RE.match(prefix)
            or scope not in ("exact", "prefix")
            or permission not in ("r", "w", "x", "s")
            or effect not in ("allow", "deny")
            or ((not config.USERNAME_RE.match(receiver)) and (not receiver == "*public"))):
        raise HTTPException(status_code=400, detail="Invalid share parameters.")
    try:
        async with db.get_db_writer(request) as conn:
            await conn.execute(
                "INSERT INTO shares (owner, prefix, scope, receiver, permission, effect) "
                "VALUES (?, ?, ?, ?, ?, ?) "
                "ON CONFLICT(owner, prefix, scope, receiver, permission, effect) DO NOTHING",
                (owner, prefix, scope, receiver, permission, effect),
            )
            await conn.commit()
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=400,
                            detail="Share rejected by a database constraint "
                                   "(check scope vs. object-name format).")


async def make_public(request, owner, name):
    """Grant everyone read + execute on one of the owner's objects."""
    if not await db.object_exists(request, owner, name):
        raise HTTPException(status_code=404)
    await set_share(request, owner, name, "exact", "*public", "r", "allow")
    await set_share(request, owner, name, "exact", "*public", "x", "allow")


async def delete_share(request: Request, owner: str, prefix: str,
                       scope: str, receiver: str, permission: str, effect: str):
    """Delete one of the owner's sharing rules."""
    async with db.get_db_writer(request) as conn:
        cur = await conn.execute(
            "DELETE FROM shares WHERE owner = ? AND prefix = ? AND scope = ? "
            "AND receiver = ? AND permission = ? AND effect = ?",
            (owner, prefix, scope, receiver, permission, effect),
        )
        await conn.commit()
    if cur.rowcount == 0:
        raise HTTPException(status_code=404)


async def execute(request: Request, requester: str, owner: str, name: str,
                  argument: str, suid: bool) -> str:
    perm = "s" if suid else "x"
    await _is_owner_or_permission(request, requester, owner, name, perm)
    if not await db.object_exists(request, owner, name):
        raise HTTPException(status_code=404)
    caller = owner if suid else requester
    proc = await asyncio.create_subprocess_exec(
        config.EXECUTE_BINARY, f"{owner}/{name}", argument, caller,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(), timeout=config.EXECUTE_TIMEOUT
        )
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        raise HTTPException(status_code=504, detail="Execution timed out")
    return stdout.decode(errors="replace")
