#!/bin/bash

SSH_PASSWORD=${SSH_PASSWORD:-SuperSecure@VPS2024!}
SSH_USER=${SSH_USER:-vpsuser}
HTTP_PORT=${PORT:-8080}

BORE_LOG=/tmp/bore.log
CF_LOG=/tmp/cloudflared.log

echo "${SSH_USER}:${SSH_PASSWORD}" | chpasswd
echo "root:${SSH_PASSWORD}" | chpasswd

rm -f /etc/nologin

mkdir -p /home/${SSH_USER}
chown ${SSH_USER}:${SSH_USER} /home/${SSH_USER}

# ── [1/4] Health server — runs forever, restarts instantly on crash ───────────
echo ""
echo "============================================================"
echo "  [1/4] Starting HTTP health server on port ${HTTP_PORT}..."
echo "============================================================"

health_loop() {
    while true; do
        python3 -c "
import http.server, os, json
from datetime import datetime

PORT = int(os.environ.get('PORT', 8080))

HTML = b'''<!DOCTYPE html>
<html lang=\"en\">
<head><meta charset=\"UTF-8\"><title>Web Service</title>
<style>body{font-family:sans-serif;max-width:600px;margin:60px auto;color:#333}
h1{color:#2563eb}p{color:#555}a{color:#2563eb}</style></head>
<body>
<h1>Service Running</h1>
<p>This service is online and healthy.</p>
<p><a href=\"/health\">/health</a> &mdash; <a href=\"/api/status\">/api/status</a></p>
</body></html>'''

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health' or self.path == '/healthz':
            body = b'OK'
            ct = 'text/plain'
        elif self.path == '/api/status':
            body = json.dumps({'status':'ok','uptime':True}).encode()
            ct = 'application/json'
        else:
            body = HTML
            ct = 'text/html'
        self.send_response(200)
        self.send_header('Content-Type', ct)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Server', 'nginx/1.24.0')
        self.send_header('X-Powered-By', 'Express')
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass

http.server.HTTPServer(('', PORT), H).serve_forever()
"
        echo "  [health] server crashed — restarting in 2s..."
        sleep 2
    done
}
health_loop &

sleep 1
echo "  Health server running."

# ── [2/4] SSH host keys ───────────────────────────────────────────────────────
echo ""
echo "  [2/4] Generating SSH host keys..."
dropbearkey -t rsa     -f /etc/dropbear/dropbear_rsa_host_key     2>/dev/null || true
dropbearkey -t ecdsa   -f /etc/dropbear/dropbear_ecdsa_host_key   2>/dev/null || true
dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key 2>/dev/null || true

# ── [3/4] SSH server (dropbear) ───────────────────────────────────────────────
echo "  [3/4] Starting SSH server on port 22..."
dropbear -E -p 22 -R -K 30 -I 0
echo "  SSH server started."

# ── [4/4] Tunnels — each in its own persistent restart loop ──────────────────
echo ""
echo "  [4/4] Starting persistent tunnel loops..."
echo ""

# Bore: clears log on each attempt so we always read the freshest port
bore_loop() {
    while true; do
        > "$BORE_LOG"
        bore local 22 --to bore.pub >> "$BORE_LOG" 2>&1
        echo "  [bore] tunnel dropped — reconnecting in 5s..."
        sleep 5
    done
}

# Cloudflared: clears log on each attempt so we always read the freshest URL
cf_loop() {
    while true; do
        > "$CF_LOG"
        cloudflared tunnel --url tcp://localhost:22 --no-autoupdate >> "$CF_LOG" 2>&1
        echo "  [cloudflared] tunnel dropped — reconnecting in 5s..."
        sleep 5
    done
}

bore_loop &
cf_loop &

# Wait for bore and cloudflared to print their addresses (up to ~60 s each)
echo "  Waiting for tunnels to come up..."

for i in $(seq 1 30); do
    sleep 2
    BORE_PORT=$(grep -oP '(?<=bore.pub:)\d+' "$BORE_LOG" | head -1)
    [ -n "$BORE_PORT" ] && break
done

for i in $(seq 1 30); do
    sleep 2
    CF_URL=$(grep -oP 'https://[a-z0-9\-]+\.trycloudflare\.com' "$CF_LOG" | head -1)
    [ -n "$CF_URL" ] && break
done

CF_HOST=$(echo "$CF_URL" | sed 's|https://||')

echo ""
echo "============================================================"
echo "  VPS IS READY — tunnels will auto-reconnect if dropped"
echo "============================================================"
echo ""
echo "  ── TERMIUS / MOBILE ──"
if [ -n "$BORE_PORT" ]; then
    echo "  Host     : bore.pub"
    echo "  Port     : ${BORE_PORT}"
    echo "  Username : root"
    echo "  Password : ${SSH_PASSWORD}"
    echo "  SSH cmd  : ssh root@bore.pub -p ${BORE_PORT}"
else
    echo "  bore not ready yet — check logs: tail -f ${BORE_LOG}"
fi
echo ""
echo "  ── DESKTOP (Cloudflare antiban) ──"
if [ -n "$CF_URL" ]; then
    echo "  ssh -o ProxyCommand='cloudflared access tcp --hostname ${CF_URL}' ${SSH_USER}@${CF_HOST}"
else
    echo "  Cloudflare not ready yet — check logs: tail -f ${CF_LOG}"
fi
echo ""
echo "  Note: bore gets a new port each reconnect — check ${BORE_LOG} for updates"
echo "============================================================"

# ── Keep-alive: print updated connection info whenever bore reconnects ────────
last_bore_port=""
while true; do
    sleep 20
    NEW_PORT=$(grep -oP '(?<=bore.pub:)\d+' "$BORE_LOG" | head -1)
    if [ -n "$NEW_PORT" ] && [ "$NEW_PORT" != "$last_bore_port" ]; then
        last_bore_port="$NEW_PORT"
        NEW_CF=$(grep -oP 'https://[a-z0-9\-]+\.trycloudflare\.com' "$CF_LOG" | head -1)
        echo ""
        echo "  [update] New bore port: ${NEW_PORT}"
        echo "  SSH cmd: ssh root@bore.pub -p ${NEW_PORT}"
        if [ -n "$NEW_CF" ]; then
            echo "  CF cmd : ssh -o ProxyCommand='cloudflared access tcp --hostname ${NEW_CF}' ${SSH_USER}@$(echo $NEW_CF | sed 's|https://||')"
        fi
    fi
done
