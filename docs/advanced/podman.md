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
* Ports below 1024 (Snikket needs 80/443) require either a rootful
  container or lowering the unprivileged port limit:

  ```console
  sysctl net.ipv4.ip_unprivileged_port_start=80
  ```

* The container remaps the prosody user to the owner of the `/snikket`
  volume automatically (PUID/PGID handling in the entrypoint). With
  rootless Podman, named volumes are owned by your user, so no manual
  ownership fixups are needed.

## Docker-compatible tooling

Tools that expect a Docker socket can be pointed at the Podman API
socket:

```console
systemctl --user enable --now podman.socket
export DOCKER_HOST=unix:///run/user/$UID/podman/podman.sock
```
