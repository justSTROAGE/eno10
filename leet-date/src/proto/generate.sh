#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

protoc \
  --proto_path=proto \
  --go_out=. --go_opt=module=github.com/leonardopreuss/leet_date \
  --go-grpc_out=. --go-grpc_opt=module=github.com/leonardopreuss/leet_date \
  proto/compress/compress.proto

echo "generated internal/compresspb/*.pb.go"
