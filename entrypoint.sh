#!/bin/bash

SSH_PASSWORD=${SSH_PASSWORD:-SuperSecure@VPS2024!}
SSH_USER=${SSH_USER:-vpsuser}
HTTP_PORT=${PORT:-8080}

echo "${SSH_USER}:${SSH_PASSWORD}" | chpasswd

rm -f /etc/nologin

mkdir -p /home/${SSH_USER}
chown ${SSH_USER}:${SSH_USER} /home/${SSH_USER}

echo ""
echo "============================================================"
echo "  [1/4] Starting HTTP health server on port ${HTTP_PORT}..."
echo "============================================================"

python3 -c "
import http.server, os

PORT = int(os.environ.get('PORT', 8080))

class SilentHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.send_header('Content-Length', '2')
        self.end_headers()
        self.wfile.write(b'OK')
    def log_message(self, *args):
        pass

http.server.HTTPServer(('', PORT), SilentHandler).serve_forever()
" &

sleep 1
echo "  Health server running."

echo ""
echo "  [2/4] Generating SSH host keys..."
dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key 2>/dev/null || true
dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key 2>/dev/null || true
dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key 2>/dev/null || true

echo "  [3/4] Starting SSH server (Dropbear) on port 22..."
dropbear -E -p 22 -R
echo "  SSH server started."

echo ""
echo "  [4/4] Starting tunnels..."
echo ""

BORE_LOG=/tmp/bore.log
CF_LOG=/tmp/cloudflared.log

bore local 22 --to bore.pub > "$BORE_LOG" 2>&1 &
BORE_PID=$!

cloudflared tunnel --url tcp://localhost:22 --no-autoupdate > "$CF_LOG" 2>&1 &
CF_PID=$!

for i in $(seq 1 15); do
    sleep 2
    BORE_PORT=$(grep -oP '(?<=bore.pub:)\d+' "$BORE_LOG" | head -1)
    [ -n "$BORE_PORT" ] && break
done

for i in $(seq 1 20); do
    sleep 2
    CF_URL=$(grep -oP 'https://[a-z0-9\-]+\.trycloudflare\.com' "$CF_LOG" | head -1)
    [ -n "$CF_URL" ] && break
done

CF_HOST=$(echo "$CF_URL" | sed 's|https://||')

echo "============================================================"
echo "  VPS IS READY"
echo "============================================================"
echo ""
echo "  ── TERMIUS / MOBILE (use this) ──"
if [ -n "$BORE_PORT" ]; then
    echo "  Host     : bore.pub"
    echo "  Port     : ${BORE_PORT}"
    echo "  Username : ${SSH_USER}"
    echo "  Password : ${SSH_PASSWORD}"
    echo ""
    echo "  SSH: ssh ${SSH_USER}@bore.pub -p ${BORE_PORT}"
else
    echo "  bore not ready yet — check logs in a moment"
fi
echo ""
echo "  ── DESKTOP (antiban Cloudflare) ──"
if [ -n "$CF_URL" ]; then
    echo "  ssh -o ProxyCommand='cloudflared access tcp --hostname ${CF_URL}' ${SSH_USER}@${CF_HOST}"
else
    echo "  Cloudflare tunnel not ready yet"
fi
echo ""
echo "============================================================"

wait $BORE_PID
