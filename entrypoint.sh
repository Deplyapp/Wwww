#!/bin/bash

SSH_PASSWORD=${SSH_PASSWORD:-SuperSecure@VPS2024!}
SSH_USER=${SSH_USER:-vpsuser}
TUNNEL_MODE=${TUNNEL_MODE:-cloudflare}
HTTP_PORT=${PORT:-8080}

echo "${SSH_USER}:${SSH_PASSWORD}" | chpasswd

echo ""
echo "============================================================"
echo "  [1/4] Starting HTTP health server on port ${HTTP_PORT}..."
echo "        (keeps the service alive on Render)"
echo "============================================================"

python3 -c "
import http.server, os, threading

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

server = http.server.HTTPServer(('', PORT), SilentHandler)
server.serve_forever()
" &

sleep 1
echo "  Health server running on port ${HTTP_PORT}."

echo ""
echo "  [2/4] Starting SSH server on port 22..."
/usr/sbin/sshd
echo "  SSH server started."

echo ""
echo "  [3/4] Starting TLS wrapper on port 443 (stunnel)..."
stunnel4 /etc/stunnel/stunnel.conf
echo "  Stunnel started — SSH wrapped in TLS on port 443."

echo ""
echo "  [4/4] Creating antiban tunnel (traffic routed via Cloudflare HTTPS)..."
echo ""

CF_LOG=/tmp/cloudflared.log
BORE_LOG=/tmp/bore.log

start_cloudflare() {
    cloudflared tunnel --url tcp://localhost:22 --no-autoupdate > "$CF_LOG" 2>&1 &
    CF_PID=$!

    for i in $(seq 1 30); do
        sleep 2
        CF_URL=$(grep -oP 'https://[a-z0-9\-]+\.trycloudflare\.com' "$CF_LOG" | head -1)
        if [ -n "$CF_URL" ]; then
            CF_HOST=$(echo "$CF_URL" | sed 's|https://||')
            echo "============================================================"
            echo "  VPS IS READY  —  ANTIBAN SSH (Cloudflare Tunnel)"
            echo "============================================================"
            echo ""
            echo "  Tunnel   : Cloudflare HTTPS — looks like normal web traffic"
            echo "  Host     : ${CF_HOST}"
            echo "  Username : ${SSH_USER}"
            echo "  Password : ${SSH_PASSWORD}"
            echo ""
            echo "  Desktop:"
            echo "    Install cloudflared first: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/"
            echo "    Then run:"
            echo "    ssh -o ProxyCommand='cloudflared access tcp --hostname ${CF_URL}' ${SSH_USER}@${CF_HOST}"
            echo ""
            echo "  Termius (mobile):"
            echo "    1. Install cloudflared on a local machine and run:"
            echo "       cloudflared access tcp --hostname ${CF_URL} --listener 127.0.0.1:2222"
            echo "    2. In Termius, SSH to 127.0.0.1 port 2222"
            echo "    --- OR use bore fallback below for direct Termius access ---"
            echo ""
            echo "============================================================"
            wait $CF_PID
            return 0
        fi
    done

    echo "  WARNING: Cloudflare tunnel timed out. Falling back to bore..."
    kill $CF_PID 2>/dev/null
    return 1
}

start_bore() {
    echo "  Starting bore tunnel..."
    bore local 22 --to bore.pub > "$BORE_LOG" 2>&1 &
    BORE_PID=$!

    sleep 6

    BORE_PORT=$(grep -oP '(?<=bore.pub:)\d+' "$BORE_LOG" | head -1)

    if [ -z "$BORE_PORT" ]; then
        echo "  ERROR: All tunnels failed. bore log:"
        cat "$BORE_LOG"
        tail -f /dev/null
    else
        echo "============================================================"
        echo "  VPS IS READY  —  SSH (bore fallback)"
        echo "============================================================"
        echo ""
        echo "  Host     : bore.pub"
        echo "  Port     : ${BORE_PORT}"
        echo "  Username : ${SSH_USER}"
        echo "  Password : ${SSH_PASSWORD}"
        echo ""
        echo "  SSH command:"
        echo "    ssh ${SSH_USER}@bore.pub -p ${BORE_PORT}"
        echo ""
        echo "  Termius:"
        echo "    Host     → bore.pub"
        echo "    Port     → ${BORE_PORT}"
        echo "    Username → ${SSH_USER}"
        echo "    Password → ${SSH_PASSWORD}"
        echo ""
        echo "============================================================"
    fi

    wait $BORE_PID
}

if [ "$TUNNEL_MODE" = "bore" ]; then
    start_bore
else
    start_cloudflare || start_bore
fi

tail -f /dev/null
