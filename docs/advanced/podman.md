# Running with Podman

Snikket works under Podman as well as Docker. Three ways to run it are
described below.

## podman compose

The `docker-compose.yml` in this repository works unmodified with
`podman compose` (which shells out to `podman-compose` or
`docker-compose` against the Podman socket):

```console
cp snikket.conf.example snikket.conf
# edit snikket.conf
podman compose up -d
```

Build the images locally first if you are not using the prebuilt ones:

```console
make images ENGINE=podman
```

## Quadlet (systemd)

Quadlet units for all four services live in `contrib/podman/`. To install:

```console
mkdir -p ~/.config/containers/systemd/snikket
cp contrib/podman/*.{container,volume} ~/.config/containers/systemd/snikket/
cp snikket.conf.example ~/.config/containers/systemd/snikket/snikket.conf
# edit snikket.conf
systemctl --user daemon-reload
systemctl --user start snikket-server snikket-proxy snikket-certs snikket-portal
```

To run system-wide instead of per-user, place the units in
`/etc/containers/systemd/` and use `systemctl` without `--user`.

## Rootless notes

* `network_mode: host` / `Network=host` works in rootless Podman. The
  container binds ports directly on the host.
* The web proxy listens on ports 80 and 443 by default. Rootless Podman
  needs the host's unprivileged port threshold at 80 or lower:

  ```console
  sudo sysctl net.ipv4.ip_unprivileged_port_start=80
  ```

  This changes a host-wide setting. To keep the default threshold, put a
  host-level reverse proxy on ports 80 and 443, then set Snikket's HTTP and
  HTTPS ports above 1024.
* The portal and web proxy run as UID and GID 65532 with read-only root
  filesystems. The server and certificate manager start as container root to
  manage volume ownership and drop privileges for their services. In rootless
  Podman, container root maps to the invoking host user.
* The proxy mounts `snikket_data` read-only. The certificate manager grants
  group 65532 read access to the TLS private key so Nginx can load it.
* Coturn shares that group to read the certificate and stores its database in
  `/snikket/prosody/turnserver/turndb`. Older databases at
  `/snikket/prosody/turndb` are moved there automatically at startup.
* The container remaps the prosody user to the owner of the `/snikket`
  volume automatically (PUID/PGID handling in the entrypoint). With
  rootless Podman, named volumes are owned by your user, so no manual
  ownership fixups are needed.
* The portal session key is stored in a separate `portal_data` volume. Back it
  up with `snikket_data`. See the [upgrade steps](../setup/upgrading.md#preserve-the-portal-session-key)
  when replacing an older portal image.

## Docker-compatible tooling

Tools that expect a Docker socket can be pointed at the Podman API
socket:

```console
systemctl --user enable --now podman.socket
export DOCKER_HOST=unix:///run/user/$UID/podman/podman.sock
```
