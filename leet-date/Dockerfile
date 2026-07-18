FROM golang:1.25-alpine@sha256:56961d79ea8129efddcc0b8643fd8a5416b4e6228cfd477e3fd61deb2672c587 AS build
WORKDIR /src

COPY src/go.mod src/go.sum ./
RUN go mod download

COPY src/ ./
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/server ./cmd/server

FROM alpine:3.20@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc
RUN apk add --no-cache ca-certificates postgresql-client \
    && addgroup -S service \
    && adduser -S -G service -u 1000 service

COPY --from=build /out/server /service/server
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
    && mkdir -p /data/uploads \
    && chown -R service:service /data

USER service
WORKDIR /service
EXPOSE 8000

ENTRYPOINT ["/entrypoint.sh"]
