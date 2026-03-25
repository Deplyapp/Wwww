FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    openssh-server \
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
    python3 \
    python3-pip \
    nodejs \
    npm \
    stunnel4 \
    socat \
    netcat-openbsd \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    -o /usr/local/bin/cloudflared \
    && chmod +x /usr/local/bin/cloudflared

RUN curl -fsSL https://github.com/ekzhang/bore/releases/download/v0.5.1/bore-v0.5.1-x86_64-unknown-linux-musl.tar.gz \
    | tar -xz -C /usr/local/bin/ \
    && chmod +x /usr/local/bin/bore

RUN mkdir -p /var/run/sshd /etc/stunnel

ENV SSH_PASSWORD=${SSH_PASSWORD:-SuperSecure@VPS2024!}
ENV SSH_USER=${SSH_USER:-vpsuser}

RUN useradd -m -s /bin/bash ${SSH_USER} && \
    echo "${SSH_USER}:${SSH_PASSWORD}" | chpasswd && \
    usermod -aG sudo ${SSH_USER} && \
    echo "${SSH_USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#Port 22/Port 22/' /etc/ssh/sshd_config && \
    echo "X11Forwarding no" >> /etc/ssh/sshd_config && \
    echo "PrintMotd yes" >> /etc/ssh/sshd_config && \
    echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config && \
    echo "ClientAliveCountMax 10" >> /etc/ssh/sshd_config

RUN openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout /etc/stunnel/stunnel.key \
    -out /etc/stunnel/stunnel.crt \
    -subj "/C=US/ST=CA/L=San Francisco/O=Server/CN=localhost"

COPY stunnel.conf /etc/stunnel/stunnel.conf

RUN ssh-keygen -A

COPY motd.txt /etc/motd
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22 443

ENTRYPOINT ["/entrypoint.sh"]
