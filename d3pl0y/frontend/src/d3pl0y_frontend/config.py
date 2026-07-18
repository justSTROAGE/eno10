from pathlib import Path
import os
import secrets
import re

DATA_DIR = Path(os.environ.get("DATA_DIR", "/data"))
OBJECT_DIR = DATA_DIR / "objects"
DB_PATH = DATA_DIR / "meta.db"
SECRET_KEY_PATH = DATA_DIR / "secret_key"
USERNAME_RE = re.compile(r"^[A-Za-z0-9_-]{1,32}$")
OBJECTNAME_RE = re.compile(r"^[A-Za-z0-9_./-]{1,64}$")

MAX_OBJECT_BYTES = 1 * 1024
EXECUTE_BINARY = "/app/vm"
EXECUTE_TIMEOUT = 5

DB_POOL_SIZE = 4

SHARED_PAGE_SIZE = 50
SHARED_CANDIDATE_BATCH = 80

USER_TTL_SECONDS = 12 * 60
CLEANUP_INTERVAL_SECONDS = 60


def get_secret_key() -> str:
    """Cookie-session signing key, generated once and persisted across restarts."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    try:
        key = SECRET_KEY_PATH.read_text().strip()
        if key:
            return key
    except (FileNotFoundError, UnicodeDecodeError):
        pass
    key = secrets.token_urlsafe(32)
    SECRET_KEY_PATH.write_text(key)
    return key
