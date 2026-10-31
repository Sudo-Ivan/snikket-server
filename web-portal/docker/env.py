import os
import secrets
import sys

_secret_key_path = "/snikket/secret_key"


def store_secret_key(secret_key, mode):
    old_mask = os.umask(0o077)
    try:
        with open(_secret_key_path, mode) as f:
            f.write(secret_key)
        os.chmod(_secret_key_path, 0o600)
    finally:
        os.umask(old_mask)


if "SNIKKET_WEB_SECRET_KEY" in os.environ:
    print("Using SNIKKET_WEB_SECRET_KEY from environment")
    store_secret_key(os.environ["SNIKKET_WEB_SECRET_KEY"], "w")
    print("SNIKKET_WEB_SECRET_KEY persisted to", _secret_key_path)
else:
    try:
        with open(_secret_key_path, "r") as f:
            SNIKKET_WEB_SECRET_KEY = f.read()
        print("Restored SNIKKET_WEB_SECRET_KEY from", _secret_key_path)
    except FileNotFoundError:
        print("Generating SNIKKET_WEB_SECRET_KEY ...")
        SNIKKET_WEB_SECRET_KEY = secrets.token_urlsafe(nbytes=32)
        store_secret_key(SNIKKET_WEB_SECRET_KEY, "x")
        print("SNIKKET_WEB_SECRET_KEY persisted to", _secret_key_path)

# Ensure that the above output is printed, even if nothing else is.
sys.stdout.flush()
sys.stderr.flush()
