from pathlib import Path
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, Response
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles
from starlette.middleware.sessions import SessionMiddleware
from aiosqlitepool import SQLiteConnectionPool

from d3pl0y_frontend import config
from d3pl0y_frontend.db import sqlite_connection, init_storage
from d3pl0y_frontend.api import router as api
from d3pl0y_frontend.web import router as web


@asynccontextmanager
async def lifespan(app: FastAPI):
    db_writer_pool = SQLiteConnectionPool(connection_factory=sqlite_connection, pool_size=1)
    db_reader_pool = SQLiteConnectionPool(connection_factory=sqlite_connection, pool_size=config.DB_POOL_SIZE)
    yield {"db_reader_pool":  db_reader_pool, "db_writer_pool": db_writer_pool}
    await db_writer_pool.close()
    await db_reader_pool.close()


init_storage()

app = FastAPI(lifespan=lifespan)
app.add_middleware(SessionMiddleware, secret_key=config.get_secret_key())
app.mount(
    "/static",
    StaticFiles(directory=str(Path(__file__).parent / "static")),
    name="static",
)
app.mount("/api", api)
app.mount("/web", web)


@app.get("/")
async def root():
    """The browser UI lives under /web; send the bare root there."""
    return RedirectResponse(url="/web/", status_code=307)


@app.middleware("http")
async def limit_body_size(request: Request, call_next):
    """Reject oversized bodies up front"""
    length = request.headers.get("content-length")
    if length is not None:
        try:
            too_big = int(length) > config.MAX_OBJECT_BYTES
        except ValueError:
            too_big = False
        if too_big:
            return Response("File too big", status_code=413)
    return await call_next(request)
