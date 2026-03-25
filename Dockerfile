FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# ── Base system packages ──────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    dropbear-bin \
    sudo \
    curl \
    wget \
    vim \
    nano \
    git \
    htop \
    net-tools \
    iputils-ping \
    unzip \
    zip \
    build-essential \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    libssl-dev \
    libffi-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    stunnel4 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Node.js 22 LTS (via NodeSource) + pnpm ───────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g pnpm \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Python 3.13 (via deadsnakes PPA) ─────────────────────────────────────────
RUN add-apt-repository ppa:deadsnakes/ppa -y \
    && apt-get update \
    && apt-get install -y \
        python3.13 \
        python3.13-venv \
        python3.13-dev \
        python3-pip \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.13 1 \
    && update-alternatives --install /usr/bin/python  python  /usr/bin/python3.13 1 \
    && curl -fsSL https://bootstrap.pypa.io/get-pip.py | python3.13 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Go 1.24.1 ────────────────────────────────────────────────────────────────
RUN curl -fsSL https://go.dev/dl/go1.24.1.linux-amd64.tar.gz \
    | tar -C /usr/local -xz

# ── Rust stable (system-wide install) ────────────────────────────────────────
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo
RUN curl -fsSL https://sh.rustup.rs \
    | sh -s -- -y --default-toolchain stable --no-modify-path \
    && chmod -R a+rwx /usr/local/rustup /usr/local/cargo

# ── Java 21 LTS (OpenJDK) ────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y openjdk-21-jdk \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64

# ── PHP 8.3 (ondrej/php PPA) ─────────────────────────────────────────────────
RUN add-apt-repository ppa:ondrej/php -y \
    && apt-get update \
    && apt-get install -y \
        php8.3 \
        php8.3-cli \
        php8.3-common \
        php8.3-curl \
        php8.3-mbstring \
        php8.3-xml \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Ruby 3.3 (brightbox PPA) ─────────────────────────────────────────────────
RUN add-apt-repository ppa:brightbox/ruby-ng -y \
    && apt-get update \
    && apt-get install -y ruby3.3 ruby3.3-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Bun (system-wide via BUN_INSTALL=/usr/local) ─────────────────────────────
RUN curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash

# ── Deno (system-wide via DENO_INSTALL=/usr/local) ───────────────────────────
RUN curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh

# ── cloudflared ──────────────────────────────────────────────────────────────
RUN curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    -o /usr/local/bin/cloudflared \
    && chmod +x /usr/local/bin/cloudflared

# ── bore ─────────────────────────────────────────────────────────────────────
RUN curl -fsSL https://github.com/ekzhang/bore/releases/download/v0.5.1/bore-v0.5.1-x86_64-unknown-linux-musl.tar.gz \
    | tar -xz -C /usr/local/bin/ \
    && chmod +x /usr/local/bin/bore

# ── Global PATH (Go + Rust cargo, available to all users) ────────────────────
RUN printf 'export PATH="/usr/local/go/bin:/usr/local/cargo/bin:$PATH"\n' \
    > /etc/profile.d/runtimes.sh \
    && chmod +x /etc/profile.d/runtimes.sh

ENV PATH="/usr/local/go/bin:/usr/local/cargo/bin:${PATH}"

# ── SSH / user setup ─────────────────────────────────────────────────────────
RUN mkdir -p /etc/dropbear

ENV SSH_PASSWORD=${SSH_PASSWORD:-SuperSecure@VPS2024!}
ENV SSH_USER=${SSH_USER:-vpsuser}

RUN useradd -m -s /bin/bash vpsuser && \
    usermod -aG sudo vpsuser && \
    echo "vpsuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

COPY motd.txt /etc/motd
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
