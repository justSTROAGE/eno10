# syntax=docker/dockerfile:1.6

FROM python:3.12-slim@sha256:c3d81d25b3154142b0b42eb1e61300024426268edeb5b5a26dd7ddf64d9daf28 AS deps
WORKDIR /build
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential libffi-dev \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt ./
RUN pip install --no-cache-dir --target=/deps -r requirements.txt

FROM python:3.12-slim@sha256:c3d81d25b3154142b0b42eb1e61300024426268edeb5b5a26dd7ddf64d9daf28
RUN useradd --create-home --uid 10001 payments \
    && mkdir -p /data \
    && chown payments:payments /data
USER payments
WORKDIR /app
COPY --from=deps /deps /deps
ENV PYTHONPATH=/deps
ENV PYTHONUNBUFFERED=1
ENV PAY_DB_PATH=/data/payments.db
ENV PAY_JWK_PATH=/data/payments-jwk.json
ENV PORT=7000
COPY --chown=payments:payments *.py /app/
EXPOSE 7000
ENTRYPOINT ["python", "/app/app.py"]
