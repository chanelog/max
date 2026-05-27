#!/bin/bash
# ════════════════════════════════════════════════════════════
#   MAX PANEL — Full Uninstaller (Clean Slate)
#   Repo: https://github.com/chanelog/max
# ────────────────────────────────────────────────────────────
#   Hapus seluruh jejak MAX PANEL dari VPS:
#     • Service systemd (xray, ws.service, ohp-*, badvpn-udpgw-*, sslh)
#     • Binary di /usr/bin & /usr/local/bin
#     • Config /etc/{maxpanel,xray,stunnel,squid,nginx/conf.d/xray}
#     • Nginx vhost panel
#     • User sistem yang dibuat panel (SSH)
#     • Cron job, splash banner, alias, log
#     • iptables rule yang di-inject panel
#     • Backup lokal (opsional, konfirmasi)
#
#   Setelah selesai: VPS bersih, siap install ulang setup-max.sh
# ════════════════════════════════════════════════════════════

set +e

# ── Warna ──────────────────────────────────────────────────────────
R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'; C='\033[1;36m'
W='\033[1;37m'; D='\033[2m'; NC='\033[0m'; BLD='\033[1m'

ok()   { echo -e "  ${G}✔${NC}  $*"; }
inf()  { echo -e "  ${C}➜${NC}  $*"; }
warn() { echo -e "  ${Y}⚠${NC}  $*"; }
err()  { echo -e "  ${R}✘${NC}  $*"; }
hdr()  { echo -e "\n${C}═════ $* ═════${NC}"; }

# ── Cek root ──────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    err "Jalankan sebagai root: sudo bash $0"
    exit 1
fi

# ── Banner & konfirmasi ────────────────────────────────────────────
clear
echo -e "${R}${BLD}"
cat <<'B'
  ╔══════════════════════════════════════════════════════════╗
  ║                                                          ║
  ║       MAX PANEL — FULL UNINSTALLER (CLEAN SLATE)         ║
  ║                                                          ║
  ║   ⚠  Akan menghapus SELURUH jejak MAX PANEL dari VPS    ║
  ║      Termasuk semua user, config, binary, & service.    ║
  ║                                                          ║
  ╚══════════════════════════════════════════════════════════╝
B
echo -e "${NC}"
echo -e "  ${Y}IP server  :${NC} $(hostname -I 2>/dev/null | awk '{print $1}')"
echo -e "  ${Y}Hostname   :${NC} $(hostname)"
echo -e "  ${Y}OS         :${NC} $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")"
echo ""
echo -ne "  ${R}Ketik ${BLD}UNINSTALL${NC}${R} untuk melanjutkan${NC}: "
read -r CONFIRM
[[ "$CONFIRM" != "UNINSTALL" ]] && { warn "Dibatalkan."; exit 0; }

echo -ne "  ${Y}Hapus juga file backup di /root/maxpanel-backup?${NC} [y/N]: "
read -r DEL_BACKUP
DEL_BACKUP="${DEL_BACKUP,,}"

echo ""

# ════════════════════════════════════════════════════════════
hdr "1/8  Menghentikan & disable semua service panel"
# ════════════════════════════════════════════════════════════
SVCS=(
    # Core panel services
    xray
    nginx
    stunnel4
    dropbear
    sslh
    squid

    # WebSocket
    ws.service ws

    # OHP (3 instance)
    ohp ohp-ssh ohp-dropbear ohp-openvpn

    # BadVPN UDPGW (multi-port)
    badvpn-udpgw-7100 badvpn-udpgw-7200 badvpn-udpgw-7300
)

for s in "${SVCS[@]}"; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${s}\\.service" \
        || systemctl list-units --all 2>/dev/null | grep -q "${s}"; then
        systemctl stop    "$s" 2>/dev/null && ok "stop  ${s}"
        systemctl disable "$s" 2>/dev/null
    fi
done

# Kill leftover proses
pkill -9 -f '/usr/bin/ws ' 2>/dev/null
pkill -9 -f 'xray'         2>/dev/null
pkill -9 -f 'ohpserver'    2>/dev/null
pkill -9 -f 'badvpn-udpgw' 2>/dev/null

# ════════════════════════════════════════════════════════════
hdr "2/8  Menghapus systemd unit files"
# ════════════════════════════════════════════════════════════
SYSD=/etc/systemd/system
UNITS=(
    xray.service
    ohp.service ohp-ssh.service ohp-dropbear.service ohp-openvpn.service
    ws.service
    badvpn-udpgw-7100.service badvpn-udpgw-7200.service badvpn-udpgw-7300.service
)

for u in "${UNITS[@]}"; do
    if [[ -f "$SYSD/$u" ]]; then
        rm -f "$SYSD/$u" && ok "rm    $SYSD/$u"
    fi
done
rm -f "$SYSD"/badvpn-udpgw-*.service "$SYSD"/ohp-*.service 2>/dev/null

systemctl daemon-reload
systemctl reset-failed 2>/dev/null

# ════════════════════════════════════════════════════════════
hdr "3/8  Menghapus binary"
# ════════════════════════════════════════════════════════════
BINS=(
    /usr/bin/ws
    /usr/bin/tun.conf
    /usr/local/bin/xray
    /usr/local/bin/badvpn-udpgw
    /usr/local/bin/ohpserver
    /usr/local/bin/menu-max
    /usr/local/bin/max-menu
)
for b in "${BINS[@]}"; do
    if [[ -e "$b" ]]; then
        rm -f "$b" && ok "rm    $b"
    fi
done

# ════════════════════════════════════════════════════════════
hdr "4/8  Hapus user sistem yang dibuat panel"
# ════════════════════════════════════════════════════════════
DBS=(
    /etc/maxpanel/ssh-users.db
)

for db in "${DBS[@]}"; do
    [[ -s "$db" ]] || continue
    while IFS='|' read -r u _ _ _; do
        [[ -z "$u" || "$u" == "root" ]] && continue
        if id "$u" &>/dev/null; then
            userdel -r "$u" 2>/dev/null && ok "userdel $u"
        fi
    done < "$db"
done

# ════════════════════════════════════════════════════════════
hdr "5/8  Hapus direktori config"
# ════════════════════════════════════════════════════════════
DIRS=(
    /etc/maxpanel
    /etc/xray
    /var/log/xray
    /var/log/maxpanel
)
for d in "${DIRS[@]}"; do
    if [[ -d "$d" ]]; then
        rm -rf "$d" && ok "rm -rf $d"
    fi
done

# Stunnel — cleanup file panel saja
if [[ -f /etc/stunnel/stunnel.conf ]]; then
    rm -f /etc/stunnel/stunnel.conf \
          /etc/stunnel/stunnel.pem  \
          /etc/stunnel/key.pem      \
          /etc/stunnel/cert.pem 2>/dev/null
    ok "wipe stunnel config & cert"
fi

# Nginx vhost panel saja
rm -f /etc/nginx/conf.d/xray.conf 2>/dev/null && ok "rm    /etc/nginx/conf.d/xray.conf"

# Squid — restore default tanpa multi-port
if [[ -f /etc/squid/squid.conf ]]; then
    sed -i '/^# MAX PANEL — multi-port/,/^http_port 8080$/d' /etc/squid/squid.conf 2>/dev/null
    ok "restore squid default"
fi

# ════════════════════════════════════════════════════════════
hdr "6/8  Hapus cron jobs panel"
# ════════════════════════════════════════════════════════════
rm -f /etc/cron.d/maxpanel-* 2>/dev/null
rm -f /etc/cron.d/trial-* 2>/dev/null
ok "rm    /etc/cron.d/{maxpanel-*,trial-*}"

systemctl restart cron 2>/dev/null || service cron restart 2>/dev/null

# ════════════════════════════════════════════════════════════
hdr "7/8  Cleanup bashrc, profile, splash"
# ════════════════════════════════════════════════════════════
for rc in /root/.bashrc /root/.profile /etc/profile.d/max-panel.sh; do
    if [[ -f "$rc" ]]; then
        sed -i '/MAX-PANEL-SPLASH/d'        "$rc" 2>/dev/null
        sed -i '/max-panel-splash/d'        "$rc" 2>/dev/null
        sed -i '/alias menu-max=/d'         "$rc" 2>/dev/null
        sed -i '/alias max-menu=/d'         "$rc" 2>/dev/null
    fi
done
rm -f /etc/profile.d/max-panel.sh \
      /etc/max-panel-splash.sh 2>/dev/null
ok "wipe alias menu-max / splash banner"

# Restore SSH config
if [[ -f /etc/ssh/sshd_config ]]; then
    if grep -qE '^Port[[:space:]]+2222$' /etc/ssh/sshd_config; then
        sed -i '/^Port[[:space:]]\+2222$/d' /etc/ssh/sshd_config
        warn "OpenSSH: dihapus 'Port 2222' dari sshd_config"
    fi
fi

# Restore Dropbear default
if [[ -f /etc/default/dropbear ]]; then
    sed -i '/^DROPBEAR_PORT=/d'       /etc/default/dropbear 2>/dev/null
    sed -i '/^DROPBEAR_EXTRA_ARGS=/d' /etc/default/dropbear 2>/dev/null
fi

# Bersihkan sysctl tuning blok
for f in /etc/sysctl.conf; do
    [[ -f "$f" ]] || continue
    sed -i '/^# >>> MAXPANEL-.*>>>$/,/^# <<< MAXPANEL-.*<<<$/d' "$f" 2>/dev/null
done
rm -f /etc/modules-load.d/maxpanel.conf 2>/dev/null
ok "wipe sysctl MAXPANEL-* blocks"

# ════════════════════════════════════════════════════════════
hdr "8/8  Hapus backup lokal (opsional)"
# ════════════════════════════════════════════════════════════
if [[ "$DEL_BACKUP" == "y" ]]; then
    if [[ -d /root/maxpanel-backup ]]; then
        rm -rf /root/maxpanel-backup
        ok "rm -rf /root/maxpanel-backup"
    fi
else
    if [[ -d /root/maxpanel-backup ]]; then
        warn "Backup di /root/maxpanel-backup DIPERTAHANKAN"
    fi
fi

# Final daemon-reload
systemctl daemon-reload
systemctl reset-failed 2>/dev/null

# ════════════════════════════════════════════════════════════
echo ""
echo -e "${G}${BLD}═══════════════════════════════════════════════════════════"
echo -e "  ✦  MAX PANEL berhasil di-uninstall sepenuhnya"
echo -e "═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${C}Selanjutnya:${NC} install ulang script terbaru"
echo ""
echo -e "  ${W}wget -O setup-max.sh https://raw.githubusercontent.com/chanelog/max/main/setup-max.sh${NC}"
echo -e "  ${W}chmod +x setup-max.sh && bash setup-max.sh${NC}"
echo ""
warn "Disarankan REBOOT VPS sebelum install ulang: ${W}reboot${NC}"
echo ""
