# S3 file uploads

By default, files shared by users are stored on the server's filesystem
in the `snikket_data` volume and served by Prosody's built-in HTTP
server (`mod_http_file_share`).

As an alternative, uploads can be stored in S3-compatible object
storage. In this mode Prosody issues XEP-0363 upload slots whose PUT
URL is a presigned S3 URL, so clients upload directly to the bucket.
Nothing is stored or proxied through Prosody.

## Configuration

Set `SNIKKET_S3_BUCKET` to enable S3 uploads. The following environment
variables configure it (all go in `snikket.conf`):

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `SNIKKET_S3_BUCKET` | yes | - | Bucket name. Presence enables S3 uploads. |
| `SNIKKET_S3_ACCESS_KEY` | yes* | - | Access key ID. |
| `SNIKKET_S3_SECRET_KEY` | yes* | - | Secret access key. |
| `SNIKKET_S3_REGION` | no | `us-east-1` | Signing region. |
| `SNIKKET_S3_ENDPOINT` | no | `https://s3.{region}.amazonaws.com` | API endpoint URL. |
| `SNIKKET_S3_PATH_STYLE` | no | `0` | `1` for path-style URLs (needed by MinIO). |
| `SNIKKET_S3_PUBLIC_URL` | no | - | Base URL for GET links (e.g. a CDN URL or public bucket endpoint). |
| `SNIKKET_S3_PREFIX` | no | - | Optional prefix prepended to all object keys. |
| `SNIKKET_S3_PUT_EXPIRY` | no | `3600` | PUT URL validity in seconds (max 604800). |
| `SNIKKET_S3_GET_EXPIRY` | no | `604800` | Presigned GET validity in seconds (max 604800, i.e. 7 days). |

\* Instead of environment variables, keys may be placed in the files
`/snikket/prosody/s3-access-key` and `/snikket/prosody/s3-secret-key`
inside the snikket_data volume.

Example (MinIO):

```
SNIKKET_S3_BUCKET=snikket-uploads
SNIKKET_S3_ENDPOINT=https://minio.example.com
SNIKKET_S3_PATH_STYLE=1
SNIKKET_S3_REGION=us-east-1
SNIKKET_S3_ACCESS_KEY=AKIA...
SNIKKET_S3_SECRET_KEY=...
SNIKKET_S3_PUBLIC_URL=https://files.example.com
```

## GET URLs and expiry

* If `SNIKKET_S3_PUBLIC_URL` is set, download links are
  `{public_url}/{object key}` and never expire. Point it at a CDN, a
  public-read bucket, or a reverse proxy in front of the bucket.
* Without a public URL, GET links are presigned and expire after
  `SNIKKET_S3_GET_EXPIRY` seconds. SigV4 presigned URLs are limited to
  7 days maximum, so a public URL is strongly recommended for file
  sharing.

## Caveats

* **Deletion/retention:** Prosody cannot delete files from S3, so the
  `SNIKKET_RETENTION_DAYS` cleanup does not apply. Configure a bucket
  lifecycle rule to expire objects instead.
* **Quotas:** `SNIKKET_UPLOAD_STORAGE_GB` and
  `SNIKKET_DAILY_UPLOAD_LIMIT_PER_USER_GB` are not enforced in S3 mode.
* **Size limit:** the per-file size limit is enforced when issuing the
  slot (`SNIKKET_UPLOAD_FILE_SIZE_LIMIT_MB`, default 500).
* Objects are stored under `PREFIX/HOST/YYYY-MM-DD/UUID/filename`.
  Filenames are sanitized to `[A-Za-z0-9._-]`.
