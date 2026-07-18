"""
Standalone reaper process that expires old users and their data.

    python -m d3pl0y_frontend.cleanup
"""
import logging
import time

from d3pl0y_frontend import config, db

_log = logging.getLogger(__name__)


def delete_expired_users(ttl_seconds) -> int:
    """Delete users registered more than ttl_seconds ago, plus their files.

    The '*public' sentinel is exempt. Each expiring user's object/share rows are
    removed by ON DELETE CASCADE; the on-disk object files are not, so their
    uuids are collected before the delete and unlinked afterwards. Returns the
    number of users removed.

    Runs synchronously in the reaper process, off the event loop.
    """
    with db.sync_db() as conn:
        uuids = [
            row["uuid"]
            for row in conn.execute(
                "SELECT o.uuid FROM objects o JOIN users u ON u.username = o.username "
                "WHERE u.username != '*public' AND u.created_at <= unixepoch() - ?",
                (ttl_seconds,),
            )
        ]
        removed = conn.execute(
            "DELETE FROM users WHERE username != '*public' "
            "AND created_at <= unixepoch() - ?",
            (ttl_seconds,),
        ).rowcount
    for u in uuids:
        try:
            (config.OBJECT_DIR / u).unlink()
        except FileNotFoundError:
            pass
    return removed


def run_reaper():
    while True:
        time.sleep(config.CLEANUP_INTERVAL_SECONDS)
        try:
            removed = delete_expired_users(config.USER_TTL_SECONDS)
            if removed:
                _log.info("reaper: removed %d expired user(s)", removed)
        except Exception:
            _log.exception("reaper: sweep failed")


def main():
    logging.basicConfig(
        level=logging.INFO,
        format="[%(asctime)s] [reaper] [%(levelname)s] %(message)s",
    )
    _log.info(
        "reaper: sweeping every %ds for users older than %ds",
        config.CLEANUP_INTERVAL_SECONDS,
        config.USER_TTL_SECONDS,
    )
    try:
        run_reaper()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
