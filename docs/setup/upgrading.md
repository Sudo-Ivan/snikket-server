---
title: Upgrading your Snikket instance
linktitle: Upgrading
description: "Upgrading your Snikket instance is easy."
date: 2021-05-19T14:32:02Z
weight: 20
---

We periodically announce new releases of the Snikket server software on our
[blog][], [Mastodon][] and [Twitter][]. You will also receive [update
notifications][] directly from your instance when it is time to upgrade.

Upgrading to a new Snikket release is typically very easy. The correct process
to use depends on the method you initially used to set up your Snikket
instance. Each method is explained here.


{{< panel style="warning" >}}
**Compatibility notes**

If your system matches *any* of the following descriptions, please check
the [host system compatibility](../troubleshooting/#host-compatibility)
section of the troubleshooting guide before you upgrade:

- ARM or Raspberry Pi devices running Debian or Raspbian 10 ("buster") or older
- Docker version 20.10.9 or earlier
{{< /panel >}}

## Upgrading

### TURN database location

If `/snikket/prosody/turndb` exists, the server moves it to
`/snikket/prosody/turnserver/turndb` at startup. No manual migration step is
needed.

### Account data import and export

The ProsodyX server build disables XEP-0227 account data import and export.
This affects moving contacts, profiles, and personal event data through the
portal. Existing account data remains in the server's live stores.

### Preserve the portal session key

The new portal image stores its session key in the `portal_data` volume. Older
images stored the key in the container filesystem. If
`SNIKKET_WEB_SECRET_KEY` is already set in `snikket.conf`, keep it through the
first start of the new image. Otherwise, copy the old key before replacing the
portal container:

```console
docker cp snikket-portal:/etc/snikket-web-portal/secret_key "$HOME/portal-secret-key"
chmod 600 "$HOME/portal-secret-key"
```

With Podman, use `podman cp` instead of `docker cp`.

Add the key to `snikket.conf`:

```console
printf '\nSNIKKET_WEB_SECRET_KEY=%s\n' "$(cat "$HOME/portal-secret-key")" >> snikket.conf
chmod 600 snikket.conf
```

With Docker Compose, pull and start the new images:

```console
docker compose pull
docker compose up -d
docker compose logs snikket_portal
```

With Podman Compose, use `podman compose pull` and `podman compose up -d`. For
Quadlet, copy the updated files from
`contrib/podman/` to your Quadlet directory. Pull all four images, then reload
systemd and restart the services:

```console
podman pull ghcr.io/sudo-ivan/snikket-server:edge
podman pull ghcr.io/sudo-ivan/snikket-web-proxy:edge
podman pull ghcr.io/sudo-ivan/snikket-cert-manager:edge
podman pull ghcr.io/sudo-ivan/snikket-web-portal:edge
systemctl --user daemon-reload
systemctl --user restart snikket-server snikket-proxy snikket-certs snikket-portal
journalctl --user -u snikket-portal
```

After the portal logs show `SNIKKET_WEB_SECRET_KEY persisted to /snikket/secret_key`,
remove the `SNIKKET_WEB_SECRET_KEY` line from `snikket.conf` and restart the
portal:

```console
sed -i '/^SNIKKET_WEB_SECRET_KEY=/d' snikket.conf
docker compose up -d snikket_portal
rm "$HOME/portal-secret-key"
```

With Podman Compose, use `podman compose up -d snikket_portal`. With Quadlet,
restart `snikket-portal` with systemd after removing the key from the
environment file.

The volume now preserves the same key across container replacements. Back up
`portal_data` with `snikket_data`. If you do not copy the key, existing browser
sessions will need to sign in again.

### Snikket quick-start

If you are using a version installed from the [original quick-start][] guide
on the website (most likely), then use these commands:

```
    cd /etc/snikket
    docker compose pull
    docker compose up -d
```

### snikket-selfhosted

If you installed Snikket using the [snikket-selfhosted][] repository, simply
run:

```
    cd /opt/snikket
    git pull
    ./scripts/update.sh
```

### Snikket hosting

If you're using our hosting service, you can upgrade by visiting your
[hosting dashboard][] and clicking the 'Update' button next to your instance.

**Note:** Updates are not always available on the hosted platform immediately
after release. If the 'Update' button is not present, try again later.
Typically you will receive a notification when an update is available.

## Check your version

There are several ways to check the version of the Snikket server you are
currently using:

### Using the web interface

1. Log into the web interface using your admin account
2. In the footer of the page click on "Snikket service"
3. Scroll to the section "Software versions"

### Using the command-line

SSH into the system where Snikket is installed, and run the following command:

```shell
docker exec snikket prosodyctl about | head -n1
```

[snikket-selfhosted]: https://github.com/snikket-im/snikket-selfhosted
[original quick-start]: https://snikket.org/service/quickstart/
[hosting dashboard]: https://my.snikket.org/
[blog]: https://snikket.org/blog/
[Mastodon]: https://fosstodon.org/@snikket_im
[Twitter]: https://twitter.com/snikket_im
[update notifications]: ../../advanced/update_notifications/
