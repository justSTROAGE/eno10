from typing import Annotated
import base64
import binascii

from fastapi import FastAPI, HTTPException, Request, Response, Form
from pydantic import BaseModel
from fastapi.responses import FileResponse, PlainTextResponse

from d3pl0y_frontend import config, db, internal

router = FastAPI()


def _validate_key(owner: str, name: str) -> None:
    if not config.USERNAME_RE.match(owner) or not config.OBJECTNAME_RE.match(name):
        raise HTTPException(status_code=404)


async def _get_authenticated_user(request: Request):
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Basic "):
        raise HTTPException(status_code=403)
    encoded = auth[len("Basic "):].strip()
    try:
        decoded = base64.b64decode(encoded, validate=True).decode("utf-8")
    except (binascii.Error, UnicodeDecodeError, ValueError):
        raise HTTPException(status_code=403)
    if ":" not in decoded:
        raise HTTPException(status_code=403)
    username, password = decoded.split(":", 1)
    if await db.verify_credentials(request, username, password):
        return username
    raise HTTPException(status_code=403)


@router.post("/user/register")
async def register(request: Request, username: Annotated[str, Form()] = ""):
    token = await internal.register(request, username)
    return Response(content=token, status_code=201)


@router.get("/user/shared/{owner}")
async def get_shared_by_user(request: Request, owner: str):
    if not config.USERNAME_RE.match(owner):
        raise HTTPException(status_code=404)
    requester = await _get_authenticated_user(request)
    shared = await internal.get_shared_objects_by_user(request, requester, owner)
    lines = [f"{s[0]}/{s[1]}:{"".join(s[2])}" for s in shared]
    return PlainTextResponse("\n".join(lines))


@router.get("/user/{owner}/{name:path}")
async def get_object(request: Request, owner: str, name: str):
    _validate_key(owner, name)
    requester = await _get_authenticated_user(request)
    path = await internal.get_object(request, requester, owner, name)
    return FileResponse(
        path, media_type="application/octet-stream",
        filename=name.rsplit("/", 1)[-1],
    )


@router.put("/user/{owner}/{name:path}")
async def put_object(request: Request, owner: str, name: str):
    _validate_key(owner, name)
    data = await request.body()
    requester = await _get_authenticated_user(request)
    created = await internal.put_object(request, requester, owner, name, data)
    return Response(status_code=201 if created else 200)


class Execution(BaseModel):
    argument: str = ""
    suid: bool = False


@router.post("/user/{owner}/{name:path}")
async def execute_object(request: Request, owner: str, name: str, execution: Execution):
    _validate_key(owner, name)
    requester = await _get_authenticated_user(request)
    out = await internal.execute(request, requester, owner, name, execution.argument, execution.suid)
    return PlainTextResponse(out)


class Share(BaseModel):
    prefix: str
    scope: str
    receiver: str = "*public"
    permission: str
    effect: str


@router.post("/user/shares")
async def set_share(request: Request, share: Share):
    requester = await _get_authenticated_user(request)
    await internal.set_share(request, requester, share.prefix, share.scope,
                             share.receiver, share.permission, share.effect)
    return Response(status_code=200)


class Publication(BaseModel):
    name: str


@router.post("/user/public")
async def make_public(request: Request, publication: Publication):
    requester = await _get_authenticated_user(request)
    _validate_key(requester, publication.name)
    await internal.make_public(request, requester, publication.name)
    return Response(status_code=200)


@router.delete("/user/{owner}/{name:path}")
async def delete_object(request: Request, owner: str, name: str):
    _validate_key(owner, name)
    requester = await _get_authenticated_user(request)
    await internal.delete_object(request, requester, owner, name)
    return Response(status_code=204)
