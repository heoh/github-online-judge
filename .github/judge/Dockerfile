FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      gnupg \
      apt-transport-https \
    && update-ca-certificates \
    && install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL https://www.ucw.cz/isolate/debian/signing-key.asc -o /etc/apt/keyrings/isolate.asc \
    && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/isolate.asc] http://www.ucw.cz/isolate/debian/ bookworm-isolate main" > /etc/apt/sources.list.d/isolate.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
      bash \
      coreutils \
      g++ \
      isolate \
      jq \
      python3 \
      python3-pip \
      time \
    && apt-get purge -y --auto-remove gnupg apt-transport-https \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /box
