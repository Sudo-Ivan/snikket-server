#!/bin/sh

if [ -z "$SNIKKET_DOMAIN" ]; then
  echo "Please provide SNIKKET_DOMAIN";
  exit 1;
fi

export SNIKKET_DOMAIN_ASCII=$(idn2 "$SNIKKET_DOMAIN")

if [ -z "$SNIKKET_ADMIN_EMAIL" ]; then
  echo "Please provide SNIKKET_ADMIN_EMAIL";
  exit 1;
fi

if [ -z "$SNIKKET_SMTP_URL" ]; then
	SNIKKET_SMTP_URL="smtp://localhost:1025/;no-tls"
fi

echo "$SNIKKET_SMTP_URL" | smtp-url-to-msmtp > /etc/msmtprc

echo "from snikket@$SNIKKET_DOMAIN_ASCII" >> /etc/msmtprc

unset SNIKKET_SMTP_URL

PUID=${PUID:=$(stat -c %u /snikket)}
PGID=${PGID:=$(stat -c %g /snikket)}

if [ "$PUID" != 0 ] && [ "$PGID" != 0 ]; then
	usermod  -o -u "$PUID" prosody
	groupmod -o -g "$PGID" prosody
fi

if ! test -d /snikket/prosody; then
	install -o prosody -g prosody -m 750 -d /snikket/prosody;
fi

chown -R prosody:prosody /var/spool/anacron /var/run/prosody /snikket/prosody /etc/prosody

## Give the TURN service access only to its own database and shared TLS keys
chgrp turnserver /snikket/prosody
chmod 0710 /snikket/prosody
install -d -o turnserver -g turnserver -m 0700 /snikket/prosody/turnserver
chown turnserver:turnserver /snikket/prosody/turnserver
chmod 0700 /snikket/prosody/turnserver
if test -f /snikket/prosody/turndb && ! test -e /snikket/prosody/turnserver/turndb; then
	mv /snikket/prosody/turndb /snikket/prosody/turnserver/turndb
fi
if test -f /snikket/prosody/turnserver/turndb; then
	chown turnserver:turnserver /snikket/prosody/turnserver/turndb
	chmod 0600 /snikket/prosody/turnserver/turndb
fi

for path in /snikket/letsencrypt /snikket/letsencrypt/live \
  /snikket/letsencrypt/archive /snikket/letsencrypt/live/* \
  /snikket/letsencrypt/archive/*; do
	if [ -d "$path" ]; then
		chgrp 65532 "$path"
		chmod 0750 "$path"
	fi
done

for cert in /snikket/letsencrypt/live/*/fullchain.pem \
	  /snikket/letsencrypt/archive/*/fullchain*.pem \
	  /snikket/letsencrypt/live/*/privkey.pem \
	  /snikket/letsencrypt/archive/*/privkey*.pem; do
	if [ -f "$cert" ]; then
		chgrp 65532 "$cert"
		chmod 0640 "$cert"
	fi
done

## Generate secret for coturn auth if necessary
if ! test -f /snikket/prosody/turn-auth-secret-v2; then
	head -c 32 /dev/urandom | base64 > /snikket/prosody/turn-auth-secret-v2;
fi

## Generate OAuth2 registration secret if necessary
if ! test -f /snikket/prosody/oauth2-registration-secret; then
	head -c 32 /dev/urandom | base64 > /snikket/prosody/oauth2-registration-secret;
fi

# COMPAT w/ alpha.20200513: remove older format
if test -f /snikket/prosody/turn-auth-secret; then
	rm /snikket/prosody/turn-auth-secret;
fi

# Migrate between storage backends if needed
# Note: this happens before we do any other operations that touch Prosody's
# data store, to ensure consistency.

if test "${SNIKKET_TWEAK_STORAGE:-files}" = "sqlite" && ! test -f /snikket/prosody/prosody.sqlite; then
	sed -i "s/SNIKKET_DOMAIN/$SNIKKET_DOMAIN/" /etc/prosody/migrator.cfg.lua
	if prosody-migrator files sqlite; then
		# Migration succeeded, delete leftovers
		find /snikket/prosody -mindepth 2 -maxdepth 3 -type f \( -name \*.dat -o -name \*.list -o -name \*.lidx \) -delete
		find /snikket/prosody -mindepth 1 -type d -empty -delete
	else
		# Migration failed, delete sqlite file and try again
		rm -fv /snikket/prosody/prosody.sqlite
		exit 1
	fi
elif test "${SNIKKET_TWEAK_STORAGE:-files}" = "files" && test -f /snikket/prosody/prosody.sqlite; then
	sed -i "s/SNIKKET_DOMAIN/$SNIKKET_DOMAIN/" /etc/prosody/migrator.cfg.lua
	if prosody-migrator sqlite files; then
		# Migration succeeded, delete leftover database
		rm -fv /snikket/prosody/prosody.sqlite
	else
		# Migration failed, delete files and try again
		find /snikket/prosody -mindepth 2 -maxdepth 3 -type f \( -name \*.dat -o -name \*.list -o -name \*.lidx \) -delete
		find /snikket/prosody -mindepth 1 -type d -empty -delete
		exit 1
	fi
fi

if test -d /snikket/prosody/http_upload; then
	prosodyctl mod_migrate_http_upload "share.$SNIKKET_DOMAIN" "$SNIKKET_DOMAIN"
fi

# COMPAT: migrate from 0.12 series role storage
if ! test -d /snikket/prosody/*/account_roles; then
	prosodyctl mod_authz_internal migrate "$SNIKKET_DOMAIN"
fi

# Migrate from prosody:normal to prosody:registered
prosodyctl mod_migrate_snikket_roles migrate "$SNIKKET_DOMAIN"

exec s6-svscan /etc/sv
