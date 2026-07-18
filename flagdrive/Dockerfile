# --- TOOLCHAIN ---
FROM rust@sha256:e14e87345b4d5964ddcc3491d27ee046a0f23820f340c3c1e24da6880141f7c0 AS toolchain

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    pkg-config \
    libssl-dev \
    curl \
    mold \
    && rm -rf /var/lib/apt/lists/*

# Install Rust target for Wasm
RUN rustup target add wasm32-unknown-unknown

# Install bin-installed tools for faster tool installs 
RUN curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash
RUN cargo binstall -y trunk@0.21.14 cargo-chef@0.1.77 wasm-bindgen-cli@0.2.121

RUN curl -Lfo /usr/local/bin/tailwindcss https://github.com/tailwindlabs/tailwindcss/releases/latest/download/tailwindcss-linux-x64 && \
    chmod +x /usr/local/bin/tailwindcss


# --- CHEF ---
FROM toolchain AS chef
WORKDIR /ctf/service
COPY . .

# Prepare recipe file
RUN cargo chef prepare --recipe-path /ctf/recipe.json > /ctf/chef.log 2>&1 \
    || (cat /ctf/chef.log && exit 1)


# --- COOK-FRONTEND ---
FROM toolchain AS cook-frontend
WORKDIR /ctf/service

# Cook recipe file
COPY --from=chef /ctf/recipe.json /ctf/recipe.json
RUN --mount=type=cache,id=cargo-registry-frontend,target=/usr/local/cargo/registry \
    --mount=type=cache,id=cargo-target-frontend,target=/ctf/service/target \
    cargo chef cook --release --package flagdrive-frontend --target wasm32-unknown-unknown --recipe-path /ctf/recipe.json > /ctf/chef.log 2>&1 \
    || (cat /ctf/chef.log && exit 1)


# --- COOK-BACKEND ---
FROM toolchain AS cook-backend
ENV RUSTFLAGS="-C link-arg=-fuse-ld=mold"
WORKDIR /ctf/service

# Cook recipe file
COPY --from=chef /ctf/recipe.json /ctf/recipe.json
RUN --mount=type=cache,id=cargo-registry-backend,target=/usr/local/cargo/registry \
    --mount=type=cache,id=cargo-target-backend,target=/ctf/service/target \
    cargo chef cook --release --package flagdrive-backend --recipe-path /ctf/recipe.json > /ctf/chef.log 2>&1 \
    || (cat /ctf/chef.log && exit 1)


# --- BUILDER-FRONTEND ---
FROM toolchain AS builder-frontend
WORKDIR /ctf/service

# Build frontend
COPY --from=cook-frontend /ctf/service/backend /ctf/service/backend
COPY Cargo.toml Cargo.lock ./
COPY backend/Cargo.toml ./backend/
COPY shared ./shared
COPY frontend ./frontend
# Pre-generate the tailwind CSS output so trunk can canonicalize the
# data-trunk tailwind-css asset link (it processes the link before running the
# build-stage hook that would otherwise generate it). tailwindcss does not
# create parent dirs, so create the directory first.
RUN mkdir -p frontend/style && \
    cd frontend && tailwindcss -i src/styles/tailwind.css -o style/tailwind.css && cd ..
RUN --mount=type=cache,id=cargo-registry-frontend,target=/usr/local/cargo/registry \
    --mount=type=cache,id=cargo-target-frontend,target=/ctf/service/target \
    cd frontend && trunk build --release --quiet && cd ..


# --- BUILDER-BACKEND ---
FROM toolchain AS builder-backend
ENV RUSTFLAGS="-C link-arg=-fuse-ld=mold"
WORKDIR /ctf/service

# Build backend
COPY --from=cook-backend /ctf/service/frontend /ctf/service/frontend
COPY Cargo.toml Cargo.lock ./
COPY frontend/Cargo.toml ./frontend/
COPY shared ./shared
COPY backend ./backend
RUN --mount=type=cache,id=cargo-registry-backend,target=/usr/local/cargo/registry \
    --mount=type=cache,id=cargo-target-backend,target=/ctf/service/target \
    cd backend && cargo build --release --quiet && \
    cp /ctf/service/target/release/flagdrive-backend /ctf/service/flagdrive-backend


# --- DATABASE ---
FROM toolchain AS database
WORKDIR /ctf/data


# --- FINAL IMAGE ---
FROM gcr.io/distroless/cc-debian13@sha256:8b5d1db6d2253036a53cb8362d3e3fa82a7caf84c247772c46a023166c64e977 AS runtime

COPY --from=builder-frontend /ctf/service/frontend/dist /ctf/service/dist
COPY --from=builder-backend /ctf/service/flagdrive-backend /ctf/service/flagdrive
COPY --from=database /ctf/data /ctf/data

ENTRYPOINT ["/ctf/service/flagdrive", "--dist", "/ctf/service/dist", "--database", "/ctf/data/flagdrive.db", "--addr", "0.0.0.0:4859"]