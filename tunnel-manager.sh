#!/bin/bash
#=============================================================================
#  SSHWS & XRAY TUNNELING MANAGER
#  Version: 3.0.1 | Author: TunnelManager (Fixed)
#  Compatible: Debian 9+/Ubuntu 16+/CentOS 7+
#=============================================================================

#======================== COLOR SCHEME =======================================
R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;34m'
M='\033[0;35m'; C='\033[0;36m'; W='\033[0;37m'; D='\033[0;90m'
BR='\033[1;31m'; BG='\033[1;32m'; BY='\033[1;33m'; BB='\033[1;34m'
BM='\033[1;35m'; BC='\033[1;36m'; BW='\033[1;37m'
BD='\033[1;90m'; RE='\033[0m'; BL='\033[5m'

#======================== GLOBAL VARIABLES ===================================
SCRIPT_DIR="/usr/local/bin/tunnel-manager"
LOG_FILE="/var/log/tunnel-manager.log"
CONF_DIR="/etc/tunnel-manager"
BIN_DIR="/usr/local/bin"
TMP_DIR="/tmp/tunnel-manager"
DATE_FMT="+%Y-%m-%d %H:%M:%S"

# GitHub Sources
GH_ACME="https://github.com/acmesh-official/acme.sh.git"
GH_XRAY="https://github.com/XTLS/Xray-core/releases"
GH_DROPBEAR="https://github.com/torvalds/linux.git"
GH_STUNNEL="https://www.stunnel.org/downloads.html"
GH_HAPROXY="http://www.haproxy.org/download/"
GH_NGINX="https://nginx.org/download/"
GH_WS_DROPBEAR="https://github.com/badudinda/ws-dropbear.git"
GH_WS_STUNNEL="https://github.com/badudinda/ws-stunnel.git"
GH_PROXY_WS="https://github.com/badudinda/proxy-ws.git"
GH_WS_SSH="https://github.com/badudinda/ws-ssh.git"

#======================== INITIALIZATION =====================================
mkdir -p "$CONF_DIR" "$TMP_DIR" "$SCRIPT_DIR"
touch "$LOG_FILE"

log() {
    echo -e "[$(date $DATE_FMT)] $1" >> "$LOG_FILE"
}

printc() {
    echo -e "$1$2${RE}"
}

#======================== VPS INFORMATION ====================================
get_os_info() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="$NAME"
        OS_VERSION="$VERSION"
        OS_ID="$ID"
    elif [ -f /etc/redhat-release ]; then
        OS_NAME=$(cat /etc/redhat-release)
        OS_VERSION=""
        OS_ID="rhel"
    else
        OS_NAME="Unknown"
        OS_VERSION=""
        OS_ID="unknown"
    fi
}

get_cpu_info() {
    CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    CPU_CORES=$(nproc)
    CPU_FREQ=$(grep "cpu MHz" /proc/cpuinfo | head -1 | awk '{print $4}')
    if [ -n "$CPU_FREQ" ]; then
        CPU_FREQ="${CPU_FREQ} MHz"
    else
        CPU_FREQ="N/A"
    fi
}

get_ram_info() {
    RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    RAM_USED=$(free -m | awk '/Mem:/ {print $3}')
    RAM_FREE=$(free -m | awk '/Mem:/ {print $4}')
    
    # FIX: Hindari pembagian dengan nol (0) yang menyebabkan error nan/inf
    if [[ "$RAM_TOTAL" =~ ^[0-9]+$ ]] && [ "$RAM_TOTAL" -gt 0 ]; then
        RAM_PERCENT=$(awk "BEGIN {printf \"%.1f\", ($RAM_USED/$RAM_TOTAL)*100}")
    else
        RAM_PERCENT="0.0"
    fi
}

get_disk_info() {
    DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
    DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
    DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')
    DISK_PERCENT=$(df -h / | awk 'NR==2 {print $5}')
}

get_network_info() {
    PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me || curl -s --max-time 5 ipinfo.io/ip || echo "N/A")
    PRIVATE_IP=$(hostname -I | awk '{print $1}')
    ISP_INFO=$(curl -s --max-time 5 ipinfo.io/org 2>/dev/null || echo "N/A")
    CITY=$(curl -s --max-time 5 ipinfo.io/city 2>/dev/null || echo "N/A")
    COUNTRY=$(curl -s --max-time 5 ipinfo.io/country 2>/dev/null || echo "N/A")
}

get_uptime_info() {
    UPTIME_SEC=$(cat /proc/uptime | awk '{print $1}')
    DAYS=$((UPTIME_SEC/86400))
    HOURS=$((($UPTIME_SEC%86400)/3600))
    MINS=$((($UPTIME_SEC%3600)/60))
    UPTIME_STR="${DAYS}d ${HOURS}h ${MINS}m"
}

get_load_info() {
    LOAD_1=$(awk '{print $1}' /proc/loadavg)
    LOAD_5=$(awk '{print $2}' /proc/loadavg)
    LOAD_15=$(awk '{print $3}' /proc/loadavg)
}

get_all_info() {
    get_os_info
    get_cpu_info
    get_ram_info
    get_disk_info
    get_network_info
    get_uptime_info
    get_load_info
}

#======================== DRAWING FUNCTIONS ==================================
draw_box() {
    local top_left="$1"
    local top_right="$2"
    local bottom_left="$3"
    local bottom_right="$4"
    local color="$5"
    local width="$6"
    local title="$7"
    
    local line=""
    for ((i=0; i<width-2; i++)); do line+="─"; done
    
    if [ -n "$title" ]; then
        local title_len=${#title}
        local mid=$(( (width-2-title_len) / 2 ))
        local left_line="" right_line=""
        for ((i=0; i<mid; i++)); do left_line+="─"; done
        for ((i=0; i<(width-2-title_len-mid); i++)); do right_line+="─"; done
        printc "$color" "${top_left}${left_line} ${BW}${title} ${color}${right_line}${top_right}"
    else
        printc "$color" "${top_left}${line}${top_right}"
    fi
}

draw_progress() {
    local percent="$1"
    local width="$2"
    local color="$3"
    
    # FIX: Hapus semua karakter selain angka di depan untuk mencegah error bash arithmetic operator desimal
    percent=$(echo "$percent" | grep -oE '^[0-9]+')
    percent=${percent:-0}
    
    # Batasi maksimal 100% agar bar tidak overflow
    if [ "$percent" -gt 100 ]; then
        percent=100
    fi

    local filled=$((percent * width / 100))
    local empty=$((width - filled))
    
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    
    printc "$color" "[$bar] ${percent}%"
}

show_header() {
    clear
    echo ""
    draw_box "╔" "╗" "" "" "$BC" 60 "SSHWS & XRAY TUNNEL MANAGER"
    printc "$BC" "╠$(printf '─%.0s' {1..58})╣"
    printc "$BC" "║" ; printc "$BW" "  Version 3.0.1 • Multi Protocol Tunneling" ; printc "$BC" "          ║"
    printc "$BC" "╚$(printf '─%.0s' {1..58})╝"
    echo ""
}

show_vps_info() {
    get_all_info
    
    local box_w=60
    draw_box "╔" "╗" "" "" "$BM" $box_w "VPS INFORMATION"
    printc "$BM" "╠$(printf '─%.0s' {1..58})╣"
    
    printf "${BM}║${RE} %-18s ${BW}%-37s${RE} ${BM}║${RE}\n" "Hostname" "$(hostname)"
    printf "${BM}║${RE} %-18s ${BW}%-37s${RE} ${BM}║${RE}\n" "OS" "$OS_NAME $OS_VERSION"
    printf "${BM}║${RE} %-18s ${BW}%-37s${RE} ${BM}║${RE}\n" "Kernel" "$(uname -r)"
    printf "${BM}║${RE} %-18s ${BW}%-37s${RE} ${BM}║${RE}\n" "Architecture" "$(uname -m)"
    printc "$BM" "╟$(printf '─%.0s' {1..58})╢"
    
    printf "${BM}║${RE} %-18s ${BW}%-37s${RE} ${BM}║${RE}\n" "CPU Model" "$CPU_MODEL"
    printf "${BM}║${RE} %-18s ${BW}%-17s %-20s${RE} ${BM}║${RE}\n" "CPU Cores" "$CPU_CORES" "Freq: $CPU_FREQ"
    printc "$BM" "╟$(printf '─%.0s' {1..58})╢"
    
    printf "${BM}║${RE} %-18s ${BW}%-10s %-10s %-15s${RE} ${BM}║${RE}\n" "Memory" "${RAM_USED}MB" "/${RAM_TOTAL}MB" "Free: ${RAM_FREE}MB"
    printf "${BM}║${RE} %-18s " ""; draw_progress "${RAM_PERCENT%%.*}" 20 "$BY"; echo ""
    printc "$BM" "╟$(printf '─%.0s' {1..58})╢"
    
    printf "${BM}║${RE} %-18s ${BW}%-10s %-10s %-15s${RE} ${BM}║${RE}\n" "Disk (/)" "$DISK_USED" "/$DISK_TOTAL" "Free: $DISK_FREE"
    printf "${BM}║${RE} %-18s " ""; draw_progress "${DISK_PERCENT%\%}" 20 "$BY"; echo ""
    printc "$BM" "╟$(printf '─%.0s' {1..58})╢"
    
    printf "${BM}║${RE} %-18s ${BG}%-37s${RE} ${BM}║${RE}\n" "Public IP" "$PUBLIC_IP"
    printf "${BM}║${RE} %-18s ${BW}%-37s${RE} ${BM}║${RE}\n" "Private IP" "$PRIVATE_IP"
    printf "${BM}║${RE} %-18s ${BW}%-37s${RE} ${BM}║${RE}\n" "Location" "$CITY, $COUNTRY"
    printf "${BM}║${RE} %-18s ${BW}%-37s${RE} ${BM}║${RE}\n" "ISP" "$ISP_INFO"
    printc "$BM" "╟$(printf '─%.0s' {1..58})╢"
    
    printf "${BM}║${RE} %-18s ${BW}%-37s${RE} ${BM}║${RE}\n" "Uptime" "$UPTIME_STR"
    printf "${BM}║${RE} %-18s ${BW}1m: %-8s 5m: %-8s 15m: %-8s${RE} ${BM}║${RE}\n" "Load Avg" "$LOAD_1" "$LOAD_5" "$LOAD_15"
    
    draw_box "╚" "╝" "" "" "$BM" $box_w ""
    echo ""
}

#======================== SERVICE STATUS =====================================
check_service() {
    if systemctl is-active --quiet "$1" 2>/dev/null; then
        printc "$G" "● RUNNING"
    elif systemctl is-enabled --quiet "$1" 2>/dev/null; then
        printc "$Y" "○ STOPPED"
    else
        printc "$R" "✗ NOT INST"
    fi
}

show_services_status() {
    local box_w=60
    draw_box "╔" "╗" "" "" "$BC" $box_w "SERVICES STATUS"
    printc "$BC" "╠$(printf '─%.0s' {1..58})╣"
    
    local services=(
        "nginx:Nginx Web Server"
        "ws-dropbear:WS Dropbear"
        "ws-stunnel:WS Stunnel"
        "ws-openssh:WS OpenSSH"
        "ws:WebSocket Service"
        "haproxy:HAProxy"
        "xray:Xray Core"
    )
    
    for svc in "${services[@]}"; do
        local name="${svc%%:*}"
        local desc="${svc##*:}"
        printf "${BC}║${RE} %-25s " "$desc"
        check_service "$name"
        printf "${BC}%-14s║${RE}\n" ""
    done
    
    draw_box "╚" "╝" "" "" "$BC" $box_w ""
    echo ""
}

#======================== INSTALLATION FUNCTIONS =============================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        printc "$R" "✗ Error: This script must be run as root!"
        exit 1
    fi
}

check_os() {
    get_os_info
    case "$OS_ID" in
        debian|ubuntu) PKG_MGR="apt"; INSTALL="apt-get install -y" ;;
        centos|rhel|fedora|rocky|almalinux) PKG_MGR="yum"; INSTALL="yum install -y" ;;
        *) printc "$R" "✗ Unsupported OS: $OS_NAME"; exit 1 ;;
    esac
}

update_system() {
    show_header
    draw_box "╔" "╗" "" "" "$BY" 60 "SYSTEM UPDATE"
    printc "$BY" "╠$(printf '─%.0s' {1..58})╣"
    printc "$W" "║  Updating system packages...                                    ║"
    printc "$BY" "╚$(printf '─%.0s' {1..58})╝"
    echo ""
    
    log "Starting system update"
    if [ "$PKG_MGR" = "apt" ]; then
        apt-get update -y -qq && apt-get upgrade -y -qq
    else
        yum update -y -q
    fi
    log "System update completed"
    printc "$G" "✓ System updated successfully!"
    sleep 2
}

install_dependencies() {
    printc "$W" "[1/3] Installing base dependencies..."
    if [ "$PKG_MGR" = "apt" ]; then
        apt-get update -qq
        apt-get install -y -qq curl wget git build-essential libssl-dev zlib1g-dev \
            libpcre3-dev libgeoip-dev libxml2-dev libxslt1-dev \
            systemd systemd-sysv lsb-release net-tools unzip jq \
            socat dnsutils cron ca-certificates 2>/dev/null
    else
        yum install -y -q curl wget git gcc make openssl-devel zlib-devel \
            pcre-devel geoip-devel libxml2-devel libxslt-devel \
            systemd net-tools unzip jq socat bind-utils cronie ca-certificates 2>/dev/null
    fi
    printc "$G" "      ✓ Base dependencies installed"
}

#------------------------ NGINX INSTALLATION ---------------------------------
install_nginx() {
    show_header
    draw_box "╔" "╗" "" "" "$BG" 60 "INSTALLING NGINX"
    printc "$BG" "╠$(printf '─%.0s' {1..58})╣"
    printc "$W" "║  Source: nginx.org                                            ║"
    printc "$BG" "╚$(printf '─%.0s' {1..58})╝"
    echo ""
    
    log "Installing Nginx"
    if command -v nginx &>/dev/null; then
        printc "$Y" "⚠ Nginx already installed. Skipping compile..."
        systemctl stop nginx 2>/dev/null
    else
        install_dependencies
        printc "$W" "[1/4] Downloading Nginx..."
        NGINX_VER="1.25.5"
        cd "$TMP_DIR"
        wget -q "https://nginx.org/download/nginx-${NGINX_VER}.tar.gz" -O nginx.tar.gz
        tar -xzf nginx.tar.gz && cd "nginx-${NGINX_VER}"
        printc "$G" "      ✓ Downloaded"
        
        printc "$W" "[2/4] Configuring..."
        ./configure --prefix=/etc/nginx --sbin-path=/usr/sbin/nginx --modules-path=/usr/lib64/nginx/modules \
            --conf-path=/etc/nginx/nginx.conf --error-log-path=/var/log/nginx/error.log \
            --http-log-path=/var/log/nginx/access.log --pid-path=/var/run/nginx.pid --lock-path=/var/run/nginx.lock \
            --with-http_ssl_module --with-http_v2_module --with-http_realip_module --with-http_gzip_static_module \
            --with-stream --with-stream_ssl_module &>/dev/null
        printc "$G" "      ✓ Configured"
        
        printc "$W" "[3/4] Compiling..."
        make -j$(nproc) &>/dev/null && make install &>/dev/null
        printc "$G" "      ✓ Compiled"
    fi
    
    printc "$W" "[4/4] Setting up service..."
    cat > /lib/systemd/system/nginx.service << 'EOF'
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=syslog.target network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target
[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t
ExecStart=/usr/sbin/nginx
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s QUIT $MAINPID
PrivateTmp=true
[Install]
WantedBy=multi-user.target
EOF
    mkdir -p /etc/nginx/conf.d /var/log/nginx /var/www/html
    systemctl daemon-reload
    systemctl enable nginx
    systemctl start nginx
    printc "$G" "      ✓ Nginx service installed"
    log "Nginx installation completed"
    printc "$BG" "\n✓ Nginx installed successfully!"
    sleep 2
}

#------------------------ ACME.SH INSTALLATION -------------------------------
install_acme() {
    show_header
    log "Installing acme.sh"
    if [ -f "$HOME/.acme.sh/acme.sh" ]; then
        printc "$Y" "⚠ acme.sh already installed. Updating..."
        "$HOME/.acme.sh/acme.sh" --upgrade
    else
        printc "$W" "[1/2] Cloning from GitHub..."
        cd "$TMP_DIR"
        git clone --depth 1 "$GH_ACME" 2>/dev/null
        cd acme.sh
        ./acme.sh --install -m admin@$(hostname -I | awk '{print $1}').local 2>/dev/null
        printc "$G" "      ✓ Cloned and installed"
    fi
    "$HOME/.acme.sh/acme.sh" --set-default-ca --server letsencrypt 2>/dev/null
    printc "$BG" "\n✓ acme.sh installed successfully!"
    sleep 2
}

#------------------------ WS SERVICES INSTALLATION ---------------------------
install_ws_dropbear() {
    show_header
    printc "$W" "Installing WS Dropbear..."
    [ "$PKG_MGR" = "apt" ] && apt-get install -y -qq dropbear 2>/dev/null || yum install -y -q dropbear 2>/dev/null
    cat > "$BIN_DIR/ws-dropbear" << 'WSEOF'
#!/bin/bash
DROPBEAR_PORT=${1:-443}
WS_PATH=${2:-/ws-dropbear}
while true; do socat TCP-LISTEN:${DROPBEAR_PORT},reuseaddr,fork EXEC:"dropbear -i -p 0",pty,stderr,setsid; done
WSEOF
    chmod +x "$BIN_DIR/ws-dropbear"
    cat > /etc/systemd/system/ws-dropbear.service << 'EOF'
[Unit]
Description=WebSocket Dropbear Tunnel
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/ws-dropbear 443 /ws-dropbear
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable ws-dropbear
    printc "$BG" "\n✓ WS Dropbear installed successfully!"
    sleep 2
}

install_ws_stunnel() {
    show_header
    printc "$W" "Installing WS Stunnel..."
    [ "$PKG_MGR" = "apt" ] && apt-get install -y -qq stunnel4 2>/dev/null || yum install -y -q stunnel 2>/dev/null
    cat > "$BIN_DIR/ws-stunnel" << 'WSEOF'
#!/bin/bash
STUNNEL_PORT=${1:-444}
TARGET_PORT=${3:-22}
while true; do socat TCP-LISTEN:${STUNNEL_PORT},reuseaddr,fork TCP:localhost:${TARGET_PORT}; done
WSEOF
    chmod +x "$BIN_DIR/ws-stunnel"
    cat > /etc/systemd/system/ws-stunnel.service << 'EOF'
[Unit]
Description=WebSocket Stunnel Tunnel
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/ws-stunnel 444 /ws-stunnel 22
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable ws-stunnel
    printc "$BG" "\n✓ WS Stunnel installed successfully!"
    sleep 2
}

install_ws() {
    show_header
    printc "$W" "Installing Generic WS..."
    $INSTALL python3 python3-pip websockify 2>/dev/null || pip3 install websockify 2>/dev/null
    cat > "$BIN_DIR/ws" << 'WSEOF'
#!/bin/bash
exec websockify ${1:-8080} ${2:-localhost}:${3:-22} --path=${4:-/ws}
WSEOF
    chmod +x "$BIN_DIR/ws"
    cat > /etc/systemd/system/ws.service << 'EOF'
[Unit]
Description=Generic WebSocket Tunnel
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/ws 8080 localhost 22 /ws
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable ws
    printc "$BG" "\n✓ Generic WS installed successfully!"
    sleep 2
}

install_ws_openssh() {
    show_header
    printc "$W" "Installing WS OpenSSH..."
    [ "$PKG_MGR" = "apt" ] && apt-get install -y -qq openssh-server 2>/dev/null || yum install -y -q openssh-server 2>/dev/null
    cat > "$BIN_DIR/ws-ssh" << 'WSEOF'
#!/bin/bash
WS_SSH_PORT=${1:-445}
TARGET_PORT=${3:-22}
while true; do socat TCP-LISTEN:${WS_SSH_PORT},reuseaddr,fork TCP:localhost:${TARGET_PORT}; done
WSEOF
    chmod +x "$BIN_DIR/ws-ssh"
    cat > /etc/systemd/system/ws-openssh.service << 'EOF'
[Unit]
Description=WebSocket OpenSSH Tunnel
After=network.target sshd.service
[Service]
Type=simple
ExecStart=/usr/local/bin/ws-ssh 445 /ws-ssh 22
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable ws-openssh
    printc "$BG" "\n✓ WS OpenSSH installed successfully!"
    sleep 2
}

#------------------------ HAPROXY & XRAY INSTALLATION ------------------------
install_haproxy() {
    show_header
    printc "$W" "Installing HAProxy..."
    if [ "$PKG_MGR" = "apt" ]; then
        apt-get install -y -qq software-properties-common 2>/dev/null
        add-apt-repository -y ppa:vbernat/haproxy-2.8 2>/dev/null
        apt-get update -qq
        apt-get install -y -qq haproxy 2>/dev/null
    else
        yum install -y -q haproxy 2>/dev/null
    fi
    mkdir -p /etc/haproxy/certs
    cat > /etc/haproxy/haproxy.cfg << 'EOF'
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000
frontend ws-in
    bind *:80
    bind *:443 ssl crt /etc/haproxy/certs/
    tcp-request inspect-delay 5s
    tcp-request content accept if { req.ssl_hello_type 1 }
    acl is_ws_dropbear path_beg /ws-dropbear
    acl is_ws_stunnel path_beg /ws-stunnel
    acl is_ws_ssh path_beg /ws-ssh
    acl is_xray path_beg /xray
    use_backend ws-dropbear if is_ws_dropbear
    use_backend ws-stunnel if is_ws_stunnel
    use_backend ws-ssh if is_ws_ssh
    use_backend xray if is_xray
    default_backend default
backend ws-dropbear
    server ws-dropbear 127.0.0.1:443
backend ws-stunnel
    server ws-stunnel 127.0.0.1:444
backend ws-ssh
    server ws-ssh 127.0.0.1:445
backend xray
    server xray 127.0.0.1:8443
backend default
    server nginx 127.0.0.1:8080
EOF
    sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/haproxy 2>/dev/null
    systemctl daemon-reload && systemctl enable haproxy
    printc "$BG" "\n✓ HAProxy installed successfully!"
    sleep 2
}

install_proxy_ws() {
    show_header
    printc "$W" "Installing proxy-ws..."
    cat > "$BIN_DIR/proxy-ws" << 'PWSEOF'
#!/bin/bash
exec socat TCP-LISTEN:${1:-8080},reuseaddr,fork TCP:${2:-127.0.0.1}:${3:-22}
PWSEOF
    chmod +x "$BIN_DIR/proxy-ws"
    printc "$BG" "\n✓ proxy-ws installed successfully!"
    sleep 2
}

install_xray() {
    show_header
    printc "$W" "Installing Xray-core..."
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) XRAY_ARCH="amd64" ;;
        aarch64) XRAY_ARCH="arm64-v8a" ;;
        armv7l) XRAY_ARCH="arm32-v7a" ;;
        *) printc "$R" "      ✗ Unsupported architecture: $ARCH"; return 1 ;;
    esac
    
    XRAY_VER=$(curl -sL "$GH_XRAY/latest" | grep -oP '"tag_name":\s*"\K[^"]+' | head -1)
    [ -z "$XRAY_VER" ] && XRAY_VER="v1.8.8"
    
    cd "$TMP_DIR"
    wget -q "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VER}/Xray-linux-${XRAY_ARCH}.zip" -O xray.zip
    unzip -o xray.zip -d xray &>/dev/null
    cp xray/xray "$BIN_DIR/" && chmod +x "$BIN_DIR/xray"
    
    mkdir -p /etc/xray /var/log/xray
    UUID=$(cat /proc/sys/kernel/random/uuid)
    echo "$UUID" > "$CONF_DIR/xray-uuid"
    
    cat > /etc/xray/config.json << EOF
{
    "log": { "loglevel": "warning", "access": "/var/log/xray/access.log", "error": "/var/log/xray/error.log" },
    "inbounds": [
        { "port": 8443, "listen": "127.0.0.1", "protocol": "vless", "settings": { "clients": [{ "id": "${UUID}", "flow": "xtls-rprx-vision" }], "decryption": "none", "fallbacks": [{ "dest": 8080 }] }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/xray" } } },
        { "port": 8444, "listen": "127.0.0.1", "protocol": "vmess", "settings": { "clients": [{ "id": "${UUID}", "alterId": 0 }] }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/vmess" } } },
        { "port": 8445, "listen": "127.0.0.1", "protocol": "trojan", "settings": { "clients": [{ "password": "${UUID}" }] }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/trojan" } } }
    ],
    "outbounds": [{ "protocol": "freedom", "settings": {} }]
}
EOF
    cat > /etc/systemd/system/xray.service << 'EOF'
[Unit]
Description=Xray Service
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartSec=3
LimitNPROC=10000
LimitNOFILE=1000000
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable xray
    printc "$BG" "\n✓ Xray ${XRAY_VER} installed successfully!"
    printc "$BW" "  UUID: $UUID"
    sleep 2
}

#======================== SSL/TLS & CONFIGURATION ============================
setup_ssl() {
    show_header
    read -p "  Enter domain name: " DOMAIN
    [ -z "$DOMAIN" ] && { printc "$R" "✗ Domain cannot be empty!"; sleep 2; return 1; }
    
    if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then install_acme; fi
    mkdir -p /var/www/html
    
    printc "$W" "[1/2] Issuing certificate..."
    "$HOME/.acme.sh/acme.sh" --issue -d "$DOMAIN" --webroot /var/www/html 2>&1 | grep -v "^[[:space:]]*$"
    
    if [ $? -ne 0 ]; then printc "$R" "✗ Certificate issuance failed!"; sleep 2; return 1; fi
    
    printc "$W" "[2/2] Installing certificate..."
    mkdir -p /etc/tunnel-manager/ssl
    "$HOME/.acme.sh/acme.sh" --install-cert -d "$DOMAIN" \
        --fullchain-file /etc/tunnel-manager/ssl/fullchain.pem \
        --key-file /etc/tunnel-manager/ssl/privkey.pem \
        --reloadcmd "systemctl reload nginx haproxy" 2>/dev/null
        
    echo "$DOMAIN" > "$CONF_DIR/domain"
    printc "$BG" "\n✓ SSL/TLS configured successfully for $DOMAIN!"
    sleep 2
}

configure_sshws_tls() {
    local domain=$(cat "$CONF_DIR/domain" 2>/dev/null || echo "")
    read -p "  Domain [${domain:-your-domain.com}]: " input_domain
    domain="${input_domain:-$domain}"
    read -p "  WS Path [/ws-dropbear]: " ws_path; ws_path="${ws_path:-/ws-dropbear}"
    read -p "  Backend Port [443]: " backend_port; backend_port="${backend_port:-443}"
    
    cat > /etc/nginx/conf.d/sshws-tls.conf << EOF
server {
    listen 80;
    server_name $domain;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name $domain;
    ssl_certificate /etc/tunnel-manager/ssl/fullchain.pem;
    ssl_certificate_key /etc/tunnel-manager/ssl/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    location $ws_path {
        proxy_pass http://127.0.0.1:$backend_port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400;
    }
    location / { root /var/www/html; index index.html; }
}
EOF
    nginx -t 2>/dev/null && { systemctl reload nginx; printc "$G" "✓ SSHWS TLS configured! -> wss://${domain}${ws_path}"; } || printc "$R" "✗ Nginx config test failed!"
    sleep 2
}

configure_sshws_ntls() {
    read -p "  Listen Port [80]: " port; port="${port:-80}"
    read -p "  WS Path [/ws-ntls]: " ws_path; ws_path="${ws_path:-/ws-ntls}"
    read -p "  Target Port [22]: " target_port; target_port="${target_port:-22}"
    
    cat > /etc/nginx/conf.d/sshws-ntls.conf << EOF
server {
    listen $port;
    server_name _;
    location $ws_path {
        proxy_pass http://127.0.0.1:$target_port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
    location / { root /var/www/html; index index.html; }
}
EOF
    nginx -t 2>/dev/null && { systemctl reload nginx; printc "$G" "✓ SSHWS NTLS configured! -> ws://${PUBLIC_IP}:${port}${ws_path}"; } || printc "$R" "✗ Nginx config test failed!"
    sleep 2
}

configure_xray_vless() {
    local uuid=$(cat "$CONF_DIR/xray-uuid" 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    read -p "  UUID [$uuid]: " input_uuid; uuid="${input_uuid:-$uuid}"
    read -p "  WS Path [/xray]: " ws_path; ws_path="${ws_path:-/xray}"
    read -p "  Listen Port [8443]: " port; port="${port:-8443}"
    
    cat > /etc/xray/config.json << EOF
{"log": { "loglevel": "warning" }, "inbounds": [{"port": $port, "listen": "127.0.0.1", "protocol": "vless", "settings": { "clients": [{ "id": "$uuid", "flow": "xtls-rprx-vision" }], "decryption": "none" }, "streamSettings": { "network": "ws", "wsSettings": { "path": "$ws_path" } }}], "outbounds": [{ "protocol": "freedom" }]}
EOF
    echo "$uuid" > "$CONF_DIR/xray-uuid" && systemctl restart xray 2>/dev/null
    printc "$G" "✓ VLESS configured! UUID: $uuid"; sleep 2
}

configure_xray_vmess() {
    local uuid=$(cat "$CONF_DIR/xray-uuid" 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    read -p "  UUID [$uuid]: " input_uuid; uuid="${input_uuid:-$uuid}"
    read -p "  WS Path [/vmess]: " ws_path; ws_path="${ws_path:-/vmess}"
    read -p "  Listen Port [8444]: " port; port="${port:-8444}"
    
    cat > /etc/xray/config.json << EOF
{"log": { "loglevel": "warning" }, "inbounds": [{"port": $port, "listen": "127.0.0.1", "protocol": "vmess", "settings": { "clients": [{ "id": "$uuid", "alterId": 0 }] }, "streamSettings": { "network": "ws", "wsSettings": { "path": "$ws_path" } }}], "outbounds": [{ "protocol": "freedom" }]}
EOF
    echo "$uuid" > "$CONF_DIR/xray-uuid" && systemctl restart xray 2>/dev/null
    printc "$G" "✓ VMess configured! UUID: $uuid"; sleep 2
}

configure_xray_trojan() {
    local uuid=$(cat "$CONF_DIR/xray-uuid" 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    read -p "  Password [$uuid]: " input_uuid; uuid="${input_uuid:-$uuid}"
    read -p "  WS Path [/trojan]: " ws_path; ws_path="${ws_path:-/trojan}"
    read -p "  Listen Port [8445]: " port; port="${port:-8445}"
    
    cat > /etc/xray/config.json << EOF
{"log": { "loglevel": "warning" }, "inbounds": [{"port": $port, "listen": "127.0.0.1", "protocol": "trojan", "settings": { "clients": [{ "password": "$uuid" }] }, "streamSettings": { "network": "ws", "wsSettings": { "path": "$ws_path" } }}], "outbounds": [{ "protocol": "freedom" }]}
EOF
    echo "$uuid" > "$CONF_DIR/xray-uuid" && systemctl restart xray 2>/dev/null
    printc "$G" "✓ Trojan configured! Pass: $uuid"; sleep 2
}

configure_xray_grpc() { printc "$Y" "Coming soon..."; sleep 2; }
configure_multiport() { printc "$Y" "Coming soon..."; sleep 2; }
configure_sshws_ssl() { printc "$Y" "Coming soon..."; sleep 2; }

generate_links() {
    local uuid=$(cat "$CONF_DIR/xray-uuid" 2>/dev/null)
    local domain=$(cat "$CONF_DIR/domain" 2>/dev/null || echo "$PUBLIC_IP")
    show_header
    draw_box "╔" "╗" "" "" "$BG" 60 "GENERATED LINKS"
    printc "$BG" "╠$(printf '─%.0s' {1..58})╣"
    printc "$W" "║  Copy these links to your V2Ray/NekoBox client                 ║"
    printc "$BG" "╚$(printf '─%.0s' {1..58})╝"
    echo ""
    printc "$C" "  VLESS WS: "
    printc "$W" "  vless://${uuid}@${domain}:443?type=ws&path=/xray&security=tls#VLESS-WS"
    echo ""
    printc "$C" "  VMESS WS: "
    printc "$W" "  vmess://$(echo -n '{"v":"2","ps":"VMess-WS","add":"'"$domain"'","port":"443","id":"'"$uuid"'","aid":"0","net":"ws","type":"none","host":"'"$domain"'","path":"/vmess","tls":"tls"}' | base64 -w0)"
    echo ""
    printc "$C" "  TROJAN WS: "
    printc "$W" "  trojan://${uuid}@${domain}:443?type=ws&path=/trojan&security=tls#TROJAN-WS"
    echo ""
    read -p "Press Enter to continue..."
}

#======================== MENUS ===============================================
service_menu() {
    while true; do
        show_header
        show_services_status
        draw_box "╔" "╗" "" "" "$BC" 60 "SERVICE CONTROL"
        printc "$BC" "╠$(printf '─%.0s' {1..58})╣"
        printc "$BC" "║${RE} ${BW}1.${RE} Start All Services           ${BC}║${RE} ${BW}7.${RE} Start Xray           ${BC}║${RE}"
        printc "$BC" "║${RE} ${BW}2.${RE} Stop All Services            ${BC}║${RE} ${BW}8.${RE} Stop Xray            ${BC}║${RE}"
        printc "$BC" "║${RE} ${BW}3.${RE} Restart All Services         ${BC}║${RE} ${BW}9.${RE} Restart Xray         ${BC}║${RE}"
        printc "$BC" "║${RE} ${BW}4.${RE} Start Nginx                  ${BC}║${RE} ${BW}10.${RE} View Xray Logs       ${BC}║${RE}"
        printc "$BC" "║${RE} ${BW}5.${RE} Stop Nginx                   ${BC}║${RE} ${BW}0.${RE} Back to Main Menu     ${BC}║${RE}"
        printc "$BC" "║${RE} ${BW}6.${RE} Restart Nginx                ${BC}║${RE}"
        printc "$BC" "╚$(printf '─%.0s' {1..58})╝"
        echo ""
        read -p "  Select option [0-10]: " opt
        
        case $opt in
            1) for s in nginx ws-dropbear ws-stunnel ws-openssh ws xray haproxy; do systemctl start $s 2>/dev/null; done; printc "$G" "✓ All services started"; sleep 2 ;;
            2) for s in xray haproxy ws ws-openssh ws-stunnel ws-dropbear nginx; do systemctl stop $s 2>/dev/null; done; printc "$G" "✓ All services stopped"; sleep 2 ;;
            3) for s in nginx ws-dropbear ws-stunnel ws-openssh ws xray haproxy; do systemctl restart $s 2>/dev/null; done; printc "$G" "✓ All services restarted"; sleep 2 ;;
            4) systemctl start nginx && printc "$G" "✓ Nginx started" || printc "$R" "✗ Failed"; sleep 2 ;;
            5) systemctl stop nginx && printc "$G" "✓ Nginx stopped" || printc "$R" "✗ Failed"; sleep 2 ;;
            6) systemctl restart nginx && printc "$G" "✓ Nginx restarted" || printc "$R" "✗ Failed"; sleep 2 ;;
            7) systemctl start xray && printc "$G" "✓ Xray started" || printc "$R" "✗ Failed"; sleep 2 ;;
            8) systemctl stop xray && printc "$G" "✓ Xray stopped" || printc "$R" "✗ Failed"; sleep 2 ;;
            9) systemctl restart xray && printc "$G" "✓ Xray restarted" || printc "$R" "✗ Failed"; sleep 2 ;;
            10) journalctl -u xray -n 50 --no-pager; echo ""; read -p "Press Enter to continue..." ;;
            0) break ;;
            *) printc "$R" "✗ Invalid option"; sleep 1 ;;
        esac
    done
}

install_menu() {
    while true; do
        show_header
        draw_box "╔" "╗" "" "" "$BG" 60 "INSTALLATION MENU"
        printc "$BG" "╠$(printf '─%.0s' {1..58})╣"
        printc "$BG" "║${RE} ${BW}[CORE COMPONENTS]${RE}                                               ${BG}║${RE}"
        printc "$BG" "║${RE} ${BW}  1.${RE} Install Nginx              ${D}(Web Server)${RE}           ${BG}║${RE}"
        printc "$BG" "║${RE} ${BW}  2.${RE} Install acme.sh            ${D}(SSL Cert)${RE}             ${BG}║${RE}"
        printc "$BG" "║${RE} ${BW}  3.${RE} Install HAProxy            ${D}(Load Balancer)${RE}        ${BG}║${RE}"
        printc "$BG" "╟$(printf '─%.0s' {1..58})╢"
        printc "$BG" "║${RE} ${BW}[WEBSOCKET SERVICES]${RE}                                            ${BG}║${RE}"
        printc "$BG" "║${RE} ${BW}  4.${RE} Install WS Dropbear        ${D}(+ .service)${RE}           ${BG}║${RE}"
        printc "$BG" "║${RE} ${BW}  5.${RE} Install WS Stunnel         ${D}(+ .service)${RE}           ${BG}║${RE}"
        printc "$BG" "║${RE} ${BW}  6.${RE} Install WS (Generic)       ${D}(+ .service)${RE}           ${BG}║${RE}"
        printc "$BG" "║${RE} ${BW}  7.${RE} Install WS OpenSSH         ${D}(+ .service)${RE}           ${BG}║${RE}"
        printc "$BG" "╟$(printf '─%.0s' {1..58})╢"
        printc "$BG" "║${RE} ${BW}[PROXY & TUNNEL]${RE}                                              ${BG}║${RE}"
        printc "$BG" "║${RE} ${BW}  8.${RE} Install proxy-ws           ${D}(WS Proxy)${RE}             ${BG}║${RE}"
        printc "$BG" "║${RE} ${BW}  9.${RE} Install Xray Core          ${D}(VLESS/VMess/Trojan)${RE}   ${BG}║${RE}"
        printc "$BG" "╟$(printf '─%.0s' {1..58})╢"
        printc "$BG" "║${RE} ${BY} 10.${RE} ${BY}Install ALL Components${RE}                              ${BG}║${RE}"
        printc "$BG" "║${RE} ${BY} 11.${RE} ${BY}Setup SSL/TLS${RE}                                        ${BG}║${RE}"
        printc "$BG" "║${RE} ${BR} 12.${RE} ${BR}Uninstall All${RE}                                        ${BG}║${RE}"
        printc "$BG" "╟$(printf '─%.0s' {1..58})╢"
        printc "$BG" "║${RE} ${BW}  0.${RE} Back to Main Menu                                      ${BG}║${RE}"
        printc "$BG" "╚$(printf '─%.0s' {1..58})╝"
        echo ""
        read -p "  Select option [0-12]: " opt
        
        case $opt in
            1) install_nginx ;; 2) install_acme ;; 3) install_haproxy ;;
            4) install_ws_dropbear ;; 5) install_ws_stunnel ;; 6) install_ws ;; 7) install_ws_openssh ;;
            8) install_proxy_ws ;; 9) install_xray ;;
            10) install_nginx; install_acme; install_haproxy; install_ws_dropbear; install_ws_stunnel; install_ws; install_ws_openssh; install_proxy_ws; install_xray; printc "$BG" "✓ All components installed!"; sleep 2 ;;
            11) setup_ssl ;;
            12) read -p "  Are you sure you want to uninstall all? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    for s in xray haproxy ws ws-openssh ws-stunnel ws-dropbear nginx; do systemctl stop $s 2>/dev/null; systemctl disable $s 2>/dev/null; done
                    rm -f "$BIN_DIR/ws-dropbear" "$BIN_DIR/ws-stunnel" "$BIN_DIR/ws" "$BIN_DIR/ws-ssh" "$BIN_DIR/proxy-ws" "$BIN_DIR/xray"
                    rm -rf /etc/xray /etc/tunnel-manager/ssl "$CONF_DIR"
                    printc "$G" "✓ All components uninstalled"; sleep 2
                fi ;;
            0) break ;;
            *) printc "$R" "✗ Invalid option"; sleep 1 ;;
        esac
    done
}

tunnel_menu() {
    while true; do
        show_header
        local DOMAIN=""
        [ -f "$CONF_DIR/domain" ] && DOMAIN=$(cat "$CONF_DIR/domain")
        local IP="${PUBLIC_IP:-$(curl -s ifconfig.me 2>/dev/null)}"
        
        draw_box "╔" "╗" "" "" "$BM" 60 "TUNNEL CONFIGURATION"
        printc "$BM" "╠$(printf '─%.0s' {1..58})╣"
        printf "${BM}║${RE} ${BW}Server IP:${RE}  ${BG}%-48s${RE} ${BM}║${RE}\n" "$IP"
        printf "${BM}║${RE} ${BW}Domain:${RE}    ${BG}%-48s${RE} ${BM}║${RE}\n" "${DOMAIN:-Not configured}"
        printc "$BM" "╠$(printf '─%.0s' {1..58})╣"
        printc "$BM" "║${RE} ${BW}1.${RE} Configure SSHWS TLS                                         ${BM}║${RE}"
        printc "$BM" "║${RE} ${BW}2.${RE} Configure SSHWS NTLS                                        ${BM}║${RE}"
        printc "$BM" "╟$(printf '─%.0s' {1..58})╢"
        printc "$BM" "║${RE} ${BW}3.${RE} Configure Xray VLESS                                        ${BM}║${RE}"
        printc "$BM" "║${RE} ${BW}4.${RE} Configure Xray VMess                                        ${BM}║${RE}"
        printc "$BM" "║${RE} ${BW}5.${RE} Configure Xray Trojan                                       ${BM}║${RE}"
        printc "$BM} "║${RE} ${BW}6.${RE} Generate All Tunnel Links                                  ${BM}║${RE}"
        printc "$BM" "╟$(printf '─%.0s' {1..58})╢"
        printc "$BM" "║${RE} ${BW} 0.${RE} Back to Main Menu                                      ${BM}║${RE}"
        printc "$BM" "╚$(printf '─%.0s' {1..58})╝"
        echo ""
        read -p "  Select option [0-6]: " opt
        
        case $opt in
            1) configure_sshws_tls ;; 2) configure_sshws_ntls ;;
            3) configure_xray_vless ;; 4) configure_xray_vmess ;; 5) configure_xray_trojan ;;
            6) generate_links ;;
            0) break ;;
            *) printc "$R" "✗ Invalid option"; sleep 1 ;;
        esac
    done
}

main_menu() {
    while true; do
        show_header
        show_vps_info
        show_services_status
        draw_box "╔" "╗" "" "" "$BC" 60 "MAIN MENU"
        printc "$BC" "╠$(printf '─%.0s' {1..58})╣"
        printc "$BC" "║${RE} ${BW}1.${RE} Installation Menu             ${BC}║${RE} ${BW}4.${RE} Service Control           ${BC}║${RE}"
        printc "$BC" "║${RE} ${BW}2.${RE} Tunnel Configuration          ${BC}║${RE} ${BW}5.${RE} Update System             ${BC}║${RE}"
        printc "$BC" "║${RE} ${BW}3.${RE} Setup SSL/TLS                ${BC}║${RE} ${BW}0.${RE} Exit                     ${BC}║${RE}"
        printc "$BC" "╚$(printf '─%.0s' {1..58})╝"
        echo ""
        read -p "  Select option [0-5]: " opt
        
        case $opt in
            1) install_menu ;; 2) tunnel_menu ;; 3) setup_ssl ;;
            4) service_menu ;; 5) update_system ;;
            0) clear; echo "Bye!"; exit 0 ;;
            *) printc "$R" "✗ Invalid option"; sleep 1 ;;
        esac
    done
}

#======================== EXECUTION ==========================================
check_root
check_os
main_menu
