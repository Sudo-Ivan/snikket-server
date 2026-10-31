FROM debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4 AS browser-assets

RUN set -eu; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get install -y --no-install-recommends libjs-bootstrap4 libjs-jquery; \
    rm -rf /var/lib/apt/lists/*


FROM cgr.dev/chainguard/wolfi-base:latest@sha256:88a20e2d017bd20cdc0cb3910de603e7bea9512a6c351a8dd3c9df212ab03d73

ARG BUILD_SERIES=dev
ARG BUILD_ID=0

RUN apk add --no-cache \
        bash=5.3-r14 \
        gettext=1.0-r8 \
        nginx-mainline=1.31.8-r1 \
        py3.13-idna=3.20-r0 \
        python-3.13=3.13.18_git20261030-r0 \
        s6=2.15.1.1-r0 \
        tini=0.19.0-r26

ENV LANG=C.UTF-8

VOLUME ["/snikket"]

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/bin/bash", "/entrypoint.sh"]

COPY entrypoint.sh /entrypoint.sh
COPY render-template.sh /usr/local/bin/render-template.sh
COPY tools/idn2.py /usr/local/bin/idn2
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/snikket-common.template /etc/nginx/templates/snikket-common
COPY nginx/startup.template /etc/nginx/templates/startup
COPY nginx/http.template /etc/nginx/templates/http
COPY nginx/https.template /etc/nginx/templates/https
COPY service /etc/sv
COPY static /var/www/html/static
COPY startup.html /var/www/html/index.html
COPY error-pages /var/www/html/_errors
COPY --from=browser-assets /usr/share/javascript/ /usr/share/javascript/

RUN chmod 555 /entrypoint.sh /usr/local/bin/render-template.sh \
      /usr/local/bin/idn2 /etc/sv/*/run \
    && chmod -R a+rX /etc/nginx/templates /var/www/html /etc/sv /usr/share/javascript

USER 65532:65532
