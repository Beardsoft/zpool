FROM debian:12-slim AS builder

RUN apt update \
    && apt install -y curl xz-utils libsqlite3-dev \
    && mkdir -p /bin/zig \
    && curl https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz -o zig.tar.xz \
    && tar -xf zig.tar.xz \
    && cp -r ./zig-linux-x86_64-0.13.0/* /bin/zig/ 

WORKDIR /build 
COPY ./src /build/src
COPY ./build.zig /build/build.zig
COPY ./build.zig.zon /build/build.zig.zon

RUN /bin/zig/zig build -Dpolicy=Devnet

FROM gcr.io/distroless/cc-debian12

COPY --from=builder /lib/x86_64-linux-gnu/libsqlite3.so.0.8.6 /lib/libsqlite3.so.0
COPY --from=builder /build/zig-out/bin/zpool /zpool
COPY devnet.config.toml /config.toml
ENV ZPOOL_CONFIG_FILE=/config.toml
CMD ["/zpool"]
