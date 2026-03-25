#!/bin/bash

SSH_PASSWORD=${SSH_PASSWORD:-SuperSecure@VPS2024!}
SSH_USER=${SSH_USER:-vpsuser}

BORE_LOG=/tmp/bore.log
CF_LOG=/tmp/cloudflared.log

# ── Set passwords ─────────────────────────────────────────────────────────────
echo "${SSH_USER}:${SSH_PASSWORD}" | chpasswd
echo "root:${SSH_PASSWORD}" | chpasswd
rm -f /etc/nologin

mkdir -p /home/${SSH_USER}
chown ${SSH_USER}:${SSH_USER} /home/${SSH_USER}

# ── Generate SSH host keys ────────────────────────────────────────────────────
echo "[setup] Generating SSH host keys..."
mkdir -p /etc/dropbear
dropbearkey -t rsa     -f /etc/dropbear/dropbear_rsa_host_key     2>/dev/null || true
dropbearkey -t ecdsa   -f /etc/dropbear/dropbear_ecdsa_host_key   2>/dev/null || true
dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key 2>/dev/null || true
echo "[setup] SSH host keys ready."

# ── Print connection info once tunnels are up (runs in background) ────────────
print_info() {
    local last_bore=""
    while true; do
        sleep 10
        BORE_PORT=$(grep -oP '(?<=bore.pub:)\d+' "$BORE_LOG" 2>/dev/null | head -1)
        CF_URL=$(grep -oP 'https://[a-z0-9\-]+\.trycloudflare\.com' "$CF_LOG" 2>/dev/null | head -1)
        CF_HOST=$(echo "$CF_URL" | sed 's|https://||')

        if [ -n "$BORE_PORT" ] && [ "$BORE_PORT" != "$last_bore" ]; then
            last_bore="$BORE_PORT"
            echo ""
            echo "============================================================"
            echo "  VPS IS READY"
            echo "============================================================"
            echo ""
            echo "  ── TERMIUS / MOBILE ──"
            echo "  Host     : bore.pub"
            echo "  Port     : ${BORE_PORT}"
            echo "  Username : root"
            echo "  Password : ${SSH_PASSWORD}"
            echo "  SSH cmd  : ssh root@bore.pub -p ${BORE_PORT}"
            echo ""
            echo "  ── DESKTOP (Cloudflare antiban) ──"
            if [ -n "$CF_URL" ]; then
                echo "  ssh -o ProxyCommand='cloudflared access tcp --hostname ${CF_URL}' ${SSH_USER}@${CF_HOST}"
            else
                echo "  Cloudflare tunnel not ready yet..."
            fi
            echo ""
            echo "  Note: bore gets a new port on reconnect — check logs for updates"
            echo "============================================================"
        fi
    done
}
print_info &

# ── Hand off to supervisord — manages all services forever ───────────────────
echo "[setup] Starting supervisord — all services managed from here..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/vps.conf
