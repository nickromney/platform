# syntax=docker/dockerfile:1.7

FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG USERNAME=vscode
ENV DEBIAN_FRONTEND=noninteractive
ENV HOMEBREW_PREFIX=/home/linuxbrew/.linuxbrew
ENV HOMEBREW_NO_AUTO_UPDATE=1
ENV HOMEBREW_NO_ENV_HINTS=1
ENV HOMEBREW_NO_INSTALL_CLEANUP=1
ENV PATH=${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin:/usr/local/bin:${PATH}

COPY Brewfile /tmp/devcontainer/Brewfile
COPY install-toolchain.sh /tmp/devcontainer/install-toolchain.sh

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash-completion \
        build-essential \
        ca-certificates \
        curl \
        dnsutils \
        file \
        fonts-freefont-ttf \
        fonts-ipafont-gothic \
        fonts-liberation \
        fonts-noto-color-emoji \
        fonts-tlwg-loma-otf \
        fonts-unifont \
        fonts-wqy-zenhei \
        git \
        iproute2 \
        iptables \
        iputils-ping \
        libasound2t64 \
        libatk-bridge2.0-0t64 \
        libatk1.0-0t64 \
        libatspi2.0-0t64 \
        libcairo2 \
        libcups2t64 \
        libdbus-1-3 \
        libdrm2 \
        libfontconfig1 \
        libfreetype6 \
        libgbm1 \
        libglib2.0-0t64 \
        libnss3-tools \
        libnspr4 \
        libnss3 \
        libpango-1.0-0 \
        libx11-6 \
        libxcb1 \
        libxcomposite1 \
        libxdamage1 \
        libxext6 \
        libxfixes3 \
        libxkbcommon0 \
        libxrandr2 \
        locales \
        make \
        netcat-openbsd \
        openssh-client \
        procps \
        python3 \
        python3-venv \
        rsync \
        sudo \
        unzip \
        xfonts-cyrillic \
        xfonts-scalable \
        xvfb \
        xz-utils \
        zip \
    && locale-gen en_GB.UTF-8 \
    && chmod +x /tmp/devcontainer/install-toolchain.sh \
    && sudo -Hiu ${USERNAME} env NONINTERACTIVE=1 bash -lc 'curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | bash' \
    && printf 'eval "$(%s/bin/brew shellenv)"\n' "${HOMEBREW_PREFIX}" >/etc/profile.d/homebrew.sh \
    && /tmp/devcontainer/install-toolchain.sh "${USERNAME}" /tmp/devcontainer/Brewfile \
    && rm -rf /var/lib/apt/lists/* /tmp/devcontainer

ENV LANG=en_GB.UTF-8
ENV LC_ALL=en_GB.UTF-8
