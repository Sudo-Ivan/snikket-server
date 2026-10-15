# Snikket server images

This monorepo builds the container images for a self-hosted
[Snikket service](https://snikket.org/service/):

| Directory | Image | Purpose |
| --- | --- | --- |
| `.` | `snikket-server` | Prosody XMPP server, coturn, s6 init |
| `web-proxy/` | `snikket-web-proxy` | nginx frontend |
| `cert-manager/` | `snikket-cert-manager` | Let's Encrypt certificate automation |
| `web-portal/` | `snikket-web-portal` | Web admin portal |

Snikket is an open-source self-hosted personal messaging service. It aims to
provide an alternative to proprietary and centralized messaging platforms
while supporting all the expected features and being easy to use.

For more information see the [Snikket website](https://snikket.org/).

## Differences from upstream

* File upload limit raised to 500MB
  (`SNIKKET_UPLOAD_FILE_SIZE_LIMIT_MB` overrides it).
* Optional S3 storage backend for file uploads - clients upload
  directly to object storage via presigned URLs. See
  `docs/advanced/s3_uploads.md`.
* All server components in one repository.
* Podman support: the Makefile auto-detects podman, the compose file
  works with `podman compose`, and Quadlet units ship in
  `contrib/podman/`. See `docs/advanced/podman.md`.
* Images publish to `ghcr.io/sudo-ivan/` with zstd layer compression
  via GitHub Actions (`.github/workflows/images.yml`).

## Getting Started with Snikket

For instructions on getting started with Snikket, see the [Snikket installation
guide](https://snikket.org/service/quickstart/) on our website.

## Building images

### Requirements

 - GNU make
 - podman (tested on 6.x) or docker
 - ansible (build-time only, runs inside the image build)

### Building

Run `make` to build all images, or `make server`, `make portal`,
`make proxy`, `make certs` for individual ones. The container engine is
auto-detected; force it with `make ENGINE=docker` or
`make ENGINE=podman`.

### Running

The easiest way is compose. Copy `snikket.conf.example` to
`snikket.conf` and edit the values in it. Then run:

```console
podman compose up -d
```

or `docker compose up -d`. For systemd-native deployment without
compose, see the Quadlet units in `contrib/podman/` and
`docs/advanced/podman.md`.
