FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      coreutils \
      g++ \
      isolate \
      jq \
      python3 \
      python3-pip \
      time \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /box
