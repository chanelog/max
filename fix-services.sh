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
# Fungsi enable + start service
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

# ────────────────────────────────────────────────────────────
# 1. SSH (OpenSSH)
# ────────────────────────────────────────────────────────────
inf "Mengecek SSH..."
fix_svc ssh "SSH (OpenSSH)"
fix_svc sshd "SSH (sshd)"  # fallback nama alternatif

# ────────────────────────────────────────────────────────────
# 2. Dropbear
# ────────────────────────────────────────────────────────────
inf "Mengecek Dropbear..."
if ! dpkg -l dropbear &>/dev/null 2>&1; then
    inf "Dropbear belum terinstall, menginstall..."
    apt-get install -y dropbear -qq 2>/dev/null && ok "Dropbear terinstall"
fi
# Aktifkan port 109 dan 143
if [[ -f /etc/default/dropbear ]]; then
    sed -i 's/^NO_START=1/NO_START=0/' /etc/default/dropbear
    sed -i 's/^DROPBEAR_PORT=.*/DROPBEAR_PORT=109/' /etc/default/dropbear
    grep -q 'DROPBEAR_EXTRA_ARGS' /etc/default/dropbear || \
        echo 'DROPBEAR_EXTRA_ARGS="-p 143"' >> /etc/default/dropbear
fi
fix_svc dropbear "Dropbear (DR)"

# ────────────────────────────────────────────────────────────
# 3. Stunnel4
# ────────────────────────────────────────────────────────────
inf "Mengecek Stunnel4 (STN)..."
if ! command -v stunnel4 &>/dev/null; then
    inf "Stunnel4 belum terinstall, menginstall..."
    apt-get install -y stunnel4 -qq 2>/dev/null && ok "Stunnel4 terinstall"
fi
# Aktifkan Stunnel
[[ -f /etc/default/stunnel4 ]] && sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4
# Buat config minimal jika belum ada
if [[ ! -f /etc/stunnel/stunnel.conf ]] && ls /etc/stunnel/*.conf 2>/dev/null | head -1 | grep -q conf; then
    : # sudah ada config
elif [[ ! -s /etc/stunnel/stunnel.conf ]]; then
    warn "Config stunnel tidak ditemukan — pastikan /etc/stunnel/*.conf sudah dikonfigurasi panel"
fi
fix_svc stunnel4 "Stunnel4 (STN)"

# ────────────────────────────────────────────────────────────
# 4. Xray
# ────────────────────────────────────────────────────────────
inf "Mengecek Xray (XRY)..."
if [[ ! -x /usr/local/bin/xray ]]; then
    err "Binary Xray tidak ditemukan di /usr/local/bin/xray"
    warn "Jalankan installer MAX Panel untuk menginstall Xray"
else
    fix_svc xray "Xray (XRY)"
fi

# ────────────────────────────────────────────────────────────
# 5. Trojan-Go (TGO)
# ────────────────────────────────────────────────────────────
inf "Mengecek Trojan-Go (TGO)..."
if [[ ! -x /usr/local/bin/trojan-go ]]; then
    err "Binary trojan-go tidak ditemukan"
    warn "Jalankan installer MAX Panel untuk menginstall Trojan-Go"
else
    fix_svc trojan-go "Trojan-Go (TGO)"
fi

# ────────────────────────────────────────────────────────────
# 6. Hysteria (HY)
# ────────────────────────────────────────────────────────────
inf "Mengecek Hysteria (HY)..."
if [[ ! -x /usr/local/bin/hysteria ]]; then
    err "Binary hysteria tidak ditemukan"
    warn "Jalankan installer MAX Panel untuk menginstall Hysteria"
else
    # Coba nama service yang mungkin
    fix_svc hysteria-server "Hysteria (HY)"
fi

# ────────────────────────────────────────────────────────────
# 7. OpenVPN (OVPN)
# ────────────────────────────────────────────────────────────
inf "Mengecek OpenVPN (OVPN)..."
if ! command -v openvpn &>/dev/null; then
    inf "OpenVPN belum terinstall, menginstall..."
    apt-get install -y openvpn -qq 2>/dev/null && ok "OpenVPN terinstall"
fi
fix_svc openvpn "OpenVPN (OVPN)"
# Coba juga dengan nama spesifik
if ! systemctl is-active --quiet openvpn; then
    fix_svc "openvpn@server" "OpenVPN@server (OVPN)"
fi

# ────────────────────────────────────────────────────────────
# 8. WireGuard (WG)
# ────────────────────────────────────────────────────────────
inf "Mengecek WireGuard (WG)..."
if ! command -v wg &>/dev/null; then
    inf "WireGuard belum terinstall, menginstall..."
    apt-get install -y wireguard -qq 2>/dev/null && ok "WireGuard terinstall"
fi
if [[ -f /etc/wireguard/wg0.conf ]]; then
    fix_svc "wg-quick@wg0" "WireGuard (WG)"
else
    warn "WireGuard: /etc/wireguard/wg0.conf belum ada — perlu dikonfigurasi panel dulu"
fi

# ────────────────────────────────────────────────────────────
# 9. Squid Proxy (SQ) — port 80, 8000, 3128
# ────────────────────────────────────────────────────────────
inf "Mengecek Squid Proxy (SQ)..."
if ! command -v squid &>/dev/null; then
    inf "Squid belum terinstall, menginstall..."
    apt-get install -y squid -qq 2>/dev/null && ok "Squid terinstall"
fi
if [[ -f /etc/squid/squid.conf ]]; then
    # Pastikan port 80 tidak dipegang process lain (mis. apache2)
    if systemctl is-active --quiet apache2 2>/dev/null; then
        warn "Apache2 aktif di port 80 — stop & disable"
        systemctl stop apache2 2>/dev/null
        systemctl disable apache2 2>/dev/null
    fi
    fix_svc squid "Squid Proxy (SQ)"
else
    warn "Squid: /etc/squid/squid.conf belum ada — jalankan installer panel dulu"
fi

# ────────────────────────────────────────────────────────────
# 10. WS-epro (SSH WebSocket)
# ────────────────────────────────────────────────────────────
inf "Mengecek WS-epro (SSH WebSocket)..."
if [[ -x /usr/bin/ws && -f /usr/bin/tun.conf ]]; then
    fix_svc ws "WS-epro (SSH WebSocket)"
else
    warn "ws.service: binary atau tun.conf belum ada — jalankan installer panel dulu"
fi

# ────────────────────────────────────────────────────────────
# 11. Nginx (reverse-proxy 81/443/8443/8880)
# ────────────────────────────────────────────────────────────
inf "Mengecek Nginx (reverse-proxy)..."
if ! command -v nginx &>/dev/null; then
    inf "Nginx belum terinstall, menginstall..."
    apt-get install -y nginx -qq 2>/dev/null && ok "Nginx terinstall"
fi
if [[ -f /etc/nginx/conf.d/xray.conf ]]; then
    fix_svc nginx "Nginx (reverse-proxy)"
else
    warn "Nginx: config xray.conf belum ada — jalankan installer panel dulu"
fi

# ────────────────────────────────────────────────────────────
# Reload daemon & ringkasan
# ────────────────────────────────────────────────────────────
echo ""
systemctl daemon-reload 2>/dev/null
echo -e "  ${CYAN}══════════════════════════════════════════════${NC}"
echo -e "  ${BOLD}  Status Akhir${NC}"
echo -e "  ${CYAN}══════════════════════════════════════════════${NC}"
echo ""

services=(ssh dropbear stunnel4 xray trojan-go hysteria-server openvpn "wg-quick@wg0" squid ws nginx)
labels=(SSH DR STN XRY TGO HY OVPN WG SQ WS NGX)

for i in "${!services[@]}"; do
    svc="${services[$i]}"
    lbl="${labels[$i]}"
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "  ${GREEN}●${NC} ${lbl} (${svc}) — ${GREEN}AKTIF${NC}"
    else
        echo -e "  ${RED}●${NC} ${lbl} (${svc}) — ${RED}TIDAK AKTIF${NC}"
    fi
done

echo ""
echo -e "  ${YELLOW}Tip:${NC} Jika masih ada yang merah, jalankan installer panel dulu:"
echo -e "  ${CYAN}bash setup-max.sh${NC}"
echo ""
