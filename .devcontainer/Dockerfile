# syntax=docker/dockerfile:1.7

FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

COPY --from=ghcr.io/astral-sh/uv:0.10.4 /uv /usr/local/bin/uv

ARG USERNAME=vscode
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/usr/local/bin:${PATH}

COPY toolchain-versions.sh /tmp/devcontainer/toolchain-versions.sh
COPY install-toolchain.sh /tmp/devcontainer/install-toolchain.sh

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bats \
        bash-completion \
        build-essential \
        ca-certificates \
        curl \
        dnsutils \
        file \
        git \
        gnupg \
        iproute2 \
        iptables \
        iputils-ping \
        locales \
        make \
        netcat-openbsd \
        neovim \
        openssh-client \
        procps \
        python3 \
        python3-venv \
        rsync \
        shellcheck \
        sudo \
        unzip \
        xz-utils \
        yamllint \
        zip \
    && locale-gen en_GB.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

RUN chmod +x /tmp/devcontainer/install-toolchain.sh \
    && /tmp/devcontainer/install-toolchain.sh --execute "${USERNAME}" \
    && rm -rf /tmp/devcontainer

ENV LANG=en_GB.UTF-8
ENV LC_ALL=en_GB.UTF-8
