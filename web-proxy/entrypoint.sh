#!/bin/bash

export SNIKKET_DOMAIN_ASCII=$(idn2 "$SNIKKET_DOMAIN")

mkdir -p /tmp/www /tmp/nginx/sites-enabled /tmp/nginx/snippets /tmp/sv \
	/tmp/nginx/client_body /tmp/nginx/proxy /tmp/nginx/fastcgi \
	/tmp/nginx/uwsgi /tmp/nginx/scgi
cp -R /var/www/html/static /var/www/html/_errors /tmp/www/
cp /var/www/html/index.html /tmp/www/index.html
cp -R /etc/sv/. /tmp/sv/
chmod -R u+rwX /tmp/sv

CERT_PATH="/snikket/letsencrypt/live/$SNIKKET_DOMAIN_ASCII/fullchain.pem"

PROTOS="${SNIKKET_TWEAK_WEB_PROXY_PROTOS:-http https}"

if test -f "$CERT_PATH"; then
	## Certs already exist - render and deploy configs
	/usr/local/bin/render-template.sh "/etc/nginx/templates/snikket-common" "/tmp/nginx/snippets/snikket-common.conf"
	for proto in $PROTOS; do
		/usr/local/bin/render-template.sh "/etc/nginx/templates/$proto" "/tmp/nginx/sites-enabled/$proto";
	done
else
	/usr/local/bin/render-template.sh "/etc/nginx/templates/startup" "/tmp/nginx/sites-enabled/startup";
fi

exec s6-svscan /tmp/sv
