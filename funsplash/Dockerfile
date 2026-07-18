ARG GLEAM_VERSION=v1.17.0

# Build stage - compile the application
FROM ghcr.io/gleam-lang/gleam:${GLEAM_VERSION}-erlang-alpine AS builder

RUN apk add --no-cache make gcc musl-dev git

# prerun
COPY ./shared/manifest.toml /build/shared/
COPY ./shared/gleam.toml /build/shared/
COPY ./client/manifest.toml /build/client/
COPY ./client/gleam.toml /build/client/
COPY ./server/manifest.toml /build/server/
COPY ./server/gleam.toml /build/server/

RUN cd /build/shared && gleam deps download
RUN cd /build/client && gleam deps download
RUN cd /build/server && gleam deps download

RUN mkdir -p /build/shared/src /build/client/src /build/server/src \
    && echo "pub fn main() { Nil }" > /build/shared/src/shared.gleam \
    && echo "pub fn main() { Nil }" > /build/client/src/client.gleam \
    && echo '@import "tailwindcss";' > /build/client/src/client.css \
    # && echo "import argus pub fn main() { let _ = argus.hasher() Nil }" > /build/server/src/server.gleam
    && echo "pub fn main() { Nil }" > /build/server/src/server.gleam

RUN cd /build/client && gleam run -m lustre/dev build
RUN cd /build/shared && gleam build
RUN cd /build/server && gleam build
RUN cd /build/server && gleam export erlang-shipment

RUN rm /build/client/src/client.gleam \
    && rm /build/client/src/client.css \
    && rm /build/shared/src/shared.gleam \
    && rm /build/server/src/server.gleam

# Add project code
# COPY ./shared /build/shared
# COPY ./client /build/client
# COPY ./server /build/server
COPY . /build

# Force rebuild of actual source files by updating their mtime, keeping dependency cache intact
RUN find /build/shared/src /build/client/src /build/server/src -type f -exec touch {} +


# Compile the client code and output to server's static directory
RUN cd /build/client \
    && gleam add --dev lustre_dev_tools \
    && gleam build
RUN cd /build/client \
    && gleam run -m lustre/dev build --minify --outdir=../server/priv/static

# Compile the server code
RUN cd /build/server \
    && gleam export erlang-shipment

# Runtime stage - slim image with only what's needed to run
FROM ghcr.io/gleam-lang/gleam:${GLEAM_VERSION}-erlang-alpine

# Copy the compiled server code from the builder stage
COPY --from=builder /build/server/build/erlang-shipment /app

# Set up the entrypoint
WORKDIR /app
RUN echo -e '#!/bin/sh\nexec ./entrypoint.sh "$@"' > ./start.sh \
    && chmod +x ./start.sh

# Set environment variables
ENV HOST=0.0.0.0
ENV PORT=8080

# Expose the port the server will run on
EXPOSE $PORT

# Run the server
CMD ["./start.sh", "run"]
