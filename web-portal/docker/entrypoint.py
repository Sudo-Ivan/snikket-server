import os


os.environ["SNIKKET_WEB_DOMAIN"] = os.environ.get("SNIKKET_DOMAIN", "")
if os.environ.get("SNIKKET_SITE_NAME"):
    os.environ["SNIKKET_WEB_SITE_NAME"] = os.environ["SNIKKET_SITE_NAME"]
for target, source in {
    "SNIKKET_WEB_TOS_URI": "SNIKKET_TOS_URI",
    "SNIKKET_WEB_PRIVACY_URI": "SNIKKET_PRIVACY_URI",
    "SNIKKET_WEB_ABUSE_EMAIL": "SNIKKET_ABUSE_EMAIL",
    "SNIKKET_WEB_SECURITY_EMAIL": "SNIKKET_SECURITY_EMAIL",
}.items():
    os.environ[target] = os.environ.get(source, "")

os.environ.setdefault("SNIKKET_TWEAK_PORTAL_INTERNAL_HTTP_INTERFACE", "127.0.0.1")
os.environ.setdefault("SNIKKET_TWEAK_PORTAL_INTERNAL_HTTP_PORT", "5765")

bind = "{}:{}".format(
    os.environ["SNIKKET_TWEAK_PORTAL_INTERNAL_HTTP_INTERFACE"],
    os.environ["SNIKKET_TWEAK_PORTAL_INTERNAL_HTTP_PORT"],
)
python = os.path.join(os.environ["VIRTUAL_ENV"], "bin", "python")
os.execv(
    python,
    [
        python,
        "-m",
        "hypercorn",
        "-b",
        bind,
        "--access-logfile=-",
        "--log-file=-",
        "snikket_web:create_app()",
    ],
)
