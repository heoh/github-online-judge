FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ARG ISOLATE_VERSION=v2.2.1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      bash \
      coreutils \
      g++ \
      jq \
      python3 \
      python3-pip \
      time \
      git \
      make \
      pkg-config \
      libcap-dev \
      libsystemd-dev \
    && update-ca-certificates \
    && git clone --depth 1 --branch "$ISOLATE_VERSION" https://github.com/ioi/isolate.git /tmp/isolate-src \
    && make -C /tmp/isolate-src CONFIGDIR=/etc isolate isolate-check-environment isolate-cg-keeper \
    && make -C /tmp/isolate-src install PREFIX=/usr VARPREFIX=/var CONFIGDIR=/etc \
    && rm -rf /tmp/isolate-src \
    && apt-get purge -y --auto-remove \
      git \
      make \
      pkg-config \
      libcap-dev \
      libsystemd-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /box
