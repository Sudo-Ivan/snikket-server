.PHONY: all images server portal proxy certs site

# Container engine: override with e.g. `make ENGINE=docker` or `make ENGINE=podman`
ENGINE ?= $(shell command -v podman >/dev/null 2>&1 && echo podman || echo docker)

TAG ?= dev

DOCS := $(docs/**.md)

all: images

images:
	$(ENGINE) build -t snikket/snikket-server:$(TAG) .
	$(ENGINE) build -t snikket/snikket-web-proxy:$(TAG) web-proxy
	$(ENGINE) build -t snikket/snikket-cert-manager:$(TAG) cert-manager
	$(ENGINE) build -t snikket/snikket-web-portal:$(TAG) web-portal

server:
	$(ENGINE) build -t snikket/snikket-server:$(TAG) .

portal:
	$(ENGINE) build -t snikket/snikket-web-portal:$(TAG) web-portal

proxy:
	$(ENGINE) build -t snikket/snikket-web-proxy:$(TAG) web-proxy

certs:
	$(ENGINE) build -t snikket/snikket-cert-manager:$(TAG) cert-manager

site: mkdocs.yml $(DOCS)
	echo $(DOCS)
	mkdocs build

docs/_po/snikket-server-docs.pot: po4a.conf $(DOCS)
	po4a \
	  --package-name snikket-server \
	  --package-version vcs \
	  --copyright-holder "Snikket Team <team@snikket.org>" \
	  po4a.conf
