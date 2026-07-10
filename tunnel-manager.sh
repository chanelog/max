#!/bin/bash
#=============================================================================
#  SSHWS & XRAY TUNNELING MANAGER
#  Version: 3.0.0 | Author: TunnelManager
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
    RAM_PERCENT=$(awk "BEGIN {printf \"%.1f\", ($RAM_USED/$RAM_TOTAL)*100}")
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
    printc "$BC" "║" ; printc "$BW" "  Version 3.0.0 • Multi Protocol Tunneling" ; printc "$BC" "          ║"
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
        apt-get update -y 2>&1 | while read line; do
            printc "$D" "  $line"
        done
        apt-get upgrade -y 2>&1 | while read line; do
            printc "$D" "  $line"
        done
    else
        yum update -y 2>&1 | while read line; do
            printc "$D" "  $line"
        done
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
        printc "$Y" "⚠ Nginx already installed. Reinstalling..."
        systemctl stop nginx 2>/dev/null
    fi
    
    install_dependencies
    
    printc "$W" "[1/4] Downloading Nginx..."
    NGINX_VER="1.25.5"
    cd "$TMP_DIR"
    wget -q "https://nginx.org/download/nginx-${NGINX_VER}.tar.gz" -O nginx.tar.gz
    tar -xzf nginx.tar.gz && cd "nginx-${NGINX_VER}"
    printc "$G" "      ✓ Downloaded"
    
    printc "$W" "[2/4] Configuring..."
    ./configure --prefix=/etc/nginx \
        --sbin-path=/usr/sbin/nginx \
        --modules-path=/usr/lib64/nginx/modules \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --pid-path=/var/run/nginx.pid \
        --lock-path=/var/run/nginx.lock \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_realip_module \
        --with-http_gzip_static_module \
        --with-http_sub_module \
        --with-stream \
        --with-stream_ssl_module \
        --with-stream_realip_module &>/dev/null
    printc "$G" "      ✓ Configured"
    
    printc "$W" "[3/4] Compiling..."
    make -j$(nproc) &>/dev/null
    make install &>/dev/null
    printc "$G" "      ✓ Compiled"
    
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

    mkdir -p /etc/nginx/conf.d /var/log/nginx
    systemctl daemon-reload
    systemctl enable nginx
    systemctl start nginx
    
    printc "$G" "      ✓ Nginx service installed"
    log "Nginx installation completed"
    printc "$BG" "\n✓ Nginx ${NGINX_VER} installed successfully!"
    sleep 2
}

#------------------------ ACME.SH INSTALLATION -------------------------------
install_acme() {
    show_header
    draw_box "╔" "╗" "" "" "$BG" 60 "INSTALLING ACME.SH"
    printc "$BG" "╠$(printf '─%.0s' {1..58})╣"
    printc "$W" "║  Source: github.com/acmesh-official/acme.sh                    ║"
    printc "$BG" "╚$(printf '─%.0s' {1..58})╝"
    echo ""
    
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
    
    printc "$W" "[2/2] Setting default CA..."
    "$HOME/.acme.sh/acme.sh" --set-default-ca --server letsencrypt 2>/dev/null
    printc "$G" "      ✓ Let's Encrypt set as default"
    
    log "acme.sh installation completed"
    printc "$BG" "\n✓ acme.sh installed successfully!"
    printc "$W" "  Usage: ~/.acme.sh/acme.sh --issue -d domain.com --webroot /var/www/html"
    sleep 2
}

#------------------------ WS DROPBEAR INSTALLATION ---------------------------
install_ws_dropbear() {
    show_header
    draw_box "╔" "╗" "" "" "$BG" 60 "INSTALLING WS DROPBEAR"
    printc "$BG" "╠$(printf '─%.0s' {1..58})╣"
    printc "$W" "║  Source: github.com/badudinda/ws-dropbear                     ║"
    printc "$BG" "╚$(printf '─%.0s' {1..58})╝"
    echo ""
    
    log "Installing WS Dropbear"
    
    printc "$W" "[1/4] Installing Dropbear SSH..."
    if [ "$PKG_MGR" = "apt" ]; then
        apt-get install -y -qq dropbear dropbear-bin 2>/dev/null
    else
        yum install -y -q dropbear 2>/dev/null
    fi
    printc "$G" "      ✓ Dropbear installed"
    
    printc "$W" "[2/4] Cloning ws-dropbear..."
    cd "$TMP_DIR"
    rm -rf ws-dropbear
    git clone --depth 1 "$GH_WS_DROPBEAR" 2>/dev/null
    printc "$G" "      ✓ Cloned"
    
    printc "$W" "[3/4] Installing binary..."
    if [ -f ws-dropbear/ws-dropbear ]; then
        cp ws-dropbear/ws-dropbear "$BIN_DIR/"
        chmod +x "$BIN_DIR/ws-dropbear"
    elif [ -f ws-dropbear/ws ]; then
        cp ws-dropbear/ws "$BIN_DIR/ws-dropbear"
        chmod +x "$BIN_DIR/ws-dropbear"
    else
        # Fallback: create wrapper script
        cat > "$BIN_DIR/ws-dropbear" << 'WSEOF'
#!/bin/bash
# WS-Dropbear Wrapper
DROPBEAR_PORT=${1:-443}
WS_PATH=${2:-/ws-dropbear}
LISTEN_IP=${3:-0.0.0.0}

if [ "$1" = "stop" ]; then
    pkill -f "ws-dropbear" 2>/dev/null
    echo "WS-Dropbear stopped"
    exit 0
fi

echo "Starting WS-Dropbear on ${LISTEN_IP}:${DROPBEAR_PORT}${WS_PATH}"
while true; do
    socat TCP-LISTEN:${DROPBEAR_PORT},bind=${LISTEN_IP},reuseaddr,fork \
        EXEC:"dropbear -i -p 0",pty,stderr,setsid
done
WSEOF
        chmod +x "$BIN_DIR/ws-dropbear"
    fi
    printc "$G" "      ✓ Binary installed"
    
    printc "$W" "[4/4] Creating service..."
    cat > /etc/systemd/system/ws-dropbear.service << 'EOF'
[Unit]
Description=WebSocket Dropbear Tunnel
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ws-dropbear 443 /ws-dropbear 0.0.0.0
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable ws-dropbear
    
    log "WS Dropbear installation completed"
    printc "$BG" "\n✓ WS Dropbear installed successfully!"
    sleep 2
}

#------------------------ WS STUNNEL INSTALLATION ----------------------------
install_ws_stunnel() {
    show_header
    draw_box "╔" "╗" "" "" "$BG" 60 "INSTALLING WS STUNNEL"
    printc "$BG" "╠$(printf '─%.0s' {1..58})╣"
    printc "$W" "║  Source: github.com/badudinda/ws-stunnel                      ║"
    printc "$BG" "╚$(printf '─%.0s' {1..58})╝"
    echo ""
    
    log "Installing WS Stunnel"
    
    printc "$W" "[1/4] Installing stunnel..."
    if [ "$PKG_MGR" = "apt" ]; then
        apt-get install -y -qq stunnel4 2>/dev/null
    else
        yum install -y -q stunnel 2>/dev/null
    fi
    printc "$G" "      ✓ Stunnel installed"
    
    printc "$W" "[2/4] Cloning ws-stunnel..."
    cd "$TMP_DIR"
    rm -rf ws-stunnel
    git clone --depth 1 "$GH_WS_STUNNEL" 2>/dev/null
    printc "$G" "      ✓ Cloned"
    
    printc "$W" "[3/4] Installing binary..."
    if [ -f ws-stunnel/ws-stunnel ]; then
        cp ws-stunnel/ws-stunnel "$BIN_DIR/"
        chmod +x "$BIN_DIR/ws-stunnel"
    else
        cat > "$BIN_DIR/ws-stunnel" << 'WSEOF'
#!/bin/bash
# WS-Stunnel Wrapper
STUNNEL_PORT=${1:-444}
WS_PATH=${2:-/ws-stunnel}
TARGET_PORT=${3:-22}
LISTEN_IP=${4:-0.0.0.0}

echo "Starting WS-Stunnel on ${LISTEN_IP}:${STUNNEL_PORT}${WS_PATH} -> localhost:${TARGET_PORT}"
while true; do
    socat TCP-LISTEN:${STUNNEL_PORT},bind=${LISTEN_IP},reuseaddr,fork \
        TCP:localhost:${TARGET_PORT}
done
WSEOF
        chmod +x "$BIN_DIR/ws-stunnel"
    fi
    printc "$G" "      ✓ Binary installed"
    
    printc "$W" "[4/4] Creating service..."
    cat > /etc/systemd/system/ws-stunnel.service << 'EOF'
[Unit]
Description=WebSocket Stunnel Tunnel
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ws-stunnel 444 /ws-stunnel 22 0.0.0.0
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable ws-stunnel
    
    log "WS Stunnel installation completed"
    printc "$BG" "\n✓ WS Stunnel installed successfully!"
    sleep 2
}

#------------------------ WS (GENERIC) INSTALLATION --------------------------
install_ws() {
    show_header
    draw_box "╔" "╗" "" "" "$BG" 60 "INSTALLING WS (GENERIC)"
    printc "$BG" "╠$(printf '─%.0s' {1..58})╣"
    printc "$W" "║  Generic WebSocket Tunnel Service                            ║"
    printc "$BG" "╚$(printf '─%.0s' {1..58})╝"
    echo ""
    
    log "Installing Generic WS"
    
    printc "$W" "[1/3] Installing dependencies..."
    $INSTALL python3 python3-pip websockify 2>/dev/null || {
        pip3 install websockify 2>/dev/null
    }
    printc "$G" "      ✓ Dependencies installed"
    
    printc "$W" "[2/3] Creating WS binary..."
    cat > "$BIN_DIR/ws" << 'WSEOF'
#!/bin/bash
# Generic WebSocket Tunnel
WS_PORT=${1:-8080}
TARGET_HOST=${2:-localhost}
TARGET_PORT=${3:-22}
WS_PATH=${4:-/ws}

if [ "$1" = "stop" ]; then
    pkill -f "websockify.*${WS_PORT}" 2>/dev/null
    echo "WS stopped"
    exit 0
fi

exec websockify ${WS_PORT} ${TARGET_HOST}:${TARGET_PORT} --path=${WS_PATH}
WSEOF
    chmod +x "$BIN_DIR/ws"
    printc "$G" "      ✓ Binary created"
    
    printc "$W" "[3/3] Creating service..."
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
    
    systemctl daemon-reload
    systemctl enable ws
    
    log "Generic WS installation completed"
    printc "$BG" "\n✓ Generic WS installed successfully!"
    sleep 2
}

#------------------------ HAPROXY INSTALLATION --------------------------------
install_haproxy() {
    show_header
    draw_box "╔" "╗" "" "" "$BG" 60 "INSTALLING HAPROXY"
    printc "$BG" "╠$(printf '─%.0s' {1..58})╣"
    printc "$W" "║  Source: haproxy.org                                         ║"
    printc "$BG" "╚$(printf '─%.0s' {1..58})╝"
    echo ""
    
    log "Installing HAProxy"
    
    printc "$W" "[1/3] Installing HAProxy..."
    if [ "$PKG_MGR" = "apt" ]; then
        apt-get install -y -qq software-properties-common 2>/dev/null
        add-apt-repository -y ppa:vbernat/haproxy-2.8 2>/dev/null
        apt-get update -qq
        apt-get install -y -qq haproxy 2>/dev/null
    else
        yum install -y -q haproxy 2>/dev/null
    fi
    printc "$G" "      ✓ HAProxy installed"
    
    printc "$W" "[2/3] Creating configuration..."
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
    
    # WS Dropbear
    acl is_ws_dropbear path_beg /ws-dropbear
    use_backend ws-dropbear if is_ws_dropbear
    
    # WS Stunnel
    acl is_ws_stunnel path_beg /ws-stunnel
    use_backend ws-stunnel if is_ws_stunnel
    
    # WS OpenSSH
    acl is_ws_ssh path_beg /ws-ssh
    use_backend ws-ssh if is_ws_ssh
    
    # Xray
    acl is_xray path_beg /xray
    use_backend xray if is_xray
    
    # Default
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
    printc "$G" "      ✓ Configuration created"
    
    printc "$W" "[3/3] Enabling service..."
    sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/haproxy 2>/dev/null
    systemctl daemon-reload
    systemctl enable haproxy
    printc "$G" "      ✓ Service enabled"
    
    log "HAProxy installation completed"
    printc "$BG" "\n✓ HAProxy installed successfully!"
    sleep 2
}

#------------------------ PROXY-WS INSTALLATION -------------------------------
install_proxy_ws() {
    show_header
    draw_box "╔" "╗" "" "" "$BG" 60 "INSTALLING PROXY-WS"
    printc "$BG" "╠$(printf '─%.0s' {1..58})╣"
    printc "$W" "║  Source: github.com/badudinda/proxy-ws                        ║"
    printc "$BG" "╚$(printf '─%.0s' {1..58})╝"
    echo ""
    
    log "Installing proxy-ws"
    
    printc "$W" "[1/3] Cloning proxy-ws..."
    cd "$TMP_DIR"
    rm -rf proxy-ws
    git clone --depth 1 "$GH_PROXY_WS" 2>/dev/null
    printc "$G" "      ✓ Cloned"
    
    printc "$W" "[2/3] Installing..."
    cd proxy-ws
    if [ -f Makefile ]; then
        make && make install 2>/dev/null
    elif [ -f setup.py ]; then
        pip3 install . 2>/dev/null
    elif [ -f proxy-ws ] || [ -f main ]; then
        cp proxy-ws "$BIN_DIR/" 2>/dev/null || cp main "$BIN_DIR/proxy-ws" 2>/dev/null
        chmod +x "$BIN_DIR/proxy-ws" 2>/dev/null
    else
        # Create proxy-ws script
        cat > "$BIN_DIR/proxy-ws" << 'PWSEOF'
#!/bin/bash
# Proxy-WS - WebSocket to TCP Proxy
LISTEN_PORT=${1:-8080}
TARGET_HOST=${2:-127.0.0.1}
TARGET_PORT=${3:-22}
WS_PATH=${4:-/}

usage() {
    echo "Usage: $0 <listen_port> <target_host> <target_port> <ws_path>"
    echo "Example: $0 8080 127.0.0.1 22 /ws"
    exit 1
}

[ "$1" = "-h" ] || [ "$1" = "--help" ] && usage

exec socat TCP-LISTEN:${LISTEN_PORT},reuseaddr,fork TCP:${TARGET_HOST}:${TARGET_PORT}
PWSEOF
        chmod +x "$BIN_DIR/proxy-ws"
    fi
    printc "$G" "      ✓ Installed"
    
    printc "$W" "[3/3] Creating configuration directory..."
    mkdir -p "$CONF_DIR/proxy-ws"
    cat > "$CONF_DIR/proxy-ws/config.conf" << 'EOF'
# Proxy-WS Configuration
LISTEN_PORT=8080
TARGET_HOST=127.0.0.1
TARGET_PORT=22
WS_PATH=/
EOF
    printc "$G" "      ✓ Configuration created"
    
    log "proxy-ws installation completed"
    printc "$BG" "\n✓ proxy-ws installed successfully!"
    sleep 2
}

#------------------------ XRAY INSTALLATION ----------------------------------
install_xray() {
    show_header
    draw_box "╔" "╗" "" "" "$BG" 60 "INSTALLING XRAY"
    printc "$BG" "╠$(printf '─%.0s' {1..58})╣"
    printc "$W" "║  Source: github.com/XTLS/Xray-core                          ║"
    printc "$BG" "╚$(printf '─%.0s' {1..58})╝"
    echo ""
    
    log "Installing Xray"
    
    printc "$W" "[1/4] Detecting architecture..."
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) XRAY_ARCH="amd64" ;;
        aarch64) XRAY_ARCH="arm64-v8a" ;;
        armv7l) XRAY_ARCH="arm32-v7a" ;;
        *) printc "$R" "      ✗ Unsupported architecture: $ARCH"; return 1 ;;
    esac
    printc "$G" "      ✓ Architecture: $XRAY_ARCH"
    
    printc "$W" "[2/4] Getting latest version..."
    XRAY_VER=$(curl -sL "$GH_XRAY/latest" | grep -oP '"tag_name":\s*"\K[^"]+' | head -1)
    if [ -z "$XRAY_VER" ]; then
        XRAY_VER="v1.8.8"
    fi
    printc "$G" "      ✓ Version: $XRAY_VER"
    
    printc "$W" "[3/4] Downloading..."
    cd "$TMP_DIR"
    XRAY_FILE="Xray-linux-${XRAY_ARCH}.zip"
    wget -q "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VER}/${XRAY_FILE}" -O xray.zip
    unzip -o xray.zip -d xray &>/dev/null
    cp xray/xray "$BIN_DIR/"
    chmod +x "$BIN_DIR/xray"
    printc "$G" "      ✓ Downloaded"
    
    printc "$W" "[4/4] Creating configuration and service..."
    mkdir -p /etc/xray /var/log/xray
    
    UUID=$(cat /proc/sys/kernel/random/uuid)
    
    cat > /etc/xray/config.json << EOF
{
    "log": {
        "loglevel": "warning",
        "access": "/var/log/xray/access.log",
        "error": "/var/log/xray/error.log"
    },
    "inbounds": [
        {
            "port": 8443,
            "listen": "127.0.0.1",
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "${UUID}",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none",
                "fallbacks": [
                    {
                        "dest": 8080
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "/xray"
                }
            }
        },
        {
            "port": 8444,
            "listen": "127.0.0.1",
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "${UUID}",
                        "alterId": 0
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "/vmess"
                }
            }
        },
        {
            "port": 8445,
            "listen": "127.0.0.1",
            "protocol": "trojan",
            "settings": {
                "clients": [
                    {
                        "password": "${UUID}"
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "/trojan"
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {}
        }
    ]
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
    
    # Save UUID for display
    echo "$UUID" > "$CONF_DIR/xray-uuid"
    
    systemctl daemon-reload
    systemctl enable xray
    
    log "Xray installation completed"
    printc "$BG" "\n✓ Xray ${XRAY_VER} installed successfully!"
    printc "$BW" "  UUID: $UUID"
    sleep 2
}

#------------------------ WS OPENSSH INSTALLATION ----------------------------
install_ws_openssh() {
    show_header
    draw_box "╔" "╗" "" "" "$BG" 60 "INSTALLING WS OPENSSH"
    printc "$BG" "╠$(printf '─%.0s' {1..58})╣"
    printc "$W" "║  Source: github.com/badudinda/ws-ssh                          ║"
    printc "$BG" "╚$(printf '─%.0s' {1..58})╝"
    echo ""
    
    log "Installing WS OpenSSH"
    
    printc "$W" "[1/4] Ensuring OpenSSH is installed..."
    if [ "$PKG_MGR" = "apt" ]; then
        apt-get install -y -qq openssh-server 2>/dev/null
    else
        yum install -y -q openssh-server 2>/dev/null
    fi
    printc "$G" "      ✓ OpenSSH installed"
    
    printc "$W" "[2/4] Cloning ws-ssh..."
    cd "$TMP_DIR"
    rm -rf ws-ssh
    git clone --depth 1 "$GH_WS_SSH" 2>/dev/null
    printc "$G" "      ✓ Cloned"
    
    printc "$W" "[3/4] Installing binary..."
    if [ -f ws-ssh/ws-ssh ]; then
        cp ws-ssh/ws-ssh "$BIN_DIR/"
        chmod +x "$BIN_DIR/ws-ssh"
    elif [ -f ws-ssh/ws ]; then
        cp ws-ssh/ws "$BIN_DIR/ws-ssh"
        chmod +x "$BIN_DIR/ws-ssh"
    else
        cat > "$BIN_DIR/ws-ssh" << 'WSEOF'
#!/bin/bash
# WS-OpenSSH Wrapper
WS_SSH_PORT=${1:-445}
WS_PATH=${2:-/ws-ssh}
TARGET_PORT=${3:-22}
LISTEN_IP=${4:-0.0.0.0}

echo "Starting WS-OpenSSH on ${LISTEN_IP}:${WS_SSH_PORT}${WS_PATH} -> localhost:${TARGET_PORT}"
while true; do
    socat TCP-LISTEN:${WS_SSH_PORT},bind=${LISTEN_IP},reuseaddr,fork \
        TCP:localhost:${TARGET_PORT}
done
WSEOF
        chmod +x "$BIN_DIR/ws-ssh"
    fi
    printc "$G" "      ✓ Binary installed"
    
    printc "$W" "[4/4] Creating service..."
    cat > /etc/systemd/system/ws-openssh.service << 'EOF'
[Unit]
Description=WebSocket OpenSSH Tunnel
After=network.target sshd.service

[Service]
Type=simple
ExecStart=/usr/local/bin/ws-ssh 445 /ws-ssh 22 0.0.0.0
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable ws-openssh
    
    log "WS OpenSSH installation completed"
    printc "$BG" "\n✓ WS OpenSSH installed successfully!"
    sleep 2
}

#======================== SSL/TLS FUNCTIONS ==================================
setup_ssl() {
    show_header
    draw_box "╔" "╗" "" "" "$BY" 60 "SSL/TLS SETUP"
    printc "$BY" "╠$(printf '─%.0s' {1..58})╣"
    printc "$W" "║  Configure SSL certificate using acme.sh                   ║"
    printc "$BY" "╚$(printf '─%.0s' {1..58})╝"
    echo ""
    
    read -p "  Enter domain name: " DOMAIN
    if [ -z "$DOMAIN" ]; then
        printc "$R" "✗ Domain cannot be empty!"
        sleep 2
        return 1
    fi
    
    read -p "  Enter email (for Let's Encrypt): " EMAIL
    EMAIL="${EMAIL:-admin@${DOMAIN}}"
    
    log "Setting up SSL for $DOMAIN"
    
    # Ensure acme.sh is installed
    if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
        printc "$W" "Installing acme.sh first..."
        install_acme
    fi
    
    # Create webroot
    mkdir -p /var/www/html
    
    printc "$W" "[1/4] Issuing certificate..."
    "$HOME/.acme.sh/acme.sh" --issue -d "$DOMAIN" --webroot /var/www/html 2>&1 | while read line; do
        printc "$D" "  $line"
    done
    
    if [ $? -ne 0 ]; then
        printc "$R" "✗ Certificate issuance failed!"
        sleep 2
        return 1
    fi
    printc "$G" "      ✓ Certificate issued"
    
    printc "$W" "[2/4] Installing certificate..."
    mkdir -p /etc/tunnel-manager/ssl
    
    "$HOME/.acme.sh/acme.sh" --install-cert -d "$DOMAIN" \
        --fullchain-file /etc/tunnel-manager/ssl/fullchain.pem \
        --key-file /etc/tunnel-manager/ssl/privkey.pem \
        --reloadcmd "systemctl reload nginx haproxy" 2>/dev/null
    
    printc "$G" "      ✓ Certificate installed"
    
    printc "$W" "[3/4] Configuring Nginx SSL..."
    if [ -f /etc/nginx/nginx.conf ]; then
        cat > /etc/nginx/conf.d/ssl.conf << EOF
server {
    listen 8080 ssl;
    server_name $DOMAIN;
    
    ssl_certificate /etc/tunnel-manager/ssl/fullchain.pem;
    ssl_certificate_key /etc/tunnel-manager/ssl/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;
    
    location / {
        root /var/www/html;
        index index.html index.htm;
    }
}
EOF
        nginx -t 2>/dev/null && systemctl reload nginx
    fi
    printc "$G" "      ✓ Nginx SSL configured"
    
    printc "$W" "[4/4] Saving domain..."
    echo "$DOMAIN" > "$CONF_DIR/domain"
    echo "$EMAIL" > "$CONF_DIR/email"
    printc "$G" "      ✓ Domain saved"
    
    log "SSL setup completed for $DOMAIN"
    printc "$BG" "\n✓ SSL/TLS configured successfully for $DOMAIN!"
    sleep 2
}

#======================== SERVICE CONTROL ====================================
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
        printc "$BC" "║${RE} ${BW}5.${RE} Stop Nginx                   ${BC}║${RE} ${BW}11.${RE} View All Logs        ${BC}║${RE}"
        printc "$BC" "║${RE} ${BW}6.${RE} Restart Nginx                ${BC}║${RE} ${BW}0.${RE} Back to Main Menu     ${BC}║${RE}"
        printc "$BC" "╚$(printf '─%.0s' {1..58})╝"
        echo ""
        read -p "  Select option [0-11]: " opt
        
        case $opt in
            1) for s in nginx ws-dropbear ws-stunnel ws-openssh ws xray haproxy; do systemctl start $s 2>/dev/null; done; printc "$G" "✓ All services started"; sleep 2 ;;
            2) for s in xray haproxy ws ws-openssh ws-stunnel ws-dropbear nginx; do systemctl stop $s 2>/dev/null; done; printc "$G" "✓ All services stopped"; sleep 2 ;;
            3) for s in nginx ws-dropbear ws-stunnel ws-openssh ws xray haproxy; do systemctl restart $s 2>/dev/null; done; printc "$G" "✓ All services restarted"; sleep 2 ;;
            4) systemctl start nginx && printc "$G" "✓ Nginx started" || printc "$R" "✗ Failed to start"; sleep 2 ;;
            5) systemctl stop nginx && printc "$G" "✓ Nginx stopped" || printc "$R" "✗ Failed to stop"; sleep 2 ;;
            6) systemctl restart nginx && printc "$G" "✓ Nginx restarted" || printc "$R" "✗ Failed to restart"; sleep 2 ;;
            7) systemctl start xray && printc "$G" "✓ Xray started" || printc "$R" "✗ Failed to start"; sleep 2 ;;
            8) systemctl stop xray && printc "$G" "✓ Xray stopped" || printc "$R" "✗ Failed to stop"; sleep 2 ;;
            9) systemctl restart xray && printc "$G" "✓ Xray restarted" || printc "$R" "✗ Failed to restart"; sleep 2 ;;
            10) journalctl -u xray -n 50 --no-pager; echo ""; read -p "Press Enter to continue..." ;;
            11) journalctl -u nginx -u ws-dropbear -u ws-stunnel -u ws-openssh -u xray -u haproxy -n 30 --no-pager; echo ""; read -p "Press Enter to continue..." ;;
            0) break ;;
            *) printc "$R" "✗ Invalid option"; sleep 1 ;;
        esac
    done
}

#======================== INSTALLATION MENU ==================================
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
            1) install_nginx ;;
            2) install_acme ;;
            3) install_haproxy ;;
            4) install_ws_dropbear ;;
            5) install_ws_stunnel ;;
            6) install_ws ;;
            7) install_ws_openssh ;;
            8) install_proxy_ws ;;
            9) install_xray ;;
            10)
                printc "$BY" "Installing all components..."
                install_nginx
                install_acme
                install_haproxy
                install_ws_dropbear
                install_ws_stunnel
                install_ws
                install_ws_openssh
                install_proxy_ws
                install_xray
                printc "$BG" "✓ All components installed!"
                sleep 2
                ;;
            11) setup_ssl ;;
            12)
                read -p "  Are you sure you want to uninstall all? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    for s in xray haproxy ws ws-openssh ws-stunnel ws-dropbear nginx; do
                        systemctl stop $s 2>/dev/null
                        systemctl disable $s 2>/dev/null
                    done
                    rm -f "$BIN_DIR/ws-dropbear" "$BIN_DIR/ws-stunnel" "$BIN_DIR/ws" "$BIN_DIR/ws-ssh" "$BIN_DIR/proxy-ws" "$BIN_DIR/xray"
                    rm -rf /etc/xray /etc/tunnel-manager/ssl "$CONF_DIR"
                    printc "$G" "✓ All components uninstalled"
                    sleep 2
                fi
                ;;
            0) break ;;
            *) printc "$R" "✗ Invalid option"; sleep 1 ;;
        esac
    done
}

#======================== TUNNEL CONFIGURATION ===============================
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
        printc "$BM" "║${RE} ${BW}[SSHWS TUNNELING]${RE}                                              ${BM}║${RE}"
        printc "$BM" "║${RE} ${BW}  1.${RE} Configure SSHWS TLS         ${D}(SSL/TLS)${RE}             ${BM}║${RE}"
        printc "$BM" "║${RE} ${BW}  2.${RE} Configure SSHWS SSL         ${D}(Direct SSL)${RE}          ${BM}║${RE}"
        printc "$BM" "║${RE} ${BW}  3.${RE} Configure SSHWS NTLS        ${D}(No TLS)${RE}             ${BM}║${RE}"
        printc "$BM" "╟$(printf '─%.0s' {1..58})╢"
        printc "$BM" "║${RE} ${BW}[XRAY TUNNELING]${RE}                                               ${BM}║${RE}"
        printc "$BM" "║${RE} ${BW}  4.${RE} Configure Xray VLESS        ${D}(WS)${RE}                 ${BM}║${RE}"
        printc "$BM" "║${RE} ${BW}  5.${RE} Configure Xray VMess        ${D}(WS)${RE}                 ${BM}║${RE}"
        printc "$BM" "║${RE} ${BW}  6.${RE} Configure Xray Trojan       ${D}(WS)${RE}                 ${BM}║${RE}"
        printc "$BM" "║${RE} ${BW}  7.${RE} Configure Xray gRPC                                   ${BM}║${RE}"
        printc "$BM" "╟$(printf '─%.0s' {1..58})╢"
        printc "$BM" "║${RE} ${BW}[MULTI-PORT]${RE}                                                   ${BM}║${RE}"
        printc "$BM" "║${RE} ${BW}  8.${RE} Configure Multi-Port Tunnel                           ${BM}║${RE}"
        printc "$BM" "║${RE} ${BW}  9.${RE} Generate All Tunnel Links                              ${BM}║${RE}"
        printc "$BM" "╟$(printf '─%.0s' {1..58})╢"
        printc "$BM" "║${RE} ${BW}  0.${RE} Back to Main Menu                                      ${BM}║${RE}"
        printc "$BM" "╚$(printf '─%.0s' {1..58})╝"
        echo ""
        read -p "  Select option [0-9]: " opt
        
        case $opt in
            1) configure_sshws_tls ;;
            2) configure_sshws_ssl ;;
            3) configure_sshws_ntls ;;
            4) configure_xray_vless ;;
            5) configure_xray_vmess ;;
            6) configure_xray_trojan ;;
            7) configure_xray_grpc ;;
            8) configure_multiport ;;
            9) generate_links ;;
            0) break ;;
            *) printc "$R" "✗ Invalid option"; sleep 1 ;;
        esac
    done
}

configure_sshws_tls() {
    show_header
    draw_box "╔" "╗" "" "" "$BG" 60 "SSHWS TLS CONFIGURATION"
    printc "$BG" "╠$(printf '─%.0s' {1..58})╣"
    printc "$W" "║  WebSocket over TLS via Nginx reverse proxy               ║"
    printc "$BG" "╚$(printf '─%.0s' {1..58})╝"
    echo ""
    
    local domain=$(cat "$CONF_DIR/domain" 2>/dev/null || echo "")
    read -p "  Domain [${domain:-your-domain.com}]: " input_domain
    domain="${input_domain:-$domain}"
    read -p "  WS Path [/ws-dropbear]: " ws_path
    ws_path="${ws_path:-/ws-dropbear}"
    read -p "  Backend Port [443]: " backend_port
    backend_port="${backend_port:-443}"
    
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
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }
    
    location / {
        root /var/www/html;
        index index.html;
    }
}
EOF
    
    nginx -t 2>/dev/null && {
        systemctl reload nginx
        log "SSHWS TLS configured for $domain"
        printc "$G" "✓ SSHWS TLS configured successfully!"
        printc "$BW" "  wss://${domain}${ws_path}"
    } || printc "$R" "✗ Nginx config test failed!"
    sleep 2
}

configure_sshws_ssl() {
    show_header
    draw_box "╔" "╗" "" "" "$BG" 60 "SSHWS SSL CONFIGURATION"
    printc "$BG" "╠$(printf '─%.0s' {1..58})╣"
    printc "$W" "║  Direct SSL termination (no Nginx)                       ║"
    printc "$BG" "╚$(printf '─%.0s' {1..58})╝"
    echo ""
    
    read -p "  Listen Port [443]: " port
    port="${port:-443}"
    read -p "  WS Path [/ws-ssl]: " ws_path
    ws_path="${ws_path:-/ws-ssl}"
    read -p "  Target Port [22]: " target_port
    target_port="${target_port:-22}"
    
    cat > /etc/stunnel/sshws-ssl.conf << EOF
[sshws-ssl]
accept = $port
connect = 127.0.0.1:$target_port
cert = /etc/tunnel-manager/ssl/fullchain.pem
key = /etc/tunnel-manager/ssl/privkey.pem
EOF
    
    log "SSHWS SSL configured on port $port"
    printc "$G" "✓ SSHWS SSL configured!"
    printc "$BW" "  Direct SSL: ${PUBLIC_IP}:${port}"
    sleep 2
}

configure_sshws_ntls() {
    show_header
    draw_box "╔" "╗" "" "" "$BG" 60 "SSHWS NTLS CONFIGURATION"
    printc "$BG" "╠$(printf '─%.0s' {1..58})╣"
    printc "$W" "║  WebSocket without TLS (Plain HTTP)                       ║"
    printc "$BG" "╚$(printf '─%.0s' {1..58})╝"
    echo ""
    
    read -p "  Listen Port [80]: " port
    port="${port:-80}"
    read -p "  WS Path [/ws-ntls]: " ws_path
    ws_path="${ws_path:-/ws-ntls}"
    read -p "  Target Port [22]: " target_port
    target_port="${target_port:-22}"
    
    cat > /etc/nginx/conf.d/sshws-ntls.conf << EOF
server {
    listen $port;
    server_name _;
    
    location $ws_path {
        proxy_pass http://127.0.0.1:$target_port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400;
    }
    
    location / {
        root /var/www/html;
        index index.html;
    }
}
EOF
    
    nginx -t 2>/dev/null && {
        systemctl reload nginx
        log "SSHWS NTLS configured on port $port"
        printc "$G" "✓ SSHWS NTLS configured!"
        printc "$BW" "  ws://${PUBLIC_IP}:${port}${ws_path}"
    } || printc "$R" "✗ Nginx config test failed!"
    sleep 2
}

configure_xray_vless() {
    show_header
    draw_box "╔" "╗" "" "" "$BG" 60 "XRAY VLESS CONFIGURATION"
    printc "$BG" "╠$(printf '─%.0s' {1..58})╣"
    printc "$W" "║  VLESS + WebSocket + XTLS-Vision                         ║"
    printc "$BG" "╚$(printf '─%.0s' {1..58})╝"
    echo ""
    
    local uuid=$(cat "$CONF_DIR/xray-uuid" 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    read -p "  UUID [$uuid]: " input_uuid
    uuid="${input_uuid:-$uuid}"
    read -p "  WS Path [/xray]: " ws_path
    ws_path="${ws_path:-/xray}"
    read -p "  Listen Port [8443]: " port
    port="${port:-8443}"
    
    cat > /etc/xray/config.json << EOF
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": $port,
        "listen": "127.0.0.1",
        "protocol": "vless",
        "settings": {
            "clients": [{ "id": "$uuid", "flow": "xtls-rprx-vision" }],
            "decryption": "none",
            "fallbacks": [{ "dest": 8080 }]
        },
        "streamSettings": {
            "network": "ws",
            "wsSettings": { "path": "$ws_path" }
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF
    
    echo "$uuid" > "$CONF_DIR/xray-uuid"
    systemctl restart xray 2>/dev/null
    log "Xray VLESS configured"
    printc "$G" "✓ VLESS configured!"
    printc "$BW" "  UUID: $uuid"
    printc "$BW" "  Path: $ws_path"
    printc "$BW" "  Port: $port"
    sleep 2
}

configure_xray_vmess() {
    show_header
    draw_box "╔" "╗" "" "" "$BG" 60 "XRAY VMESS CONFIGURATION"
    printc "$BG" "╠$(printf '─%.0s' {1..58})╣"
    printc "$W" "║  VMess + WebSocket                                         ║"
    printc "$BG" "╚$(printf '─%.0s' {1..58})╝"
    echo ""
    
    local uuid=$(cat "$CONF_DIR/xray-uuid" 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    read -p "  UUID [$uuid]: " input_uuid
    uuid="${input_uuid:-$uuid}"
    read -p "  WS Path [/vmess]: " ws_path
    ws_path="${ws_path:-/vmess}"
    read -p "  Listen Port [8444]: " port
    port="${port:-8444}"
    
    cat > /etc/xray/config.json << EOF
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": $port,
        "listen": "127.0.0.1",
        "protocol": "vmess",
        "settings": {
            "clients": [{ "id": "$uuid", "alterId": 0 }]
        },
        "streamSettings": {
            "network": "ws",
            "wsSettings": { "path": "$ws_path" }
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF
    
    echo "$uuid" > "$CONF_DIR/xray-uuid"
    systemctl restart xray 2>/dev/null
    log "Xray VMess configured"
    printc "$G" "✓ VMess configured!"
    sleep 2
}

configure_xray_trojan() {
    show_header
    draw_box "╔" "╗" "" "" "$BG" 60 "XRAY TROJAN CONFIGURATION"
    printc "$BG" "╠$(printf '─%.0s' {1..58})╣"
    printc "$W" "║  Trojan + WebSocket                                        ║"
    printc "$BG" "╚$(printf '─%.0s' {1..58})╝"
    echo ""
    
    local password=$(cat /proc/sys/kernel/random/uuid)
    read -p "  Password [$password]: " input_pass
    password="${input_pass:-$password}"
    read -p "  WS Path [/trojan]: " ws_path
    ws_path="${ws_path:-/trojan}"
    read -p "  Listen Port [8445]: " port
    port="${port:-8445}"
    
    cat > /etc/xray/config.json << EOF
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": $port,
        "listen": "127.0.0.1",
        "protocol": "trojan",
        "settings": {
            "clients": [{ "password": "$password" }]
        },
        "streamSettings": {
            "network": "ws",
            "wsSettings": { "path": "$ws_path" }
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF
    
    systemctl restart xray 2>/dev/null
    log "Xray Trojan configured"
    printc "$G" "✓ Trojan configured!"
    sleep 2
}

configure_xray_grpc() {
    show_header
    draw_box "╔" "╗" "" "" "$BG" 60 "XRAY GRPC CONFIGURATION"
    printc "$BG" "╠$(printf '─%.0s' {1..58})╣"
    printc "$W" "║  VLESS/VMess + gRPC                                       ║"
    printc "$BG" "╚$(printf '─%.0s' {1..58})╝"
    echo ""
    
    local uuid=$(cat "$CONF_DIR/xray-uuid" 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    read -p "  UUID [$uuid]: " input_uuid
    uuid="${input_uuid:-$uuid}"
    read -p "  Service Name [grpc]: " service_name
    service_name="${service_name:-grpc}"
    read -p "  Protocol [vless]: " protocol
    protocol="${protocol:-vless}"
    read -p "  Listen Port [8446]: " port
    port="${port:-8446}"
    
    cat > /etc/xray/config.json << EOF
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": $port,
        "listen": "127.0.0.1",
        "protocol": "$protocol",
        "settings": {
            "clients": [{ "id": "$uuid", "flow": "xtls-rprx-vision" }],
            "decryption": "none"
        },
        "streamSettings": {
            "network": "grpc",
            "grpcSettings": {
                "serviceName": "$service_name"
            }
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF
    
    echo "$uuid" > "$CONF_DIR/xray-uuid"
    systemctl restart xray 2>/dev/null
    log "Xray gRPC configured"
    printc "$G" "✓ gRPC configured!"
    sleep 2
}

configure_multiport() {
    show_header
    draw_box "╔" "╗" "" "" "$BG" 60 "MULTI-PORT TUNNEL CONFIGURATION"
    printc "$BG" "╠$(printf '─%.0s' {1..58})╣"
    printc "$W" "║  Configure multiple tunnel ports                            ║"
    printc "$BG" "╚$(printf '─%.0s' {1..58})╝"
    echo ""
    
    printc "$W" "  Current port mappings:"
    printc "$D" "  ─────────────────────────────────────────────────────────────"
    printf "  ${BW}%-10s %-15s %-15s %-15s${RE}\n" "Type" "External" "Internal" "Path"
    printc "$D" "  ─────────────────────────────────────────────────────────────"
    
    [ -f /etc/systemd/system/ws-dropbear.service ] && \
        printf "  ${G}%-10s${RE} %-15s %-15s %-15s\n" "Dropbear" "443" "22" "/ws-dropbear"
    [ -f /etc/systemd/system/ws-stunnel.service ] && \
        printf "  ${G}%-10s${RE} %-15s %-15s %-15s\n" "Stunnel" "444" "22" "/ws-stunnel"
    [ -f /etc/systemd/system/ws-openssh.service ] && \
        printf "  ${G}%-10s${RE} %-15s %-15s %-15s\n" "OpenSSH" "445" "22" "/ws-ssh"
    [ -f /etc/xray/config.json ] && {
        printf "  ${G}%-10s${RE} %-15s %-15s %-15s\n" "Xray" "8443" "—" "/xray"
        printf "  ${G}%-10s${RE} %-15s %-15s %-15s\n" "VMess" "8444" "—" "/vmess"
        printf "  ${G}%-10s${RE} %-15s %-15s %-15s\n" "Trojan" "8445" "—" "/trojan"
    }
    
    echo ""
    printc "$Y" "  To modify ports, edit the service files:"
    printc "$D" "  • /etc/systemd/system/ws-dropbear.service"
    printc "$D" "  • /etc/systemd/system/ws-stunnel.service"
    printc "$D" "  • /etc/systemd/system/ws-openssh.service"
    printc "$D" "  • /etc/xray/config.json"
    echo ""
    printc "$Y" "  Then run: systemctl daemon-reload && systemctl restart <service>"
    echo ""
    read -p "  Press Enter to continue..."
}

generate_links() {
    show_header
    local domain=$(cat "$CONF_DIR/domain" 2>/dev/null || echo "")
    local ip="${PUBLIC_IP:-$(curl -s ifconfig.me 2>/dev/null)}"
    local uuid=$(cat "$CONF_DIR/xray-uuid" 2>/dev/null || echo "YOUR-UUID")
    
    draw_box "╔" "╗" "" "" "$BC" 60 "GENERATED TUNNEL LINKS"
    printc "$BC" "╠$(printf '─%.0s' {1..58})╣"
    
    if [ -n "$domain" ]; then
        printc "$BC" "║${RE} ${BW}[TLS Links - Domain]${RE}                                          ${BC}║${RE}"
        printc "$BC" "╟$(printf '─%.0s' {1..58})╢"
        printc "$G" "║ SSHWS TLS:"; printc "$BW" " wss://${domain}/ws-dropbear$(printf ' %.0s' {1..21})║${RE}"
        printc "$G" "║ SSH Stunnel:"; printc "$BW" " wss://${domain}/ws-stunnel$(printf ' %.0s' {1..22})║${RE}"
        printc "$G" "║ SSH OpenSSH:"; printc "$BW" " wss://${domain}/ws-ssh$(printf ' %.0s' {1..25})║${RE}"
        printc "$G" "║ VLESS WS:"; printc "$BW" "   vless://${uuid}@${domain}:443?path=/xray$(printf ' %.0s' {1..8})║${RE}"
        printc "$G" "║ VMess WS:"; printc "$BW" "   vmess://${uuid}@${domain}:443?path=/vmess$(printf ' %.0s' {1..7})║${RE}"
        printc "$BC" "╟$(printf '─%.0s' {1..58})╢"
    fi
    
    printc "$BC" "║${RE} ${BW}[NTLS Links - IP]${RE}                                             ${BC}║${RE}"
    printc "$BC" "╟$(printf '─%.0s' {1..58})╢"
    printc "$Y" "║ SSHWS NTLS:"; printc "$BW" " ws://${ip}:80/ws-ntls$(printf ' %.0s' {1..23})║${RE}"
    printc "$Y" "║ SSH Direct:"; printc "$BW" " ssh://${ip}:22$(printf ' %.0s' {1..31})║${RE}"
    printc "$BC" "╟$(printf '─%.0s' {1..58})╢"
    printc "$BC" "║${RE} ${BW}[Xray UUID]${RE}                                                    ${BC}║${RE}"
    printc "$BC" "╟$(printf '─%.0s' {1..58})╢"
    printf "${BC}║${RE} ${BG}%-58s${RE} ${BC}║${RE}\n" "$uuid"
    
    draw_box "╚" "╝" "" "" "$BC" 60 ""
    echo ""
    read -p "  Press Enter to continue..."
}

#======================== UPDATE MENU =======================================
update_menu() {
    while true; do
        show_header
        draw_box "╔" "╗" "" "" "$BY" 60 "UPDATE MENU"
        printc "$BY" "╠$(printf '─%.0s' {1..58})╣"
        printc "$BY" "║${RE} ${BW}[SYSTEM UPDATES]${RE}                                               ${BY}║${RE}"
        printc "$BY" "║${RE} ${BW}  1.${RE} Update System Packages                                 ${BY}║${RE}"
        printc "$BY" "║${RE} ${BW}  2.${RE} Update Kernel                                           ${BY}║${RE}"
        printc "$BY" "╟$(printf '─%.0s' {1..58})╢"
        printc "$BY" "║${RE} ${BW}[COMPONENT UPDATES]${RE}                                            ${BY}║${RE}"
        printc "$BY" "║${RE} ${BW}  3.${RE} Update Nginx             ${D}(Recompile)${RE}           ${BY}║${RE}"
        printc "$BY" "║${RE} ${BW}  4.${RE} Update Xray Core          ${D}(Latest release)${RE}     ${BY}║${RE}"
        printc "$BY" "║${RE} ${BW}  5.${RE} Update acme.sh            ${D}(Git pull)${RE}           ${BY}║${RE}"
        printc "$BY" "║${RE} ${BW}  6.${RE} Update WS Dropbear        ${D}(Git pull)${RE}           ${BY}║${RE}"
        printc "$BY" "║${RE} ${BW}  7.${RE} Update WS Stunnel         ${D}(Git pull)${RE}           ${BY}║${RE}"
        printc "$BY" "║${RE} ${BW}  8.${RE} Update WS OpenSSH         ${D}(Git pull)${RE}           ${BY}║${RE}"
        printc "$BY" "║${RE} ${BW}  9.${RE} Update proxy-ws           ${D}(Git pull)${RE}           ${BY}║${RE}"
        printc "$BY" "╟$(printf '─%.0s' {1..58})╢"
        printc "$BY" "║${RE} ${BW}[BULK UPDATES]${RE}                                               ${BY}║${RE}"
        printc "$BY" "║${RE} ${BY} 10.${RE} ${BY}Update All Components${RE}                                ${BY}║${RE}"
        printc "$BY" "║${RE} ${BY} 11.${RE} ${BY}Update Script (Self)${RE}                                 ${BY}║${RE}"
        printc "$BY" "╟$(printf '─%.0s' {1..58})╢"
        printc "$BY" "║${RE} ${BW}[RENEWAL]${RE}                                                       ${BY}║${RE}"
        printc "$BY" "║${RE} ${BW} 12.${RE} Renew SSL Certificates                                ${BY}║${RE}"
        printc "$BY" "╟$(printf '─%.0s' {1..58})╢"
        printc "$BY" "║${RE} ${BW}  0.${RE} Back to Main Menu                                      ${BY}║${RE}"
        printc "$BY" "╚$(printf '─%.0s' {1..58})╝"
        echo ""
        read -p "  Select option [0-12]: " opt
        
        case $opt in
            1) update_system ;;
            2)
                show_header
                printc "$W" "Updating kernel..."
                if [ "$PKG_MGR" = "apt" ]; then
                    apt-get install -y linux-image-amd64 2>&1 | tail -5
                else
                    yum update -y kernel 2>&1 | tail -5
                fi
                printc "$G" "✓ Kernel updated. Reboot required."
                sleep 2
                ;;
            3) install_nginx ;;
            4) install_xray ;;
            5)
                if [ -f "$HOME/.acme.sh/acme.sh" ]; then
                    "$HOME/.acme.sh/acme.sh" --upgrade --auto-upgrade
                    printc "$G" "✓ acme.sh updated"
                else
                    install_acme
                fi
                sleep 2
                ;;
            6)
                cd "$TMP_DIR/ws-dropbear" 2>/dev/null && git pull 2>/dev/null
                printc "$G" "✓ WS Dropbear updated"
                sleep 2
                ;;
            7)
                cd "$TMP_DIR/ws-stunnel" 2>/dev/null && git pull 2>/dev/null
                printc "$G" "✓ WS Stunnel updated"
                sleep 2
                ;;
            8)
                cd "$TMP_DIR/ws-ssh" 2>/dev/null && git pull 2>/dev/null
                printc "$G" "✓ WS OpenSSH updated"
                sleep 2
                ;;
            9)
                cd "$TMP_DIR/proxy-ws" 2>/dev/null && git pull 2>/dev/null
                printc "$G" "✓ proxy-ws updated"
                sleep 2
                ;;
            10)
                printc "$BY" "Updating all components..."
                update_system
                install_nginx
                install_xray
                if [ -f "$HOME/.acme.sh/acme.sh" ]; then
                    "$HOME/.acme.sh/acme.sh" --upgrade --auto-upgrade 2>/dev/null
                fi
                for repo in ws-dropbear ws-stunnel ws-ssh proxy-ws; do
                    cd "$TMP_DIR/$repo" 2>/dev/null && git pull 2>/dev/null
                done
                printc "$G" "✓ All components updated!"
                sleep 2
                ;;
            11)
                printc "$W" "Checking for script updates..."
                SCRIPT_URL="https://raw.githubusercontent.com/youruser/tunnel-manager/main/tunnel-manager.sh"
                NEW_VER=$(curl -sL "$SCRIPT_URL" | grep "Version:" | head -1 | grep -oP '[\d.]+' | head -1)
                printc "$W" "Latest version: $NEW_VER"
                printc "$Y" "Please download manually or set up your update URL"
                sleep 2
                ;;
            12)
                printc "$W" "Renewing SSL certificates..."
                "$HOME/.acme.sh/acme.sh" --cron --home "$HOME/.acme.sh" 2>/dev/null
                printc "$G" "✓ SSL renewal attempted"
                sleep 2
                ;;
            0) break ;;
            *) printc "$R" "✗ Invalid option"; sleep 1 ;;
        esac
    done
}

#======================== UTILITY MENU =======================================
utility_menu() {
    while true; do
        show_header
        draw_box "╔" "╗" "" "" "$BM" 60 "UTILITIES"
        printc "$BM" "╠$(printf '─%.0s' {1..58})╣"
        printc "$BM" "║${RE} ${BW}[NETWORK]${RE}                                                       ${BM}║${RE}"
        printc "$BM" "║${RE} ${BW}  1.${RE} Port Scanner                                                   ${BM}║${RE}"
        printc "$BM" "║${RE} ${BW}  2.${RE} Check Open Ports                                              ${BM}║${RE}"
        printc "$BM" "║${RE} ${BW}  3.${RE} DNS Lookup                                                     ${BM}║${RE}"
        printc "$BM" "║${RE} ${BW}  4.${RE} Speed Test                                                     ${BM}║${RE}"
        printc "$BM" "╟$(printf '─%.0s' {1..58})╢"
        printc "$BM" "║${RE} ${BW}[MANAGEMENT]${RE}                                                    ${BM}║${RE}"
        printc "$BM" "║${RE} ${BW}  5.${RE} Change SSH Port                                               ${BM}║${RE}"
        printc "$BM" "║${RE} ${BW}  6.${RE} Manage Users                                                  ${BM}║${RE}"
        printc "$BM" "║${RE} ${BW}  7.${RE} Firewall Setup                                                ${BM}║${RE}"
        printc "$BM" "║${RE} ${BW}  8.${RE} View Logs                                                     ${BM}║${RE}"
        printc "$BM" "╟$(printf '─%.0s' {1..58})╢"
        printc "$BM" "║${RE} ${BW}[MONITORING]${RE}                                                    ${BM}║${RE}"
        printc "$BM" "║${RE} ${BW}  9.${RE} Real-time Connections                                         ${BM}║${RE}"
        printc "$BM" "║${RE} ${BW} 10.${RE} Bandwidth Monitor                                             ${BM}║${RE}"
        printc "$BM" "║${RE} ${BW} 11.${RE} Process Monitor                                               ${BM}║${RE}"
        printc "$BM" "╟$(printf '─%.0s' {1..58})╢"
        printc "$BM" "║${RE} ${BW}  0.${RE} Back to Main Menu                                             ${BM}║${RE}"
        printc "$BM" "╚$(printf '─%.0s' {1..58})╝"
        echo ""
        read -p "  Select option [0-11]: " opt
        
        case $opt in
            1)
                read -p "  Enter host to scan: " host
                read -p "  Enter port range (e.g., 1-1000): " ports
                printc "$W" "Scanning $host ports $ports..."
                if command -v nmap &>/dev/null; then
                    nmap -p "$ports" "$host" 2>/dev/null
                else
                    for p in $(seq ${ports%-*} ${ports#*-}); do
                        (echo >/dev/tcp/"$host"/$p) 2>/dev/null && printc "$G" "  Port $p: OPEN"
                    done
                fi
                read -p "Press Enter to continue..."
                ;;
            2)
                printc "$W" "Open ports:"
                ss -tlnp | grep LISTEN
                read -p "Press Enter to continue..."
                ;;
            3)
                read -p "  Enter domain: " domain
                dig "$domain" +short 2>/dev/null || nslookup "$domain" 2>/dev/null
                read -p "Press Enter to continue..."
                ;;
            4)
                printc "$W" "Running speed test..."
                if command -v speedtest-cli &>/dev/null; then
                    speedtest-cli --simple
                else
                    pip3 install speedtest-cli -q 2>/dev/null
                    speedtest-cli --simple
                fi
                read -p "Press Enter to continue..."
                ;;
            5)
                read -p "  New SSH port [22]: " new_port
                new_port="${new_port:-22}"
                sed -i "s/^#*Port .*/Port $new_port/" /etc/ssh/sshd_config
                systemctl restart sshd
                printc "$G" "✓ SSH port changed to $new_port"
                sleep 2
                ;;
            6)
                read -p "  Enter username to create: " username
                if [ -n "$username" ]; then
                    useradd -m -s /bin/bash "$username" 2>/dev/null
                    passwd "$username"
                    printc "$G" "✓ User $username created"
                fi
                sleep 2
                ;;
            7)
                printc "$W" "Setting up firewall..."
                if command -v ufw &>/dev/null; then
                    ufw allow 22/tcp
                    ufw allow 80/tcp
                    ufw allow 443/tcp
                    ufw allow 443/udp
                    for p in 444 445 8080 8443 8444 8445; do
                        ufw allow $p/tcp 2>/dev/null
                    done
                    ufw --force enable
                    printc "$G" "✓ UFW firewall configured"
                elif command -v firewall-cmd &>/dev/null; then
                    firewall-cmd --permanent --add-service=ssh
                    firewall-cmd --permanent --add-service=http
                    firewall-cmd --permanent --add-service=https
                    for p in 444 445 8080 8443 8444 8445; do
                        firewall-cmd --permanent --add-port=$p/tcp 2>/dev/null
                    done
                    firewall-cmd --reload
                    printc "$G" "✓ Firewalld configured"
                else
                    printc "$Y" "⚠ No firewall tool found"
                fi
                sleep 2
                ;;
            8)
                printc "$W" "Recent logs:"
                tail -50 "$LOG_FILE"
                read -p "Press Enter to continue..."
                ;;
            9)
                printc "$W" "Active connections:"
                watch -n 1 "ss -tnp | grep -E 'ESTAB|ws-|xray|dropbear'" 2>/dev/null || \
                ss -tnp | grep -E 'ESTAB|ws-|xray|dropbear'
                read -p "Press Enter to continue..."
                ;;
            10)
                if command -v iftop &>/dev/null; then
                    iftop -n
                elif command -v nload &>/dev/null; then
                    nload
                else
                    printc "$Y" "Installing nload..."
                    $INSTALL nload 2>/dev/null
                    nload
                fi
                ;;
            11)
                if command -v htop &>/dev/null; then
                    htop
                else
                    top -bn1 | head -20
                    read -p "Press Enter to continue..."
                fi
                ;;
            0) break ;;
            *) printc "$R" "✗ Invalid option"; sleep 1 ;;
        esac
    done
}

#======================== ABOUT MENU =========================================
show_about() {
    show_header
    draw_box "╔" "╗" "" "" "$BC" 60 "ABOUT"
    printc "$BC" "╠$(printf '─%.0s' {1..58})╣"
    printc "$BC" "║${RE}" ; printc "$BW" "  SSHWS & XRAY TUNNEL MANAGER" ; printc "$BC" "                            ║${RE}"
    printc "$BC" "╟$(printf '─%.0s' {1..58})╢"
    printf "${BC}║${RE} ${BW}Version:${RE}     %-49s${BC}║${RE}\n" "3.0.0"
    printf "${BC}║${RE} ${BW}Author:${RE}      %-49s${BC}║${RE}\n" "TunnelManager"
    printf "${BC}║${RE} ${BW}License:${RE}     %-49s${BC}║${RE}\n" "MIT"
    printc "$BC" "╟$(printf '─%.0s' {1..58})╢"
    printc "$BC" "║${RE} ${BW}Features:${RE}                                                       ${BC}║${RE}"
    printc "$BC" "║${RE}  • Multi-protocol tunneling (SSHWS, Xray)                       ${BC}║${RE}"
    printc "$BC" "║${RE}  • TLS/SSL/NTLS support                                         ${BC}║${RE}"
    printc "$BC" "║${RE}  • VLESS, VMess, Trojan protocols                              ${BC}║${RE}"
    printc "$BC" "║${RE}  • WebSocket & gRPC transport                                  ${BC}║${RE}"
    printc "$BC" "║${RE}  • HAProxy load balancing                                      ${BC}║${RE}"
    printc "$BC" "║${RE}  • Auto SSL with Let's Encrypt                                 ${BC}║${RE}"
    printc "$BC" "╟$(printf '─%.0s' {1..58})╢"
    printc "$BC" "║${RE} ${BW}GitHub Sources:${RE}                                                  ${BC}║${RE}"
    printc "$BC" "║${RE}  • acmesh-official/acme.sh                                     ${BC}║${RE}"
    printc "$BC" "║${RE}  • XTLS/Xray-core                                             ${BC}║${RE}"
    printc "$BC" "║${RE}  • badudinda/ws-dropbear                                       ${BC}║${RE}"
    printc "$BC" "║${RE}  • badudinda/ws-stunnel                                        ${BC}║${RE}"
    printc "$BC" "║${RE}  • badudinda/ws-ssh                                            ${BC}║${RE}"
    printc "$BC" "║${RE}  • badudinda/proxy-ws                                          ${BC}║${RE}"
    draw_box "╚" "╝" "" "" "$BC" 60 ""
    echo ""
    read -p "  Press Enter to continue..."
}

#======================== MAIN MENU ==========================================
main_menu() {
    while true; do
        show_header
        show_vps_info
        show_services_status
        
        draw_box "╔" "╗" "" "" "$BW" 60 "MAIN MENU"
        printc "$BW" "╠$(printf '─%.0s' {1..58})╣"
        printc "$BW" "║${RE} ${BG}  1.${RE} ${BG}Installation Menu${RE}        ${D}[Install Components]${RE}         ${BW}║${RE}"
        printc "$BW" "║${RE} ${BG}  2.${RE} ${BG}Tunnel Configuration${RE}     ${D}[SSHWS/Xray Config]${RE}         ${BW}║${RE}"
        printc "$BW" "║${RE} ${BG}  3.${RE} ${BG}Service Control${RE}         ${D}[Start/Stop/Restart]${RE}         ${BW}║${RE}"
        printc "$BW" "║${RE} ${BG}  4.${RE} ${BG}Update Menu${RE}             ${D}[System & Components]${RE}       ${BW}║${RE}"
        printc "$BW" "║${RE} ${BG}  5.${RE} ${BG}Utilities${RE}                ${D}[Network & Monitoring]${RE}      ${BW}║${RE}"
        printc "$BW" "╟$(printf '─%.0s' {1..58})╢"
        printc "$BW" "║${RE} ${BW}  6.${RE} Generate Tunnel Links                                     ${BW}║${RE}"
        printc "$BW" "║${RE} ${BW}  7.${RE} View Xray UUID                                             ${BW}║${RE}"
        printc "$BW" "║${RE} ${BW}  8.${RE} About                                                       ${BW}║${RE}"
        printc "$BW" "╟$(printf '─%.0s' {1..58})╢"
        printc "$BW" "║${RE} ${BR}  0.${RE} ${BR}Exit${RE}                                                      ${BW}║${RE}"
        printc "$BW" "╚$(printf '─%.0s' {1..58})╝"
        echo ""
        read -p "  Select option [0-8]: " opt
        
        case $opt in
            1) install_menu ;;
            2) tunnel_menu ;;
            3) service_menu ;;
            4) update_menu ;;
            5) utility_menu ;;
            6) generate_links ;;
            7)
                show_header
                local uuid=$(cat "$CONF_DIR/xray-uuid" 2>/dev/null || echo "Not configured")
                printc "$BW" "  Xray UUID: "
                printc "$BG" "$uuid"
                echo ""
                read -p "  Press Enter to continue..."
                ;;
            8) show_about ;;
            0)
                clear
                printc "$BW" "\n  Thank you for using SSHWS & Xray Tunnel Manager!"
                printc "$D" "  Logs: $LOG_FILE\n"
                exit 0
                ;;
            *) printc "$R" "✗ Invalid option"; sleep 1 ;;
        esac
    done
}

#======================== ENTRY POINT ========================================
check_root
check_os
main_menu