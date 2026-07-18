FROM debian:sid-slim@sha256:54f7a23f03be1e9fe2849c61a7455588ea29b84c1659440f8ece2aea4c9871af AS hare-builder

ARG DEBIAN_SNAPSHOT=20260716T202147Z
RUN rm -f /etc/apt/sources.list /etc/apt/sources.list.d/debian.sources \
    && printf 'deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/%s/ sid main\n' \
        "$DEBIAN_SNAPSHOT" > /etc/apt/sources.list.d/snapshot.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        make \
        hare \
        libsqlite3-dev \
        gcc \
        git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build/vm
ARG HARE_SQLITE_COMMIT=2177216280305e110a09e5fb98888fdab4fb97a8
RUN mkdir vendor \
    && git clone https://git.sr.ht/~blainsmith/hare-sqlite vendor/hare-sqlite \
    && git -C vendor/hare-sqlite checkout --detach "$HARE_SQLITE_COMMIT"
COPY vm/ .
RUN make

FROM python:3.12.13-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        libsqlite3-0 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY frontend/pyproject.toml .
RUN mkdir -p src/frontend && touch src/frontend/__init__.py && pip install --no-cache-dir . && rm -r src/frontend
COPY frontend/src ./src
RUN pip install --no-cache-dir --no-deps .

COPY --from=hare-builder /build/vm/vm ./vm

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENV DATA_DIR=/data
VOLUME ["/data"]

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["gunicorn", "-k", "uvicorn.workers.UvicornWorker", \
     "--workers", "2", "--bind", "0.0.0.0:2553", "d3pl0y_frontend.app:app"]
