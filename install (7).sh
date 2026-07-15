#!/usr/bin/env bash
#
# ============================================================================
#  SSHWS + XRAY PANEL INSTALLER
#  Auto installer: OpenSSH-WS, Dropbear-WS, Stunnel, Nginx, HAProxy,
#                   Xray-core (VMess/VLESS/Trojan over WS+TLS), BadVPN-UDPGW,
#                   ACME.sh (Let's Encrypt), fail2ban, vnstat
#
#  Sumber bahan   : https://github.com/chanelog/bin
#  Target OS      : Ubuntu 20.04 / 22.04 / 24.04  |  Debian 10 / 11 / 12
#  Wajib          : root, domain yang A record-nya SUDAH mengarah ke IP VPS
# ============================================================================

set -uo pipefail

# ---------------------------------------------------------------------------
# GLOBAL VARIABLES
# ---------------------------------------------------------------------------
BIN_REPO="https://raw.githubusercontent.com/chanelog/bin/main"
PANEL_DIR="/etc/vpn-panel"
PANEL_CONF="${PANEL_DIR}/panel.conf"
SSHWS_DIR="/etc/sshws"
SSHWS_INFO="${SSHWS_DIR}/info"
XRAY_DIR="/usr/local/etc/xray"
XRAY_BIN="/usr/local/bin/xray"
LOG_FILE="/var/log/vpn-panel-install.log"
CERT_DIR="/etc/vpn-panel/cert"

DOMAIN=""
IP_VPS=""
ARCH=""
OS_NAME=""
OS_VER=""

# Port map (dipakai konsisten di seluruh script & menu)
PORT_SSH_OPENSSH="22"
PORT_SSH_DROPBEAR="109"
PORT_SSH_OPENSSH_SSL="444"
PORT_SSH_DROPBEAR_SSL="777"
PORT_HAPROXY_TLS="443"
PORT_NGINX_HTTP="80"
PORT_NGINX_TLS_INTERNAL="8443"
PORT_UDPGW="7300"
PORT_XRAY_VMESS="10001"
PORT_XRAY_VLESS="10002"
PORT_XRAY_TROJAN="10003"
PORT_HAPROXY_STATS="9999"

WS_PATH_OPENSSH="/ssh-ws"
WS_PATH_DROPBEAR="/ssh-ws-dropbear"
WS_PATH_VMESS="/vmess"
WS_PATH_VLESS="/vless"
WS_PATH_TROJAN="/trojan-ws"

# ---------------------------------------------------------------------------
# COLORS & UI HELPERS
# ---------------------------------------------------------------------------
C_RESET="\e[0m"
C_CYAN="\e[0;36m"
C_GREEN="\e[0;32m"
C_RED="\e[0;31m"
C_YELLOW="\e[0;33m"
C_WHITE="\e[1;37m"
LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

banner() {
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    echo -e "${C_WHITE} $1${C_RESET}"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
}

step() {
    echo -e "\n${C_CYAN}▶ $1${C_RESET}"
}

ok() {
    echo -e "  ${C_GREEN}✓${C_RESET} $1"
}

warn() {
    echo -e "  ${C_YELLOW}⚠${C_RESET} $1"
}

err() {
    echo -e "  ${C_RED}✗ $1${C_RESET}"
}

die() {
    err "$1"
    echo -e "${C_RED}Instalasi dihentikan. Cek log: ${LOG_FILE}${C_RESET}"
    exit 1
}

# Jalankan perintah, log ke file, tampilkan pesan singkat only on error
run() {
    local desc="$1"; shift
    if "$@" >>"${LOG_FILE}" 2>&1; then
        ok "$desc"
        return 0
    else
        err "$desc (gagal — detail di ${LOG_FILE})"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# PREFLIGHT: root & OS check
# ---------------------------------------------------------------------------
check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        die "Script ini harus dijalankan sebagai root. Coba: sudo bash install.sh"
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        OS_NAME="${ID:-unknown}"
        OS_VER="${VERSION_ID:-0}"
    else
        die "Tidak bisa mendeteksi OS (/etc/os-release tidak ada)."
    fi

    case "$OS_NAME" in
        ubuntu|debian) ;;
        *) die "OS '$OS_NAME' belum didukung. Gunakan Ubuntu 20.04/22.04/24.04 atau Debian 10/11/12." ;;
    esac

    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64|amd64) ARCH="64" ;;
        aarch64|arm64) ARCH="arm64-v8a" ;;
        *) die "Arsitektur '$ARCH' belum didukung (hanya x86_64 / arm64)." ;;
    esac

    ok "OS terdeteksi: ${OS_NAME} ${OS_VER} (${ARCH})"
}

check_systemd() {
    if ! command -v systemctl >/dev/null 2>&1; then
        die "systemd tidak ditemukan. VPS ini tidak didukung (butuh systemd)."
    fi
    if [[ ! -d /run/systemd/system ]]; then
        die "systemd tidak berjalan sebagai init (PID 1). VPS/container ini tidak didukung."
    fi
}

# ---------------------------------------------------------------------------
# INPUT: domain & IP
# ---------------------------------------------------------------------------
detect_ip() {
    local ip=""
    ip="$(curl -s -4 --max-time 6 https://api.ipify.org || true)"
    if [[ -z "$ip" ]]; then
        ip="$(curl -s -4 --max-time 6 https://ifconfig.me || true)"
    fi
    if [[ -z "$ip" ]]; then
        ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi
    IP_VPS="$ip"
}

validate_domain() {
    local d="$1"
    [[ "$d" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

ask_domain() {
    detect_ip
    echo ""
    banner "KONFIGURASI DOMAIN"
    echo -e "  IP VPS terdeteksi : ${C_GREEN}${IP_VPS:-tidak terdeteksi}${C_RESET}"
    echo -e "  ${C_YELLOW}Pastikan domain kamu (A record) sudah mengarah ke IP di atas.${C_RESET}"
    echo ""

    if [[ -n "${DOMAIN_ARG:-}" ]]; then
        DOMAIN="$DOMAIN_ARG"
    else
        while true; do
            read -rp "  Masukkan domain (contoh: vpn.domainkamu.com): " DOMAIN
            if validate_domain "$DOMAIN"; then
                break
            else
                err "Format domain tidak valid, coba lagi."
            fi
        done
    fi

    echo ""
    read -rp "  Lanjutkan instalasi untuk domain '${DOMAIN}'? [Y/n]: " CONFIRM
    CONFIRM="${CONFIRM:-Y}"
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        die "Instalasi dibatalkan oleh user."
    fi
}

# ---------------------------------------------------------------------------
# BASE DEPENDENCIES
# ---------------------------------------------------------------------------
install_base_deps() {
    step "Install paket dasar"
    export DEBIAN_FRONTEND=noninteractive
    run "Update daftar paket (apt update)" apt-get update -y
    run "Install paket dasar (curl, wget, unzip, cron, dll)" apt-get install -y \
        curl wget unzip zip socat cron bc jq uuid-runtime openssl \
        dnsutils netcat-openbsd iproute2 lsb-release ca-certificates \
        gnupg net-tools cron xxd coreutils speedtest-cli
    run "Aktifkan layanan cron" systemctl enable --now cron
}

set_timezone() {
    step "Konfigurasi timezone & hostname"
    run "Set timezone ke Asia/Jakarta" timedatectl set-timezone Asia/Jakarta
}

# ---------------------------------------------------------------------------
# PANEL DIRECTORY
# ---------------------------------------------------------------------------
prepare_panel_dirs() {
    mkdir -p "$PANEL_DIR" "$SSHWS_DIR" "$XRAY_DIR" "$CERT_DIR" \
             /etc/vpn-panel/xray-users /var/log/vpn-panel
    touch "$LOG_FILE"
}

# ---------------------------------------------------------------------------
# AMBIL BAHAN DARI REPO chanelog/bin
# ---------------------------------------------------------------------------
fetch_bin_repo_assets() {
    step "Ambil bahan dari repo chanelog/bin"
    local tmp="/tmp/chanelog-bin"
    mkdir -p "$tmp"

    run "Download Xray-core (Xray-linux-${ARCH}.zip)" \
        wget -q -O "${tmp}/xray.zip" "${BIN_REPO}/Xray-linux-${ARCH}.zip"
    (cd "$tmp" && unzip -o -q xray.zip -d xray_extract) >>"${LOG_FILE}" 2>&1
    if [[ -f "${tmp}/xray_extract/xray" ]]; then
        install -m 755 "${tmp}/xray_extract/xray" "$XRAY_BIN"
        install -m 644 "${tmp}/xray_extract/geoip.dat" "${XRAY_DIR}/geoip.dat" 2>/dev/null
        install -m 644 "${tmp}/xray_extract/geosite.dat" "${XRAY_DIR}/geosite.dat" 2>/dev/null
        ok "Xray-core terpasang di ${XRAY_BIN}"
    else
        die "Gagal mengekstrak Xray-core dari repo."
    fi

    run "Download acme.sh" wget -q -O "${tmp}/acme.sh" "${BIN_REPO}/acme.sh"
    chmod +x "${tmp}/acme.sh"

    run "Download tools SSH (bin.zip)" wget -q -O "${tmp}/bin.zip" "${BIN_REPO}/bin.zip"
    (cd "$tmp" && unzip -o -q bin.zip -d sshtools) >>"${LOG_FILE}" 2>&1
    for f in add-ssh del-ssh list-ssh switch-domain switch-host uninstall-ssh; do
        if [[ -f "${tmp}/sshtools/${f}" ]]; then
            install -m 755 "${tmp}/sshtools/${f}" "/usr/local/bin/${f}"
        else
            warn "Tool ${f} tidak ditemukan di bin.zip, dilewati."
        fi
    done
    ok "Tools manajemen akun SSH terpasang di /usr/local/bin"

    run "Download BadVPN UDPGW" wget -q -O "/usr/local/bin/udpgw" "${BIN_REPO}/udpgw"
    chmod +x /usr/local/bin/udpgw

    # simpan acme.sh installer sementara untuk step berikutnya
    mkdir -p "${PANEL_DIR}/tmp"
    cp "${tmp}/acme.sh" "${PANEL_DIR}/tmp/acme.sh"
}

# ---------------------------------------------------------------------------
# OPENSSH (akun tunnel, port 22)
# ---------------------------------------------------------------------------
setup_openssh() {
    step "Konfigurasi OpenSSH (port ${PORT_SSH_OPENSSH})"
    run "Install openssh-server" apt-get install -y openssh-server

    local sshd_conf="/etc/ssh/sshd_config"
    cp -n "$sshd_conf" "${sshd_conf}.bak-panel" 2>/dev/null || true

    # Pastikan port 22 & password auth aktif (dibutuhkan akun tunnel)
    sed -i 's/^#\?Port .*/Port 22/' "$sshd_conf"
    sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' "$sshd_conf"
    sed -i 's/^#\?ClientAliveInterval .*/ClientAliveInterval 60/' "$sshd_conf"
    sed -i 's/^#\?ClientAliveCountMax .*/ClientAliveCountMax 3/' "$sshd_conf"
    grep -q "^ClientAliveInterval" "$sshd_conf" || echo "ClientAliveInterval 60" >> "$sshd_conf"
    grep -q "^ClientAliveCountMax" "$sshd_conf" || echo "ClientAliveCountMax 3" >> "$sshd_conf"

    run "Restart layanan ssh" systemctl restart ssh
    run "Aktifkan layanan ssh saat boot" systemctl enable ssh
}

# ---------------------------------------------------------------------------
# DROPBEAR (akun tunnel, port 109)
# ---------------------------------------------------------------------------
setup_dropbear() {
    step "Konfigurasi Dropbear (port ${PORT_SSH_DROPBEAR})"
    run "Install dropbear" apt-get install -y dropbear

    local dcfg="/etc/default/dropbear"
    if [[ -f "$dcfg" ]]; then
        sed -i "s/^DROPBEAR_PORT=.*/DROPBEAR_PORT=${PORT_SSH_DROPBEAR}/" "$dcfg"
        grep -q "^DROPBEAR_PORT=" "$dcfg" || echo "DROPBEAR_PORT=${PORT_SSH_DROPBEAR}" >> "$dcfg"
        sed -i 's/^NO_START=.*/NO_START=0/' "$dcfg"
    fi
    # Beberapa distro pakai systemd socket unit yang override port default
    mkdir -p /etc/systemd/system/dropbear.socket.d
    cat > /etc/systemd/system/dropbear.socket.d/override.conf << EOF
[Socket]
ListenStream=
ListenStream=${PORT_SSH_DROPBEAR}
EOF

    run "Reload systemd daemon" systemctl daemon-reload
    run "Restart layanan dropbear" systemctl restart dropbear || true
    run "Aktifkan layanan dropbear saat boot" systemctl enable dropbear || true
}

# ---------------------------------------------------------------------------
# WSTUNNEL (WS <-> TCP relay, backend untuk SSH & Dropbear over WebSocket)
# Dipakai karena OpenSSH/Dropbear tidak bisa langsung menerima proxy_pass
# websocket dari Nginx (mereka bicara protokol SSH mentah, bukan HTTP).
# wstunnel adalah web-server asli yang paham HTTP upgrade, jadi Nginx bisa
# reverse-proxy websocket ke wstunnel, lalu wstunnel neruskan ke SSH/Dropbear.
# ---------------------------------------------------------------------------
PORT_WSTUNNEL_OPENSSH="2087"
PORT_WSTUNNEL_DROPBEAR="2088"

setup_wstunnel() {
    step "Install wstunnel (WS relay untuk SSH & Dropbear)"
    local ver_tag
    ver_tag="$(curl -sIL https://github.com/erebe/wstunnel/releases/latest \
        | grep -i '^location' | tail -1 | sed -E 's#.*/tag/v##; s/[[:space:]]+$//')"
    if [[ -z "$ver_tag" ]]; then
        ver_tag="10.6.1"
        warn "Tidak bisa deteksi versi terbaru wstunnel, pakai fallback v${ver_tag}"
    fi

    local wsarch="amd64"
    [[ "$ARCH" == "arm64-v8a" ]] && wsarch="arm64"

    local url="https://github.com/erebe/wstunnel/releases/download/v${ver_tag}/wstunnel_${ver_tag}_linux_${wsarch}.tar.gz"
    local tmp="/tmp/wstunnel_dl"
    mkdir -p "$tmp"

    run "Download wstunnel v${ver_tag}" wget -q -O "${tmp}/wstunnel.tar.gz" "$url"
    (cd "$tmp" && tar -xzf wstunnel.tar.gz) >>"${LOG_FILE}" 2>&1
    if [[ -f "${tmp}/wstunnel" ]]; then
        install -m 755 "${tmp}/wstunnel" /usr/local/bin/wstunnel
        ok "wstunnel terpasang di /usr/local/bin/wstunnel"
    else
        die "Gagal mengambil binary wstunnel."
    fi

    cat > /etc/systemd/system/wstunnel-openssh.service << EOF
[Unit]
Description=WS Tunnel relay -> OpenSSH (internal)
After=network.target ssh.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/wstunnel server ws://127.0.0.1:${PORT_WSTUNNEL_OPENSSH} --restrict-to "127.0.0.1:${PORT_SSH_OPENSSH}"
Restart=always
RestartSec=3
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/wstunnel-dropbear.service << EOF
[Unit]
Description=WS Tunnel relay -> Dropbear (internal)
After=network.target dropbear.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/wstunnel server ws://127.0.0.1:${PORT_WSTUNNEL_DROPBEAR} --restrict-to "127.0.0.1:${PORT_SSH_DROPBEAR}"
Restart=always
RestartSec=3
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    run "Reload systemd daemon" systemctl daemon-reload
    run "Aktifkan wstunnel-openssh" systemctl enable --now wstunnel-openssh
    run "Aktifkan wstunnel-dropbear" systemctl enable --now wstunnel-dropbear
}

# ---------------------------------------------------------------------------
# NGINX (reverse proxy WebSocket untuk SSH-WS & Xray, terminasi TLS internal)
# ---------------------------------------------------------------------------
write_nginx_conf() {
    local tls_block="$1"   # "yes" untuk sertakan server block TLS 8443

    cat > /etc/nginx/sites-available/vpn-panel.conf << EOF
# ============ VPN PANEL - managed by install.sh, jangan edit manual ============
server {
    listen ${PORT_NGINX_HTTP};
    server_name ${DOMAIN};

    root /var/www/vpn-panel;
    index index.html;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/vpn-panel;
        default_type "text/plain";
    }

    location = / {
        default_type text/plain;
        return 200 "Active\\n";
    }

    location ${WS_PATH_OPENSSH} {
        proxy_pass http://127.0.0.1:${PORT_WSTUNNEL_OPENSSH};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location ${WS_PATH_DROPBEAR} {
        proxy_pass http://127.0.0.1:${PORT_WSTUNNEL_DROPBEAR};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location ${WS_PATH_VMESS} {
        proxy_pass http://127.0.0.1:${PORT_XRAY_VMESS};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
    }

    location ${WS_PATH_VLESS} {
        proxy_pass http://127.0.0.1:${PORT_XRAY_VLESS};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
    }

    location ${WS_PATH_TROJAN} {
        proxy_pass http://127.0.0.1:${PORT_XRAY_TROJAN};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
    }
}
EOF

    if [[ "$tls_block" == "yes" ]]; then
        cat >> /etc/nginx/sites-available/vpn-panel.conf << EOF

server {
    listen 127.0.0.1:${PORT_NGINX_TLS_INTERNAL} ssl http2;
    server_name ${DOMAIN};

    ssl_certificate     ${CERT_DIR}/fullchain.pem;
    ssl_certificate_key ${CERT_DIR}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root /var/www/vpn-panel;
    index index.html;

    location = / {
        default_type text/plain;
        return 200 "Active\\n";
    }

    location ${WS_PATH_OPENSSH} {
        proxy_pass http://127.0.0.1:${PORT_WSTUNNEL_OPENSSH};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location ${WS_PATH_DROPBEAR} {
        proxy_pass http://127.0.0.1:${PORT_WSTUNNEL_DROPBEAR};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location ${WS_PATH_VMESS} {
        proxy_pass http://127.0.0.1:${PORT_XRAY_VMESS};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
    }

    location ${WS_PATH_VLESS} {
        proxy_pass http://127.0.0.1:${PORT_XRAY_VLESS};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
    }

    location ${WS_PATH_TROJAN} {
        proxy_pass http://127.0.0.1:${PORT_XRAY_TROJAN};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
    }
}
EOF
    fi
}

setup_nginx_http_only() {
    step "Konfigurasi Nginx (HTTP dahulu, untuk validasi SSL)"
    run "Install nginx" apt-get install -y nginx
    mkdir -p /var/www/vpn-panel
    echo "<h1>${DOMAIN}</h1><p>Service Active.</p>" > /var/www/vpn-panel/index.html

    rm -f /etc/nginx/sites-enabled/default
    write_nginx_conf "no"
    ln -sf /etc/nginx/sites-available/vpn-panel.conf /etc/nginx/sites-enabled/vpn-panel.conf

    if nginx -t >>"${LOG_FILE}" 2>&1; then
        ok "Konfigurasi Nginx valid"
    else
        die "Konfigurasi Nginx tidak valid, cek ${LOG_FILE}"
    fi
    run "Restart nginx" systemctl restart nginx
    run "Aktifkan nginx saat boot" systemctl enable nginx
}

enable_nginx_tls() {
    step "Aktifkan blok TLS internal Nginx (port ${PORT_NGINX_TLS_INTERNAL})"
    write_nginx_conf "yes"
    if nginx -t >>"${LOG_FILE}" 2>&1; then
        ok "Konfigurasi Nginx (dengan TLS) valid"
        run "Reload nginx" systemctl reload nginx
    else
        die "Konfigurasi Nginx TLS tidak valid, cek ${LOG_FILE}"
    fi
}

# ---------------------------------------------------------------------------
# ACME.SH — SSL Let's Encrypt (webroot, lalu auto-renew)
# ---------------------------------------------------------------------------
issue_ssl_certificate() {
    step "Terbitkan sertifikat SSL Let's Encrypt untuk ${DOMAIN}"
    bash "${PANEL_DIR}/tmp/acme.sh" --install \
        --home "/root/.acme.sh" \
        --accountemail "admin@${DOMAIN}" \
        --nocron >>"${LOG_FILE}" 2>&1

    local acme_bin="/root/.acme.sh/acme.sh"

    run "Set default CA ke Let's Encrypt" "$acme_bin" --set-default-ca --server letsencrypt

    if "$acme_bin" --issue -d "${DOMAIN}" -w /var/www/vpn-panel --keylength ec-256 >>"${LOG_FILE}" 2>&1; then
        ok "Sertifikat berhasil diterbitkan untuk ${DOMAIN}"
    else
        warn "Gagal menerbitkan sertifikat asli. Membuat sertifikat self-signed sementara."
        openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
            -keyout "${CERT_DIR}/privkey.pem" -out "${CERT_DIR}/fullchain.pem" \
            -subj "/CN=${DOMAIN}" >>"${LOG_FILE}" 2>&1
        return 0
    fi

    cat > /usr/local/bin/vpn-panel-cert-sync.sh << EOF
#!/usr/bin/env bash
cat "${CERT_DIR}/fullchain.pem" "${CERT_DIR}/privkey.pem" > "${CERT_DIR}/stunnel.pem"
chmod 600 "${CERT_DIR}/stunnel.pem"
systemctl reload nginx  >/dev/null 2>&1
systemctl reload haproxy >/dev/null 2>&1
systemctl restart stunnel4 >/dev/null 2>&1
EOF
    chmod +x /usr/local/bin/vpn-panel-cert-sync.sh

    "$acme_bin" --install-cert -d "${DOMAIN}" --ecc \
        --fullchain-file "${CERT_DIR}/fullchain.pem" \
        --key-file "${CERT_DIR}/privkey.pem" \
        --reloadcmd "/usr/local/bin/vpn-panel-cert-sync.sh" \
        >>"${LOG_FILE}" 2>&1

    # acme.sh --install sudah otomatis menambahkan cron renew (--nocron di atas menonaktifkannya,
    # jadi kita buat sendiri agar waktunya konsisten & tercatat rapi)
    ( crontab -l 2>/dev/null | grep -v "acme.sh --cron"; \
      echo "15 3 * * * \"$acme_bin\" --cron --home \"/root/.acme.sh\" > /var/log/vpn-panel/acme-renew.log 2>&1" ) | crontab -
    ok "Auto-renew SSL terjadwal tiap hari jam 03:15"
}

# ---------------------------------------------------------------------------
# HELPER: gabungkan fullchain+key jadi satu file .pem (dibutuhkan stunnel)
# ---------------------------------------------------------------------------
sync_stunnel_cert() {
    if [[ -f "${CERT_DIR}/fullchain.pem" && -f "${CERT_DIR}/privkey.pem" ]]; then
        cat "${CERT_DIR}/fullchain.pem" "${CERT_DIR}/privkey.pem" > "${CERT_DIR}/stunnel.pem"
        chmod 600 "${CERT_DIR}/stunnel.pem"
    fi
}

# ---------------------------------------------------------------------------
# STUNNEL — bungkus SSH & Dropbear dengan TLS (port 444 & 777)
# ---------------------------------------------------------------------------
setup_stunnel() {
    step "Konfigurasi Stunnel (SSH-SSL & Dropbear-SSL)"
    run "Install stunnel4" apt-get install -y stunnel4
    sync_stunnel_cert

    cat > /etc/stunnel/stunnel.conf << EOF
; ============ VPN PANEL - managed by install.sh ============
pid = /var/run/stunnel4.pid
setuid = stunnel4
setgid = stunnel4
cert = ${CERT_DIR}/stunnel.pem
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[openssh-ssl]
accept = ${PORT_SSH_OPENSSH_SSL}
connect = 127.0.0.1:${PORT_SSH_OPENSSH}

[dropbear-ssl]
accept = ${PORT_SSH_DROPBEAR_SSL}
connect = 127.0.0.1:${PORT_SSH_DROPBEAR}
EOF

    if [[ -f /etc/default/stunnel4 ]]; then
        sed -i 's/^ENABLED=.*/ENABLED=1/' /etc/default/stunnel4
        grep -q "^ENABLED=" /etc/default/stunnel4 || echo "ENABLED=1" >> /etc/default/stunnel4
    fi

    run "Restart stunnel4" systemctl restart stunnel4
    run "Aktifkan stunnel4 saat boot" systemctl enable stunnel4
}

# ---------------------------------------------------------------------------
# HAPROXY — pintu masuk publik 443, SNI passthrough -> Nginx TLS internal
# ---------------------------------------------------------------------------
setup_haproxy() {
    step "Konfigurasi HAProxy (port ${PORT_HAPROXY_TLS} publik)"
    run "Install haproxy" apt-get install -y haproxy

    local stats_pass
    stats_pass="$(openssl rand -hex 8)"
    echo "$stats_pass" > "${PANEL_DIR}/haproxy_stats_pass"
    chmod 600 "${PANEL_DIR}/haproxy_stats_pass"

    cat > /etc/haproxy/haproxy.cfg << EOF
# ============ VPN PANEL - managed by install.sh, jangan edit manual ============
global
    log /dev/log local0
    maxconn 8192
    daemon
    tune.ssl.default-dh-param 2048

defaults
    log     global
    mode    tcp
    option  tcplog
    timeout connect 5s
    timeout client  1h
    timeout server  1h
    retries 2

# Pintu masuk publik 443: intip SNI dari ClientHello (tanpa buka enkripsi),
# lalu terusin apa adanya ke Nginx yang pegang sertifikat aslinya.
# Struktur ini juga jadi titik untuk nambah backend lain di masa depan
# (misal Xray Reality/gRPC) tinggal tambah rule 'use_backend ... if { req.ssl_sni ... }'.
frontend ft_public_tls
    bind *:${PORT_HAPROXY_TLS}
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }
    default_backend bk_nginx_tls

backend bk_nginx_tls
    server nginx_tls 127.0.0.1:${PORT_NGINX_TLS_INTERNAL} check

listen stats
    bind 127.0.0.1:${PORT_HAPROXY_STATS}
    mode http
    stats enable
    stats uri /
    stats refresh 10s
    stats auth admin:${stats_pass}
EOF

    if haproxy -c -f /etc/haproxy/haproxy.cfg >>"${LOG_FILE}" 2>&1; then
        ok "Konfigurasi HAProxy valid"
    else
        die "Konfigurasi HAProxy tidak valid, cek ${LOG_FILE}"
    fi
    run "Restart haproxy" systemctl restart haproxy
    run "Aktifkan haproxy saat boot" systemctl enable haproxy
}

# ---------------------------------------------------------------------------
# XRAY-CORE — VMess-WS, VLESS-WS, Trojan-WS (semua di belakang Nginx)
# ---------------------------------------------------------------------------
setup_xray() {
    step "Konfigurasi Xray-core"

    cat > "${XRAY_DIR}/config.json" << EOF
{
  "log": { "loglevel": "warning", "access": "/var/log/vpn-panel/xray/access.log", "error": "/var/log/vpn-panel/xray/error.log" },
  "inbounds": [
    {
      "tag": "vmess-ws",
      "listen": "127.0.0.1",
      "port": ${PORT_XRAY_VMESS},
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "${WS_PATH_VMESS}" } }
    },
    {
      "tag": "vless-ws",
      "listen": "127.0.0.1",
      "port": ${PORT_XRAY_VLESS},
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "${WS_PATH_VLESS}" } }
    },
    {
      "tag": "trojan-ws",
      "listen": "127.0.0.1",
      "port": ${PORT_XRAY_TROJAN},
      "protocol": "trojan",
      "settings": { "clients": [] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "${WS_PATH_TROJAN}" } }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "blocked" }
  ]
}
EOF

    if ! id xray >/dev/null 2>&1; then
        useradd -r -M -s /usr/sbin/nologin xray >>"${LOG_FILE}" 2>&1
    fi
    # Pastikan grup xray benar-benar ada & jadi grup utama user xray
    # (di sebagian image, useradd -r tidak otomatis bikin grup senama).
    if ! getent group xray >/dev/null 2>&1; then
        groupadd -r xray >>"${LOG_FILE}" 2>&1
    fi
    usermod -g xray xray >>"${LOG_FILE}" 2>&1 || true

    mkdir -p /var/log/vpn-panel/xray
    run "Set kepemilikan direktori Xray & log ke user xray" \
        chown -R xray:xray "$XRAY_DIR" /var/log/vpn-panel/xray

    cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target

[Service]
Type=simple
User=xray
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=${XRAY_BIN} run -config ${XRAY_DIR}/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    if "$XRAY_BIN" run -test -config "${XRAY_DIR}/config.json" >>"${LOG_FILE}" 2>&1; then
        ok "Konfigurasi Xray valid"
    else
        die "Konfigurasi Xray tidak valid, cek ${LOG_FILE}"
    fi

    run "Reload systemd daemon" systemctl daemon-reload
    run "Aktifkan & start xray" systemctl enable --now xray
}

# ---------------------------------------------------------------------------
# BADVPN-UDPGW — forwarding UDP (game/voice) via SSH tunnel
# ---------------------------------------------------------------------------
setup_udpgw() {
    step "Konfigurasi BadVPN UDPGW (port ${PORT_UDPGW}/udp)"

    cat > /etc/systemd/system/badvpn-udpgw.service << EOF
[Unit]
Description=BadVPN UDPGW Forwarder
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/local/bin/udpgw --listen-addr 127.0.0.1:${PORT_UDPGW} --max-clients 1024 --max-connections-for-client 20
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    run "Reload systemd daemon" systemctl daemon-reload
    run "Aktifkan & start badvpn-udpgw" systemctl enable --now badvpn-udpgw
}

# ---------------------------------------------------------------------------
# FAIL2BAN — proteksi brute-force SSH
# ---------------------------------------------------------------------------
setup_fail2ban() {
    step "Konfigurasi Fail2ban"
    run "Install fail2ban" apt-get install -y fail2ban
    run "Install python3-systemd (backend journald)" apt-get install -y python3-systemd

    cat > /etc/fail2ban/jail.d/vpn-panel.conf << EOF
[sshd]
enabled  = true
backend  = systemd
port     = ${PORT_SSH_OPENSSH},${PORT_SSH_OPENSSH_SSL}
maxretry = 5
findtime = 600
bantime  = 3600
EOF

    run "Restart fail2ban" systemctl restart fail2ban
    run "Aktifkan fail2ban saat boot" systemctl enable fail2ban
}

# ---------------------------------------------------------------------------
# VNSTAT — monitor bandwidth
# ---------------------------------------------------------------------------
setup_vnstat() {
    step "Konfigurasi vnstat (monitor bandwidth)"
    run "Install vnstat" apt-get install -y vnstat
    local iface
    iface="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}' | head -1)"
    if [[ -n "$iface" ]]; then
        vnstat --add -i "$iface" >>"${LOG_FILE}" 2>&1 || true
        echo "$iface" > "${PANEL_DIR}/net_iface"
    fi
    run "Restart vnstat" systemctl restart vnstat
    run "Aktifkan vnstat saat boot" systemctl enable vnstat
}

# ---------------------------------------------------------------------------
# FIREWALL (ufw) — buka semua port yang dipakai panel
# ---------------------------------------------------------------------------
setup_firewall() {
    step "Konfigurasi firewall (ufw)"
    if ! command -v ufw >/dev/null 2>&1; then
        apt-get install -y ufw >>"${LOG_FILE}" 2>&1
    fi
    for p in "${PORT_SSH_OPENSSH}" "${PORT_SSH_DROPBEAR}" "${PORT_SSH_OPENSSH_SSL}" \
             "${PORT_SSH_DROPBEAR_SSL}" "${PORT_NGINX_HTTP}" "${PORT_HAPROXY_TLS}"; do
        ufw allow "${p}/tcp" >>"${LOG_FILE}" 2>&1 || true
    done
    ufw allow "${PORT_UDPGW}/udp" >>"${LOG_FILE}" 2>&1 || true
    if ufw status | grep -q "Status: active"; then
        ok "Firewall sudah aktif, rule ditambahkan"
    else
        echo "y" | ufw enable >>"${LOG_FILE}" 2>&1 || true
        ok "Firewall diaktifkan dengan rule yang dibutuhkan"
    fi
}

# ---------------------------------------------------------------------------
# /etc/sshws/info — dibutuhkan add-ssh/del-ssh/list-ssh/switch-* dari repo
# ---------------------------------------------------------------------------
write_sshws_info() {
    step "Tulis konfigurasi ${SSHWS_INFO}"
    mkdir -p "$SSHWS_DIR"
    printf '%s\n%s\n' "${IP_VPS}" "${DOMAIN}" > "$SSHWS_INFO"
    ok "IP & domain tersimpan untuk tools SSH bawaan repo"
}

# ---------------------------------------------------------------------------
# TULIS /usr/local/bin/menu (menu utama panel)
# ---------------------------------------------------------------------------
write_menu_script() {
    step "Pasang menu utama ke /usr/local/bin/menu"
    cat > /usr/local/bin/menu << 'MENU_PANEL_EOF'
#!/usr/bin/env bash
# ============================================================================
#  VPN PANEL MENU  —  SSH-WS / Dropbear-WS / Xray (VMess-VLESS-Trojan)
#  Dibuat oleh installer, jangan dipindah dari /usr/local/bin/menu
# ============================================================================

PANEL_DIR="/etc/vpn-panel"
SSHWS_INFO="/etc/sshws/info"
XRAY_DIR="/usr/local/etc/xray"
XRAY_CONF="${XRAY_DIR}/config.json"
XRAY_BIN="/usr/local/bin/xray"
XRAY_USERS_DIR="${PANEL_DIR}/xray-users"
CERT_DIR="${PANEL_DIR}/cert"

PORT_SSH_OPENSSH="22"
PORT_SSH_DROPBEAR="109"
PORT_SSH_OPENSSH_SSL="444"
PORT_SSH_DROPBEAR_SSL="777"
PORT_HAPROXY_TLS="443"
PORT_NGINX_HTTP="80"
PORT_UDPGW="7300"

WS_PATH_OPENSSH="/ssh-ws"
WS_PATH_DROPBEAR="/ssh-ws-dropbear"
WS_PATH_VMESS="/vmess"
WS_PATH_VLESS="/vless"
WS_PATH_TROJAN="/trojan-ws"

C_RESET="\e[0m"
C_CYAN="\e[0;36m"
C_GREEN="\e[0;32m"
C_RED="\e[0;31m"
C_YELLOW="\e[0;33m"
C_WHITE="\e[1;37m"
C_BOLD="\e[1m"
LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

get_domain() { sed -n '2p' "$SSHWS_INFO" 2>/dev/null; }
get_ip()     { sed -n '1p' "$SSHWS_INFO" 2>/dev/null; }

pause() {
    echo ""
    read -rp "  Tekan [Enter] untuk kembali ke menu..." _
}

cls_header() {
    clear
    local domain ip
    domain="$(get_domain)"
    ip="$(get_ip)"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    echo -e "${C_WHITE}${C_BOLD}                     V P N   P A N E L${C_RESET}"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    echo -e "  Domain : ${C_GREEN}${domain:-belum diatur}${C_RESET}"
    echo -e "  IP VPS : ${C_GREEN}${ip:-tidak diketahui}${C_RESET}"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
}

svc_status_dot() {
    if systemctl is-active --quiet "$1" 2>/dev/null; then
        echo -e "${C_GREEN}●${C_RESET}"
    else
        echo -e "${C_RED}●${C_RESET}"
    fi
}

# ---------------------------------------------------------------------------
# DASHBOARD / INFO VPS
# ---------------------------------------------------------------------------
show_dashboard() {
    cls_header
    local os_pretty kernel uptime_str ram_used ram_total cpu_load disk_used disk_total
    local isp city count_ssh count_xray

    os_pretty="$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2)"
    kernel="$(uname -r)"
    uptime_str="$(uptime -p 2>/dev/null | sed 's/^up //')"
    ram_used="$(free -m | awk '/Mem:/ {print $3}')"
    ram_total="$(free -m | awk '/Mem:/ {print $2}')"
    cpu_load="$(uptime | awk -F'load average:' '{print $2}' | xargs)"
    disk_used="$(df -h / | awk 'NR==2 {print $3}')"
    disk_total="$(df -h / | awk 'NR==2 {print $2}')"

    local geo
    geo="$(curl -s --max-time 4 http://ip-api.com/line/?fields=isp,city,country 2>/dev/null)"
    isp="$(echo "$geo" | sed -n '1p')"
    city="$(echo "$geo" | sed -n '2p')"

    count_ssh="$(awk -F: '$3>=1000 && $3<60000 {print $1}' /etc/passwd | wc -l)"
    count_xray="$(find "$XRAY_USERS_DIR" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l)"

    echo -e "  ${C_WHITE}Sistem${C_RESET}"
    echo -e "   OS         : ${os_pretty:-unknown}"
    echo -e "   Kernel     : ${kernel}"
    echo -e "   Uptime     : ${uptime_str:-n/a}"
    echo -e "   RAM        : ${ram_used:-?}MB / ${ram_total:-?}MB"
    echo -e "   CPU load   : ${cpu_load:-n/a}"
    echo -e "   Disk       : ${disk_used:-?} / ${disk_total:-?}"
    echo -e "   ISP        : ${isp:-tidak terdeteksi}"
    echo -e "   Lokasi     : ${city:-tidak terdeteksi}"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    echo -e "  ${C_WHITE}Akun${C_RESET}"
    echo -e "   Akun SSH aktif  : ${count_ssh}"
    echo -e "   Akun Xray aktif : ${count_xray}"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    echo -e "  ${C_WHITE}Status Layanan${C_RESET}"
    printf "   %-22s %-4s  %-22s %-4s\n" \
        "$(echo -e "OpenSSH $(svc_status_dot ssh)")" "" \
        "$(echo -e "Dropbear $(svc_status_dot dropbear)")" ""
    printf "   %-22s %-22s\n" \
        "$(echo -e "Nginx $(svc_status_dot nginx)")" \
        "$(echo -e "HAProxy $(svc_status_dot haproxy)")"
    printf "   %-22s %-22s\n" \
        "$(echo -e "Stunnel4 $(svc_status_dot stunnel4)")" \
        "$(echo -e "Xray $(svc_status_dot xray)")"
    printf "   %-22s %-22s\n" \
        "$(echo -e "WS-Tunnel OpenSSH $(svc_status_dot wstunnel-openssh)")" \
        "$(echo -e "WS-Tunnel Dropbear $(svc_status_dot wstunnel-dropbear)")"
    printf "   %-22s %-22s\n" \
        "$(echo -e "BadVPN-UDPGW $(svc_status_dot badvpn-udpgw)")" \
        "$(echo -e "Fail2ban $(svc_status_dot fail2ban)")"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
}

# ---------------------------------------------------------------------------
# MENU: SSH & DROPBEAR
# ---------------------------------------------------------------------------
ssh_extend_account() {
    cls_header
    echo -e "  ${C_WHITE}PERPANJANG AKUN SSH${C_RESET}"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    read -rp "  Username        : " uname_in
    if ! id "$uname_in" >/dev/null 2>&1; then
        echo -e "  ${C_RED}User '${uname_in}' tidak ditemukan.${C_RESET}"
        pause; return
    fi
    read -rp "  Tambah berapa hari : " add_days
    if ! [[ "$add_days" =~ ^[0-9]+$ ]]; then
        echo -e "  ${C_RED}Jumlah hari tidak valid.${C_RESET}"
        pause; return
    fi

    local cron_day cron_month
    cron_day="$(date -d "+${add_days} days" +"%d")"
    cron_month="$(date -d "+${add_days} days" +"%m")"

    ( crontab -l 2>/dev/null | grep -v "userdel -r ${uname_in} #SSHWS" ) | crontab -
    ( crontab -l 2>/dev/null; echo "01 00 ${cron_day} ${cron_month} * userdel -r ${uname_in} #SSHWS" ) | crontab -

    echo -e "  ${C_GREEN}✓ Akun '${uname_in}' diperpanjang ${add_days} hari (expired baru: $(date -d "+${add_days} days" +'%d %b %Y')).${C_RESET}"
    pause
}

ssh_menu() {
    while true; do
        cls_header
        echo -e "  ${C_WHITE}MENU SSH & DROPBEAR${C_RESET}"
        echo -e "${C_CYAN}${LINE}${C_RESET}"
        echo -e "   ${C_GREEN}1)${C_RESET} Buat Akun SSH"
        echo -e "   ${C_GREEN}2)${C_RESET} Hapus Akun SSH"
        echo -e "   ${C_GREEN}3)${C_RESET} List Akun SSH"
        echo -e "   ${C_GREEN}4)${C_RESET} Perpanjang Akun SSH"
        echo -e "   ${C_GREEN}5)${C_RESET} Ganti Domain (label saja)"
        echo -e "   ${C_GREEN}6)${C_RESET} Ganti IP (label saja)"
        echo -e "   ${C_GREEN}7)${C_RESET} Uninstall modul SSH-WS"
        echo -e "   ${C_RED}0)${C_RESET} Kembali"
        echo -e "${C_CYAN}${LINE}${C_RESET}"
        read -rp "  Pilih menu : " opt
        case "$opt" in
            1) clear; /usr/local/bin/add-ssh; pause ;;
            2) clear; /usr/local/bin/del-ssh; pause ;;
            3) clear; /usr/local/bin/list-ssh; pause ;;
            4) ssh_extend_account ;;
            5) clear; /usr/local/bin/switch-domain; pause ;;
            6) clear; /usr/local/bin/switch-host; pause ;;
            7) clear
               echo -e "  ${C_YELLOW}Ini akan menghapus modul SSH-WS (bukan Xray).${C_RESET}"
               read -rp "  Yakin lanjut? (y/N): " yn
               if [[ "$yn" =~ ^[Yy]$ ]]; then /usr/local/bin/uninstall-ssh; fi
               pause ;;
            0) return ;;
            *) : ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# XRAY — helper inti (jq, validasi, restart aman)
# ---------------------------------------------------------------------------
xray_tag_for() {
    case "$1" in
        vmess)  echo "vmess-ws" ;;
        vless)  echo "vless-ws" ;;
        trojan) echo "trojan-ws" ;;
    esac
}

xray_path_for() {
    case "$1" in
        vmess)  echo "$WS_PATH_VMESS" ;;
        vless)  echo "$WS_PATH_VLESS" ;;
        trojan) echo "$WS_PATH_TROJAN" ;;
    esac
}

# Terapkan filter jq ke config Xray secara aman (validasi dulu sebelum ganti file asli)
xray_apply_jq() {
    local filter="$1"
    local tmp
    tmp="$(mktemp --suffix=.json)"
    if ! jq "$filter" "$XRAY_CONF" > "$tmp" 2>/tmp/xray_jq_err; then
        echo -e "  ${C_RED}Gagal memproses konfigurasi (jq error). Lihat /tmp/xray_jq_err${C_RESET}"
        rm -f "$tmp"
        return 1
    fi
    if ! jq empty "$tmp" >/dev/null 2>&1; then
        echo -e "  ${C_RED}Hasil konfigurasi tidak valid (JSON rusak), dibatalkan.${C_RESET}"
        rm -f "$tmp"
        return 1
    fi
    if ! "$XRAY_BIN" run -test -config "$tmp" >/tmp/xray_test_err 2>&1; then
        echo -e "  ${C_RED}Konfigurasi Xray tidak valid, dibatalkan. Lihat /tmp/xray_test_err${C_RESET}"
        rm -f "$tmp"
        return 1
    fi
    mv "$tmp" "$XRAY_CONF"
    chown xray:xray "$XRAY_CONF" 2>/dev/null
    systemctl restart xray
    return 0
}

xray_add_user() {
    cls_header
    echo -e "  ${C_WHITE}TAMBAH AKUN XRAY${C_RESET}"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    echo -e "   ${C_GREEN}1)${C_RESET} VMess"
    echo -e "   ${C_GREEN}2)${C_RESET} VLESS"
    echo -e "   ${C_GREEN}3)${C_RESET} Trojan"
    read -rp "  Pilih protokol : " proto_opt
    local proto
    case "$proto_opt" in
        1) proto="vmess" ;;
        2) proto="vless" ;;
        3) proto="trojan" ;;
        *) echo -e "  ${C_RED}Pilihan tidak valid.${C_RESET}"; pause; return ;;
    esac

    read -rp "  Username         : " uname_in
    if [[ -z "$uname_in" ]]; then
        echo -e "  ${C_RED}Username tidak boleh kosong.${C_RESET}"; pause; return
    fi
    if [[ -f "${XRAY_USERS_DIR}/${uname_in}.json" ]]; then
        echo -e "  ${C_RED}Username '${uname_in}' sudah dipakai.${C_RESET}"; pause; return
    fi
    read -rp "  Masa aktif (hari): " days_in
    if ! [[ "$days_in" =~ ^[0-9]+$ ]]; then
        echo -e "  ${C_RED}Jumlah hari tidak valid.${C_RESET}"; pause; return
    fi

    local tag cred domain created expired
    tag="$(xray_tag_for "$proto")"
    domain="$(get_domain)"
    created="$(date +%Y-%m-%d)"
    expired="$(date -d "+${days_in} days" +%Y-%m-%d)"

    if [[ "$proto" == "trojan" ]]; then
        cred="$(openssl rand -hex 12)"
        xray_apply_jq '(.inbounds[] | select(.tag=="'"$tag"'") | .settings.clients) += [{"password":"'"$cred"'","email":"'"$uname_in"'"}]' || { pause; return; }
    else
        cred="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen)"
        xray_apply_jq '(.inbounds[] | select(.tag=="'"$tag"'") | .settings.clients) += [{"id":"'"$cred"'","email":"'"$uname_in"'"}]' || { pause; return; }
    fi

    mkdir -p "$XRAY_USERS_DIR"
    jq -n --arg u "$uname_in" --arg p "$proto" --arg c "$cred" --arg cr "$created" --arg ex "$expired" \
        '{username:$u, protocol:$p, cred:$c, created:$cr, expired:$ex}' > "${XRAY_USERS_DIR}/${uname_in}.json"

    echo ""
    echo -e "  ${C_GREEN}✓ Akun Xray (${proto}) berhasil dibuat.${C_RESET}"
    show_xray_account_info "$uname_in"
    pause
}

show_xray_account_info() {
    local uname_in="$1"
    local meta="${XRAY_USERS_DIR}/${uname_in}.json"
    [[ -f "$meta" ]] || { echo -e "  ${C_RED}Data akun tidak ditemukan.${C_RESET}"; return; }

    local proto cred expired domain path link b64
    proto="$(jq -r .protocol "$meta")"
    cred="$(jq -r .cred "$meta")"
    expired="$(jq -r .expired "$meta")"
    domain="$(get_domain)"
    path="$(xray_path_for "$proto")"

    echo -e "${C_CYAN}${LINE}${C_RESET}"
    echo -e "   Username   : ${uname_in}"
    echo -e "   Protokol   : ${proto}"
    echo -e "   Domain     : ${domain}"
    echo -e "   Port TLS   : ${PORT_HAPROXY_TLS}  (WS+TLS, dianjurkan)"
    echo -e "   Port HTTP  : ${PORT_NGINX_HTTP}   (WS non-TLS)"
    echo -e "   Path       : ${path}"
    echo -e "   Expired    : ${expired}"
    if [[ "$proto" == "trojan" ]]; then
        echo -e "   Password   : ${cred}"
        link="trojan://${cred}@${domain}:${PORT_HAPROXY_TLS}?security=tls&type=ws&host=${domain}&path=$(printf '%s' "$path" | sed 's#/#%2F#g')&sni=${domain}#${uname_in}"
    else
        echo -e "   UUID       : ${cred}"
        if [[ "$proto" == "vless" ]]; then
            link="vless://${cred}@${domain}:${PORT_HAPROXY_TLS}?encryption=none&security=tls&type=ws&host=${domain}&path=$(printf '%s' "$path" | sed 's#/#%2F#g')&sni=${domain}#${uname_in}"
        else
            b64="$(jq -n --arg ps "$uname_in" --arg add "$domain" --arg port "$PORT_HAPROXY_TLS" \
                    --arg id "$cred" --arg host "$domain" --arg path "$path" \
                    '{v:"2",ps:$ps,add:$add,port:$port,id:$id,aid:"0",net:"ws",type:"none",host:$host,path:$path,tls:"tls",sni:$host}' \
                    | base64 -w0)"
            link="vmess://${b64}"
        fi
    fi
    echo -e "   Link       : ${C_YELLOW}${link}${C_RESET}"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
}

xray_list_users() {
    cls_header
    echo -e "  ${C_WHITE}DAFTAR AKUN XRAY${C_RESET}"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    printf "   %-16s %-8s %-12s\n" "Username" "Proto" "Expired"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    if [[ -d "$XRAY_USERS_DIR" ]] && [[ -n "$(ls -A "$XRAY_USERS_DIR" 2>/dev/null)" ]]; then
        for f in "$XRAY_USERS_DIR"/*.json; do
            local u p e
            u="$(jq -r .username "$f")"
            p="$(jq -r .protocol "$f")"
            e="$(jq -r .expired "$f")"
            printf "   %-16s %-8s %-12s\n" "$u" "$p" "$e"
        done
    else
        echo -e "   Belum ada akun Xray."
    fi
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    pause
}

xray_del_user() {
    cls_header
    echo -e "  ${C_WHITE}HAPUS AKUN XRAY${C_RESET}"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    read -rp "  Username : " uname_in
    local meta="${XRAY_USERS_DIR}/${uname_in}.json"
    if [[ ! -f "$meta" ]]; then
        echo -e "  ${C_RED}Akun '${uname_in}' tidak ditemukan.${C_RESET}"; pause; return
    fi
    local proto tag
    proto="$(jq -r .protocol "$meta")"
    tag="$(xray_tag_for "$proto")"

    if xray_apply_jq '(.inbounds[] | select(.tag=="'"$tag"'") | .settings.clients) |= map(select(.email != "'"$uname_in"'"))'; then
        rm -f "$meta"
        echo -e "  ${C_GREEN}✓ Akun '${uname_in}' dihapus.${C_RESET}"
    fi
    pause
}

xray_extend_user() {
    cls_header
    echo -e "  ${C_WHITE}PERPANJANG AKUN XRAY${C_RESET}"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    read -rp "  Username           : " uname_in
    local meta="${XRAY_USERS_DIR}/${uname_in}.json"
    if [[ ! -f "$meta" ]]; then
        echo -e "  ${C_RED}Akun '${uname_in}' tidak ditemukan.${C_RESET}"; pause; return
    fi
    read -rp "  Tambah berapa hari : " add_days
    if ! [[ "$add_days" =~ ^[0-9]+$ ]]; then
        echo -e "  ${C_RED}Jumlah hari tidak valid.${C_RESET}"; pause; return
    fi
    local new_expired tmp
    new_expired="$(date -d "+${add_days} days" +%Y-%m-%d)"
    tmp="$(mktemp)"
    jq --arg ex "$new_expired" '.expired = $ex' "$meta" > "$tmp" && mv "$tmp" "$meta"
    echo -e "  ${C_GREEN}✓ Akun '${uname_in}' diperpanjang sampai ${new_expired}.${C_RESET}"
    pause
}

xray_menu() {
    while true; do
        cls_header
        echo -e "  ${C_WHITE}MENU XRAY (VMess / VLESS / Trojan)${C_RESET}"
        echo -e "${C_CYAN}${LINE}${C_RESET}"
        echo -e "   ${C_GREEN}1)${C_RESET} Buat Akun Xray"
        echo -e "   ${C_GREEN}2)${C_RESET} Hapus Akun Xray"
        echo -e "   ${C_GREEN}3)${C_RESET} List Akun Xray"
        echo -e "   ${C_GREEN}4)${C_RESET} Perpanjang Akun Xray"
        echo -e "   ${C_GREEN}5)${C_RESET} Lihat Detail / Link Akun"
        echo -e "   ${C_RED}0)${C_RESET} Kembali"
        echo -e "${C_CYAN}${LINE}${C_RESET}"
        read -rp "  Pilih menu : " opt
        case "$opt" in
            1) xray_add_user ;;
            2) xray_del_user ;;
            3) xray_list_users ;;
            4) xray_extend_user ;;
            5) cls_header
               read -rp "  Username : " un
               show_xray_account_info "$un"
               pause ;;
            0) return ;;
            *) : ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# MENU: LAYANAN (service control)
# ---------------------------------------------------------------------------
ALL_SERVICES=(ssh dropbear nginx haproxy stunnel4 xray wstunnel-openssh wstunnel-dropbear badvpn-udpgw fail2ban vnstat)

service_status_all() {
    cls_header
    echo -e "  ${C_WHITE}STATUS SEMUA LAYANAN${C_RESET}"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    for s in "${ALL_SERVICES[@]}"; do
        local dot state
        dot="$(svc_status_dot "$s")"
        state="$(systemctl is-active "$s" 2>/dev/null)"
        printf "   %b %-24s %s\n" "$dot" "$s" "$state"
    done
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    pause
}

service_restart_all() {
    cls_header
    echo -e "  ${C_WHITE}RESTART SEMUA LAYANAN${C_RESET}"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    for s in "${ALL_SERVICES[@]}"; do
        if systemctl restart "$s" >/dev/null 2>&1; then
            echo -e "   ${C_GREEN}✓${C_RESET} $s berhasil di-restart"
        else
            echo -e "   ${C_RED}✗${C_RESET} $s gagal di-restart"
        fi
    done
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    pause
}

service_restart_one() {
    cls_header
    echo -e "  ${C_WHITE}RESTART LAYANAN TERTENTU${C_RESET}"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    local i=1
    for s in "${ALL_SERVICES[@]}"; do
        echo -e "   ${C_GREEN}${i})${C_RESET} $s"
        i=$((i+1))
    done
    echo -e "   ${C_RED}0)${C_RESET} Batal"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    read -rp "  Pilih layanan : " idx
    if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#ALL_SERVICES[@]} )); then
        local svc="${ALL_SERVICES[$((idx-1))]}"
        if systemctl restart "$svc" >/dev/null 2>&1; then
            echo -e "  ${C_GREEN}✓ $svc berhasil di-restart.${C_RESET}"
        else
            echo -e "  ${C_RED}✗ $svc gagal di-restart.${C_RESET}"
        fi
    fi
    pause
}

service_view_logs() {
    cls_header
    echo -e "  ${C_WHITE}LIHAT LOG LAYANAN (50 baris terakhir)${C_RESET}"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    local i=1
    for s in "${ALL_SERVICES[@]}"; do
        echo -e "   ${C_GREEN}${i})${C_RESET} $s"
        i=$((i+1))
    done
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    read -rp "  Pilih layanan : " idx
    if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#ALL_SERVICES[@]} )); then
        clear
        journalctl -u "${ALL_SERVICES[$((idx-1))]}" -n 50 --no-pager
    fi
    pause
}

service_menu() {
    while true; do
        cls_header
        echo -e "  ${C_WHITE}MENU LAYANAN${C_RESET}"
        echo -e "${C_CYAN}${LINE}${C_RESET}"
        echo -e "   ${C_GREEN}1)${C_RESET} Status semua layanan"
        echo -e "   ${C_GREEN}2)${C_RESET} Restart semua layanan"
        echo -e "   ${C_GREEN}3)${C_RESET} Restart layanan tertentu"
        echo -e "   ${C_GREEN}4)${C_RESET} Lihat log layanan"
        echo -e "   ${C_RED}0)${C_RESET} Kembali"
        echo -e "${C_CYAN}${LINE}${C_RESET}"
        read -rp "  Pilih menu : " opt
        case "$opt" in
            1) service_status_all ;;
            2) service_restart_all ;;
            3) service_restart_one ;;
            4) service_view_logs ;;
            0) return ;;
            *) : ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# MENU: SYSTEM TOOLS
# ---------------------------------------------------------------------------
tool_bandwidth() {
    clear
    echo -e "  ${C_WHITE}PEMAKAIAN BANDWIDTH (vnstat)${C_RESET}"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    vnstat 2>/dev/null || echo -e "  ${C_YELLOW}vnstat belum ada data (baru dipasang, tunggu beberapa saat).${C_RESET}"
    pause
}

tool_speedtest() {
    clear
    echo -e "  ${C_WHITE}SPEEDTEST${C_RESET}"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    if command -v speedtest-cli >/dev/null 2>&1; then
        speedtest-cli --simple
    else
        echo -e "  ${C_RED}speedtest-cli tidak terpasang.${C_RESET}"
    fi
    pause
}

tool_renew_ssl() {
    clear
    echo -e "  ${C_WHITE}PERPANJANG SERTIFIKAT SSL${C_RESET}"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    if [[ -x /root/.acme.sh/acme.sh ]]; then
        /root/.acme.sh/acme.sh --renew -d "$(get_domain)" --ecc --force
        /usr/local/bin/vpn-panel-cert-sync.sh
        echo -e "  ${C_GREEN}✓ Selesai.${C_RESET}"
    else
        echo -e "  ${C_RED}acme.sh tidak ditemukan di /root/.acme.sh/${C_RESET}"
    fi
    pause
}

tool_change_domain_full() {
    clear
    echo -e "  ${C_WHITE}GANTI DOMAIN (LENGKAP: SSL + NGINX + HAPROXY)${C_RESET}"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    local old_domain new_domain
    old_domain="$(get_domain)"
    echo -e "  Domain saat ini : ${old_domain}"
    read -rp "  Domain baru     : " new_domain
    if [[ -z "$new_domain" ]]; then
        echo -e "  ${C_RED}Domain tidak boleh kosong.${C_RESET}"; pause; return
    fi
    read -rp "  Lanjutkan ganti ke '${new_domain}'? Pastikan A record sudah diarahkan. [y/N]: " yn
    [[ "$yn" =~ ^[Yy]$ ]] || { pause; return; }

    printf '%s\n%s\n' "$(get_ip)" "$new_domain" > "$SSHWS_INFO"
    sed -i "s/${old_domain}/${new_domain}/g" /etc/nginx/sites-available/vpn-panel.conf

    if nginx -t >/dev/null 2>&1; then
        systemctl reload nginx
        echo -e "  ${C_GREEN}✓ Nginx diperbarui.${C_RESET}"
    else
        echo -e "  ${C_RED}✗ Konfigurasi Nginx tidak valid setelah ganti domain, cek manual!${C_RESET}"
        pause; return
    fi

    if [[ -x /root/.acme.sh/acme.sh ]]; then
        if /root/.acme.sh/acme.sh --issue -d "$new_domain" -w /var/www/vpn-panel --keylength ec-256 --force; then
            /root/.acme.sh/acme.sh --install-cert -d "$new_domain" --ecc \
                --fullchain-file "${CERT_DIR}/fullchain.pem" \
                --key-file "${CERT_DIR}/privkey.pem" \
                --reloadcmd "/usr/local/bin/vpn-panel-cert-sync.sh"
            /usr/local/bin/vpn-panel-cert-sync.sh
            echo -e "  ${C_GREEN}✓ Sertifikat SSL untuk '${new_domain}' berhasil diterbitkan.${C_RESET}"
        else
            echo -e "  ${C_RED}✗ Gagal menerbitkan sertifikat baru. Domain sudah diganti tapi SSL masih pakai yang lama.${C_RESET}"
        fi
    fi
    pause
}

tool_port_info() {
    clear
    local domain; domain="$(get_domain)"
    echo -e "  ${C_WHITE}INFO PORT & PATH${C_RESET}"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    echo -e "   Domain               : ${domain}"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    echo -e "   ${C_WHITE}SSH / Dropbear${C_RESET}"
    printf "    %-28s : %s\n" "OpenSSH (direct)"        "${PORT_SSH_OPENSSH}"
    printf "    %-28s : %s\n" "Dropbear (direct)"       "${PORT_SSH_DROPBEAR}"
    printf "    %-28s : %s\n" "OpenSSH SSL (stunnel)"   "${PORT_SSH_OPENSSH_SSL}"
    printf "    %-28s : %s\n" "Dropbear SSL (stunnel)"  "${PORT_SSH_DROPBEAR_SSL}"
    printf "    %-28s : %s (path %s)\n" "SSH over WS+TLS" "${PORT_HAPROXY_TLS}" "${WS_PATH_OPENSSH}"
    printf "    %-28s : %s (path %s)\n" "SSH over WS non-TLS" "${PORT_NGINX_HTTP}" "${WS_PATH_OPENSSH}"
    printf "    %-28s : %s (path %s)\n" "Dropbear over WS+TLS" "${PORT_HAPROXY_TLS}" "${WS_PATH_DROPBEAR}"
    printf "    %-28s : %s/udp\n" "BadVPN UDPGW" "${PORT_UDPGW}"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    echo -e "   ${C_WHITE}Xray${C_RESET}"
    printf "    %-28s : %s (path %s)\n" "VMess WS+TLS"  "${PORT_HAPROXY_TLS}" "${WS_PATH_VMESS}"
    printf "    %-28s : %s (path %s)\n" "VLESS WS+TLS"  "${PORT_HAPROXY_TLS}" "${WS_PATH_VLESS}"
    printf "    %-28s : %s (path %s)\n" "Trojan WS+TLS" "${PORT_HAPROXY_TLS}" "${WS_PATH_TROJAN}"
    echo -e "${C_CYAN}${LINE}${C_RESET}"
    pause
}

tool_reboot() {
    clear
    echo -e "  ${C_YELLOW}VPS akan reboot sekarang.${C_RESET}"
    read -rp "  Yakin? (y/N): " yn
    [[ "$yn" =~ ^[Yy]$ ]] && reboot
}

tool_uninstall_all() {
    clear
    echo -e "  ${C_RED}${C_BOLD}UNINSTALL SELURUH PANEL${C_RESET}"
    echo -e "  Ini akan menghapus SSH-WS, Xray, Nginx, HAProxy, Stunnel, dan semua akun."
    read -rp "  Ketik 'HAPUS' untuk konfirmasi: " conf
    [[ "$conf" == "HAPUS" ]] || { pause; return; }

    systemctl disable --now nginx haproxy stunnel4 xray wstunnel-openssh wstunnel-dropbear badvpn-udpgw fail2ban vnstat dropbear 2>/dev/null
    [[ -x /usr/local/bin/uninstall-ssh ]] && /usr/local/bin/uninstall-ssh
    rm -rf /etc/vpn-panel /etc/sshws /usr/local/etc/xray /etc/nginx/sites-available/vpn-panel.conf \
           /etc/nginx/sites-enabled/vpn-panel.conf /etc/haproxy/haproxy.cfg /etc/stunnel/stunnel.conf \
           /etc/systemd/system/xray.service /etc/systemd/system/wstunnel-*.service \
           /etc/systemd/system/badvpn-udpgw.service /usr/local/bin/xray /usr/local/bin/wstunnel \
           /usr/local/bin/menu /usr/local/bin/udpgw
    systemctl daemon-reload
    echo -e "  ${C_GREEN}Panel telah dihapus. Sampai jumpa.${C_RESET}"
    exit 0
}

system_menu() {
    while true; do
        cls_header
        echo -e "  ${C_WHITE}MENU SYSTEM TOOLS${C_RESET}"
        echo -e "${C_CYAN}${LINE}${C_RESET}"
        echo -e "   ${C_GREEN}1)${C_RESET} Info VPS lengkap"
        echo -e "   ${C_GREEN}2)${C_RESET} Pemakaian bandwidth"
        echo -e "   ${C_GREEN}3)${C_RESET} Speedtest"
        echo -e "   ${C_GREEN}4)${C_RESET} Info Port & Path"
        echo -e "   ${C_GREEN}5)${C_RESET} Perpanjang sertifikat SSL"
        echo -e "   ${C_GREEN}6)${C_RESET} Ganti domain (lengkap)"
        echo -e "   ${C_GREEN}7)${C_RESET} Reboot VPS"
        echo -e "   ${C_RED}8)${C_RESET} Uninstall seluruh panel"
        echo -e "   ${C_RED}0)${C_RESET} Kembali"
        echo -e "${C_CYAN}${LINE}${C_RESET}"
        read -rp "  Pilih menu : " opt
        case "$opt" in
            1) show_dashboard; pause ;;
            2) tool_bandwidth ;;
            3) tool_speedtest ;;
            4) tool_port_info ;;
            5) tool_renew_ssl ;;
            6) tool_change_domain_full ;;
            7) tool_reboot ;;
            8) tool_uninstall_all ;;
            0) return ;;
            *) : ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# MAIN LOOP
# ---------------------------------------------------------------------------
main_menu() {
    while true; do
        show_dashboard
        echo -e "   ${C_GREEN}1)${C_RESET} Menu SSH & Dropbear"
        echo -e "   ${C_GREEN}2)${C_RESET} Menu Xray (VMess/VLESS/Trojan)"
        echo -e "   ${C_GREEN}3)${C_RESET} Menu Layanan (status/restart/logs)"
        echo -e "   ${C_GREEN}4)${C_RESET} System Tools"
        echo -e "   ${C_RED}0)${C_RESET} Keluar"
        echo -e "${C_CYAN}${LINE}${C_RESET}"
        read -rp "  Pilih menu : " opt
        case "$opt" in
            1) ssh_menu ;;
            2) xray_menu ;;
            3) service_menu ;;
            4) system_menu ;;
            0) echo ""; exit 0 ;;
            *) : ;;
        esac
    done
}

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Menu ini harus dijalankan sebagai root."
    exit 1
fi
main_menu
MENU_PANEL_EOF
    chmod +x /usr/local/bin/menu
    ok "Menu terpasang. Jalankan dengan mengetik: menu"
}

# ---------------------------------------------------------------------------
# CRON: bersihkan otomatis akun Xray yang sudah expired (tiap hari 00:05)
# ---------------------------------------------------------------------------
setup_xray_expiry_cron() {
    step "Jadwalkan pembersihan otomatis akun Xray kedaluwarsa"

    cat > /usr/local/bin/vpn-panel-xray-cleanup.sh << 'CLEANUP_SCRIPT_EOF'
#!/usr/bin/env bash
# Hapus akun Xray yang sudah lewat tanggal expired-nya.
XRAY_USERS_DIR="/etc/vpn-panel/xray-users"
XRAY_CONF="/usr/local/etc/xray/config.json"
XRAY_BIN="/usr/local/bin/xray"
TODAY="$(date +%Y-%m-%d)"
CHANGED=0

[[ -d "$XRAY_USERS_DIR" ]] || exit 0

for meta in "$XRAY_USERS_DIR"/*.json; do
    [[ -f "$meta" ]] || continue
    expired="$(jq -r .expired "$meta" 2>/dev/null)"
    [[ -z "$expired" || "$expired" == "null" ]] && continue
    if [[ "$expired" < "$TODAY" ]]; then
        username="$(jq -r .username "$meta")"
        protocol="$(jq -r .protocol "$meta")"
        case "$protocol" in
            vmess)  tag="vmess-ws" ;;
            vless)  tag="vless-ws" ;;
            trojan) tag="trojan-ws" ;;
            *) continue ;;
        esac
        tmp="$(mktemp --suffix=.json)"
        if jq '(.inbounds[] | select(.tag=="'"$tag"'") | .settings.clients) |= map(select(.email != "'"$username"'"))' \
            "$XRAY_CONF" > "$tmp" 2>/dev/null && jq empty "$tmp" >/dev/null 2>&1; then
            mv "$tmp" "$XRAY_CONF"
            rm -f "$meta"
            CHANGED=1
            echo "$(date '+%F %T') - akun expired dihapus: $username ($protocol)" >> /var/log/vpn-panel/xray-cleanup.log
        else
            rm -f "$tmp"
        fi
    fi
done

[[ "$CHANGED" -eq 1 ]] && systemctl restart xray
CLEANUP_SCRIPT_EOF
    chmod +x /usr/local/bin/vpn-panel-xray-cleanup.sh

    ( crontab -l 2>/dev/null | grep -v "vpn-panel-xray-cleanup.sh"; \
      echo "5 0 * * * /usr/local/bin/vpn-panel-xray-cleanup.sh" ) | crontab -
    ok "Cron pembersihan akun Xray expired terjadwal tiap hari jam 00:05"
}

# ---------------------------------------------------------------------------
# VALIDASI AKHIR
# ---------------------------------------------------------------------------
final_validation() {
    step "Validasi akhir semua layanan"
    local all_ok=1
    local services=(ssh dropbear nginx haproxy stunnel4 xray wstunnel-openssh wstunnel-dropbear badvpn-udpgw fail2ban cron)
    for s in "${services[@]}"; do
        if systemctl is-active --quiet "$s"; then
            ok "$s aktif"
        else
            warn "$s TIDAK aktif — cek: systemctl status $s"
            all_ok=0
        fi
    done
    if [[ "$all_ok" -eq 1 ]]; then
        ok "Semua layanan berjalan normal"
    else
        warn "Beberapa layanan bermasalah, cek log di ${LOG_FILE} dan 'journalctl -u <service>'"
    fi
}

save_panel_conf() {
    cat > "$PANEL_CONF" << EOF
DOMAIN=${DOMAIN}
IP=${IP_VPS}
INSTALL_DATE=$(date +%Y-%m-%d)
VERSION=1.0
EOF
}

print_summary() {
    echo ""
    echo -e "${C_GREEN}${LINE}${C_RESET}"
    echo -e "${C_WHITE}          INSTALASI SELESAI — SSHWS + XRAY PANEL${C_RESET}"
    echo -e "${C_GREEN}${LINE}${C_RESET}"
    echo -e "  Domain               : ${C_GREEN}${DOMAIN}${C_RESET}"
    echo -e "  IP VPS               : ${C_GREEN}${IP_VPS}${C_RESET}"
    echo ""
    echo -e "  ${C_WHITE}Port SSH / Dropbear${C_RESET}"
    echo -e "   OpenSSH             : ${PORT_SSH_OPENSSH}"
    echo -e "   Dropbear            : ${PORT_SSH_DROPBEAR}"
    echo -e "   OpenSSH SSL(stunnel): ${PORT_SSH_OPENSSH_SSL}"
    echo -e "   Dropbear SSL(stunnel): ${PORT_SSH_DROPBEAR_SSL}"
    echo -e "   SSH over WS+TLS     : ${PORT_HAPROXY_TLS}  path ${WS_PATH_OPENSSH}"
    echo -e "   SSH over WS non-TLS : ${PORT_NGINX_HTTP}   path ${WS_PATH_OPENSSH}"
    echo -e "   BadVPN UDPGW        : ${PORT_UDPGW}/udp"
    echo ""
    echo -e "  ${C_WHITE}Xray${C_RESET}"
    echo -e "   VMess WS+TLS        : ${PORT_HAPROXY_TLS}  path ${WS_PATH_VMESS}"
    echo -e "   VLESS WS+TLS        : ${PORT_HAPROXY_TLS}  path ${WS_PATH_VLESS}"
    echo -e "   Trojan WS+TLS       : ${PORT_HAPROXY_TLS}  path ${WS_PATH_TROJAN}"
    echo ""
    echo -e "  ${C_WHITE}Selanjutnya${C_RESET}"
    echo -e "   Ketik ${C_YELLOW}menu${C_RESET} untuk membuka panel (buat akun SSH/Xray, dsb)."
    echo -e "   Log instalasi        : ${LOG_FILE}"
    echo -e "${C_GREEN}${LINE}${C_RESET}"
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
main() {
    check_root
    detect_os
    check_systemd

    mkdir -p "$(dirname "$LOG_FILE")"
    : > "$LOG_FILE"

    ask_domain
    prepare_panel_dirs

    install_base_deps
    set_timezone
    fetch_bin_repo_assets

    setup_openssh
    setup_dropbear
    setup_wstunnel

    setup_nginx_http_only
    issue_ssl_certificate
    enable_nginx_tls

    setup_stunnel
    setup_haproxy
    setup_xray
    setup_udpgw
    setup_fail2ban
    setup_vnstat
    setup_firewall

    write_sshws_info
    setup_xray_expiry_cron
    write_menu_script
    save_panel_conf

    final_validation
    print_summary
}

main "$@"
