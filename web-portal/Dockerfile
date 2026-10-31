FROM debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4 AS assets

ARG BUILD_SERIES=dev
ARG BUILD_ID=0

RUN set -eu; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        python3 python3-babel sassc make; \
    rm -rf /var/lib/apt/lists/*

COPY Makefile /opt/snikket-web-portal/Makefile
COPY snikket_web/ /opt/snikket-web-portal/snikket_web
COPY babel.cfg /opt/snikket-web-portal/babel.cfg

WORKDIR /opt/snikket-web-portal

RUN make

RUN echo "$BUILD_SERIES $BUILD_ID" > /opt/snikket-web-portal/.app_version \
    && mkdir -p /snikket \
    && chown 65532:65532 /snikket


FROM cgr.dev/chainguard/wolfi-base:latest@sha256:88a20e2d017bd20cdc0cb3910de603e7bea9512a6c351a8dd3c9df212ab03d73 AS dependencies

RUN apk add --no-cache python-3.13-dev=3.13.18_git20261030-r0

ENV VIRTUAL_ENV=/opt/snikket-venv

RUN python3.13 -m venv "$VIRTUAL_ENV"

COPY requirements.lock /tmp/requirements.lock

RUN "$VIRTUAL_ENV/bin/pip" install --no-cache-dir --require-hashes -r /tmp/requirements.lock \
    && "$VIRTUAL_ENV/bin/pip" uninstall -y setuptools \
    && rm -rf "$VIRTUAL_ENV/lib/python3.13/site-packages/pip" \
        "$VIRTUAL_ENV/lib/python3.13/site-packages/pip-"*.dist-info \
        "$VIRTUAL_ENV/bin/pip"*


FROM cgr.dev/chainguard/wolfi-base:latest@sha256:88a20e2d017bd20cdc0cb3910de603e7bea9512a6c351a8dd3c9df212ab03d73

RUN apk add --no-cache \
        ca-certificates-bundle=20261020-r0 \
        python-3.13=3.13.18_git20261030-r0

ENV VIRTUAL_ENV=/opt/snikket-venv \
    PATH=/opt/snikket-venv/bin:$PATH \
    PYTHONPATH=/opt/snikket-web-portal \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    SNIKKET_WEB_PYENV=/etc/snikket-web-portal/env.py \
    SNIKKET_WEB_PROSODY_ENDPOINT=http://127.0.0.1:5280/

WORKDIR /opt/snikket-web-portal

COPY --from=dependencies /opt/snikket-venv /opt/snikket-venv
COPY --from=assets /opt/snikket-web-portal/snikket_web/ /opt/snikket-web-portal/snikket_web/
COPY --from=assets /opt/snikket-web-portal/babel.cfg /opt/snikket-web-portal/babel.cfg
COPY --from=assets /opt/snikket-web-portal/.app_version /opt/snikket-web-portal/.app_version
COPY --from=assets --chown=65532:65532 /snikket /snikket
COPY docker/env.py /etc/snikket-web-portal/env.py
COPY docker/entrypoint.py /entrypoint.py

RUN chown -R 65532:65532 /opt/snikket-web-portal /opt/snikket-venv /etc/snikket-web-portal /entrypoint.py

USER 65532:65532

ENTRYPOINT ["/usr/bin/python3.13", "/entrypoint.py"]
