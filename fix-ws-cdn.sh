#!/bin/bash
# ════════════════════════════════════════════════════════════
#  FIX WS CDN — MAX PANEL
#  Memperbaiki Nginx config untuk SSH WS via Cloudflare CDN
#  - Tambah path alternatif (/ , /ws, /cdn, /ssh)
#  - Hapus validator "$http_upgrade != websocket" yg suka block
#  - Tambah listener public di port 8880 (backup non-CDN)
#  - Tambah header Cloudflare-friendly
#  Jalankan: bash fix-ws-cdn.sh
# ════════════════════════════════════════════════════════════

RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'
CYAN='\033[1;36m'; NC='\033[0m'; BOLD='\033[1m'

[[ $EUID -ne 0 ]] && { echo -e "${RED}Jalankan sebagai root!${NC}"; exit 1; }

ok()   { echo -e "  ${GREEN}✔${NC}  $*"; }
err()  { echo -e "  ${RED}✘${NC}  $*"; }
inf()  { echo -e "  ${CYAN}➜${NC}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; }

# Auto-detect domain dari config Nginx existing
detect_domain() {
    local d
    d=$(grep -hE '^\s*server_name\s+' /etc/nginx/conf.d/*.conf 2>/dev/null \
        | head -1 | awk '{print $2}' | tr -d ';')
    [[ -z "$d" || "$d" == "_" ]] && d="_"
    echo "$d"
}

DOMAIN=$(detect_domain)

echo ""
echo -e "  ${CYAN}══════════════════════════════════════════════${NC}"
echo -e "  ${BOLD}  MAX PANEL — Fix WS CDN (NTLS + TLS)${NC}"
echo -e "  ${CYAN}══════════════════════════════════════════════${NC}"
echo ""
inf "Domain terdeteksi: ${BOLD}${DOMAIN}${NC}"
echo ""

# ────────────────────────────────────────────────────────────
# 1. Backup config lama
# ────────────────────────────────────────────────────────────
TS=$(date +%Y%m%d-%H%M%S)
if [[ -f /etc/nginx/conf.d/xray.conf ]]; then
    cp /etc/nginx/conf.d/xray.conf "/etc/nginx/conf.d/xray.conf.bak-${TS}"
    ok "Backup: /etc/nginx/conf.d/xray.conf.bak-${TS}"
fi

# ────────────────────────────────────────────────────────────
# 2. Tulis config Nginx yang fix
# ────────────────────────────────────────────────────────────
inf "Menulis config Nginx baru (CDN-friendly)..."

cat > /etc/nginx/conf.d/xray.conf <<NGX
# MAX PANEL — Xray reverse-proxy + SSH-WS (CDN-optimized)
map \$http_upgrade \$connection_upgrade { default upgrade; '' close; }

# === HTTP 80 (plain / Cloudflare NTLS) ===============================
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name ${DOMAIN} _;
    root /var/www/html;
    index index.html;

    # CDN-friendly headers
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    # ============ Xray paths (validator dipertahankan) ============
    location = /vmess {
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_read_timeout 300s;
    }

    location = /vless {
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_read_timeout 300s;
    }

    location = /trojan-ws {
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_read_timeout 300s;
    }

    # ============ SSH WebSocket — multiple paths ============
    # FIX: tanpa validator, supaya HTTP Custom dengan payload variatif tetap lewat
    location = /ws-ssh    { proxy_pass http://127.0.0.1:8880; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 7200s; proxy_buffering off; }
    location = /ws        { proxy_pass http://127.0.0.1:8880; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 7200s; proxy_buffering off; }
    location = /ssh       { proxy_pass http://127.0.0.1:8880; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 7200s; proxy_buffering off; }
    location = /cdn       { proxy_pass http://127.0.0.1:8880; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 7200s; proxy_buffering off; }
    location = /tunnel    { proxy_pass http://127.0.0.1:8880; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 7200s; proxy_buffering off; }

    # Root path: kalau ada Upgrade header → forward ke WS proxy, kalau tidak → halaman OK
    location / {
        if (\$http_upgrade) {
            set \$is_ws 1;
        }
        if (\$is_ws = 1) {
            proxy_pass http://127.0.0.1:8880;
        }
        return 200 'MAX PANEL OK';
        add_header Content-Type text/plain;
    }
}

# === TLS 443 (primary / Cloudflare TLS) ==============================
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN} _;

    ssl_certificate     /etc/xray/xray.crt;
    ssl_certificate_key /etc/xray/xray.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL:10m;

    # CDN-friendly headers
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    # gRPC
    location ^~ /vless-grpc  { grpc_pass grpc://127.0.0.1:10004; grpc_set_header Host \$host; client_max_body_size 0; }
    location ^~ /trojan-grpc { grpc_pass grpc://127.0.0.1:10005; grpc_set_header Host \$host; client_max_body_size 0; }

    # WS Xray
    location = /vmess     { proxy_pass http://127.0.0.1:10001; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 300s; }
    location = /vless     { proxy_pass http://127.0.0.1:10002; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 300s; }
    location = /trojan-ws { proxy_pass http://127.0.0.1:10003; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 300s; }

    # SSH WS — multiple paths
    location = /ws-ssh    { proxy_pass http://127.0.0.1:8880; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 7200s; proxy_buffering off; }
    location = /ws        { proxy_pass http://127.0.0.1:8880; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 7200s; proxy_buffering off; }
    location = /ssh       { proxy_pass http://127.0.0.1:8880; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 7200s; proxy_buffering off; }
    location = /cdn       { proxy_pass http://127.0.0.1:8880; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 7200s; proxy_buffering off; }
    location = /tunnel    { proxy_pass http://127.0.0.1:8880; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_read_timeout 7200s; proxy_buffering off; }

    location / { return 200 'MAX PANEL OK'; add_header Content-Type text/plain; }
}

# === Alt-TLS 8443 ====================================================
server {
    listen 8443 ssl http2;
    listen [::]:8443 ssl http2;
    server_name ${DOMAIN} _;

    ssl_certificate     /etc/xray/xray.crt;
    ssl_certificate_key /etc/xray/xray.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    location ^~ /vless-grpc  { grpc_pass grpc://127.0.0.1:10004; grpc_set_header Host \$host; client_max_body_size 0; }
    location ^~ /trojan-grpc { grpc_pass grpc://127.0.0.1:10005; grpc_set_header Host \$host; client_max_body_size 0; }
    location = /vmess     { proxy_pass http://127.0.0.1:10001; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; }
    location = /vless     { proxy_pass http://127.0.0.1:10002; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; }
    location = /trojan-ws { proxy_pass http://127.0.0.1:10003; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; }
    location = /ws-ssh    { proxy_pass http://127.0.0.1:8880;  proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_buffering off; }
    location = /ws        { proxy_pass http://127.0.0.1:8880;  proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection \$connection_upgrade; proxy_set_header Host \$host; proxy_buffering off; }
    location / { return 200 'MAX PANEL OK'; add_header Content-Type text/plain; }
}
NGX

# ────────────────────────────────────────────────────────────
# 3. Test & restart Nginx
# ────────────────────────────────────────────────────────────
inf "Testing Nginx config..."
if nginx -t &>/dev/null; then
    ok "Nginx config valid"
    systemctl restart nginx
    if systemctl is-active --quiet nginx; then
        ok "Nginx restart sukses"
    else
        err "Nginx gagal start — cek: systemctl status nginx"
        exit 1
    fi
else
    err "Nginx config INVALID — restore backup"
    if [[ -f "/etc/nginx/conf.d/xray.conf.bak-${TS}" ]]; then
        cp "/etc/nginx/conf.d/xray.conf.bak-${TS}" /etc/nginx/conf.d/xray.conf
        nginx -t 2>&1 | tail -5
    fi
    exit 1
fi

# ────────────────────────────────────────────────────────────
# 4. Test endpoint dari localhost
# ────────────────────────────────────────────────────────────
echo ""
inf "Verifikasi endpoint dari localhost..."

test_path() {
    local proto="$1" port="$2" path="$3"
    local url
    if [[ "$proto" == "https" ]]; then
        url="https://127.0.0.1:${port}${path}"
        code=$(curl -sk -o /dev/null -w "%{http_code}" \
               -H "Host: ${DOMAIN}" -H "Upgrade: websocket" -H "Connection: Upgrade" \
               --max-time 5 "$url" 2>/dev/null)
    else
        url="http://127.0.0.1:${port}${path}"
        code=$(curl -s -o /dev/null -w "%{http_code}" \
               -H "Host: ${DOMAIN}" -H "Upgrade: websocket" -H "Connection: Upgrade" \
               --max-time 5 "$url" 2>/dev/null)
    fi

    if [[ "$code" == "101" || "$code" == "200" ]]; then
        ok "${proto}://...:${port}${path} → HTTP ${code}"
    else
        warn "${proto}://...:${port}${path} → HTTP ${code}"
    fi
}

# Port 80
for p in /ws-ssh /ws /ssh /cdn /tunnel; do
    test_path http 80 "$p"
done

# Port 443
for p in /ws-ssh /ws /ssh /cdn /tunnel; do
    test_path https 443 "$p"
done

# ────────────────────────────────────────────────────────────
# 5. Service WS proxy check
# ────────────────────────────────────────────────────────────
echo ""
inf "Status service ws-max-8880..."
if systemctl is-active --quiet ws-max-8880; then
    ok "ws-max-8880 — AKTIF"
else
    warn "ws-max-8880 — TIDAK AKTIF, restart..."
    systemctl restart ws-max-8880
    sleep 1
    systemctl is-active --quiet ws-max-8880 && ok "ws-max-8880 — AKTIF" || err "ws-max-8880 — GAGAL"
fi

# ────────────────────────────────────────────────────────────
# 6. Cloudflare reminder
# ────────────────────────────────────────────────────────────
echo ""
echo -e "  ${CYAN}══════════════════════════════════════════════${NC}"
echo -e "  ${BOLD}  Checklist Cloudflare Dashboard${NC}"
echo -e "  ${CYAN}══════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${YELLOW}Wajib di Cloudflare Dashboard:${NC}"
echo -e "    1. SSL/TLS → Overview → mode: ${GREEN}Flexible${NC} atau ${GREEN}Full${NC}"
echo -e "    2. SSL/TLS → Edge Certificates → Always Use HTTPS: ${RED}OFF${NC} (untuk NTLS)"
echo -e "    3. Network → WebSockets: ${GREEN}ON${NC}"
echo -e "    4. Network → Pseudo IPv4: ${RED}Off${NC}"
echo -e "    5. DNS: record A ${BOLD}${DOMAIN}${NC} → orange cloud ${YELLOW}(proxied)${NC}"
echo ""
echo -e "  ${CYAN}══════════════════════════════════════════════${NC}"
echo -e "  ${BOLD}  Setting HTTP Custom (di HP)${NC}"
echo -e "  ${CYAN}══════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}WS CDN NTLS (port 80):${NC}"
echo -e "    Mode    : ${GREEN}Direct${NC}"
echo -e "    Host    : ${GREEN}${DOMAIN}${NC}"
echo -e "    Port    : ${GREEN}80${NC}"
echo -e "    Payload : ${CYAN}GET / HTTP/1.1[crlf]Host: ${DOMAIN}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]${NC}"
echo ""
echo -e "  ${BOLD}WS CDN TLS (port 443):${NC}"
echo -e "    Mode    : ${GREEN}SSL/TLS${NC}"
echo -e "    Host    : ${GREEN}${DOMAIN}${NC}"
echo -e "    Port    : ${GREEN}443${NC}"
echo -e "    SNI     : ${GREEN}${DOMAIN}${NC}"
echo -e "    Payload : ${CYAN}GET / HTTP/1.1[crlf]Host: ${DOMAIN}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]${NC}"
echo ""
echo -e "  ${BOLD}Path bisa diganti:${NC} ${GREEN}/${NC} (root), ${GREEN}/ws${NC}, ${GREEN}/ws-ssh${NC}, ${GREEN}/ssh${NC}, ${GREEN}/cdn${NC}, ${GREEN}/tunnel${NC}"
echo ""
