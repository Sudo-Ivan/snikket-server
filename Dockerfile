FROM debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4 AS coturn-build

RUN set -eux; \
    printf 'deb-src http://deb.debian.org/debian forky main\n' > /etc/apt/sources.list.d/forky-src.list; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential ca-certificates dpkg-dev libevent-dev libsqlite3-dev \
        libssl-dev pkgconf; \
    cd /tmp; \
    apt-get source coturn=4.18.0-1; \
    cd /tmp/coturn-4.18.0; \
    CPPFLAGS="$(dpkg-buildflags --get CPPFLAGS)" \
        CFLAGS="$(dpkg-buildflags --get CFLAGS)" \
        LDFLAGS="$(dpkg-buildflags --get LDFLAGS)" \
    TURN_NO_MYSQL=1 TURN_NO_PQ=1 TURN_NO_MONGO=1 TURN_NO_HIREDIS=1 \
        TURN_NO_SYSTEMD=1 ./configure --prefix=/usr --disable-rpath; \
    make -j"$(nproc)"; \
    if ldd bin/turnserver | grep -Eq 'lib(mariadb|pq|hiredis)'; then exit 1; fi; \
    strip --strip-unneeded bin/turnserver; \
    install -D -m 0755 bin/turnserver /out/usr/bin/turnserver; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/* /tmp/coturn-*


FROM debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4 AS prosodyx-build

RUN set -eux; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl git libexpat1-dev libicu-dev \
        liblua5.4-dev libssl-dev lua5.4; \
    git clone --depth=1 --branch v13.0.7-quad4.2 \
        https://github.com/Quad4-Software/prosodyx.git /src/prosodyx; \
    test "$(git -C /src/prosodyx rev-parse HEAD)" = \
        5a97993c6aaa7caae0ea2b49e97cfe6b22af1d22; \
    cd /src/prosodyx; \
    ./scripts/fetch-deps.sh deps.lock /build/deps; \
    mkdir -p /rootfs

ENV HARDEN_CFLAGS="-O2 -fstack-protector-strong -D_FORTIFY_SOURCE=3" \
    HARDEN_LDFLAGS="-Wl,-z,relro,-z,now"

RUN set -eux; \
    ver() { awk -F '\t' -v n="$1" '$1==n { print $2 }' /src/prosodyx/deps.lock; }; \
    cd /build/deps/luasocket-$(ver luasocket); \
    make -C src linux LUAV=5.4 \
        LUAINC_linux=/usr/include/lua5.4 \
        CC_linux=gcc \
        CFLAGS_linux="-I/usr/include/lua5.4 -DLUASOCKET_ -Wall -Wshadow -Wextra -Wimplicit $HARDEN_CFLAGS -fPIC" \
        LDFLAGS_linux="$HARDEN_LDFLAGS -shared -fPIC -o"; \
    make -C src install-unix LUAV=5.4 prefix=/usr DESTDIR=/rootfs; \
    cd /build/deps/luaexpat-$(ver luaexpat); \
    make lib LUA_INC="-I/usr/include/lua5.4" \
        CFLAGS="$HARDEN_CFLAGS" LDFLAGS="$HARDEN_LDFLAGS"; \
    make install LUA_V=5.4 DESTDIR=/rootfs; \
    cd /build/deps/luafilesystem-$(ver luafilesystem); \
    make lib LUA_VERSION=5.4 LUA_INC="-I/usr/include/lua5.4" \
        WARN="-Wall -W -Waggregate-return -Wcast-align -Wmissing-prototypes -Wnested-externs -Wshadow -Wwrite-strings -pedantic -fPIC $HARDEN_CFLAGS"; \
    make install LUA_VERSION=5.4 PREFIX=/usr DESTDIR=/rootfs; \
    cd /build/deps/luasec-$(ver luasec); \
    make linux INC_PATH="-I/usr/include/lua5.4" \
        LNX_CFLAGS="$HARDEN_CFLAGS -fPIC -Wall -pedantic -I. -I/usr/include/lua5.4 -DWITH_LUASOCKET" \
        LNX_LDFLAGS="$HARDEN_LDFLAGS -fPIC -shared -L./luasocket"; \
    make install LUAPATH=/rootfs/usr/share/lua/5.4 \
        LUACPATH=/rootfs/usr/lib/lua/5.4

WORKDIR /src/prosodyx

RUN set -eux; \
    ./configure \
        --prefix=/usr \
        --sysconfdir=/etc/prosody \
        --datadir=/snikket/prosody \
        --lua-version=5.4 \
        --lua-suffix=5.4 \
        --runwith=/usr/bin/lua5.4 \
        --idn-library=icu \
        --with-random=getrandom \
        --no-example-certs \
        --add-cflags="$HARDEN_CFLAGS" \
        --add-ldflags="$HARDEN_LDFLAGS"; \
    make -j"$(nproc)"; \
    make install DESTDIR=/rootfs; \
    make -C tools/migration install DESTDIR=/rootfs PREFIX=/usr \
        SYSCONFDIR=/etc/prosody LIBDIR=/usr/lib \
        DATADIR=/snikket/prosody RUNWITH=lua5.4; \
    sed -i '1s|.*|#!/usr/bin/lua5.4|' /rootfs/usr/bin/prosody-migrator; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/* /build


FROM debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4

ARG BUILD_SERIES=dev
ARG BUILD_ID=0

# Install dependencies

RUN install -d -m 755 /snikket;

COPY tools/smtp-url-to-msmtp.lua /usr/local/bin/smtp-url-to-msmtp
RUN chmod 550 /usr/local/bin/smtp-url-to-msmtp

COPY docker/entrypoint.sh /bin/entrypoint.sh
RUN chmod 770 /bin/entrypoint.sh
ENTRYPOINT ["/bin/entrypoint.sh"]

COPY ansible /opt/ansible

COPY snikket-modules /usr/local/lib/snikket-modules
COPY --from=coturn-build /out/usr/bin/turnserver /usr/bin/turnserver
COPY --from=prosodyx-build /rootfs/usr/ /usr/

# Required for idn2 to work, and probably generally good
ENV LANG=C.UTF-8

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        gpg gpg-agent \
        ansible python3-passlib \
        build-essential\
    && c_rehash \
    && ansible-playbook -c local -i localhost, --extra-vars "ansible_python_interpreter=/usr/bin/python3" /opt/ansible/snikket.yml \
    && apt-get remove --purge -y \
         ansible \
         gpg gpg-agent \
         python3-passlib \
         python3 python3-apt python3-minimal \
         python3.13 python3.13-minimal \
         libpython3-stdlib libpython3.13-minimal libpython3.13-stdlib \
         build-essential \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/cache/*

RUN echo "Snikket $BUILD_SERIES $BUILD_ID" > /usr/lib/prosody/snikket.version

VOLUME ["/snikket"]
