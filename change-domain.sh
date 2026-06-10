#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════
#  MAX PANEL — Change Domain (NTLS + TLS, CDN-aware)
#  Usage:
#    bash change-domain.sh                       # interaktif, tanya domain
#    bash change-domain.sh ssh.example.com       # langsung set
#    bash change-domain.sh ssh.example.com cf    # mode Cloudflare proxied
#    bash change-domain.sh ssh.example.com origin  # mode direct (no CDN)
# ════════════════════════════════════════════════════════════════════════

set -uo pipefail

# ─── Warna ──────────────────────────────────────────────────────────────
NC=$'\033[0m'; BLD=$'\033[1m'; DIM=$'\033[2m'
GREEN=$'\033[1;32m'; RED=$'\033[1;31m'; YELLOW=$'\033[1;33m'
CYAN=$'\033[1;36m'; BLUE=$'\033[1;34m'

ok()   { echo -e "  ${GREEN}✔${NC}  $*"; }
inf()  { echo -e "  ${CYAN}➜${NC}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; }
err()  { echo -e "  ${RED}✘${NC}  $*"; }
hr()   { echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"; }

# ─── Path konstanta (selaras dengan setup-max.sh) ───────────────────────
MAX_DIR="/etc/maxpanel"
MAX_DOMF="${MAX_DIR}/domain.conf"
ZIV_DIR="/etc/zivpn"
ZIV_DOMF="${ZIV_DIR}/domain.conf"
NGX_CONF="/etc/nginx/conf.d/xray.conf"
XRAY_CRT="/etc/xray/xray.crt"
XRAY_KEY="/etc/xray/xray.key"
TS=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/root/maxpanel-backup/change-domain-${TS}"

# ─── Cek root ───────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && { err "Jalankan sebagai root."; exit 1; }

# ─── Argumen ────────────────────────────────────────────────────────────
NEW_DOMAIN="${1:-}"
MODE="${2:-}"   # cf | origin | (kosong = auto-detect)

if [[ -z "$NEW_DOMAIN" ]]; then
    hr
    echo -e "  ${BLD}MAX PANEL — Change Domain${NC}"
    hr
    read -rp "  Masukkan domain baru: " NEW_DOMAIN
fi

# ─── Validasi format domain ─────────────────────────────────────────────
if ! [[ "$NEW_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$ ]]; then
    err "Format domain tidak valid: $NEW_DOMAIN"
    exit 1
fi

NEW_DOMAIN=$(echo "$NEW_DOMAIN" | tr '[:upper:]' '[:lower:]')

# ─── Domain lama (auto-detect) ──────────────────────────────────────────
OLD_DOMAIN=""
[[ -f "$MAX_DOMF" ]] && OLD_DOMAIN=$(tr -d '[:space:]' < "$MAX_DOMF" 2>/dev/null)
[[ -z "$OLD_DOMAIN" && -f "$ZIV_DOMF" ]] && OLD_DOMAIN=$(tr -d '[:space:]' < "$ZIV_DOMF" 2>/dev/null)
if [[ -z "$OLD_DOMAIN" && -f "$NGX_CONF" ]]; then
    OLD_DOMAIN=$(grep -E '^\s*server_name\s+' "$NGX_CONF" 2>/dev/null \
                 | head -1 | awk '{print $2}' | tr -d ';')
fi

hr
echo -e "  ${BLD}MAX PANEL — Change Domain${NC}"
hr
inf "Domain lama   : ${OLD_DOMAIN:-<tidak terdeteksi>}"
inf "Domain baru   : ${BLD}${NEW_DOMAIN}${NC}"

# ─── Resolve DNS & cek mode CDN/origin ──────────────────────────────────
inf "Resolving DNS..."
RESOLVED_IPS=$(getent ahostsv4 "$NEW_DOMAIN" 2>/dev/null | awk '{print $1}' | sort -u)
if [[ -z "$RESOLVED_IPS" ]]; then
    err "DNS tidak resolve untuk $NEW_DOMAIN. Pastikan A record sudah dibuat."
    exit 1
fi
echo "$RESOLVED_IPS" | while read -r ip; do echo "      ${DIM}→ $ip${NC}"; done

VPS_IP=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null \
          || hostname -I | awk '{print $1}')
inf "IP VPS        : $VPS_IP"

IS_CLOUDFLARE=0
if echo "$RESOLVED_IPS" | grep -qE '^(104\.(1[6-9]|2[0-9]|3[01])\.|172\.(6[4-9]|[7-9][0-9])\.|173\.245\.|103\.21\.244\.|103\.22\.200\.|103\.31\.4\.|141\.101\.|108\.162\.|190\.93\.|188\.114\.|197\.234\.240\.|198\.41\.128\.|162\.158\.|131\.0\.72\.)'; then
    IS_CLOUDFLARE=1
fi

if [[ -z "$MODE" ]]; then
    if (( IS_CLOUDFLARE )); then
        MODE="cf"
        ok "Cloudflare proxied terdeteksi (orange cloud) → mode CDN"
    elif echo "$RESOLVED_IPS" | grep -qx "$VPS_IP"; then
        MODE="origin"
        ok "Direct A record ke VPS terdeteksi → mode origin"
    else
        warn "DNS tidak menunjuk ke IP VPS dan bukan Cloudflare → asumsi mode origin"
        MODE="origin"
    fi
fi

# ─── Konfirmasi ─────────────────────────────────────────────────────────
echo
read -rp "  Lanjutkan ganti domain ke '${NEW_DOMAIN}' (mode=${MODE})? [y/N] " yn
[[ "${yn,,}" != "y" ]] && { warn "Dibatalkan."; exit 0; }

# ─── Backup ─────────────────────────────────────────────────────────────
mkdir -p "$BACKUP_DIR"
inf "Backup ke $BACKUP_DIR ..."
[[ -f "$MAX_DOMF" ]] && cp -a "$MAX_DOMF" "$BACKUP_DIR/" 2>/dev/null
[[ -f "$ZIV_DOMF" ]] && cp -a "$ZIV_DOMF" "$BACKUP_DIR/" 2>/dev/null
[[ -f "$NGX_CONF" ]] && cp -a "$NGX_CONF" "$BACKUP_DIR/" 2>/dev/null
ok "Backup selesai"

# ─── Tulis domain.conf ──────────────────────────────────────────────────
mkdir -p "$MAX_DIR"
echo -n "$NEW_DOMAIN" > "$MAX_DOMF"
ok "Tulis $MAX_DOMF"

if [[ -d "$ZIV_DIR" ]]; then
    echo -n "$NEW_DOMAIN" > "$ZIV_DOMF"
    ok "Tulis $ZIV_DOMF"
fi

# ─── Replace domain lama di semua file maxpanel/zivpn (kalau ada) ──────
if [[ -n "$OLD_DOMAIN" && "$OLD_DOMAIN" != "$NEW_DOMAIN" ]]; then
    inf "Replace '$OLD_DOMAIN' → '$NEW_DOMAIN' di config..."
    OLD_ESC=$(printf '%s' "$OLD_DOMAIN" | sed 's/[.[\*^$/]/\\&/g')
    NEW_ESC=$(printf '%s' "$NEW_DOMAIN" | sed 's/[\&/]/\\&/g')
    shopt -s nullglob
    PATCH_LIST=( /etc/maxpanel/*.conf /etc/zivpn/*.conf /etc/zivpn/*.json \
                 /etc/xray/*.json /etc/v2ray/*.json /etc/stunnel/*.conf )
    shopt -u nullglob
    for f in "${PATCH_LIST[@]}"; do
        [[ -f "$f" ]] || continue
        if grep -q "$OLD_DOMAIN" "$f" 2>/dev/null; then
            sed -i "s/${OLD_ESC}/${NEW_ESC}/g" "$f"
            ok "  patched: $f"
        fi
    done
fi

# ─── Regenerate Nginx config ────────────────────────────────────────────
inf "Generate Nginx config..."
mkdir -p /etc/nginx/conf.d
rm -f /etc/nginx/sites-enabled/default 2>/dev/null

# Pastikan cert ada untuk listener TLS
HAS_CERT=0
if [[ -f "$XRAY_CRT" && -f "$XRAY_KEY" ]]; then
    HAS_CERT=1
elif [[ "$MODE" == "origin" ]]; then
    inf "Cert tidak ada → generate self-signed (origin mode)..."
    mkdir -p /etc/xray
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
        -subj "/CN=${NEW_DOMAIN}" \
        -keyout "$XRAY_KEY" -out "$XRAY_CRT" 2>/dev/null && HAS_CERT=1
    [[ $HAS_CERT -eq 1 ]] && ok "Self-signed cert generated" || warn "Gagal generate cert"
fi

# Tulis config Nginx (selalu sertakan listener 80; 443/8443 hanya jika cert ada)
{
cat <<NGX
# MAX PANEL — Xray reverse-proxy (auto-generated by change-domain.sh)
map \$http_upgrade \$connection_upgrade { default upgrade; '' close; }

# === HTTP 80 (plain — CDN-friendly) ===================================
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name ${NEW_DOMAIN} _;
    root /var/www/html;
    index index.html;

    location = /vmess     { if (\$http_upgrade != "websocket") { return 404; } proxy_pass http://127.0.0.1:10001; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 300s; }
    location = /vless     { if (\$http_upgrade != "websocket") { return 404; } proxy_pass http://127.0.0.1:10002; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 300s; }
    location = /trojan-ws { if (\$http_upgrade != "websocket") { return 404; } proxy_pass http://127.0.0.1:10003; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 300s; }

    # SSH-over-WebSocket aliases (semua → 127.0.0.1:8880)
    location = /ws-ssh { proxy_pass http://127.0.0.1:8880; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 7200s; proxy_buffering off; }
    location = /ws     { proxy_pass http://127.0.0.1:8880; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 7200s; proxy_buffering off; }
    location = /ssh    { proxy_pass http://127.0.0.1:8880; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 7200s; proxy_buffering off; }
    location = /cdn    { proxy_pass http://127.0.0.1:8880; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 7200s; proxy_buffering off; }
    location = /tunnel { proxy_pass http://127.0.0.1:8880; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 7200s; proxy_buffering off; }

    location / { return 200 'MAX PANEL OK'; add_header Content-Type text/plain; }
}
NGX

if (( HAS_CERT )); then
cat <<NGX

# === TLS 443 ==========================================================
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${NEW_DOMAIN} _;

    ssl_certificate     ${XRAY_CRT};
    ssl_certificate_key ${XRAY_KEY};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL:10m;

    location ^~ /vless-grpc  { grpc_pass grpc://127.0.0.1:10004; grpc_set_header Host \$host; client_max_body_size 0; }
    location ^~ /trojan-grpc { grpc_pass grpc://127.0.0.1:10005; grpc_set_header Host \$host; client_max_body_size 0; }

    location = /vmess     { proxy_pass http://127.0.0.1:10001; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 300s; }
    location = /vless     { proxy_pass http://127.0.0.1:10002; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 300s; }
    location = /trojan-ws { proxy_pass http://127.0.0.1:10003; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 300s; }

    location = /ws-ssh { proxy_pass http://127.0.0.1:8880; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 7200s; proxy_buffering off; }
    location = /ws     { proxy_pass http://127.0.0.1:8880; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 7200s; proxy_buffering off; }
    location = /ssh    { proxy_pass http://127.0.0.1:8880; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 7200s; proxy_buffering off; }
    location = /cdn    { proxy_pass http://127.0.0.1:8880; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 7200s; proxy_buffering off; }
    location = /tunnel { proxy_pass http://127.0.0.1:8880; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 7200s; proxy_buffering off; }

    location / { return 200 'MAX PANEL OK'; add_header Content-Type text/plain; }
}

# === Alt-TLS 8443 =====================================================
server {
    listen 8443 ssl http2;
    listen [::]:8443 ssl http2;
    server_name ${NEW_DOMAIN} _;

    ssl_certificate     ${XRAY_CRT};
    ssl_certificate_key ${XRAY_KEY};
    ssl_protocols TLSv1.2 TLSv1.3;

    location ^~ /vless-grpc  { grpc_pass grpc://127.0.0.1:10004; grpc_set_header Host \$host; client_max_body_size 0; }
    location ^~ /trojan-grpc { grpc_pass grpc://127.0.0.1:10005; grpc_set_header Host \$host; client_max_body_size 0; }
    location = /vmess     { proxy_pass http://127.0.0.1:10001; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; }
    location = /vless     { proxy_pass http://127.0.0.1:10002; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; }
    location = /trojan-ws { proxy_pass http://127.0.0.1:10003; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; }
    location = /ws-ssh    { proxy_pass http://127.0.0.1:8880;  proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_buffering off; }
    location / { return 200 'MAX PANEL OK'; add_header Content-Type text/plain; }
}
NGX
fi
} > "$NGX_CONF"

ok "Tulis $NGX_CONF"

# ─── Test & restart Nginx ───────────────────────────────────────────────
inf "Test Nginx config..."
if nginx -t 2>/tmp/ngxtest.log; then
    ok "Nginx config valid"
    systemctl restart nginx 2>/dev/null && ok "Nginx restarted" \
        || { err "Gagal restart Nginx"; exit 1; }
else
    err "Nginx config INVALID — rollback ke backup"
    cp -a "$BACKUP_DIR/xray.conf" "$NGX_CONF" 2>/dev/null
    cat /tmp/ngxtest.log
    exit 1
fi

# ─── Restart service terkait ────────────────────────────────────────────
for svc in ws-max-8880 xray v2ray stunnel4 zivpn; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
        systemctl restart "$svc" 2>/dev/null \
            && ok "Restart $svc" || warn "Gagal restart $svc"
    fi
done

# ─── Verifikasi endpoint ────────────────────────────────────────────────
hr
echo -e "  ${BLD}Verifikasi endpoint dari localhost${NC}"
hr
for path in /ws-ssh /ws /ssh /cdn /tunnel; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:80${path}" 2>/dev/null)
    if [[ "$code" == "200" || "$code" == "404" || "$code" == "101" ]]; then
        ok "http://...:80${path} → HTTP $code"
    else
        warn "http://...:80${path} → HTTP $code"
    fi
done

if (( HAS_CERT )); then
    for path in /ws-ssh /ws /ssh /cdn /tunnel; do
        code=$(curl -ks -o /dev/null -w '%{http_code}' --max-time 5 "https://127.0.0.1:443${path}" 2>/dev/null)
        if [[ "$code" == "200" || "$code" == "404" || "$code" == "101" ]]; then
            ok "https://...:443${path} → HTTP $code"
        else
            warn "https://...:443${path} → HTTP $code"
        fi
    done
fi

# ─── Ringkasan ──────────────────────────────────────────────────────────
hr
echo -e "  ${BLD}${GREEN}✓ Domain berhasil diganti ke: ${NEW_DOMAIN}${NC}"
hr
echo
echo -e "  ${BLD}Mode:${NC} ${MODE}"
if [[ "$MODE" == "cf" ]]; then
    echo
    echo -e "  ${YELLOW}Wajib di Cloudflare Dashboard:${NC}"
    echo "    1. SSL/TLS → Overview → mode: Flexible (atau Full)"
    echo "    2. SSL/TLS → Edge Certificates → Always Use HTTPS: OFF (untuk NTLS)"
    echo "    3. Network → WebSockets: ON"
    echo "    4. Network → Pseudo IPv4: Off"
    echo "    5. DNS: A record ${NEW_DOMAIN} → orange cloud (proxied)"
fi
echo
echo -e "  ${BLD}Setting HTTP Custom (di HP):${NC}"
echo "    WS NTLS  : Direct, Host=${NEW_DOMAIN}, Port=80"
echo "    WS TLS   : SSL/TLS, Host=${NEW_DOMAIN}, Port=443, SNI=${NEW_DOMAIN}"
echo "    Payload  : GET / HTTP/1.1[crlf]Host: ${NEW_DOMAIN}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
echo "    Path     : / atau /ws /ws-ssh /ssh /cdn /tunnel"
echo
echo -e "  ${DIM}Backup config lama: ${BACKUP_DIR}${NC}"
echo
