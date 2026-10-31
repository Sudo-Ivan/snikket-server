#!/opt/certbot/bin/python

import sys

import idna


try:
    print(idna.encode(sys.argv[1], uts46=True, std3_rules=True).decode("ascii"))
except (IndexError, idna.IDNAError) as error:
    print(error, file=sys.stderr)
    raise SystemExit(1)
