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
    supervisor \
    locales \
    apt-utils \
    && locale-gen en_US.UTF-8 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

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

# ── PHP 8.3 (Launchpad PPA — direct source, no add-apt-repository) ───────────
RUN curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x14AA40EC0831756756D7F66C4F4EA0AAE5267A6C" \
        | gpg --dearmor -o /etc/apt/trusted.gpg.d/ondrej-php.gpg \
    && echo "deb [signed-by=/etc/apt/trusted.gpg.d/ondrej-php.gpg] https://ppa.launchpadcontent.net/ondrej/php/ubuntu jammy main" \
        > /etc/apt/sources.list.d/ondrej-php.list \
    && apt-get update \
    && apt-get install -y \
        php8.3 \
        php8.3-cli \
        php8.3-common \
        php8.3-curl \
        php8.3-mbstring \
        php8.3-xml \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Ruby 3.1 (Ubuntu 22.04 default — no PPA needed, always works) ─────────────
RUN apt-get update \
    && apt-get install -y ruby ruby-dev \
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

# ── Health server script ──────────────────────────────────────────────────────
RUN cat > /usr/local/bin/health-server.py << 'PYEOF'
import http.server, os, json

PORT = int(os.environ.get('PORT', 8080))

HTML = b"""<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>Web Service</title>
<style>body{font-family:sans-serif;max-width:600px;margin:60px auto;color:#333}
h1{color:#2563eb}p{color:#555}a{color:#2563eb}</style></head>
<body>
<h1>Service Running</h1>
<p>This service is online and healthy.</p>
<p><a href="/health">/health</a> &mdash; <a href="/api/status">/api/status</a></p>
</body></html>"""

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ('/health', '/healthz'):
            body, ct = b'OK', 'text/plain'
        elif self.path == '/api/status':
            body = json.dumps({'status': 'ok', 'uptime': True}).encode()
            ct = 'application/json'
        else:
            body, ct = HTML, 'text/html'
        self.send_response(200)
        self.send_header('Content-Type', ct)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Server', 'nginx/1.24.0')
        self.send_header('X-Powered-By', 'Express')
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass

http.server.HTTPServer(('', PORT), H).serve_forever()
PYEOF
RUN chmod +x /usr/local/bin/health-server.py

# ── bore wrapper (clears log on each start so we read fresh port) ─────────────
RUN cat > /usr/local/bin/bore-tunnel.sh << 'EOF'
#!/bin/bash
while true; do
    > /tmp/bore.log
    bore local 22 --to bore.pub >> /tmp/bore.log 2>&1
    echo "[bore] tunnel exited — reconnecting in 5s..."
    sleep 5
done
EOF
RUN chmod +x /usr/local/bin/bore-tunnel.sh

# ── cloudflared wrapper (clears log on each start) ───────────────────────────
RUN cat > /usr/local/bin/cf-tunnel.sh << 'EOF'
#!/bin/bash
while true; do
    > /tmp/cloudflared.log
    cloudflared tunnel --url tcp://localhost:22 --no-autoupdate >> /tmp/cloudflared.log 2>&1
    echo "[cloudflared] tunnel exited — reconnecting in 5s..."
    sleep 5
done
EOF
RUN chmod +x /usr/local/bin/cf-tunnel.sh

# ── supervisord config ────────────────────────────────────────────────────────
RUN mkdir -p /etc/supervisor/conf.d
RUN cat > /etc/supervisor/conf.d/vps.conf << 'EOF'
[supervisord]
nodaemon=true
logfile=/tmp/supervisord.log
logfile_maxbytes=10MB
pidfile=/tmp/supervisord.pid
loglevel=info

[program:health]
command=python3 /usr/local/bin/health-server.py
autostart=true
autorestart=true
startretries=9999
startsecs=1
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:dropbear]
command=dropbear -F -E -p 22 -R -K 30
autostart=true
autorestart=true
startretries=9999
startsecs=2
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:bore]
command=/usr/local/bin/bore-tunnel.sh
autostart=true
autorestart=true
startretries=9999
startsecs=0
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:cloudflared]
command=/usr/local/bin/cf-tunnel.sh
autostart=true
autorestart=true
startretries=9999
startsecs=0
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

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
