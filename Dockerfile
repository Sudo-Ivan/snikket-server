FROM debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4 AS coturn-source

RUN set -eux; \
    printf 'deb-src http://deb.debian.org/debian forky main\n' > /etc/apt/sources.list.d/forky-src.list; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates dpkg-dev; \
    cd /tmp; \
    apt-get source coturn=4.18.0-1; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/*


FROM cgr.dev/chainguard/wolfi-base:latest@sha256:73f2cab0f11208427595d4bdd784046bc4116ef7cc52f0c1b48b6b7f820288d5 AS coturn-build

RUN apk add --no-cache \
        build-base=1-r10 \
        coreutils=9.12-r7 \
        libevent-dev=2.1.13-r3 \
        openssl-dev=3.6.5-r6 \
        pkgconf=3.0.10-r2 \
        sqlite-dev=3.54.1-r0

COPY --from=coturn-source /tmp/coturn-4.18.0 /src/coturn

RUN set -eux; \
    cd /src/coturn; \
    env CPPFLAGS="-D_FORTIFY_SOURCE=3" \
        CFLAGS="-O2 -fstack-protector-strong -D_FORTIFY_SOURCE=3" \
        LDFLAGS="-Wl,-z,relro,-z,now" \
    TURN_NO_MYSQL=1 TURN_NO_PQ=1 TURN_NO_MONGO=1 TURN_NO_HIREDIS=1 \
        TURN_NO_SYSTEMD=1 ./configure --prefix=/usr --disable-rpath; \
    make -j"$(nproc)"; \
    if readelf -d bin/turnserver | grep -Eq 'NEEDED.*(mariadb|pq|hiredis)'; then exit 1; fi; \
    strip --strip-unneeded bin/turnserver; \
    install -D -m 0755 bin/turnserver /out/usr/bin/turnserver; \
    rm -rf /src/coturn


FROM debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4 AS lua-deps-source

RUN set -eux; \
    printf 'deb-src http://deb.debian.org/debian trixie main\n' > /etc/apt/sources.list.d/src.list; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends dpkg-dev; \
    cd /tmp; \
    apt-get source lua-dbi=0.7.4-1; \
    apt-get source lua-lsqlite3=0.9.6-1; \
    apt-get source lua-unbound=1.0.0-2; \
    apt-get source lua-readline=3.3-3; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/*


FROM cgr.dev/chainguard/wolfi-base:latest@sha256:73f2cab0f11208427595d4bdd784046bc4116ef7cc52f0c1b48b6b7f820288d5 AS prosodyx-build

RUN apk add --no-cache \
        build-base=1-r10 \
        ca-certificates-bundle=20261020-r0 \
        coreutils=9.12-r7 \
        curl=8.23.0-r3 \
        expat-dev=2.9.0-r0 \
        git=2.56.0-r3 \
        icu-dev=79.1-r0 \
        lua5.4=5.4.9-r2 \
        lua5.4-dev=5.4.9-r2 \
        openssl-dev=3.6.5-r6 \
        pkgconf=3.0.10-r2 \
        readline-dev=8.3-r3 \
        sqlite-dev=3.54.1-r0 \
        unbound-dev=1.25.1-r1

COPY --from=lua-deps-source /tmp/lua-dbi-0.7.4 /build/lua-dbi
COPY --from=lua-deps-source /tmp/lua-lsqlite3-0.9.6 /build/lua-lsqlite3
COPY --from=lua-deps-source /tmp/lua-unbound-1.0.0 /build/lua-unbound
COPY --from=lua-deps-source /tmp/lua-readline-3.3 /build/lua-readline

RUN set -eux; \
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
        LUACPATH=/rootfs/usr/lib/lua/5.4; \
    mkdir -p /rootfs/usr/share/lua/5.4 /rootfs/usr/lib/lua/5.4; \
    make -C /build/lua-dbi install_sqlite3 \
        LUA_V=5.4 LUA_LDIR=/rootfs/usr/share/lua/5.4 \
        LUA_CDIR=/rootfs/usr/lib/lua/5.4 LUA_INC=-I/usr/include/lua5.4 \
        COMMON_CFLAGS="$HARDEN_CFLAGS -fPIC -DPIC -std=c99" \
        LDFLAGS="$HARDEN_LDFLAGS"; \
    gcc -shared -fPIC $HARDEN_CFLAGS -I/usr/include/lua5.4 \
        -DLSQLITE_VERSION='"0.9.6"' \
        -o /rootfs/usr/lib/lua/5.4/lsqlite3.so \
        /build/lua-lsqlite3/lsqlite3.c -lsqlite3 $HARDEN_LDFLAGS; \
    make -C /build/lua-unbound all LUA_VERSION=5.4 LUA_PC=lua5.4 LD=gcc \
        LUA_LIBDIR=/usr/lib/lua/5.4 MYCFLAGS="$HARDEN_CFLAGS" \
        MYLDFLAGS="$HARDEN_LDFLAGS"; \
    make -C /build/lua-unbound install LUA_VERSION=5.4 LUA_PC=lua5.4 LD=gcc \
        LUA_LIBDIR=/usr/lib/lua/5.4 DESTDIR=/rootfs; \
    gcc -shared -fPIC $HARDEN_CFLAGS -I/usr/include/lua5.4 \
        -o /rootfs/usr/lib/lua/5.4/C-readline.so \
        /build/lua-readline/C-readline.c -lreadline $HARDEN_LDFLAGS; \
    install -m 0644 /build/lua-readline/readline.lua \
        /rootfs/usr/share/lua/5.4/readline.lua; \
    strip --strip-unneeded /rootfs/usr/lib/lua/5.4/dbd/sqlite3.so \
        /rootfs/usr/lib/lua/5.4/lsqlite3.so \
        /rootfs/usr/lib/lua/5.4/lunbound.so \
        /rootfs/usr/lib/lua/5.4/C-readline.so

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
    rm -rf /var/cache/apk/* /build /src/prosodyx


FROM debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4 AS server-config

ARG BUILD_SERIES=dev
ARG BUILD_ID=0

# Install dependencies

RUN install -d -m 755 /snikket;

COPY tools/smtp-url-to-msmtp.lua /usr/local/bin/smtp-url-to-msmtp
RUN chmod 550 /usr/local/bin/smtp-url-to-msmtp

COPY docker/entrypoint.sh /bin/entrypoint.sh
RUN chmod 770 /bin/entrypoint.sh

COPY ansible /opt/ansible

COPY snikket-modules /usr/local/lib/snikket-modules
COPY --from=coturn-build /out/usr/bin/turnserver /usr/bin/turnserver
COPY --from=prosodyx-build /rootfs/usr/ /usr/

# Required for idn2 to work, and probably generally good
ENV LANG=C.UTF-8

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        ansible python3-passlib \
        build-essential\
    && c_rehash \
    && ansible-playbook -c local -i localhost, --extra-vars "ansible_python_interpreter=/usr/bin/python3" /opt/ansible/snikket.yml \
    && apt-get remove --purge -y \
         ansible \
         python3-passlib \
         python3 python3-apt python3-minimal \
         python3.13 python3.13-minimal \
         libpython3-stdlib libpython3.13-minimal libpython3.13-stdlib \
         build-essential \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/cache/*

RUN echo "Snikket $BUILD_SERIES $BUILD_ID" > /usr/lib/prosody/snikket.version


FROM cgr.dev/chainguard/wolfi-base:latest@sha256:73f2cab0f11208427595d4bdd784046bc4116ef7cc52f0c1b48b6b7f820288d5 AS runtime

ENV LANG=C.UTF-8

RUN apk add --no-cache \
        bash=5.3-r14 \
        ca-certificates-bundle=20261020-r0 \
        coreutils=9.12-r7 \
        curl=8.23.0-r3 \
        findutils=4.11.0-r5 \
        grep=3.12-r11 \
        idn2-utils=2.3.8-r12 \
        jq=1.8.2-r3 \
        libevent=2.1.13-r3 \
        libexpat1=2.9.0-r0 \
        libicu79=79.1-r0 \
        lua5.4=5.4.9-r2 \
        msmtp=1.8.34-r1 \
        openssl=3.6.5-r6 \
        procps=4.0.7-r3 \
        qrencode=4.1.1-r3 \
        readline=8.3-r3 \
        s6=2.15.1.1-r0 \
        sed=4.10-r5 \
        shadow=4.20.3-r3 \
        sqlite-libs=3.54.1-r0 \
        su-exec=0.3-r4 \
        unbound-libs=1.25.1-r1 \
        zlib=1.3.2.1_rc20260921-r1 \
        zstd=1.5.7-r12

COPY --from=prosodyx-build /rootfs/usr/bin/ /usr/bin/
COPY --from=prosodyx-build /rootfs/usr/lib/lua/ /usr/lib/lua/
COPY --from=prosodyx-build /rootfs/usr/lib/prosody/ /usr/lib/prosody/
COPY --from=prosodyx-build /rootfs/usr/share/lua/ /usr/share/lua/
COPY --from=server-config /usr/lib/prosody/modules/ /usr/lib/prosody/modules/
COPY --from=server-config /usr/lib/prosody/snikket.version /usr/lib/prosody/snikket.version
COPY --from=server-config /etc/prosody/ /etc/prosody/
COPY --from=server-config /etc/sv/ /etc/sv/
COPY --from=server-config /etc/cron.daily/refresh-certs /etc/cron.daily/refresh-certs
COPY --from=server-config /etc/msmtprc /etc/msmtprc
COPY --from=server-config /etc/turnserver.conf /etc/turnserver.conf
COPY --from=server-config /bin/entrypoint.sh /bin/entrypoint.sh
COPY --from=server-config /usr/local/bin/ /usr/local/bin/
COPY --from=server-config /usr/local/lib/prosody-modules/ /usr/local/lib/prosody-modules/
COPY --from=server-config /usr/local/lib/snikket-modules/ /usr/local/lib/snikket-modules/
COPY --from=server-config /usr/local/share/snikket/ /usr/local/share/snikket/
COPY --from=server-config /usr/share/dns/root.ds /usr/share/dns/root.ds
COPY --from=coturn-build /out/usr/bin/turnserver /usr/bin/turnserver

RUN set -eux; \
    groupadd -g 999 prosody; \
    useradd -u 999 -g prosody -d /var/lib/prosody -M -s /sbin/nologin prosody; \
    useradd -u 998 -g nonroot -d / -M -s /sbin/nologin turnserver; \
    mkdir -p /snikket /etc/cron.daily /var/run/prosody /var/tmp /usr/sbin; \
    chmod 1777 /var/tmp; \
    ln -sfn /usr/bin/lua5.4 /usr/bin/lua; \
    ln -sfn /usr/bin/msmtp /usr/sbin/sendmail

VOLUME ["/snikket"]

ENTRYPOINT ["/bin/entrypoint.sh"]
