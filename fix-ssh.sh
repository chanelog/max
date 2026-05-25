#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#   MAX PANEL — FIX SSH OFFLINE
#   Skrip darurat: pulihkan akses SSH yang hilang setelah update.
#
#   Kasus yang ditangani:
#     1. OpenSSH dipindah ke port 2222 (default panel) — kasih tau cara akses
#     2. Service ssh.service mati / config rusak
#     3. Dropbear bentrok port 22
#     4. Firewall iptables blokir port SSH
#
#   Pakai:
#     bash fix-ssh.sh           → diagnosis + auto-fix
#     bash fix-ssh.sh --port22  → paksa OpenSSH balik ke port 22
# ═══════════════════════════════════════════════════════════════

# Warna
R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'; B='\033[1;36m'; W='\033[1;37m'; D='\033[2m'; N='\033[0m'

ok()   { echo -e "  ${G}✔${N}  $*"; }
inf()  { echo -e "  ${B}➜${N}  $*"; }
warn() { echo -e "  ${Y}⚠${N}  $*"; }
err()  { echo -e "  ${R}✘${N}  $*"; }
sep()  { echo -e "  ${D}─────────────────────────────────────────────────────${N}"; }

# Cek root
if [[ $EUID -ne 0 ]]; then
    err "Jalankan sebagai root: sudo bash fix-ssh.sh"
    exit 1
fi

clear
echo ""
echo -e "  ${W}╔════════════════════════════════════════════╗${N}"
echo -e "  ${W}║   MAX PANEL — DIAGNOSIS & FIX SSH         ║${N}"
echo -e "  ${W}╚════════════════════════════════════════════╝${N}"
echo ""

# ═══════════════════════════════════════════════════════════════
# STEP 1: Diagnosis
# ═══════════════════════════════════════════════════════════════
echo -e "  ${W}[STEP 1] Diagnosis service & port${N}"
sep

# Cek status service
SSH_ACTIVE=0
if systemctl is-active --quiet ssh 2>/dev/null; then
    ok "ssh.service        : ${G}ACTIVE${N}"
    SSH_ACTIVE=1
elif systemctl is-active --quiet sshd 2>/dev/null; then
    ok "sshd.service       : ${G}ACTIVE${N}"
    SSH_ACTIVE=1
else
    err "ssh/sshd service   : ${R}NOT RUNNING${N}"
fi

if systemctl is-active --quiet dropbear 2>/dev/null; then
    ok "dropbear.service   : ${G}ACTIVE${N}"
else
    warn "dropbear.service   : ${Y}NOT RUNNING${N}"
fi

# Cek port yang listening
echo ""
inf "Port yang listening:"
if command -v ss &>/dev/null; then
    ss -tlnp 2>/dev/null | grep -E ':(22|2222|143|445|777)\b' \
        | awk '{printf "    %s  →  %s\n", $4, $NF}' \
        | sort -u
else
    netstat -tlnp 2>/dev/null | grep -E ':(22|2222|143|445|777)\b' \
        | awk '{printf "    %s  →  %s\n", $4, $NF}' \
        | sort -u
fi

# Cek config sshd
echo ""
inf "Config /etc/ssh/sshd_config (baris Port):"
grep -E '^[[:space:]]*Port[[:space:]]' /etc/ssh/sshd_config 2>/dev/null \
    | sed 's/^/    /' || echo -e "    ${R}(tidak ada baris Port — pakai default 22)${N}"

# Test config syntax
echo ""
if sshd -t 2>/dev/null; then
    ok "Syntax sshd_config : ${G}VALID${N}"
else
    err "Syntax sshd_config : ${R}INVALID${N}"
    sshd -t 2>&1 | sed 's/^/    /'
fi

# ═══════════════════════════════════════════════════════════════
# STEP 2: Auto-fix
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "  ${W}[STEP 2] Auto-fix${N}"
sep

MODE="auto"
[[ "$1" == "--port22" ]] && MODE="port22"

if [[ "$MODE" == "port22" ]]; then
    inf "Mode: ${Y}FORCE PORT 22${N} (OpenSSH balik ke port klasik)"

    # Stop dropbear (yang nempel di port 22)
    inf "Stop Dropbear (release port 22)..."
    systemctl stop dropbear 2>/dev/null

    # Update sshd_config: hapus Port 2222, set Port 22
    inf "Update sshd_config: Port 22..."
    sed -i '/^Port[[:space:]]\+2222$/d'  /etc/ssh/sshd_config
    sed -i '/^Port[[:space:]]\+22$/d'    /etc/ssh/sshd_config
    sed -i '/^#Port/d'                   /etc/ssh/sshd_config
    echo "Port 22" >> /etc/ssh/sshd_config

    # Pastikan PermitRootLogin yes (biar bisa login)
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

    # Pindah Dropbear ke port 143 saja (lepas port 22)
    if [[ -f /etc/default/dropbear ]]; then
        inf "Pindah Dropbear ke port 143 saja..."
        sed -i '/^DROPBEAR_PORT=/d' /etc/default/dropbear
        echo 'DROPBEAR_PORT=143' >> /etc/default/dropbear
        sed -i '/^DROPBEAR_EXTRA_ARGS=/d' /etc/default/dropbear
        echo 'DROPBEAR_EXTRA_ARGS=""' >> /etc/default/dropbear
    fi
else
    inf "Mode: ${G}AUTO-FIX${N} (pertahankan port 2222)"

    # Pastikan port 2222 ada
    if ! grep -qE '^Port[[:space:]]+2222$' /etc/ssh/sshd_config 2>/dev/null; then
        inf "Tambahkan Port 2222 ke sshd_config..."
        echo "Port 2222" >> /etc/ssh/sshd_config
    fi

    # Pastikan PermitRootLogin & PasswordAuth on
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
fi

# Buka firewall untuk port SSH (kalau iptables aktif)
if command -v iptables &>/dev/null; then
    inf "Buka firewall untuk port SSH..."
    if [[ "$MODE" == "port22" ]]; then
        iptables -I INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null
    else
        iptables -I INPUT -p tcp --dport 2222 -j ACCEPT 2>/dev/null
        iptables -I INPUT -p tcp --dport 22   -j ACCEPT 2>/dev/null
    fi
    iptables -I INPUT -p tcp --dport 143  -j ACCEPT 2>/dev/null
    netfilter-persistent save &>/dev/null || true
fi

# Test config sebelum restart
echo ""
inf "Test syntax sshd_config..."
if sshd -t 2>/dev/null; then
    ok "Syntax valid"
else
    err "Syntax INVALID — ROLLBACK!"
    sshd -t 2>&1 | sed 's/^/    /'
    echo ""
    err "Tidak akan restart SSH untuk menghindari lock-out!"
    err "Edit manual: nano /etc/ssh/sshd_config"
    exit 1
fi

# Restart services
echo ""
inf "Restart service..."

if systemctl restart ssh 2>/dev/null; then
    ok "ssh.service di-restart"
elif systemctl restart sshd 2>/dev/null; then
    ok "sshd.service di-restart"
else
    err "Gagal restart SSH service"
fi

if [[ "$MODE" == "port22" ]]; then
    if systemctl restart dropbear 2>/dev/null; then
        ok "Dropbear di-restart (port 143)"
    fi
else
    if systemctl restart dropbear 2>/dev/null; then
        ok "Dropbear di-restart (port 22, 143)"
    fi
fi

# ═══════════════════════════════════════════════════════════════
# STEP 3: Verifikasi
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "  ${W}[STEP 3] Verifikasi${N}"
sep
sleep 2

if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
    ok "SSH service: ${G}AKTIF${N}"
else
    err "SSH service: ${R}MASIH MATI${N}"
    err "Cek log: journalctl -u ssh -n 30"
    exit 1
fi

# IP server
IP=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')

# Cek port listening
echo ""
inf "Port SSH yang listening:"
ss -tlnp 2>/dev/null | grep -E ':(22|2222)\b' | awk '{printf "    ✓  %s  →  %s\n", $4, $NF}' || \
    netstat -tlnp 2>/dev/null | grep -E ':(22|2222)\b' | awk '{printf "    ✓  %s  →  %s\n", $4, $NF}'

# Info cara akses
echo ""
echo -e "  ${G}╔════════════════════════════════════════════╗${N}"
echo -e "  ${G}║         CARA AKSES SSH SEKARANG            ║${N}"
echo -e "  ${G}╚════════════════════════════════════════════╝${N}"
echo ""

if [[ "$MODE" == "port22" ]]; then
    echo -e "  ${W}OpenSSH (port 22):${N}"
    echo -e "      ${B}ssh root@${IP}${N}"
    echo ""
    echo -e "  ${W}Dropbear (port 143):${N}"
    echo -e "      ${B}ssh root@${IP} -p 143${N}"
else
    echo -e "  ${W}OpenSSH (port 2222 — RECOMMENDED):${N}"
    echo -e "      ${B}ssh root@${IP} -p 2222${N}"
    echo ""
    echo -e "  ${W}Dropbear (port 22 — kompatibel SSH biasa):${N}"
    echo -e "      ${B}ssh root@${IP}${N}"
    echo ""
    echo -e "  ${W}Dropbear (port 143):${N}"
    echo -e "      ${B}ssh root@${IP} -p 143${N}"
fi
echo ""
echo -e "  ${D}Kalau masih bermasalah, jalankan:${N}"
echo -e "      ${Y}bash fix-ssh.sh --port22${N}   ${D}(force OpenSSH ke port 22)${N}"
echo ""
