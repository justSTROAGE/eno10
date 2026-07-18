import re
from typing import Optional, Annotated
from http import HTTPStatus

from starlette.exceptions import HTTPException as StarletteHTTPException
from fastapi.exceptions import RequestValidationError
from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, RedirectResponse

from d3pl0y_frontend import config, db, vmcode, internal
from d3pl0y_frontend.rendering import flash, render, url_for


router = FastAPI()


def _current_user(request: Request):
    user = request.session.get("username")
    if user is None:
        raise HTTPException(status_code=403, detail="You need to be logged in.")
    return user


def _validate_key(owner: str, name: str) -> None:
    if not config.USERNAME_RE.match(owner) or not config.OBJECTNAME_RE.match(name):
        raise HTTPException(status_code=400, detail="Invalid object reference.")


def _error_page(request: Request, code: int, description: str | None = None):
    try:
        name = HTTPStatus(code).phrase
    except ValueError:
        name = "Error"
    return render(
        request, "error.html", status_code=code, container_class="narrow",
        code=code, name=name, description=description or "Something went wrong.",
    )


@router.exception_handler(StarletteHTTPException)
async def handle_error(request: Request, exc: StarletteHTTPException):
    description = exc.detail if isinstance(exc.detail, str) and exc.detail else None
    return _error_page(request, exc.status_code, description)


@router.exception_handler(RequestValidationError)
async def handle_validation_error(request: Request, exc: RequestValidationError):
    return _error_page(request, 400, "The request was malformed.")


def _object_size(uuid):
    try:
        return (config.OBJECT_DIR / uuid).stat().st_size
    except OSError:
        return 0


def _parse_cursor(after: str):
    """'<owner>/<name>' page cursor -> (owner, name), or None when absent.

    A username can't contain '/', so the first one always separates the two.
    """
    if not after:
        return None
    owner, _, name = after.partition("/")
    if not config.USERNAME_RE.match(owner) or not config.OBJECTNAME_RE.match(name):
        raise HTTPException(status_code=400, detail="Invalid page cursor.")
    return owner, name


def _format_cursor(key) -> str:
    return f"{key[0]}/{key[1]}" if key else None


def _group_objects(items):
    """Group objects by their top-level prefix ('' for root-level names)."""
    groups, order = {}, []
    for o in items:
        folder = o["name"].split("/", 1)[0] + "/" if "/" in o["name"] else ""
        if folder not in groups:
            groups[folder] = []
            order.append(folder)
        groups[folder].append(o)
    result = []
    if "" in groups:
        result.append(("", groups[""]))
    result.extend((f, groups[f]) for f in order if f != "")
    return result


def _parse_hex(text):
    """Forgiving hex parser. Returns (data, error_message); one of them is None."""
    out = bytearray()
    for tok in re.split(r"[\s,;:]+", text.strip()):
        if tok == "":
            continue
        if tok[:2].lower() == "0x":
            tok = tok[2:]
        if not re.fullmatch(r"[0-9a-fA-F]+", tok):
            return None, f"'{tok}' is not valid hexadecimal."
        if len(tok) % 2 != 0:
            return None, f"'{tok}' has an odd number of hex digits."
        out.extend(bytes.fromhex(tok))
    if not out:
        return None, "Enter some hex bytes to store."
    return bytes(out), None


@router.get("/")
def index(request: Request):
    if request.session.get("username"):
        return RedirectResponse(url_for("web.objects_page"), status_code=303)
    return render(request, "landing.html")


@router.get("/register")
def register_form(request: Request):
    return render(request, "register.html", container_class="narrow")


@router.post("/register")
async def register(request: Request, username: Annotated[str, Form()] = ""):
    token = await internal.register(request, username)
    request.session["username"] = username
    return render(
        request, "registered.html", status_code=201, container_class="narrow",
        username=username, token=token,
    )


@router.get("/login")
def login_form(request: Request, next: str = ""):
    return render(
        request, "login.html", container_class="narrow", nav="login", next=next,
    )


@router.post("/login")
async def login(request: Request, username: Annotated[str, Form()] = "",
                token: Annotated[str, Form()] = ""):
    username = username.strip()
    if await db.verify_credentials(request, username, token):
        request.session["username"] = username
        return RedirectResponse(url_for("web.objects_page"), status_code=303)
    return render(
        request, "login.html", status_code=401, container_class="narrow",
        nav="login", username=username, error="Invalid username or token.",
    )


@router.get("/logout")
def logout(request: Request):
    request.session.pop("username", None)
    return RedirectResponse(url_for("web.index"), status_code=303)


@router.get("/help")
def help_page(request: Request):
    return render(request, "help.html", nav="help", ops=vmcode.OP_REFERENCE)


@router.get("/objects/list")
async def objects_page(request: Request):
    requester = _current_user(request)
    objects = await internal.get_owned_objects(request, requester)
    objects = [{"name": o[0], "size": _object_size(o[1])} for o in objects]
    return render(
        request, "objects.html", nav="objects", groups=_group_objects(objects),
        count=len(objects), total_size=sum(o["size"] for o in objects)
    )


@router.get("/objects/view")
async def object_detail(request: Request, owner: str = "", name: str = ""):
    requester = _current_user(request)
    _validate_key(owner, name)
    if not await db.object_exists(request, owner, name):
        raise HTTPException(status_code=404)

    perms = await internal.get_permissions(request, requester, owner, name)
    is_owner = owner == requester
    can_read = is_owner or "r" in perms
    can_write = is_owner or "w" in perms
    can_exec = is_owner or "x" in perms
    can_suid = (not is_owner) and "s" in perms
    if not (is_owner or can_read or can_exec or can_suid):
        raise HTTPException(status_code=403)

    size = None
    hexdump = ""
    vm_mem_note = ""
    disrows, dis_truncated, hex_truncated = [], False, False
    if can_read:
        path = await internal.get_object(request, requester, owner, name)
        data = path.read_bytes()
        size = len(data)
        hexdump, hex_truncated = vmcode.hexdump_text(data)
        disrows, dis_truncated = vmcode.disassemble(data)
        vm_mem_note = f"{size} byte{'s' if size != 1 else ''}"

    shares = None
    if is_owner:
        shares = await internal.get_shares_for_object(request, owner, name)

    return render(
        request, "object_detail.html", nav="objects",
        owner=owner, name=name, is_owner=is_owner,
        can_read=can_read, can_write=can_write, can_exec=can_exec, can_suid=can_suid,
        size=size, shares=shares,
        hexdump=hexdump, hex_truncated=hex_truncated,
        disrows=disrows, dis_truncated=dis_truncated,
        vm_mem_note=vm_mem_note, vmcode_hex_limit=vmcode.HEX_LIMIT,
    )


@router.get("/objects/shared")
async def shared_page(request: Request, after: str = ""):
    requester = _current_user(request)
    rows, next_key = await internal.get_shared_objects(
        request, requester, after=_parse_cursor(after))
    groups, order = {}, []
    for owner, name, perms in rows:
        if owner not in groups:
            groups[owner] = []
            order.append(owner)
        groups[owner].append({"name": name, "perms": perms})
    return render(
        request, "shared.html", nav="shared",
        shared_groups=[(o, groups[o]) for o in order],
        count=len(rows), paged=bool(after),
        next_after=_format_cursor(next_key),
    )


@router.get("/objects/download")
async def download(request: Request, owner: str = "", name: str = ""):
    requester = _current_user(request)
    _validate_key(owner, name)
    path = await internal.get_object(request, requester, owner, name)
    return FileResponse(
        path, media_type="application/octet-stream",
        filename=name.rsplit("/", 1)[-1],
    )


@router.post("/objects/upload")
async def upload(request: Request, name: Annotated[str, Form()] = "",
                 file: Optional[UploadFile] = File(None)):
    requester = _current_user(request)
    name = name.strip()
    if not config.OBJECTNAME_RE.match(name):
        raise HTTPException(status_code=400, detail="Invalid object name.")
    data = await file.read() if file is not None else b""
    created = await internal.put_object(request, requester, requester, name, data)
    flash(request, f"{'Uploaded' if created else 'Overwrote'} {name} ({len(data)} bytes).", "success")
    return RedirectResponse(url_for("web.objects_page"), status_code=303)


@router.post("/objects/compose")
async def compose(request: Request, name: Annotated[str, Form()] = "", hex: Annotated[str, Form()] = ""):
    """Store an object authored as hex bytes in the browser (e.g. a VM program)."""
    requester = _current_user(request)
    name = name.strip()
    if not config.OBJECTNAME_RE.match(name):
        raise HTTPException(status_code=400, detail="Invalid object name.")
    data, error = _parse_hex(hex)
    if error is not None:
        flash(request, error, "error")
        return RedirectResponse(url_for("web.objects_page"), status_code=303)
    await internal.put_object(request, requester, requester, name, data)
    flash(request, f"Saved {len(data)} bytes to {name}.", "success")
    return RedirectResponse(
        url_for("web.object_detail", owner=requester, name=name), status_code=303)


@router.post("/objects/delete")
async def delete(request: Request, owner: Annotated[str, Form()], name: Annotated[str, Form()]):
    requester = _current_user(request)
    _validate_key(owner, name)
    await internal.delete_object(request, requester, owner, name)
    flash(request, f"Deleted {name}.", "success")
    return RedirectResponse(url_for("web.objects_page"), status_code=303)


@router.post("/objects/public")
async def make_public(request: Request, name: Annotated[str, Form()] = ""):
    requester = _current_user(request)
    _validate_key(requester, name)
    await internal.make_public(request, requester, name)
    flash(request, f"{name} is now public (read + execute for everyone).", "success")
    return RedirectResponse(
        url_for("web.object_detail", owner=requester, name=name), status_code=303)


@router.post("/share/add")
async def share(request: Request,
                prefix: Annotated[str, Form()] = "",
                scope: Annotated[str, Form()] = "",
                receiver: Annotated[str, Form()] = "",
                permission: Annotated[str, Form()] = "",
                effect: Annotated[str, Form()] = ""):
    requester = _current_user(request)
    await internal.set_share(request, requester, prefix, scope, receiver, permission, effect)
    if scope == "exact":
        return RedirectResponse(
            url_for("web.object_detail", owner=requester, name=prefix), status_code=303)
    return RedirectResponse(url_for("web.objects_page"), status_code=303)


@router.post("/share/delete")
async def delete_share(request: Request,
                       prefix: Annotated[str, Form()] = "",
                       scope: Annotated[str, Form()] = "",
                       receiver: Annotated[str, Form()] = "",
                       permission: Annotated[str, Form()] = "",
                       effect: Annotated[str, Form()] = ""):
    requester = _current_user(request)
    await internal.delete_share(request, requester, prefix, scope, receiver, permission, effect)
    if scope == "exact":
        return RedirectResponse(
            url_for("web.object_detail", owner=requester, name=prefix), status_code=303)
    return RedirectResponse(url_for("web.objects_page"), status_code=303)


@router.post("/objects/execute")
async def execute(request: Request,
                  owner: Annotated[str, Form()],
                  name: Annotated[str, Form()],
                  argument: Annotated[str, Form()] = "",
                  suid: Annotated[bool, Form()] = False):
    requester = _current_user(request)
    _validate_key(owner, name)
    out = await internal.execute(request, requester, owner, name, argument, suid)
    return render(
        request, "execute_result.html", nav="objects",
        owner=owner, name=name, arg=argument, output=out,
    )
