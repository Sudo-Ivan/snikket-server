# Working notes

## Layout

Monorepo of the four Snikket server components:

- `.` - snikket-server (Prosody + coturn + s6). `Dockerfile` at root runs
  `ansible/snikket.yml` inside the image.
- `web-portal/`, `web-proxy/`, `cert-manager/` - merged from the separate
  upstream repos, history preserved.

## Build

- `make images` builds all four; `make server|portal|proxy|certs` for one.
- `ENGINE=podman|docker` overrides engine auto-detection (podman preferred
  when both exist). `TAG=dev` sets the tag.
- Prosody version pins live in `ansible/snikket.yml`:
  `prosody.snapshot` (date of the trixie snapshots suite at
  packages.prosody.im) and `prosody_modules.revision` (hg rev of
  hg.prosody.im/prosody-modules).

## Test locally

- Build: `podman build -t snikket/snikket-server:dev .`
- Run: needs `SNIKKET_DOMAIN` + `SNIKKET_ADMIN_EMAIL` env and a certbot-style
  cert under `/snikket/letsencrypt/live/<domain>/` (self-signed works) in
  the `snikket_data` volume, else Prosody waits for certs forever.
- Rootless podman cannot bind ports <1024 unless
  `net.ipv4.ip_unprivileged_port_start` is lowered.
- Admin shell inside the container: `podman exec -it <ctr> prosodyctl shell`.
  Lines starting with `>` evaluate Lua; module events can be fired manually
  via `prosody.hosts["share.<dom>"].events.fire_event(...)`.

## Key env vars

- `SNIKKET_UPLOAD_FILE_SIZE_LIMIT_MB` - per-file upload limit (default 500).
- `SNIKKET_S3_*` - optional S3 backend for uploads, see
  `docs/advanced/s3_uploads.md`. Implemented by
  `snikket-modules/mod_http_upload_s3/`.

## CI

`.github/workflows/images.yml` builds all four images and pushes to
`ghcr.io/sudo-ivan/` with zstd layer compression. Actions are SHA-pinned.
