IMAGE ?= warp-docker
TAG ?= latest
PLATFORMS ?= linux/amd64,linux/arm64
SSSERVER_IMAGE ?= ghcr.io/shadowsocks/ssserver-rust:latest

.PHONY: build publish

build:
	docker build --build-arg SSSERVER_IMAGE=$(SSSERVER_IMAGE) -t $(IMAGE):$(TAG) .

publish:
	docker buildx build --platform $(PLATFORMS) --build-arg SSSERVER_IMAGE=$(SSSERVER_IMAGE) -t $(IMAGE):$(TAG) --push .
