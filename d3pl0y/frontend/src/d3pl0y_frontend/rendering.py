"""Jinja2 rendering plus small Flask-compatible template helpers.

The HTML templates were written against Flask's environment, so they expect a
few globals: ``url_for`` (endpoint name -> URL), ``session`` (the cookie session
dict) and ``get_flashed_messages``. This module reproduces those against the
Starlette request/session so the templates render unchanged.
"""
from pathlib import Path
from urllib.parse import urlencode

from jinja2 import Environment, FileSystemLoader, select_autoescape
from starlette.requests import Request
from starlette.responses import HTMLResponse

_TEMPLATES_DIR = Path(__file__).parent / "templates"

_WEB_PREFIX = "/web"

_ROUTES = {
    "web.index": "/",
    "web.objects_page": "/objects/list",
    "web.shared_page": "/objects/shared",
    "web.help_page": "/help",
    "web.login_form": "/login",
    "web.login": "/login",
    "web.logout": "/logout",
    "web.register_form": "/register",
    "web.register": "/register",
    "web.upload": "/objects/upload",
    "web.compose": "/objects/compose",
    "web.object_detail": "/objects/view",
    "web.download": "/objects/download",
    "web.delete": "/objects/delete",
    "web.execute": "/objects/execute",
    "web.make_public": "/objects/public",
    "web.share": "/share/add",
    "web.delete_share": "/share/delete",
}


def url_for(endpoint: str, **values) -> str:
    """Flask-style ``url_for``: endpoint name to a URL, extra kwargs -> query."""
    if endpoint == "static":
        path = "/static/" + values.pop("filename")
    else:
        path = _WEB_PREFIX + _ROUTES[endpoint]
    values = {k: v for k, v in values.items() if v is not None}
    if values:
        path += "?" + urlencode(values)
    return path


env = Environment(
    loader=FileSystemLoader(str(_TEMPLATES_DIR)),
    autoescape=select_autoescape(["html", "xml"]),
)
env.globals["url_for"] = url_for


def _session(request: Request):
    """The cookie session, or an empty stand-in when SessionMiddleware isn't in
    scope yet (e.g. rendering an error from middleware before it has run)."""
    try:
        return request.session
    except (AssertionError, KeyError):
        return {}


def flash(request: Request, message: str, category: str = "message") -> None:
    """Queue a one-shot message, consumed by the next ``get_flashed_messages``."""
    request.session.setdefault("_flashes", []).append([category, message])


def _flashed_messages(request: Request):
    def get_flashed_messages(with_categories: bool = False, category_filter=()):
        flashes = _session(request).pop("_flashes", [])
        if category_filter:
            flashes = [f for f in flashes if f[0] in category_filter]
        if with_categories:
            return [(c, m) for c, m in flashes]
        return [m for _, m in flashes]
    return get_flashed_messages


def render(request: Request, template: str, status_code: int = 200, **context) -> HTMLResponse:
    """Render a template with the Flask-compatible helpers wired in."""
    context.setdefault("session", _session(request))
    context["get_flashed_messages"] = _flashed_messages(request)
    html = env.get_template(template).render(**context)
    return HTMLResponse(html, status_code=status_code)
