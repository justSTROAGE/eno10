FROM debian:bookworm-slim AS builder

ARG SIMH_REV=7994e0a7ce66321cbb11379e10de9fc1944942d9

RUN apt update
RUN apt install -y --no-install-recommends \
        build-essential cmake ninja-build pkg-config git ca-certificates \
        libpcre3-dev libpng-dev libsdl2-dev libsdl2-ttf-dev \
        libpcap-dev libfreetype6-dev zlib1g-dev libvdeplug-dev
RUN rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN git clone https://github.com/open-simh/simh.git \
 && cd simh && git checkout "${SIMH_REV}"

# Local SimH modifications (see deploy/simh.patch for the annotated diff):
#  - sim_ether.c   : VDE socket mode 0700
#  - sim_sock.c    : force SO_REUSEADDR
#  - sim_tmxr.c    : poll every call (no connect-poll interval); round-robin
#                    line assignment (spread reuse across the line set)
#  - pdp11_cpu.c   : route DSM-11 idle loop (CLR @#177776) to sim_idle()
#  - pdp11_vh.c    : DHU11 spawn-on-connect race fix (force a clean carrier
#                    0->1 edge when a reused line's drop was never delivered)
COPY simh.patch /tmp/simh.patch
RUN cd /build/simh && git apply --verbose /tmp/simh.patch

RUN cd /build/simh \
 && cmake -B build -G Ninja -DCMAKE_C_STANDARD=11 -DCMAKE_BUILD_TYPE=Release \
 && cmake --build build --target pdp11

FROM debian:bookworm-slim

RUN apt update -y
RUN apt install -y --no-install-recommends \
        libpcre3 libpng16-16 libsdl2-2.0-0 libsdl2-ttf-2.0-0 \
        libpcap0.8 libfreetype6 zlib1g vde2 python3
RUN rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/simh/BIN/pdp11 /usr/local/bin/pdp11

RUN mkdir -p /opt/simh /sim/state /vde

WORKDIR /sim/state
