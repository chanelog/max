#!/bin/bash
# ════════════════════════════════════════════════════════════
#  FIX SERVICES — MAX PANEL
#  Aktifkan semua service yang merah (tidak aktif)
#  Jalankan sebagai root: bash fix-services.sh
# ════════════════════════════════════════════════════════════

RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'
CYAN='\033[1;36m'; NC='\033[0m'; BOLD='\033[1m'

[[ $EUID -ne 0 ]] && { echo -e "${RED}Jalankan sebagai root!${NC}"; exit 1; }

ok()   { echo -e "  ${GREEN}✔${NC}  $*"; }
err()  { echo -e "  ${RED}✘${NC}  $*"; }
inf()  { echo -e "  ${CYAN}➜${NC}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; }

echo ""
echo -e "  ${CYAN}══════════════════════════════════════════════${NC}"
echo -e "  ${BOLD}  MAX PANEL — Fix & Aktifkan Semua Service${NC}"
echo -e "  ${CYAN}══════════════════════════════════════════════${NC}"
echo ""

# ────────────────────────────────────────────────────────────
fix_svc() {
    local name="$1" display="${2:-$1}"
    if systemctl list-unit-files --quiet "$name" 2>/dev/null | grep -q "$name"; then
        systemctl enable "$name" --quiet 2>/dev/null
        systemctl restart "$name" 2>/dev/null
        sleep 1
        if systemctl is-active --quiet "$name"; then
            ok "$display — ${GREEN}AKTIF${NC}"
        else
            err "$display — ${RED}GAGAL${NC} (cek: journalctl -u $name -n 20)"
        fi
    else
        warn "$display — ${YELLOW}Unit tidak ditemukan${NC} (mungkin belum terinstall)"
    fi
}

# 1. SSH (OpenSSH) — port 22
inf "Mengecek SSH..."
fix_svc ssh "SSH (OpenSSH)"
fix_svc sshd "SSH (sshd)"

# 2. Dropbear — port 109, 143
inf "Mengecek Dropbear..."
if ! dpkg -l dropbear &>/dev/null 2>&1; then
    inf "Dropbear belum terinstall, menginstall..."
    apt-get install -y dropbear -qq 2>/dev/null && ok "Dropbear terinstall"
fi
if [[ -f /etc/default/dropbear ]]; then
    sed -i 's/^NO_START=1/NO_START=0/' /etc/default/dropbear
    sed -i 's/^DROPBEAR_PORT=.*/DROPBEAR_PORT=109/' /etc/default/dropbear
    grep -q 'DROPBEAR_EXTRA_ARGS' /etc/default/dropbear || \
        echo 'DROPBEAR_EXTRA_ARGS="-p 143"' >> /etc/default/dropbear
fi
fix_svc dropbear "Dropbear (DR)"

# 3. Stunnel4 — port 445, 777, 7777-internal
inf "Mengecek Stunnel4 (STN)..."
if ! command -v stunnel4 &>/dev/null; then
    apt-get install -y stunnel4 -qq 2>/dev/null && ok "Stunnel4 terinstall"
fi
[[ -f /etc/default/stunnel4 ]] && sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4
fix_svc stunnel4 "Stunnel4 (STN)"

# 4. Xray (XRY) — internal 10001-10005
inf "Mengecek Xray (XRY)..."
if [[ ! -x /usr/local/bin/xray ]]; then
    err "Binary Xray tidak ditemukan di /usr/local/bin/xray"
    warn "Jalankan installer MAX Panel untuk menginstall Xray"
else
    fix_svc xray "Xray (XRY)"
fi

# 5. SSLH multiplexer (port 443) — SSH/SSL/HTTP/WS
inf "Mengecek SSLH multiplexer (SLH)..."
if ! command -v sslh &>/dev/null; then
    echo 'sslh sslh/inetd_or_standalone select standalone' | debconf-set-selections 2>/dev/null
    apt-get install -y sslh -qq 2>/dev/null && ok "SSLH terinstall"
fi
if [[ -f /etc/default/sslh ]]; then
    if systemctl is-active --quiet apache2 2>/dev/null; then
        warn "Apache2 aktif — stop & disable"
        systemctl stop apache2 2>/dev/null
        systemctl disable apache2 2>/dev/null
    fi
    fix_svc sslh "SSLH multiplexer (SLH)"
else
    warn "SSLH: /etc/default/sslh belum ada — jalankan installer panel dulu"
fi

# 6. WS-epro (Websocket TLS/NTLS/Ovpn) — internal 8881 + public 2086
inf "Mengecek WS-epro (Websocket)..."
if [[ -x /usr/bin/ws && -f /usr/bin/tun.conf ]]; then
    fix_svc ws "WS-epro (Websocket)"
else
    warn "ws.service: binary atau tun.conf belum ada — jalankan installer panel dulu"
fi

# 7. Nginx (port 89 + internal 7443 + 8880 NTLS)
inf "Mengecek Nginx (reverse-proxy)..."
if ! command -v nginx &>/dev/null; then
    apt-get install -y nginx -qq 2>/dev/null && ok "Nginx terinstall"
fi
if [[ -f /etc/nginx/conf.d/xray.conf ]]; then
    fix_svc nginx "Nginx (reverse-proxy)"
else
    warn "Nginx: config xray.conf belum ada — jalankan installer panel dulu"
fi

# 8. BadVPN UDPGW — port 7100, 7200, 7300
inf "Mengecek BadVPN UDPGW..."
for p in 7100 7200 7300; do
    fix_svc "badvpn-udpgw-${p}" "BadVPN UDPGW ${p}"
done

# 9. OHP — port 8181 (SSH), 8282 (Dropbear), 8383 (OpenVPN)
inf "Mengecek OHP (HTTP Tunnel)..."
for n in ssh dropbear openvpn; do
    fix_svc "ohp-${n}" "OHP ${n}"
done

# 10. Squid Proxy — default OFF (3128, 8080)
inf "Mengecek Squid Proxy (default OFF)..."
if systemctl list-unit-files --quiet squid 2>/dev/null | grep -q squid; then
    if systemctl is-active --quiet squid; then
        ok "Squid Proxy — ${GREEN}AKTIF${NC} (manual enable)"
    else
        warn "Squid Proxy — ${YELLOW}OFF${NC} (sesuai default)"
    fi
fi

# Reload daemon & ringkasan
echo ""
systemctl daemon-reload 2>/dev/null
echo -e "  ${CYAN}══════════════════════════════════════════════${NC}"
echo -e "  ${BOLD}  Status Akhir${NC}"
echo -e "  ${CYAN}══════════════════════════════════════════════${NC}"
echo ""

services=(ssh dropbear stunnel4 xray sslh ws nginx
          badvpn-udpgw-7100 badvpn-udpgw-7200 badvpn-udpgw-7300
          ohp-ssh ohp-dropbear ohp-openvpn squid)
labels=(SSH DR STN XRY SLH WS NGX
        UDP1 UDP2 UDP3
        OHP-SSH OHP-DR OHP-OVPN SQ)

for i in "${!services[@]}"; do
    svc="${services[$i]}"
    lbl="${labels[$i]}"
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "  ${GREEN}●${NC} ${lbl} (${svc}) — ${GREEN}AKTIF${NC}"
    elif [[ "$svc" == "squid" ]]; then
        echo -e "  ${YELLOW}●${NC} ${lbl} (${svc}) — ${YELLOW}OFF (default)${NC}"
    else
        echo -e "  ${RED}●${NC} ${lbl} (${svc}) — ${RED}TIDAK AKTIF${NC}"
    fi
done

echo ""
echo -e "  ${YELLOW}Tip:${NC} Jika masih ada yang merah, jalankan installer panel dulu:"
echo -e "  ${CYAN}bash setup-max.sh${NC}"
echo ""
