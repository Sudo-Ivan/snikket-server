FROM cgr.dev/chainguard/wolfi-base:latest@sha256:88a20e2d017bd20cdc0cb3910de603e7bea9512a6c351a8dd3c9df212ab03d73 AS certbot-build

RUN apk add --no-cache python-3.13-dev=3.13.18_git20261030-r0

RUN python3.13 -m venv /opt/certbot

COPY requirements.lock /tmp/requirements.lock

RUN /opt/certbot/bin/pip install --no-cache-dir --require-hashes -r /tmp/requirements.lock \
    && /opt/certbot/bin/pip uninstall -y setuptools \
    && rm -rf /opt/certbot/lib/python3.13/site-packages/pip \
        /opt/certbot/lib/python3.13/site-packages/pip-*.dist-info \
        /opt/certbot/bin/pip*


FROM cgr.dev/chainguard/wolfi-base:latest@sha256:88a20e2d017bd20cdc0cb3910de603e7bea9512a6c351a8dd3c9df212ab03d73

ARG BUILD_SERIES=dev
ARG BUILD_ID=0

RUN apk add --no-cache \
        bash=5.3-r14 \
        coreutils=9.12-r7 \
        curl=8.23.0-r2 \
        findutils=4.11.0-r5 \
        grep=3.12-r11 \
        jq=1.8.2-r3 \
        python-3.13=3.13.18_git20261030-r0 \
        sed=4.10-r5 \
        shadow=4.20.3-r3 \
        tini=0.19.0-r26

ENV PATH=/opt/certbot/bin:$PATH \
    SNIKKET_CERT_PROXY_GID=65532

VOLUME ["/snikket"]

COPY --from=certbot-build /opt/certbot /opt/certbot
COPY entrypoint.sh /entrypoint.sh
COPY certbot.cron /etc/cron.daily/certbot
COPY sendmail /usr/sbin/sendmail
COPY wait_for_http.py /usr/local/bin/wait_for_http.py
COPY tools/idn2.py /usr/local/bin/idn2
COPY tools/report-error.sh /usr/local/bin/report-error.sh

RUN chmod 555 /entrypoint.sh /etc/cron.daily/certbot /usr/sbin/sendmail \
      /usr/local/bin/idn2 /usr/local/bin/report-error.sh \
      /usr/local/bin/wait_for_http.py \
    && useradd -md /snikket/letsencrypt letsencrypt

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/bin/bash", "/entrypoint.sh"]
