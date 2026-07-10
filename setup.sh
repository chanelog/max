#!/bin/bash
# ════════════════════════════════════════════════════════════
#   MAX PANEL — Premium VPS Tunneling Panel
#   Creator : MAX Team  |  v2.5-fixed
#   Ketik   : menu-max  untuk membuka panel
#   Support : Debian (all) & Ubuntu (all)
# ════════════════════════════════════════════════════════════

check_root() {
    [[ $EUID -ne 0 ]] && { echo -e "\n\033[1;31m  ✘  Jalankan sebagai root!\033[0m\n"; exit 1; }
}

check_os() {
    [[ ! -f /etc/os-release ]] && { echo -e "\n\033[1;31m  ✘  OS tidak dikenali!\033[0m\n"; exit 1; }
    source /etc/os-release 2>/dev/null
    local os_name os_like
    os_name=$(echo "${ID}" | tr '[:upper:]' '[:lower:]')
    os_like=$(echo "${ID_LIKE:-}" | tr '[:upper:]' '[:lower:]')
    if [[ "$os_name" != "debian" && "$os_name" != "ubuntu" ]] \
       && [[ "$os_like" != *"debian"* && "$os_like" != *"ubuntu"* ]]; then
        echo -e "\033[1;31m  ✘  Hanya Debian & Ubuntu yang didukung!\033[0m"; exit 1
    fi
    OS_NAME="${PRETTY_NAME:-$ID $VERSION_ID}"; OS_ID="$os_name"
    export OS_NAME OS_ID
}

# ════════════════════════════════════════════════════════════
#  KONSTANTA & PATH
# ════════════════════════════════════════════════════════════
DIR="/etc/maxpanel"; LOGDIR="/var/log/maxpanel"; BACKUPDIR="/root/maxpanel-backup"
THEMEF="$DIR/theme.conf";   DOMF="$DIR/domain.conf";  BOTF="$DIR/bot.conf"
STRF="$DIR/store.conf";     MLDB="$DIR/maxlogin.db";   LIMITF="$DIR/limit.conf"
VERSIONF="$DIR/version.txt"
SSH_DB="$DIR/ssh-users.db";        VMESS_DB="$DIR/vmess-users.db"
VLESS_DB="$DIR/vless-users.db";    TROJAN_DB="$DIR/trojan-users.db"
TROJANGO_DB="$DIR/trojango-users.db"; OVPN_DB="$DIR/openvpn-users.db"
WG_DB="$DIR/wireguard-users.db";   HY_DB="$DIR/hysteria-users.db"
SS_DB="$DIR/ss-users.db"
XRAY_CFG="/etc/xray/config.json";  XRAY_BIN="/usr/local/bin/xray"
XRAY_CRT="/etc/xray/xray.crt";     XRAY_KEY="/etc/xray/xray.key"
XRAY_LOG="/var/log/xray/access.log"
TROJANGO_DIR="/etc/trojan-go";      TROJANGO_CFG="$TROJANGO_DIR/config.json"
TROJANGO_BIN="/usr/local/bin/trojan-go"
HY_DIR="/etc/hysteria";             HY_CFG="$HY_DIR/config.yaml"
HY_BIN="/usr/local/bin/hysteria"
WG_DIR="/etc/wireguard";            WG_CFG="$WG_DIR/wg0.conf"
WG_CLIENT_DIR="$DIR/wg-clients"
WS_DIR="/etc/maxpanel/ws";          WS_BIN="$WS_DIR/ws-proxy.py"
BIN_REPO="https://raw.githubusercontent.com/chanelog/bin/main"
XRAY_URL="${BIN_REPO}/Xray-linux-64.zip"
XRAY_URL_ARM="${BIN_REPO}/Xray-linux-arm64-v8a.zip"
TROJAN_GO_URL="${BIN_REPO}/trojan-go-linux-amd64.zip"
ACME_URL="${BIN_REPO}/acme.sh"
JQ_URL="${BIN_REPO}/jq-linux-amd64"
HYSTERIA_URL="https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64"
DROPBEAR_URL="${BIN_REPO}/dropbear-master.zip"
STUNNEL_URL="${BIN_REPO}/stunnel-master.zip"
WS_TUNNEL_URL="${BIN_REPO}/ws_tunnel.py"
WS_SSH_SERVER_URL="${BIN_REPO}/ws-ssh-server.py"
SCRIPT_VERSION="2.5"

# ════════════════════════════════════════════════════════════
#  TEMA — 15 PREMIUM
# ════════════════════════════════════════════════════════════
load_theme() {
    local theme=1
    [[ -f "$THEMEF" ]] && theme=$(cat "$THEMEF" 2>/dev/null)
    case "$theme" in
        2)  A1='\033[38;5;51m';  A2='\033[1;36m';     A3='\033[0;36m'; A4='\033[38;5;123m'; AL='\033[38;5;87m';  AT='\033[1;37m'; THEME_NAME="ARCTIC CYAN" ;;
        3)  A1='\033[38;5;46m';  A2='\033[1;32m';     A3='\033[38;5;40m'; A4='\033[38;5;118m'; AL='\033[38;5;82m';  AT='\033[1;37m'; THEME_NAME="MATRIX GREEN" ;;
        4)  A1='\033[38;5;220m'; A2='\033[38;5;226m'; A3='\033[38;5;214m'; A4='\033[38;5;208m'; AL='\033[38;5;228m'; AT='\033[1;37m'; THEME_NAME="ROYAL GOLD" ;;
        5)  A1='\033[38;5;196m'; A2='\033[1;31m';     A3='\033[38;5;203m'; A4='\033[38;5;197m'; AL='\033[38;5;204m'; AT='\033[1;37m'; THEME_NAME="CRIMSON RED" ;;
        6)  A1='\033[38;5;213m'; A2='\033[38;5;218m'; A3='\033[38;5;219m'; A4='\033[38;5;211m'; AL='\033[38;5;225m'; AT='\033[1;37m'; THEME_NAME="SAKURA PINK" ;;
        7)  A1='\033[1;37m';     A2='\033[1;37m';     A3='\033[38;5;51m'; A4='\033[1;33m';     AL='\033[38;5;196m'; AT='\033[1;37m'; THEME_NAME="RAINBOW" ;;
        8)  A1='\033[38;5;27m';  A2='\033[38;5;33m';  A3='\033[38;5;39m'; A4='\033[38;5;45m';  AL='\033[38;5;81m';  AT='\033[1;37m'; THEME_NAME="OCEAN BLUE" ;;
        9)  A1='\033[38;5;202m'; A2='\033[38;5;208m'; A3='\033[38;5;214m'; A4='\033[38;5;220m'; AL='\033[38;5;215m'; AT='\033[1;37m'; THEME_NAME="SUNSET ORANGE" ;;
        10) A1='\033[38;5;239m'; A2='\033[38;5;245m'; A3='\033[38;5;250m'; A4='\033[38;5;153m'; AL='\033[38;5;189m'; AT='\033[1;37m'; THEME_NAME="MIDNIGHT" ;;
        11) A1='\033[38;5;35m';  A2='\033[38;5;41m';  A3='\033[38;5;48m'; A4='\033[38;5;85m';  AL='\033[38;5;121m'; AT='\033[1;37m'; THEME_NAME="EMERALD" ;;
        12) A1='\033[38;5;99m';  A2='\033[38;5;105m'; A3='\033[38;5;111m'; A4='\033[38;5;183m'; AL='\033[38;5;189m'; AT='\033[1;37m'; THEME_NAME="LAVENDER" ;;
        13) A1='\033[38;5;210m'; A2='\033[38;5;216m'; A3='\033[38;5;222m'; A4='\033[38;5;217m'; AL='\033[38;5;224m'; AT='\033[1;37m'; THEME_NAME="ROSE GOLD" ;;
        14) A1='\033[38;5;195m'; A2='\033[38;5;231m'; A3='\033[38;5;159m'; A4='\033[38;5;123m'; AL='\033[38;5;255m'; AT='\033[38;5;231m'; THEME_NAME="ICE WHITE" ;;
        15) A1='\033[38;5;129m'; A2='\033[38;5;135m'; A3='\033[38;5;141m'; A4='\033[38;5;201m'; AL='\033[38;5;171m'; AT='\033[1;37m'; THEME_NAME="NEON PURPLE" ;;
        *)  A1='\033[38;5;135m'; A2='\033[1;35m';     A3='\033[38;5;141m'; A4='\033[1;33m';     AL='\033[38;5;141m'; AT='\033[38;5;231m'; THEME_NAME="VIOLET" ;;
    esac
    NC='\033[0m'; BLD='\033[1m'; DIM='\033[2m'; IT='\033[3m'
    W='\033[1;37m'; LG='\033[1;32m'; LR='\033[1;31m'; LC='\033[1;36m'; Y='\033[1;33m'
    export A1 A2 A3 A4 AL AT NC BLD DIM IT W LG LR LC Y THEME_NAME
}

# ════════════════════════════════════════════════════════════
#  UTILS
# ════════════════════════════════════════════════════════════
_DASH="───────────────────────────────────────────────────────────────"
ok()    { echo -e "  ${A2}✔${NC}  $*"; }
inf()   { echo -e "  ${A3}➜${NC}  $*"; }
warn()  { echo -e "  ${A4}⚠${NC}  $*"; }
err()   { echo -e "  \033[1;31m✘${NC}  $*"; }
pause() { echo ""; echo -ne "  ${DIM}╰─ [ Enter ] kembali ke menu...${NC}"; read -r; }
_btn()  { printf "  %b\n" "$1"; }

_apply_block() {
    local marker="$1" file="$2"
    [[ -z "$marker" || -z "$file" ]] && return 1
    [[ ! -f "$file" ]] && { mkdir -p "$(dirname "$file")"; : > "$file"; }
    sed -i "/^# >>> MAXPANEL-${marker} >>>$/,/^# <<< MAXPANEL-${marker} <<<$/d" "$file" 2>/dev/null
    { echo ""; echo "# >>> MAXPANEL-${marker} >>>"; cat; echo "# <<< MAXPANEL-${marker} <<<"; } >> "$file"
}

get_ip() {
    local ip
    for src in "curl -s4 --max-time 5 ifconfig.me" "curl -s4 --max-time 5 icanhazip.com" "curl -s4 --max-time 5 api.ipify.org"; do
        ip=$(eval "$src" 2>/dev/null | tr -d '[:space:]')
        [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && { echo "$ip"; return; }
    done
    hostname -I 2>/dev/null | awk '{print $1}'
}
get_domain() { [[ -f "$DOMF" ]] && cat "$DOMF" 2>/dev/null || get_ip; }
get_iface()  { ip -4 route ls 2>/dev/null | awk '/default/ {print $5; exit}'; }
verify_binary() {
    local sz; sz=$(stat -c%s "$1" 2>/dev/null || echo 0)
    [[ ! -f "$1" || "$sz" -lt "${2:-100000}" ]] && return 1; return 0
}
dl() {
    local url="$1" out="$2"
    wget --tries=3 --timeout=30 -q -O "$out" "$url" 2>/dev/null && [[ -s "$out" ]] && return 0
    rm -f "$out" 2>/dev/null
    curl -fsSL --retry 3 --max-time 30 -o "$out" "$url" 2>/dev/null && [[ -s "$out" ]] && return 0
    rm -f "$out" 2>/dev/null; return 1
}
is_up()     { systemctl is-active --quiet "$1" 2>/dev/null; }
svc_badge() { is_up "$1" && printf '%b' "${LG}●${NC}" || printf '%b' "${LR}●${NC}"; }

total_users_all() {
    local t=0 f cnt
    for f in "$SSH_DB" "$VMESS_DB" "$VLESS_DB" "$TROJAN_DB" "$TROJANGO_DB" "$OVPN_DB" "$WG_DB" "$HY_DB" "$SS_DB"; do
        [[ -f "$f" ]] && { cnt=$(grep -c '' "$f" 2>/dev/null); [[ "$cnt" =~ ^[0-9]+$ ]] && t=$((t+cnt)); }
    done; echo "$t"
}
exp_users_all() {
    local t=0 f td; td=$(TZ="Asia/Jakarta" date +%Y-%m-%d)
    for f in "$SSH_DB" "$VMESS_DB" "$VLESS_DB" "$TROJAN_DB" "$TROJANGO_DB" "$OVPN_DB" "$WG_DB" "$HY_DB" "$SS_DB"; do
        [[ -f "$f" ]] && t=$((t + $(awk -F'|' -v d="$td" '$3<d{c++}END{print c+0}' "$f" 2>/dev/null)))
    done; echo "$t"
}

get_maxlogin() { grep "^${1}|" "$MLDB" 2>/dev/null | cut -d'|' -f2 | head -1; }
set_maxlogin() { mkdir -p "$DIR"; touch "$MLDB"; sed -i "/^${1}|/d" "$MLDB" 2>/dev/null; echo "${1}|${2}" >> "$MLDB"; }
del_maxlogin() { sed -i "/^${1}|/d" "$MLDB" 2>/dev/null; }

# ════════════════════════════════════════════════════════════
#  BANNER & INFO VPS
# ════════════════════════════════════════════════════════════
draw_logo() {
    local cur_theme L1 L2 L3 L4 L5
    cur_theme=$(cat "$THEMEF" 2>/dev/null || echo 1)
    if [[ "$cur_theme" == "7" ]]; then
        L1='\033[38;5;196m'; L2='\033[38;5;214m'; L3='\033[38;5;226m'; L4='\033[38;5;82m';  L5='\033[38;5;51m'
    else L1="$AL"; L2="$AL"; L3="$A3"; L4="$AL"; L5="$A3"; fi
    echo ""
    echo -e "  ${A1}${_DASH}${NC}"
    echo -e "  ${L1}${BLD}  ███╗   ███╗ █████╗ ██╗  ██╗    ██████╗  █████╗ ███╗   ██╗ ${NC}"
    echo -e "  ${L2}${BLD}  ████╗ ████║██╔══██╗╚██╗██╔╝    ██╔══██╗██╔══██╗████╗  ██║ ${NC}"
    echo -e "  ${L3}${BLD}  ██╔████╔██║███████║ ╚███╔╝     ██████╔╝███████║██╔██╗ ██║ ${NC}"
    echo -e "  ${L4}${BLD}  ██║╚██╔╝██║██╔══██║ ██╔██╗     ██╔═══╝ ██╔══██║██║╚██╗██║ ${NC}"
    echo -e "  ${L5}${BLD}  ██║ ╚═╝ ██║██║  ██║██╔╝ ██╗    ██║     ██║  ██║██║ ╚████║ ${NC}"
    echo -e "  ${DIM}  ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝    ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝ ${NC}"
    echo -e "  ${A1}${_DASH}${NC}"
    echo -e "  ${A4}             ✦  * MAX PREMIUM TUNNELING PANEL *  ✦      ${NC}"
    echo -e "  ${DIM}       +---------------- ${A2}[ ALL-IN-ONE ]${DIM} ---------------+  ${NC}"
    echo -e "  ${A1}${_DASH}${NC}"
}

draw_vps() {
    local ip domain ram_u ram_t cpu du dt du_pct os hn total expc now_time now_date
    ip=$(get_ip); domain=$(get_domain)
    ram_u=$(free -m 2>/dev/null | awk '/^Mem/{print $3}')
    ram_t=$(free -m 2>/dev/null | awk '/^Mem/{print $2}')
    cpu=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{printf "%.1f",$2}' || echo "0.0")
    du=$(df -h / 2>/dev/null | awk 'NR==2{print $3}'); dt=$(df -h / 2>/dev/null | awk 'NR==2{print $2}')
    du_pct=$(df / 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%')
    os=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo "Linux"); hn=$(hostname)
    total=$(total_users_all); expc=$(exp_users_all)
    now_time=$(TZ="Asia/Jakarta" date "+%H:%M"); now_date=$(TZ="Asia/Jakarta" date "+%d/%m/%Y")
    local ram_pct=0
    [[ "$ram_t" -gt 0 ]] 2>/dev/null && ram_pct=$(( ram_u * 100 / ram_t ))
    local brand="MAX PANEL"
    [[ -f "$STRF" ]] && { source "$STRF" 2>/dev/null; brand="${BRAND:-MAX PANEL}"; }
    local tema_display
    if [[ "${THEME_NAME:-}" == "RAINBOW" ]]; then
        tema_display="\033[38;5;196mR\033[38;5;208mA\033[38;5;226mI\033[38;5;82mN\033[38;5;51mB\033[38;5;171mO\033[38;5;213mW\033[0m"
    else tema_display="${AL}${THEME_NAME}${NC}"; fi

    echo ""
    echo -e "  ${A1}${_DASH}${NC}"
    echo -e "  ${A4}◈${NC} ${BLD}${A4}INFO VPS${NC}  ${DIM}${now_time}  │  ${now_date}${NC}"
    echo -e "  ${A1}${_DASH}${NC}"
    local os_short domain_short
    os_short=$(echo "$os" | cut -c1-14); domain_short=$(echo "$domain" | cut -c1-18)
    _btn "  ${DIM}HOST    ${NC}${A1}│${NC} ${A3}$(printf '%-16s' "$hn")${NC}  ${DIM}OS    ${NC}${A1}│${NC} ${W}${os_short}${NC}"
    echo -e "  ${A1}${_DASH}${NC}"
    _btn "  ${DIM}IP ADDR ${NC}${A1}│${NC} ${A3}$(printf '%-16s' "$ip")${NC}  ${DIM}DOMAIN  ${NC}${A1}│${NC} ${W}${domain_short}${NC}"
    echo -e "  ${A1}${_DASH}${NC}"
    _btn "  ${DIM}USER    ${NC}${A1}│${NC} ${Y}$(printf '%-16s' "$total")${NC}  ${DIM}BRAND   ${NC}${A1}│${NC} ${A4}${brand}${NC}"
    echo -e "  ${A1}${_DASH}${NC}"

    _mini_bar() {
        local pct=${1:-0} filled empty color bar="" i
        filled=$(( pct * 10 / 100 )); [[ $filled -gt 10 ]] && filled=10; empty=$(( 10 - filled ))
        if [[ $pct -ge 80 ]]; then color="$LR"; elif [[ $pct -ge 60 ]]; then color="$Y"; else color="$LG"; fi
        for ((i=0;i<filled;i++)); do bar+="█"; done
        for ((i=0;i<empty;i++)); do bar+="░"; done
        printf "${color}%s${NC}" "$bar"
    }

    local cpu_pct=${cpu%.*}; [[ -z "$cpu_pct" || "$cpu_pct" == "?" ]] && cpu_pct=0
    local cpu_col ram_col dsk_col dsk_pct=${du_pct:-0}
    [[ $cpu_pct -ge 80 ]] && cpu_col="$LR" || { [[ $cpu_pct -ge 60 ]] && cpu_col="$Y" || cpu_col="$LG"; }
    [[ $ram_pct -ge 80 ]] && ram_col="$LR" || { [[ $ram_pct -ge 60 ]] && ram_col="$Y" || ram_col="$A3"; }
    [[ $dsk_pct -ge 80 ]] && dsk_col="$LR" || { [[ $dsk_pct -ge 60 ]] && dsk_col="$Y" || dsk_col="$Y"; }
    local cpu_bar ram_bar disk_bar
    cpu_bar=$(_mini_bar "$cpu_pct"); ram_bar=$(_mini_bar "$ram_pct"); disk_bar=$(_mini_bar "$dsk_pct")

    _btn "  ${DIM}CPU${NC} ${cpu_col}${cpu}%${NC}  ${cpu_bar}  ${A1}│${NC}  ${DIM}RAM${NC} ${ram_col}${ram_u}/${ram_t}MB${NC}  ${ram_bar}"
    echo -e "  ${A1}${_DASH}${NC}"
    _btn "  ${DIM}DISK${NC} ${dsk_col}${du}/${dt}${NC}  ${disk_bar}"
    echo -e "  ${A1}${_DASH}${NC}"

    local ssh_b dr_b stun_b ngx_b ws_b hap_b xray_b tgo_b hy_b ovpn_b wg_b
    ssh_b=$(svc_badge ssh); dr_b=$(svc_badge dropbear); stun_b=$(svc_badge stunnel4)
    ngx_b=$(svc_badge nginx); ws_b=$(svc_badge ws-ssh-proxy); hap_b=$(svc_badge haproxy)
    xray_b=$(svc_badge xray); tgo_b=$(svc_badge trojan-go); hy_b=$(svc_badge hysteria-server)
    ovpn_b=$(svc_badge openvpn); wg_b=$(svc_badge "wg-quick@wg0")

    _btn "  ${DIM}SSH${NC}${ssh_b}  ${DIM}DR${NC}${dr_b}  ${DIM}STN${NC}${stun_b}  ${DIM}NGX${NC}${ngx_b}  ${DIM}WS${NC}${ws_b}  ${DIM}HAP${NC}${hap_b}"
    _btn "  ${DIM}XRY${NC}${xray_b}  ${DIM}TGO${NC}${tgo_b}  ${DIM}HY${NC}${hy_b}  ${DIM}OVPN${NC}${ovpn_b}  ${DIM}WG${NC}${wg_b}"

    echo -e "  ${A1}${_DASH}${NC}"
    _btn "  ${DIM}AKUN${NC} ${A3}${total}${NC}  ${A1}│${NC}  ${DIM}EXP${NC} ${LR}${expc}${NC}  ${A1}│${NC}  ${DIM}TEMA${NC}  ${tema_display}"
    echo -e "  ${A1}${_DASH}${NC}"
    echo ""
}
show_header() { clear; load_theme; draw_logo; draw_vps; }

show_box_ssh() {
    local u="$1" p="$2" exp="$3" maxl="${4:-2}" ip dom
    ip=$(get_ip); dom=$(get_domain)
    local brand="MAX PANEL"
    [[ -f "$STRF" ]] && { source "$STRF" 2>/dev/null; brand="${BRAND:-MAX PANEL}"; }
    echo ""
    echo -e "  ${LG}✅ Akun SSH/OpenSSH — ${brand}${NC}"
    echo -e "  ${A1}┌─────────────────────────────────────────────────────────${NC}"
    printf  "  ${A1}│${NC} 👤 ${DIM}Username${NC} : ${BLD}${W}%s${NC}\n" "$u"
    printf  "  ${A1}│${NC} 🔑 ${DIM}Password${NC} : ${BLD}${A3}%s${NC}\n" "$p"
    echo -e "  ${A1}├─────────────────────────────────────────────────────────${NC}"
    printf  "  ${A1}│${NC} 🖥  ${DIM}IP Publik${NC} : ${LG}%s${NC}\n" "$ip"
    printf  "  ${A1}│${NC} 🌐 ${DIM}Host     ${NC} : ${W}%s${NC}\n" "$dom"
    printf  "  ${A1}│${NC} 🔌 ${DIM}Port SSH ${NC}: ${Y}22${NC}  |  ${DIM}Dropbear${NC}: ${Y}109, 143${NC}\n"
    printf  "  ${A1}│${NC} 🔒 ${DIM}Stunnel  ${NC}: ${Y}445 (→DB:109)  777 (→SSH:22)${NC}\n"
    echo -e "  ${A1}├── ${LG}Nginx / HAProxy Reverse-Proxy${NC} ${A1}───────────────${NC}"
    printf  "  ${A1}│${NC} 🌐 ${DIM}HTTP     ${NC}: ${Y}ws://%s:80/ws-ssh${NC}\n" "$dom"
    printf  "  ${A1}│${NC} 🔒 ${DIM}HTTPS    ${NC}: ${Y}wss://%s:443/ws-ssh${NC}\n" "$dom"
    printf  "  ${A1}│${NC} 🔒 ${DIM}Alt-TLS  ${NC}: ${Y}wss://%s:8443/ws-ssh${NC}\n" "$dom"
    echo -e "  ${A1}├─────────────────────────────────────────────────────────${NC}"
    printf  "  ${A1}│${NC} 🔒 ${DIM}MaxLogin${NC} : ${Y}%s device${NC}\n" "$maxl"
    printf  "  ${A1}│${NC} 📅 ${DIM}Expired ${NC} : ${Y}%s${NC}\n" "$exp"
    echo -e "  ${A1}└─────────────────────────────────────────────────────────${NC}"
    echo ""
}

# ════════════════════════════════════════════════════════════
#  1. INSTALLER — Dependencies
# ════════════════════════════════════════════════════════════
install_deps() {
    inf "Update apt & install dependensi inti..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq 2>/dev/null || true
    apt-get install -y -qq \
        wget curl jq unzip zip tar net-tools openvpn easy-rsa \
        vnstat htop iftop bmon screen tmux cron rsyslog uuid-runtime sudo lsb-release \
        fail2ban git build-essential libssl-dev python3 python3-pip dnsutils socat \
        figlet wireguard wireguard-tools resolvconf qrencode bc \
        iptables iptables-persistent netfilter-persistent ca-certificates \
        gnupg2 lsof psmisc openssl python3-websockify nginx haproxy stunnel4 2>/dev/null || true
    ok "Dependensi terpasang"
}

# ════════════════════════════════════════════════════════════
#  2. INSTALLER — Download Binaries
# ════════════════════════════════════════════════════════════
install_all_bins() {
    inf "Download binary dari ${W}chanelog/bin${NC}..."
    local tmp; tmp=$(mktemp -d)
    local ok_count=0 fail_count=0 arch; arch=$(uname -m)

    _dl_bin() {
        local url="$1" dest="$2" min="${3:-100000}" label="${4:-$(basename "$dest")}"
        inf "  ↓ $label"
        if dl "$url" "$dest" && chmod +x "$dest" && verify_binary "$dest" "$min"; then
            ok "    ✓ $label"; ok_count=$((ok_count+1)); return 0
        else
            warn "    ✗ Gagal $label"; rm -f "$dest" 2>/dev/null; fail_count=$((fail_count+1)); return 1
        fi
    }

    _dl_zip() {
        local url="$1" zname="$2" bin_in_zip="$3" dest="$4" min="${5:-500000}" label="${6:-$(basename "$dest")}"
        inf "  ↓ $label (zip)"
        if dl "$url" "$tmp/$zname"; then
            unzip -qo "$tmp/$zname" -d "$tmp/${zname%.zip}" 2>/dev/null
            local found; found=$(find "$tmp/${zname%.zip}" -type f -name "$bin_in_zip" 2>/dev/null | head -1)
            if [[ -n "$found" ]] && verify_binary "$found" "$min"; then
                install -m755 "$found" "$dest"; ok "    ✓ $label"; ok_count=$((ok_count+1)); return 0
            fi
        fi
        warn "    ✗ Gagal $label"; fail_count=$((fail_count+1)); return 1
    }

    [[ ! -x "$XRAY_BIN" ]] && {
        case "$arch" in
            aarch64|arm64) _dl_zip "$XRAY_URL_ARM" "Xray-linux-arm64-v8a.zip" "xray" "$XRAY_BIN" 1000000 "Xray (arm64)" ;;
            *)             _dl_zip "$XRAY_URL"     "Xray-linux-64.zip"        "xray" "$XRAY_BIN" 1000000 "Xray (amd64)" ;;
        esac
    } || ok "  ✓ Xray ada — skip"

    [[ ! -x "$TROJANGO_BIN" ]] && { mkdir -p "$TROJANGO_DIR"
        _dl_zip "$TROJAN_GO_URL" "trojan-go-linux-amd64.zip" "trojan-go" "$TROJANGO_BIN" 1000000 "Trojan-Go"
    } || ok "  ✓ Trojan-Go ada — skip"

    command -v jq &>/dev/null || _dl_bin "$JQ_URL" "/usr/local/bin/jq" 500000 "jq"

    local ACME_BIN="$HOME/.acme.sh/acme.sh"
    if [[ ! -x "$ACME_BIN" ]]; then
        inf "  ↓ acme.sh"
        local ta; ta=$(mktemp)
        if dl "$ACME_URL" "$ta"; then
            chmod +x "$ta"; bash "$ta" --install --home "$HOME/.acme.sh" --noprofile &>/dev/null
            rm -f "$ta"
            [[ -x "$ACME_BIN" ]] && { ok "    ✓ acme.sh"; ok_count=$((ok_count+1)); } \
                                  || { warn "    ✗ acme.sh gagal"; fail_count=$((fail_count+1)); }
        else warn "    ✗ Gagal download acme.sh"; fail_count=$((fail_count+1)); fi
    else ok "  ✓ acme.sh ada — skip"; fi

    rm -rf "$tmp"
    echo -e "  ${BLD}Selesai${NC}: ${LG}${ok_count} berhasil${NC}, ${Y}${fail_count} gagal${NC}"
}

# ════════════════════════════════════════════════════════════
#  3. INSTALLER — SSH + Dropbear + Stunnel
# ════════════════════════════════════════════════════════════
install_ssh() {
    inf "Konfigurasi OpenSSH (port 22)..."
    sed -i 's/^#\?Port .*/Port 22/' /etc/ssh/sshd_config 2>/dev/null
    grep -qE '^Port[[:space:]]+22$' /etc/ssh/sshd_config 2>/dev/null || echo "Port 22" >> /etc/ssh/sshd_config
    sed -i '/^Port[[:space:]]\+80$/d;/^Port[[:space:]]\+443$/d' /etc/ssh/sshd_config 2>/dev/null
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config 2>/dev/null
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
    ok "OpenSSH siap: port 22"

    inf "Install Dropbear (port 109, 143)..."
    local db_tmp; db_tmp=$(mktemp -d); local db_ok=0
    if dl "$DROPBEAR_URL" "$db_tmp/dropbear-master.zip"; then
        unzip -qo "$db_tmp/dropbear-master.zip" -d "$db_tmp/dropbear" 2>/dev/null
        local db_bin; db_bin=$(find "$db_tmp/dropbear" -type f -name "dropbear" ! -name "*.c" ! -name "*.h" 2>/dev/null | head -1)
        if [[ -n "$db_bin" ]] && verify_binary "$db_bin" 100000; then
            install -m755 "$db_bin" /usr/sbin/dropbear
            local dbk; dbk=$(find "$db_tmp/dropbear" -type f -name "dropbearkey" ! -name "*.c" ! -name "*.h" 2>/dev/null | head -1)
            [[ -n "$dbk" ]] && install -m755 "$dbk" /usr/bin/dropbearkey
            db_ok=1
        fi
    fi
    rm -rf "$db_tmp"
    [[ "$db_ok" == "0" ]] && apt-get install -y -qq dropbear 2>/dev/null || true

    mkdir -p /etc/dropbear
    [[ ! -f /etc/dropbear/dropbear_rsa_host_key   ]] && dropbearkey -t rsa   -f /etc/dropbear/dropbear_rsa_host_key   &>/dev/null || true
    [[ ! -f /etc/dropbear/dropbear_ecdsa_host_key ]] && dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key &>/dev/null || true
    [[ ! -f /etc/dropbear/dropbear_ed25519_host_key ]] && dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key &>/dev/null || true

    grep -qx '/bin/false'        /etc/shells 2>/dev/null || echo '/bin/false'        >> /etc/shells
    grep -qx '/usr/sbin/nologin' /etc/shells 2>/dev/null || echo '/usr/sbin/nologin' >> /etc/shells

    if [[ ! -f /etc/systemd/system/dropbear.service ]]; then
        cat > /etc/systemd/system/dropbear.service <<'DBSVC'
[Unit]
Description=MAX Panel — Dropbear SSH
After=network.target
[Service]
Type=forking
ExecStart=/usr/sbin/dropbear -p 109 -p 143 -W 65536 -R
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
Restart=on-failure
RestartSec=3
[Install]
WantedBy=multi-user.target
DBSVC
        systemctl daemon-reload 2>/dev/null
    fi
    systemctl enable dropbear &>/dev/null; systemctl restart dropbear 2>/dev/null
    ok "Dropbear siap: 109, 143"

    inf "Install Stunnel (445 → DB:109 / 777 → SSH:22)..."
    local st_tmp; st_tmp=$(mktemp -d); local st_ok=0
    if dl "$STUNNEL_URL" "$st_tmp/stunnel-master.zip"; then
        unzip -qo "$st_tmp/stunnel-master.zip" -d "$st_tmp/stunnel" 2>/dev/null
        local st_bin; st_bin=$(find "$st_tmp/stunnel" -type f -name "stunnel" ! -name "*.c" ! -name "*.h" 2>/dev/null | head -1)
        if [[ -n "$st_bin" ]] && verify_binary "$st_bin" 100000; then
            install -m755 "$st_bin" /usr/bin/stunnel4
            [[ ! -e /usr/bin/stunnel ]] && ln -sf /usr/bin/stunnel4 /usr/bin/stunnel
            st_ok=1
        fi
    fi
    rm -rf "$st_tmp"
    [[ "$st_ok" == "0" ]] && apt-get install -y -qq stunnel4 2>/dev/null || true

    id stunnel4 &>/dev/null || useradd -r -s /bin/false stunnel4 2>/dev/null || true
    mkdir -p /etc/stunnel /var/run/stunnel4
    chown stunnel4:stunnel4 /var/run/stunnel4 2>/dev/null || true

    local dom; dom=$(get_domain)
    if [[ -s "/etc/ssl/maxpanel/${dom}/key.pem" && -s "/etc/ssl/maxpanel/${dom}/fullchain.pem" ]]; then
        cat "/etc/ssl/maxpanel/${dom}/key.pem" "/etc/ssl/maxpanel/${dom}/fullchain.pem" > /etc/stunnel/stunnel.pem
    elif [[ -s /etc/xray/xray.key && -s /etc/xray/xray.crt ]]; then
        cat /etc/xray/xray.key /etc/xray/xray.crt > /etc/stunnel/stunnel.pem
    else
        openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
            -subj "/C=ID/O=MAX/CN=${dom}" \
            -keyout /etc/stunnel/key.pem -out /etc/stunnel/cert.pem &>/dev/null
        cat /etc/stunnel/key.pem /etc/stunnel/cert.pem > /etc/stunnel/stunnel.pem
        chmod 600 /etc/stunnel/key.pem
    fi
    chmod 600 /etc/stunnel/stunnel.pem

    cat > /etc/stunnel/stunnel.conf <<'STUN'
cert = /etc/stunnel/stunnel.pem
pid = /var/run/stunnel4/stunnel.pid
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1
[dropbear-ssl-445]
accept = 445
connect = 127.0.0.1:109
[openssh-ssl-777]
accept = 777
connect = 127.0.0.1:22
STUN
    sed -i 's/^ENABLED=.*/ENABLED=1/' /etc/default/stunnel4 2>/dev/null
    [[ -f /etc/default/stunnel4 ]] || echo "ENABLED=1" > /etc/default/stunnel4
    systemctl enable stunnel4 &>/dev/null
    pkill -9 stunnel4 2>/dev/null; rm -f /var/run/stunnel4/stunnel.pid; sleep 1
    systemctl restart stunnel4 2>/dev/null
    ok "Stunnel siap: 445 (→DB:109), 777 (→SSH:22)"
}

# ════════════════════════════════════════════════════════════
#  4. INSTALLER — Xray-core
# ════════════════════════════════════════════════════════════
install_xray() {
    inf "Install Xray-core..."
    mkdir -p /etc/xray /var/log/xray; touch "$XRAY_LOG" /var/log/xray/error.log
    if [[ ! -x "$XRAY_BIN" ]] || ! "$XRAY_BIN" version &>/dev/null; then
        local tmp; tmp=$(mktemp -d); local arch; arch=$(uname -m)
        local url; case "$arch" in aarch64|arm64) url="$XRAY_URL_ARM" ;; *) url="$XRAY_URL" ;; esac
        if dl "$url" "$tmp/xray.zip"; then
            unzip -qo "$tmp/xray.zip" -d "$tmp" 2>/dev/null
            if [[ -f "$tmp/xray" ]] && verify_binary "$tmp/xray" 1000000; then
                install -m755 "$tmp/xray" "$XRAY_BIN"; ok "Xray-core terpasang"
            else err "Binary Xray rusak"; rm -rf "$tmp"; return 1; fi
        else err "Gagal download Xray-core"; rm -rf "$tmp"; return 1; fi
        rm -rf "$tmp"
    else ok "Xray-core ada — skip"; fi

    [[ ! -s "$XRAY_CRT" ]] && {
        local dom; dom=$(get_domain)
        openssl req -x509 -nodes -newkey rsa:2048 -days 365 -subj "/CN=${dom}" -keyout "$XRAY_KEY" -out "$XRAY_CRT" &>/dev/null
        chmod 644 "$XRAY_CRT"; chmod 600 "$XRAY_KEY"
    }

    cat > "$XRAY_CFG" <<'XCFG'
{
  "log": {"loglevel":"warning","access":"/var/log/xray/access.log","error":"/var/log/xray/error.log"},
  "inbounds": [
    {"port":10001,"listen":"127.0.0.1","protocol":"vmess","settings":{"clients":[]},"streamSettings":{"network":"ws","wsSettings":{"path":"/vmess"}},"sniffing":{"enabled":true,"destOverride":["http","tls"]},"tag":"vmess-ws"},
    {"port":10002,"listen":"127.0.0.1","protocol":"vless","settings":{"clients":[],"decryption":"none"},"streamSettings":{"network":"ws","wsSettings":{"path":"/vless"}},"sniffing":{"enabled":true,"destOverride":["http","tls"]},"tag":"vless-ws"},
    {"port":10003,"listen":"127.0.0.1","protocol":"trojan","settings":{"clients":[]},"streamSettings":{"network":"ws","wsSettings":{"path":"/trojan-ws"}},"tag":"trojan-ws"},
    {"port":10004,"listen":"127.0.0.1","protocol":"vless","settings":{"clients":[],"decryption":"none"},"streamSettings":{"network":"grpc","grpcSettings":{"serviceName":"vless-grpc"}},"tag":"vless-grpc"},
    {"port":10005,"listen":"127.0.0.1","protocol":"trojan","settings":{"clients":[]},"streamSettings":{"network":"grpc","grpcSettings":{"serviceName":"trojan-grpc"}},"tag":"trojan-grpc"},
    {"port":8388,"protocol":"shadowsocks","settings":{"clients":[],"network":"tcp,udp"},"tag":"ss-2022"}
  ],
  "outbounds":[{"protocol":"freedom","tag":"direct"},{"protocol":"blackhole","tag":"blocked"}]
}
XCFG
    cat > /etc/systemd/system/xray.service <<XEOF
[Unit]
Description=Xray Service
After=network.target nss-lookup.target
[Service]
User=root
ExecStart=$XRAY_BIN run -c $XRAY_CFG
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
XEOF
    systemctl daemon-reload; systemctl enable xray &>/dev/null; systemctl restart xray 2>/dev/null; sleep 1
    is_up xray && ok "Xray-core aktif" || warn "Xray belum aktif"
}

# ════════════════════════════════════════════════════════════
#  5. INSTALLER — Trojan-Go, Hysteria, OpenVPN, WireGuard
# ════════════════════════════════════════════════════════════
install_trojan_go() {
    inf "Install Trojan-Go..."; mkdir -p "$TROJANGO_DIR"
    if [[ ! -x "$TROJANGO_BIN" ]]; then
        local tmp; tmp=$(mktemp -d)
        if dl "$TROJAN_GO_URL" "$tmp/trojan-go.zip"; then
            unzip -qo "$tmp/trojan-go.zip" -d "$tmp" 2>/dev/null
            if [[ -f "$tmp/trojan-go" ]] && verify_binary "$tmp/trojan-go" 1000000; then
                install -m755 "$tmp/trojan-go" "$TROJANGO_BIN"; ok "Trojan-Go terpasang"
            else err "Binary Trojan-Go rusak"; rm -rf "$tmp"; return 1; fi
        else err "Gagal download Trojan-Go"; rm -rf "$tmp"; return 1; fi
        rm -rf "$tmp"
    else ok "Trojan-Go ada — skip"; fi

    [[ ! -s "$TROJANGO_DIR/server.crt" ]] && {
        local dom; dom=$(get_domain)
        openssl req -x509 -nodes -newkey rsa:2048 -days 365 -subj "/CN=${dom}" -keyout "$TROJANGO_DIR/server.key" -out "$TROJANGO_DIR/server.crt" &>/dev/null
    }
    cat > "$TROJANGO_CFG" <<'TGCFG'
{"run_type":"server","local_addr":"0.0.0.0","local_port":2087,"remote_addr":"127.0.0.1","remote_port":80,"password":[],"ssl":{"cert":"/etc/trojan-go/server.crt","key":"/etc/trojan-go/server.key","sni":"","alpn":["http/1.1"]},"websocket":{"enabled":true,"path":"/trojan-go","host":""},"router":{"enabled":false}}
TGCFG
    cat > /etc/systemd/system/trojan-go.service <<TGEOF
[Unit]
Description=Trojan-Go Server
After=network.target
[Service]
Type=simple
User=root
ExecStart=$TROJANGO_BIN -config $TROJANGO_CFG
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
TGEOF
    systemctl daemon-reload; systemctl enable trojan-go &>/dev/null; systemctl restart trojan-go 2>/dev/null
    is_up trojan-go && ok "Trojan-Go aktif (port 2087)" || warn "Trojan-Go gagal start"
}

install_hysteria() {
    inf "Install Hysteria 2..."; mkdir -p "$HY_DIR"
    if [[ ! -x "$HY_BIN" ]]; then
        local tmp; tmp=$(mktemp -d)
        if dl "$HYSTERIA_URL" "$tmp/hysteria" && verify_binary "$tmp/hysteria" 1000000; then
            install -m755 "$tmp/hysteria" "$HY_BIN"; ok "Hysteria 2 terpasang"
        else err "Gagal download/verify Hysteria"; rm -rf "$tmp"; return 1; fi
        rm -rf "$tmp"
    else ok "Hysteria ada — skip"; fi

    [[ ! -s "$HY_DIR/server.crt" ]] && {
        local dom; dom=$(get_domain)
        openssl req -x509 -nodes -newkey rsa:2048 -days 365 -subj "/CN=${dom}" -keyout "$HY_DIR/server.key" -out "$HY_DIR/server.crt" &>/dev/null
    }
    cat > "$HY_CFG" <<'HYCFG'
listen: :36712
tls:
  cert: /etc/hysteria/server.crt
  key:  /etc/hysteria/server.key
auth:
  type: userpass
  userpass:
    maxpanel: "maxpanel2024"
masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true
quic:
  initStreamReceiveWindow:   8388608
  maxStreamReceiveWindow:    8388608
  initConnReceiveWindow:    20971520
  maxConnReceiveWindow:     20971520
HYCFG
    cat > /etc/systemd/system/hysteria-server.service <<'HYEOF'
[Unit]
Description=Hysteria 2 Server
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
HYEOF
    local IFACE; IFACE=$(get_iface)
    iptables -I INPUT -p udp --dport 36712 -j ACCEPT 2>/dev/null
    while iptables -t nat -D PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :36712 2>/dev/null; do :; done
    iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :36712 2>/dev/null
    netfilter-persistent save &>/dev/null
    systemctl daemon-reload; systemctl enable hysteria-server &>/dev/null; systemctl restart hysteria-server 2>/dev/null
    is_up hysteria-server && ok "Hysteria 2 aktif (UDP 36712)" || warn "Hysteria belum aktif"
}

install_openvpn() {
    inf "Install OpenVPN (TCP 1194 + UDP 2200)..."
    mkdir -p /etc/openvpn/server /etc/openvpn/easy-rsa /etc/openvpn/client
    if [[ ! -s /etc/openvpn/server/ca.crt ]]; then
        local ER=/etc/openvpn/easy-rsa
        [[ -d /usr/share/easy-rsa ]] && cp -r /usr/share/easy-rsa/* "$ER/" 2>/dev/null
        cd "$ER" || return 1
        export EASYRSA_BATCH=1 EASYRSA_REQ_CN="MAX-CA"
        ./easyrsa init-pki &>/dev/null; ./easyrsa --batch build-ca nopass &>/dev/null
        ./easyrsa --batch gen-req server nopass &>/dev/null; ./easyrsa --batch sign-req server server &>/dev/null
        ./easyrsa gen-dh &>/dev/null; openvpn --genkey secret /etc/openvpn/server/ta.key &>/dev/null
        cp "$ER/pki/ca.crt" "$ER/pki/issued/server.crt" "$ER/pki/private/server.key" "$ER/pki/dh.pem" /etc/openvpn/server/
        chmod 600 /etc/openvpn/server/server.key /etc/openvpn/server/ta.key 2>/dev/null
        cd - >/dev/null || true; ok "OpenVPN PKI dibuat"
    else ok "OpenVPN PKI ada — skip"; fi

    local IFACE; IFACE=$(get_iface)
    for proto_port in "tcp:1194:tun:10.200.0.0" "udp:2200:tun1:10.201.0.0"; do
        local proto port dev subnet; IFS=: read -r proto port dev subnet <<< "$proto_port"
        cat > "/etc/openvpn/server/${proto}.conf" <<OVPNCFG
port ${port}
proto ${proto}
dev ${dev}
ca /etc/openvpn/server/ca.crt
cert /etc/openvpn/server/server.crt
key /etc/openvpn/server/server.key
dh /etc/openvpn/server/dh.pem
tls-auth /etc/openvpn/server/ta.key 0
server ${subnet} 255.255.255.0
ifconfig-pool-persist /etc/openvpn/server/ipp-${proto}.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
keepalive 10 120
data-ciphers AES-256-GCM:AES-128-GCM:AES-128-CBC
data-ciphers-fallback AES-128-CBC
auth SHA256
user nobody
group nogroup
persist-key
persist-tun
status /var/log/openvpn-${proto}-status.log
log /var/log/openvpn-${proto}.log
verb 3
plugin /usr/lib/openvpn/openvpn-plugin-auth-pam.so login
duplicate-cn
script-security 3
client-cert-not-required
username-as-common-name
OVPNCFG
    done
    _apply_block "OPENVPN-FORWARD" /etc/sysctl.conf <<'SC'
net.ipv4.ip_forward=1
SC
    sysctl -p &>/dev/null
    iptables -t nat -C POSTROUTING -s 10.200.0.0/24 -o "$IFACE" -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 10.200.0.0/24 -o "$IFACE" -j MASQUERADE
    iptables -t nat -C POSTROUTING -s 10.201.0.0/24 -o "$IFACE" -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 10.201.0.0/24 -o "$IFACE" -j MASQUERADE
    netfilter-persistent save &>/dev/null
    systemctl enable openvpn-server@tcp openvpn-server@udp &>/dev/null
    systemctl restart openvpn-server@tcp 2>/dev/null; systemctl restart openvpn-server@udp 2>/dev/null
    ok "OpenVPN siap: TCP 1194 + UDP 2200"
}

install_wireguard() {
    inf "Install WireGuard (UDP 51820)..."
    mkdir -p "$WG_DIR" "$WG_CLIENT_DIR"; chmod 700 "$WG_DIR"
    if [[ ! -s "$WG_DIR/server_private.key" ]]; then
        local privk pubk; privk=$(wg genkey); pubk=$(echo "$privk" | wg pubkey)
        ( umask 077; echo "$privk" > "$WG_DIR/server_private.key" )
        echo "$pubk" > "$WG_DIR/server_public.key"
        chmod 600 "$WG_DIR/server_private.key"; chmod 644 "$WG_DIR/server_public.key"
    fi
    local IFACE SPRIV; IFACE=$(get_iface); SPRIV=$(cat "$WG_DIR/server_private.key")
    ( umask 077; cat > "$WG_CFG" <<WGCFG
[Interface]
Address = 10.66.66.1/24
ListenPort = 51820
PrivateKey = $SPRIV
SaveConfig = false
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $IFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $IFACE -j MASQUERADE
WGCFG
)
    _apply_block "WG-FORWARD" /etc/sysctl.conf <<'SC'
net.ipv4.ip_forward=1
SC
    sysctl -p &>/dev/null
    systemctl enable wg-quick@wg0 &>/dev/null; systemctl restart wg-quick@wg0 2>/dev/null
    is_up "wg-quick@wg0" && ok "WireGuard aktif (UDP 51820)" || warn "WireGuard belum aktif"
}

# ════════════════════════════════════════════════════════════
#  6. INSTALLER — WS SSH Proxy (Backend untuk Nginx/HAProxy)
# ════════════════════════════════════════════════════════════
install_ws_ssh_proxy() {
    inf "Install WebSocket SSH Proxy..."
    mkdir -p "$WS_DIR"; chmod 700 "$WS_DIR"
    local ws_ok=0

    if dl "$WS_SSH_SERVER_URL" "$WS_DIR/ws-ssh-server.py" && dl "$WS_TUNNEL_URL" "$WS_DIR/ws_tunnel.py"; then
        chmod +x "$WS_DIR/ws-ssh-server.py" "$WS_DIR/ws_tunnel.py"
        ws_ok=1
    else
        warn "Gagal download WS proxy — pakai fallback inline"
        cat > "$WS_BIN" <<'WSPY'
#!/usr/bin/env python3
import socket, threading, sys, signal
LISTEN_HOST = '127.0.0.1'
LISTEN_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8880
TARGET_HOST, TARGET_PORT = '127.0.0.1', 22
RESPONSE = b'HTTP/1.1 200 Connection Established\r\nProxy-Agent: MAX-WS\r\n\r\n'
BUFLEN = 65536
def relay(src, dst):
    try:
        while True:
            data = src.recv(BUFLEN)
            if not data: break
            dst.sendall(data)
    except: pass
def handle(c):
    try:
        req = c.recv(BUFLEN)
        if req: c.sendall(RESPONSE)
        s = socket.create_connection((TARGET_HOST, TARGET_PORT), timeout=10)
        threading.Thread(target=relay, args=(c, s), daemon=True).start()
        relay(s, c)
    except: pass
    finally:
        try: c.close()
        except: pass
def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((LISTEN_HOST, LISTEN_PORT)); srv.listen(128)
    signal.signal(signal.SIGTERM, lambda s,f: sys.exit(0))
    while True:
        c, _ = srv.accept()
        threading.Thread(target=handle, args=(c,), daemon=True).start()
if __name__ == '__main__': main()
WSPY
    fi

    cat > /etc/systemd/system/ws-ssh-proxy.service <<WSEOF
[Unit]
Description=MAX Panel — WS SSH Proxy
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/python3 $WS_BIN 8880
Restart=on-failure
RestartSec=3
[Install]
WantedBy=multi-user.target
WSEOF
    systemctl daemon-reload
    systemctl enable ws-ssh-proxy &>/dev/null
    systemctl restart ws-ssh-proxy 2>/dev/null
    is_up ws-ssh-proxy && ok "WS SSH Proxy aktif (port 8880)" || warn "WS SSH Proxy gagal start"
}

# ════════════════════════════════════════════════════════════
#  7. INSTALLER — Nginx (Frontend Reverse Proxy)
# ════════════════════════════════════════════════════════════
install_nginx() {
    inf "Konfigurasi Nginx Reverse Proxy..."
    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
    rm -f /etc/nginx/sites-enabled/default

    cat > /etc/nginx/sites-available/maxpanel <<'NGINXCFG'
server {
    listen 80;
    listen [::]:80;
    server_name _;
    location /ws-ssh { proxy_pass http://127.0.0.1:8880; proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host $host; proxy_read_timeout 86400; }
    location /vmess { proxy_pass http://127.0.0.1:10001; proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host $host; }
    location /vless { proxy_pass http://127.0.0.1:10002; proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host $host; }
    location /trojan-ws { proxy_pass http://127.0.0.1:10003; proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host $host; }
    location /trojan-go { proxy_pass http://127.0.0.1:2087; proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host $host; }
    location /vless-grpc { grpc_pass grpc://127.0.0.1:10004; }
    location /trojan-grpc { grpc_pass grpc://127.0.0.1:10005; }
    location / { default_type text/html; return 200 '<!DOCTYPE html><html><body style="background:#000;color:#0ff;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;font-family:monospace"><h1>MAX PANEL</h1></body></html>'; }
}
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name _;
    ssl_certificate     /etc/xray/xray.crt;
    ssl_certificate_key /etc/xray/xray.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    location /ws-ssh { proxy_pass http://127.0.0.1:8880; proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host $host; proxy_read_timeout 86400; }
    location /vmess { proxy_pass http://127.0.0.1:10001; proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host $host; }
    location /vless { proxy_pass http://127.0.0.1:10002; proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host $host; }
    location /trojan-ws { proxy_pass http://127.0.0.1:10003; proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host $host; }
    location /vless-grpc { grpc_pass grpc://127.0.0.1:10004; }
    location /trojan-grpc { grpc_pass grpc://127.0.0.1:10005; }
}
NGINXCFG
    ln -sf /etc/nginx/sites-available/maxpanel /etc/nginx/sites-enabled/maxpanel
    nginx -t &>/dev/null
    systemctl enable nginx &>/dev/null
    systemctl restart nginx 2>/dev/null
    is_up nginx && ok "Nginx aktif (Port 80 & 443)" || warn "Nginx gagal start"
}

# ════════════════════════════════════════════════════════════
#  8. INSTALLER — HAProxy (Alternative TLS Port 8443)
# ════════════════════════════════════════════════════════════
install_haproxy() {
    inf "Konfigurasi HAProxy (Alt-TLS port 8443)..."
    local dom; dom=$(get_domain)
    mkdir -p /etc/haproxy/ssl
    
    [[ ! -s /etc/haproxy/ssl/haproxy.pem ]] && {
        openssl req -x509 -nodes -newkey rsa:2048 -days 3650 -subj "/C=ID/O=MAX/CN=${dom}" \
            -keyout /etc/haproxy/ssl/haproxy.key -out /etc/haproxy/ssl/haproxy.crt &>/dev/null
        cat /etc/haproxy/ssl/haproxy.key /etc/haproxy/ssl/haproxy.crt > /etc/haproxy/ssl/haproxy.pem
        chmod 600 /etc/haproxy/ssl/haproxy.pem
    }

    cat > /etc/haproxy/haproxy.cfg <<'HAPCFG'
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon
    maxconn 4096
defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms
frontend max_front
    bind *:8443 ssl crt /etc/haproxy/ssl/haproxy.pem alpn h2,http/1.1
    mode http
    option forwardfor
    acl is_ws_ssh path_beg /ws-ssh
    acl is_vmess path_beg /vmess
    acl is_vless path_beg /vless
    acl is_trojan_ws path_beg /trojan-ws
    acl is_vless_grpc path_beg /vless-grpc
    acl is_trojan_grpc path_beg /trojan-grpc
    use_backend ws_ssh if is_ws_ssh
    use_backend vmess_ws if is_vmess
    use_backend vless_ws if is_vless
    use_backend trojan_ws if is_trojan_ws
    use_backend vless_grpc if is_vless_grpc
    use_backend trojan_grpc if is_trojan_grpc
    default_backend def_backend
backend def_backend
    mode http
    server def1 127.0.0.1:80
backend ws_ssh
    mode http
    option http-server-close
    server ws1 127.0.0.1:8880
backend vmess_ws
    mode http
    server vmess1 127.0.0.1:10001
backend vless_ws
    mode http
    server vless1 127.0.0.1:10002
backend trojan_ws
    mode http
    server trojan1 127.0.0.1:10003
backend vless_grpc
    mode http
    server vgrpc1 127.0.0.1:10004
backend trojan_grpc
    mode http
    server tgrpc1 127.0.0.1:10005
HAPCFG
    sed -i 's/^ENABLED=.*/ENABLED=1/' /etc/default/haproxy 2>/dev/null
    systemctl enable haproxy &>/dev/null
    systemctl restart haproxy 2>/dev/null
    is_up haproxy && ok "HAProxy aktif (Port 8443)" || warn "HAProxy gagal start"
}

# ════════════════════════════════════════════════════════════
#  9. INSTALLER — Acme.sh SSL (Harus Paling Akhir)
# ════════════════════════════════════════════════════════════
install_acme() {
    local ACME_BIN="$HOME/.acme.sh/acme.sh"
    if [[ ! -x "$ACME_BIN" ]]; then
        warn "acme.sh tidak ditemukan, skip integrasi SSL"
        return 1
    fi

    local dom; dom=$(get_domain)
    if [[ "$dom" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        inf "Menggunakan IP VPS, SSL Acme.sh dilewati"
        return 0
    fi

    inf "Menerbitkan SSL untuk domain ${W}${dom}${NC}..."
    mkdir -p "/etc/ssl/maxpanel/${dom}"
    
    # Matikan sementara Nginx/HAP agar port 80 bebas untuk verifikasi ACME
    systemctl stop nginx haproxy 2>/dev/null
    "$ACME_BIN" --issue -d "$dom" --standalone --httpport 80 --force 2>/dev/null
    
    if [[ -s "$HOME/.acme.sh/${dom}/fullchain.cer" ]]; then
        "$ACME_BIN" --install-cert -d "$dom" \
            --fullchain-file "/etc/ssl/maxpanel/${dom}/fullchain.pem" \
            --key-file "/etc/ssl/maxpanel/${dom}/key.pem" \
            --reloadcmd "systemctl start nginx haproxy stunnel4" 2>/dev/null
            
        # Salin ke Xray
        cp "/etc/ssl/maxpanel/${dom}/fullchain.pem" "$XRAY_CRT" 2>/dev/null
        cp "/etc/ssl/maxpanel/${dom}/key.pem" "$XRAY_KEY" 2>/dev/null
        chmod 600 "$XRAY_KEY" 2>/dev/null
        
        # Salin ke Stunnel
        cat "/etc/ssl/maxpanel/${dom}/key.pem" "/etc/ssl/maxpanel/${dom}/fullchain.pem" > /etc/stunnel/stunnel.pem 2>/dev/null
        chmod 600 /etc/stunnel/stunnel.pem 2>/dev/null
        
        # Salin ke HAProxy
        cat "/etc/ssl/maxpanel/${dom}/key.pem" "/etc/ssl/maxpanel/${dom}/fullchain.pem" > /etc/haproxy/ssl/haproxy.pem 2>/dev/null
        chmod 600 /etc/haproxy/ssl/haproxy.pem 2>/dev/null
        
        # Update path SSL Nginx
        sed -i "s|ssl_certificate.*|ssl_certificate     /etc/ssl/maxpanel/${dom}/fullchain.pem;|g" /etc/nginx/sites-available/maxpanel
        sed -i "s|ssl_certificate_key.*|ssl_certificate_key /etc/ssl/maxpanel/${dom}/key.pem;|g" /etc/nginx/sites-available/maxpanel
        
        # Restart semua service yang terkait SSL
        systemctl restart xray stunnel4 nginx haproxy 2>/dev/null
        ok "SSL Berhasil diterbitkan untuk ${dom}"
    else
        warn "Gagal menerbitkan SSL (pastikan domain A Record mengarah ke IP VPS ini)"
        # Nyalakan kembali jika gagal
        systemctl start nginx haproxy 2>/dev/null
    fi
}

# ════════════════════════════════════════════════════════════
#  MAIN INSTALLER — Orchestrator (Urutan Eksekusi)
# ════════════════════════════════════════════════════════════
install_all() {
    clear
    load_theme
    draw_logo
    echo -e "  ${A4}◈${NC} ${BLD}MULAI PROSES INSTALASI MAX PANEL${NC}"
    echo -e "  ${A1}${_DASH}${NC}"
    
    mkdir -p "$DIR" "$LOGDIR" "$BACKUPDIR"
    touch "$SSH_DB" "$VMESS_DB" "$VLESS_DB" "$TROJAN_DB" "$TROJANGO_DB" \
          "$OVPN_DB" "$WG_DB" "$HY_DB" "$SS_DB" "$MLDB" "$DOMF" "$VERSIONF"
    echo "$SCRIPT_VERSION" > "$VERSIONF"

    check_root
    check_os

    # Langkah 1: Input Domain
    local current_dom
    current_dom=$(get_domain)
    echo -e "  ${A4}◈${NC} ${BLD}KONFIGURASI DOMAIN${NC}"
    echo -e "  ${A1}${_DASH}${NC}"
    echo -e "  ${DIM}Domain saat ini: ${W}${current_dom}${NC}"
    echo ""
    echo -ne "  ${A3}➜${NC} ${BLD}Masukkan Domain (tekan Enter untuk lewati pakai IP):${NC} "
    read -r new_dom
    if [[ -n "$new_dom" ]]; then
        new_dom=$(echo "$new_dom" | sed 's|^https\?://||' | sed 's|/.*||' | tr '[:upper:]' '[:lower:]')
        echo "$new_dom" > "$DOMF"
        ok "Domain disimpan: ${W}$new_dom${NC}"
    else
        warn "Menggunakan IP VPS (SSL Acme.sh akan dilewati)"
    fi
    echo -e "  ${A1}${_DASH}${NC}"

    # Langkah 2: Dependencies & Binneris
    install_deps
    install_all_bins

    # Langkah 3: Basis Tunneling
    install_ssh           
    install_xray
    install_trojan_go
    install_hysteria
    install_openvpn
    install_wireguard

    # Langkah 4: Websocket & Reverse Proxy
    install_ws_ssh_proxy  
    install_nginx         
    install_haproxy       

    # Langkah 5: Sertifikat SSL (Harus paling akhir)
    install_acme          

    echo ""
    echo -e "  ${A1}${_DASH}${NC}"
    echo -e "  ${LG}  ✔ INSTALASI MAX PANEL SELESAI!${NC}"
    echo -e "  ${A1}${_DASH}${NC}"
    echo -e "  ${DIM}  Ketik ${A2}menu-max${NC} ${DIM}untuk membuka panel.${NC}"
    echo -e "  ${A1}${_DASH}${NC}"
    echo ""
}

# ════════════════════════════════════════════════════════════
#  TRIGGER START
# ════════════════════════════════════════════════════════════
if [[ -f "$DIR/menu-max.sh" ]]; then
    source "$DIR/menu-max.sh"
elif [[ "$1" == "--install" || "$1" == "install" ]]; then
    install_all
else
    install_all
fi