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

RUN mkdir -p /var/run/sshd /run/sshd /etc/stunnel

ENV SSH_PASSWORD=${SSH_PASSWORD:-SuperSecure@VPS2024!}
ENV SSH_USER=${SSH_USER:-vpsuser}

RUN useradd -m -s /bin/bash ${SSH_USER} && \
    echo "${SSH_USER}:${SSH_PASSWORD}" | chpasswd && \
    usermod -aG sudo ${SSH_USER} && \
    echo "${SSH_USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN cat > /etc/ssh/sshd_config << 'EOF'
Port 22
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM no
X11Forwarding no
PrintMotd yes
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
ClientAliveInterval 60
ClientAliveCountMax 10
EOF

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
