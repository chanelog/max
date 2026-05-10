#!/bin/bash

# ============================================
#   UDP Custom Installer
#   By: Script Auto Installer
# ============================================

# Warna
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Cek root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Script ini harus dijalankan sebagai root!${NC}"
    exit 1
fi

echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}       UDP Custom Auto Installer           ${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# ============================================
# INSTALL DEPENDENCIES
# ============================================
echo -e "${YELLOW}[1/6] Menginstall dependencies...${NC}"
apt-get update -y > /dev/null 2>&1
apt-get install -y curl wget unzip > /dev/null 2>&1
echo -e "${GREEN}    Dependencies berhasil diinstall${NC}"

# ============================================
# DOWNLOAD UDP CUSTOM BINARY
# ============================================
echo -e "${YELLOW}[2/6] Mendownload UDP Custom binary...${NC}"
wget -q --show-progress -O /usr/local/bin/udp-custom \
    "https://github.com/chanelog/max/releases/download/bin/udp-custom-linux-amd64"

if [[ $? -ne 0 ]]; then
    echo -e "${RED}    Gagal mendownload UDP Custom binary!${NC}"
    exit 1
fi

chmod +x /usr/local/bin/udp-custom
echo -e "${GREEN}    UDP Custom binary berhasil didownload${NC}"

# ============================================
# DOWNLOAD UDPGW
# ============================================
echo -e "${YELLOW}[3/6] Mendownload UDPGW...${NC}"
wget -q --show-progress -O /usr/local/bin/udpgw \
    "https://github.com/chanelog/max/raw/main/udpgw"

if [[ $? -ne 0 ]]; then
    echo -e "${RED}    Gagal mendownload UDPGW!${NC}"
    exit 1
fi

chmod +x /usr/local/bin/udpgw
echo -e "${GREEN}    UDPGW berhasil didownload${NC}"

# ============================================
# BUAT KONFIGURASI
# ============================================
echo -e "${YELLOW}[4/6] Membuat konfigurasi...${NC}"
mkdir -p /etc/udp-custom

cat > /etc/udp-custom/config.json << 'EOF'
{
  "listen": ":36712",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "auth": {
    "mode": "passwords"
  }
}
EOF

# Buat file passwords kosong jika belum ada
touch /etc/udp-custom/passwords.json
echo -e "${GREEN}    Konfigurasi berhasil dibuat di /etc/udp-custom/config.json${NC}"

# ============================================
# BUAT SYSTEMD SERVICE UDP CUSTOM
# ============================================
echo -e "${YELLOW}[5/6] Membuat systemd service...${NC}"

cat > /etc/systemd/system/udp-custom.service << 'EOF'
[Unit]
Description=UDP Custom Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/udp-custom server --config /etc/udp-custom/config.json
Restart=always
RestartSec=3
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/udpgw.service << 'EOF'
[Unit]
Description=UDPGW Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/udpgw --listen 127.0.0.1:7300 --max-clients 1000 --max-connections-for-client 10
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

# Enable & Start UDP Custom
systemctl enable udp-custom > /dev/null 2>&1
systemctl start udp-custom

# Enable & Start UDPGW
systemctl enable udpgw > /dev/null 2>&1
systemctl start udpgw

echo -e "${GREEN}    Service berhasil dibuat dan dijalankan${NC}"

# ============================================
# KONFIGURASI UFW
# ============================================
echo -e "${YELLOW}[6/6] Mengkonfigurasi UFW...${NC}"

# Install UFW jika belum ada
apt-get install -y ufw > /dev/null 2>&1

# Reset UFW (opsional, hapus baris ini jika tidak mau reset)
ufw --force reset > /dev/null 2>&1

# Izinkan SSH dulu agar tidak terkunci
ufw allow 22/tcp > /dev/null 2>&1

# Izinkan semua port UDP 1-65535
ufw allow 1:65535/udp > /dev/null 2>&1

# Izinkan port UDP Custom (36712)
ufw allow 36712/udp > /dev/null 2>&1
ufw allow 36712/tcp > /dev/null 2>&1

# Izinkan UDPGW lokal (7300)
ufw allow from 127.0.0.1 to any port 7300 > /dev/null 2>&1

# Aktifkan UFW
ufw --force enable > /dev/null 2>&1

echo -e "${GREEN}    UFW berhasil dikonfigurasi${NC}"

# ============================================
# SELESAI
# ============================================
echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}      Instalasi Selesai!                   ${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e " ${YELLOW}Info Service:${NC}"
echo -e "   UDP Custom Port : ${GREEN}36712${NC}"
echo -e "   UDPGW Port      : ${GREEN}7300 (localhost)${NC}"
echo -e "   Config          : ${GREEN}/etc/udp-custom/config.json${NC}"
echo ""
echo -e " ${YELLOW}Status Service:${NC}"
echo -e "   UDP Custom : $(systemctl is-active udp-custom)"
echo -e "   UDPGW      : $(systemctl is-active udpgw)"
echo ""
echo -e " ${YELLOW}Perintah Berguna:${NC}"
echo -e "   Start   : systemctl start udp-custom"
echo -e "   Stop    : systemctl stop udp-custom"
echo -e "   Restart : systemctl restart udp-custom"
echo -e "   Status  : systemctl status udp-custom"
echo ""
echo -e "${BLUE}============================================${NC}"
