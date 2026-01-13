#!/bin/bash
# ===========================================
# ZIVPN COMPLETE SCRIPT - INSTALLER + MENU MANAGER
# Github   : https://github.com/Pondok-Vpn/
# Created  : PONDOK VPN (C) 2026-01-06
# Telegram : @bendakerep
# Email    : redzall55@gmail.com
# ===========================================

# == VALIDASI WARNA ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;95m'
ORANGE='\033[38;5;214m'
LIGHT_CYAN='\033[1;96m'
WHITE='\033[1;37m'
NC='\033[0m'

# Variables
CONFIG_DIR="/etc/zivpn"
CONFIG_FILE="$CONFIG_DIR/config.json"
USER_DB="$CONFIG_DIR/users.db"
LOG_FILE="/var/log/zivpn_menu.log"
TELEGRAM_CONF="$CONFIG_DIR/telegram.conf"
BACKUP_DIR="/var/backups/zivpn"
SERVICE_FILE="/etc/systemd/system/zivpn.service"
BINARY_PATH="/usr/local/bin/zivpn"
MENU_SCRIPT="/usr/local/bin/zivpn-menu"

# ===========================================
#           INSTALLER FUNCTIONS
# ===========================================

log() {
    echo -e "[$(date '+%H:%M:%S')] $1"
}

show_banner() {
    clear
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}        ZIVPN COMPLETE SCRIPT          ${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
}

check_license() {
    log "${YELLOW}Checking license...${NC}"
    
    # Get server IP
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    log "${CYAN}Server IP: $SERVER_IP${NC}"
    
    # Skip license check if argument --no-license
    if [ "$1" == "--no-license" ]; then
        echo -e "${YELLOW}⚠️  License check skipped${NC}"
        return 0
    fi
    
    LICENSE_URL="https://raw.githubusercontent.com/Pondok-Vpn/Pondok-Vpn/main/DAFTAR"
    LICENSE_FILE=$(mktemp)
    
    if curl -s "$LICENSE_URL" -o "$LICENSE_FILE" 2>/dev/null; then
        if grep -q "^$SERVER_IP" "$LICENSE_FILE"; then
            LICENSE_INFO=$(grep "^$SERVER_IP" "$LICENSE_FILE")
            USER_NAME=$(echo "$LICENSE_INFO" | awk '{print $2}')
            EXPIRY_DATE=$(echo "$LICENSE_INFO" | awk '{print $3}')
            
            CURRENT_DATE=$(date +%Y-%m-%d)
            if [[ "$CURRENT_DATE" > "$EXPIRY_DATE" ]]; then
                echo -e "${RED}========================================${NC}"
                echo -e "${RED}           LICENSE EXPIRED!            ${NC}"
                echo -e "${RED}========================================${NC}"
                rm -f "$LICENSE_FILE"
                exit 1
            fi
            
            echo -e "${GREEN}✓ License valid for: $USER_NAME${NC}"
            echo -e "${CYAN}✓ Expiry date: $EXPIRY_DATE${NC}"
            
            mkdir -p /etc/zivpn
            echo "$USER_NAME" > /etc/zivpn/.license_info
            echo "$EXPIRY_DATE" >> /etc/zivpn/.license_info
            
        else
            echo -e "${YELLOW}⚠️  IP not registered, running in trial mode${NC}"
        fi
        
        rm -f "$LICENSE_FILE"
    else
        echo -e "${YELLOW}⚠️  Cannot connect to license server${NC}"
        echo -e "${YELLOW}Running in evaluation mode...${NC}"
    fi
    
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Script must be run as root!${NC}"
        echo -e "${YELLOW}Use: sudo bash $0${NC}"
        exit 1
    fi
}

setup_swap() {
    log "${YELLOW}Setting up swap for 1GB RAM...${NC}"
    
    if ! swapon --show | grep -q "/swapfile"; then
        fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        echo "vm.swappiness=30" >> /etc/sysctl.conf
        sysctl -p
        
        echo -e "${GREEN}✓ 2GB swap created${NC}"
    else
        echo -e "${GREEN}✓ Swap already exists${NC}"
    fi
    echo ""
}

install_deps() {
    log "${YELLOW}Installing minimal dependencies...${NC}"
    pkill apt 2>/dev/null || true
    pkill dpkg 2>/dev/null || true
    apt-get update -y
    apt-get upgrade -y
    apt-get install -y wget curl openssl net-tools iptables jq figlet lolcat
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}   ✅ Dependencies installed${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
}

download_binary() {
    log "${YELLOW}Detecting architecture...${NC}"
    
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]] || [[ "$ARCH" == "amd64" ]]; then
        BINARY_NAME="udp-zivpn-linux-amd64"
        log "${GREEN}Architecture: AMD64${NC}"
    elif [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
        BINARY_NAME="udp-zivpn-linux-arm64"
        log "${GREEN}Architecture: ARM64${NC}"
    else
        log "${RED}Unsupported architecture: $ARCH${NC}"
        exit 1
    fi
    
    log "${YELLOW}Downloading ZIVPN binary...${NC}"
    
    # Try multiple sources
    SOURCES=(
        "https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/$BINARY_NAME"
        "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/$BINARY_NAME"
        "https://cdn.jsdelivr.net/gh/zahidbd2/udp-zivpn@latest/$BINARY_NAME"
    )
    
    for url in "${SOURCES[@]}"; do
        log "${CYAN}Trying: $(echo $url | cut -d'/' -f3)...${NC}"
        
        if wget --timeout=30 -q "$url" -O /usr/local/bin/zivpn; then
            if [ -f /usr/local/bin/zivpn ]; then
                FILE_SIZE=$(stat -c%s /usr/local/bin/zivpn 2>/dev/null || echo 0)
                if [ $FILE_SIZE -gt 1000000 ]; then
                    chmod +x /usr/local/bin/zivpn
                    echo -e "${GREEN}✓ Binary downloaded ($((FILE_SIZE/1024/1024))MB)${NC}"
                    return 0
                fi
            fi
        fi
        rm -f /usr/local/bin/zivpn 2>/dev/null
    done
    
    # ALL FAILED - STOP INSTALLATION
    log "${RED}❌ FATAL: Cannot download binary!${NC}"
    echo ""
    echo -e "${YELLOW}Please download manually:${NC}"
    echo "----------------------------------------"
    echo "cd /usr/local/bin"
    if [[ "$ARCH" == "x86_64" ]] || [[ "$ARCH" == "amd64" ]]; then
        echo "wget https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/udp-zivpn-linux-amd64 -O zivpn"
    else
        echo "wget https://raw.githubusercontent.com/Pondok-Vpn/udp-ziv/main/udp-zivpn-linux-arm64 -O zivpn"
    fi
    echo "chmod +x zivpn"
    echo "systemctl restart zivpn"
    echo "----------------------------------------"
    exit 1
}

setup_config() {
    log "${YELLOW}Creating configuration...${NC}"
    
    mkdir -p "$CONFIG_DIR"
    
    IP_ADDRESS=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
        -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=$IP_ADDRESS" \
        -keyout "$CONFIG_DIR/zivpn.key" \
        -out "$CONFIG_DIR/zivpn.crt"
    
    cat > "$CONFIG_FILE" << 'EOF'
{
  "listen": "0.0.0.0:5667",
  "cert": "/etc/zivpn/zivpn.crt",
  "key": "/etc/zivpn/zivpn.key",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": ["zivpn123"]
  }
}
EOF
    
    echo "zivpn123:9999999999:PONDOKVPN" > "$USER_DB"
    touch "$CONFIG_DIR/devices.db"
    touch "$CONFIG_DIR/locked.db"
    
    sysctl -w net.core.rmem_max=16777216
    sysctl -w net.core.wmem_max=16777216
    
    echo -e "${GREEN}✓ Configuration created${NC}"
    echo ""
}

create_service() {
    log "${YELLOW}Creating systemd service...${NC}"
    
    cat > "$SERVICE_FILE" << 'EOF'
[Unit]
Description=zivpn VPN Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable zivpn.service
    
    echo -e "${GREEN}✓ Service created${NC}"
    echo ""
}

setup_firewall() {
    log "${YELLOW}Setting up firewall...${NC}"
    
    iptables -I INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null || true
    iptables -I INPUT -p tcp --dport 5667 -j ACCEPT 2>/dev/null || true
    
    echo -e "${GREEN}✓ Firewall configured${NC}"
    echo ""
}

start_service() {
    log "${YELLOW}Starting ZIVPN service...${NC}"
    
    systemctl start zivpn.service
    sleep 3
    
    if systemctl is-active --quiet zivpn.service; then
        echo -e "${GREEN}✅ Service: RUNNING${NC}"
    else
        echo -e "${RED}❌ Service: FAILED${NC}"
        return 1
    fi
    
    if ss -tulpn | grep -q ":5667"; then
        echo -e "${GREEN}✅ Port 5667: LISTENING${NC}"
    else
        echo -e "${RED}❌ Port 5667: NOT LISTENING${NC}"
    fi
    
    echo ""
}

install_zivpn() {
    show_banner
    check_root
    check_license "$1"
    setup_swap
    install_deps
    download_binary
    setup_config
    create_service
    setup_firewall
    
    if ! start_service; then
        echo -e "${RED}Service failed to start! Check logs above.${NC}"
        echo ""
    fi
    
    # Copy this script as menu manager
    cp "$0" "$MENU_SCRIPT"
    chmod +x "$MENU_SCRIPT"
    
    if ! grep -q "alias zivpn=" /root/.bashrc; then
        echo "alias zivpn='$MENU_SCRIPT'" >> /root/.bashrc
    fi
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}    ✅  ZIVPN INSTALLATION COMPLETE!  ${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    echo ""
    echo -e "${YELLOW}📦 SERVER INFORMATION:${NC}"
    echo -e "  IP Address  : $SERVER_IP"
    echo -e "  Port        : 5667 UDP"
    echo -e "  Password    : zivpn123"
    echo ""
    echo -e "${YELLOW}🚀 QUICK COMMANDS:${NC}"
    echo -e "  Check status : ${GREEN}systemctl status zivpn${NC}"
    echo -e "  Restart      : ${GREEN}systemctl restart zivpn${NC}"
    echo -e "  Open menu    : ${GREEN}zivpn${NC} or ${GREEN}$MENU_SCRIPT${NC}"
    echo ""
    
    sleep 3
    
    # Auto open menu if not batch mode
    if [ "$1" != "--batch" ]; then
        echo -e "${YELLOW}Opening menu in 3 seconds...${NC}"
        sleep 3
        show_menu_manager
    fi
}

# ===========================================
#           MENU MANAGER FUNCTIONS
# ===========================================

log_action() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

check_and_install_figlet() {
    if ! command -v figlet &> /dev/null; then
        apt-get install -y figlet > /dev/null 2>&1
    fi
    
    if ! command -v lolcat &> /dev/null; then
        apt-get install -y lolcat > /dev/null 2>&1
    fi
}

get_system_info() {
    IP_ADDRESS=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    if [ -f "$CONFIG_DIR/zivpn.crt" ]; then
        HOST_NAME=$(openssl x509 -in "$CONFIG_DIR/zivpn.crt" -noout -subject 2>/dev/null | sed -n 's/.*CN = //p')
        if [ "$HOST_NAME" = "zivpn" ] || [ -z "$HOST_NAME" ]; then
            HOST_NAME="$IP_ADDRESS"
        fi
    else
        HOST_NAME="$IP_ADDRESS"
    fi
    
    OS_INFO=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "Unknown")
    OS_SHORT=$(echo "$OS_INFO" | awk '{print $1}')
    
    ISP_INFO=$(curl -s ipinfo.io/org 2>/dev/null | cut -d' ' -f2- | head -1 || echo "Unknown")
    ISP_SHORT=$(echo "$ISP_INFO" | awk '{print $1}')
    
    RAM_TOTAL=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "0")
    RAM_USED=$(free -m 2>/dev/null | awk '/^Mem:/{print $3}' || echo "0")
    
    if [ "$RAM_TOTAL" -gt 0 ] 2>/dev/null; then
        RAM_PERCENT=$((RAM_USED * 100 / RAM_TOTAL))
    else
        RAM_PERCENT=0
    fi
    
    RAM_INFO="${RAM_USED}MB/${RAM_TOTAL}MB"
    
    CPU_CORES=$(nproc 2>/dev/null || echo "1")
    CPU_INFO="$CPU_CORES cores"
    
    if [ -f "/etc/zivpn/.license_info" ]; then
        LICENSE_USER=$(head -1 /etc/zivpn/.license_info 2>/dev/null || echo "Unknown")
        LICENSE_EXP=$(tail -1 /etc/zivpn/.license_info 2>/dev/null || echo "Unknown")
    else
        LICENSE_USER="Unknown"
        LICENSE_EXP="Unknown"
    fi
    
    TOTAL_USERS=$(wc -l < "$USER_DB" 2>/dev/null || echo "0")
    
    if systemctl is-active --quiet zivpn.service; then
        SERVICE_STATUS="${GREEN}Active${NC}"
    else
        SERVICE_STATUS="${RED}stopped${NC}"
    fi
}

show_info_panel() {
    get_system_info
    
    clear
    
    check_and_install_figlet
    echo ""
    echo -e "${BLUE}"
    figlet -f small "PONDOK - VPN" | lolcat
    echo -e "${NC}"
    echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${WHITE}  IP VPS : ${CYAN}$(printf '%-15s' "$IP_ADDRESS")${WHITE}        HOST : ${CYAN}$(printf '%-20s' "$HOST_NAME")${NC}"
    echo -e "${BLUE}║${WHITE}  OS     : ${CYAN}$(printf '%-15s' "$OS_SHORT")${WHITE}        EXP  : ${CYAN}$(printf '%-20s' "$LICENSE_EXP")${NC}"
    echo -e "${BLUE}║${WHITE}  ISP    : ${CYAN}$(printf '%-15s' "$ISP_SHORT")${WHITE}        RAM  : ${CYAN}$(printf '%-20s' "$RAM_INFO")${NC}"
    echo -e "${BLUE}║${WHITE}  CPU    : ${CYAN}$(printf '%-15s' "$CPU_INFO")${WHITE}        USER : ${CYAN}$(printf '%-20s' "$TOTAL_USERS")${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
    echo -e "                    ${WHITE}Status : ${SERVICE_STATUS}${NC}"
}

show_main_menu() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                    ║${NC}"
    echo -e "${BLUE}║${ORANGE} ◉ 1.${CYAN} BUAT AKUN ZIVPN${ORANGE}           ◉ 5.${CYAN} BOT SETTING${WHITE}    ${BLUE}║${NC}"
    echo -e "${BLUE}║                                                    ║${NC}"
    echo -e "${BLUE}║${ORANGE} ◉ 2.${CYAN} BUAT AKUN TRIAL${ORANGE}           ◉ 6.${CYAN} FEATURES${WHITE}       ${BLUE}║${NC}"
    echo -e "${BLUE}║                                                    ║${NC}"
    echo -e "${BLUE}║${ORANGE} ◉ 3.${CYAN} RENEW AKUN${ORANGE}                ◉ 7.${CYAN} HAPUS AKUN${WHITE}     ${BLUE}║${NC}"
    echo -e "${BLUE}║                                                    ║${NC}"
    echo -e "${BLUE}║${ORANGE} ◉ 4.${CYAN} RESTART SERVIS${ORANGE}            ◉ 0.${CYAN} EXIT${WHITE}           ${BLUE}║${NC}"
    echo -e "${BLUE}║                                                    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
}

create_account() {
    clear
    echo ""
    echo -e "${BLUE}"
    figlet -f digital "CREATE ACCOUNT" | lolcat
    echo -e "${NC}"
    
    echo -e "${BLUE}╔═══════════════════════════╗${NC}"
    echo -e "${WHITE}    📝 BUAT AKUN ZIVPN${NC}"
    echo -e "${BLUE}╚═══════════════════════════╝${NC}"
    
    echo ""
    read -p "Masukkan nama client: " client_name
    read -p "Masukkan password (min 6 karakter): " password
    read -p "Masukkan masa aktif (hari): " days
    
    if [ -z "$client_name" ] || [ -z "$password" ] || [ -z "$days" ]; then
        echo -e "${RED}Error: Semua field harus diisi!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    if [ ${#password} -lt 6 ]; then
        echo -e "${RED}Error: Password minimal 6 karakter!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Masa aktif harus angka!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    expiry_date=$(date -d "+$days days" +"%d %B %Y")
    expiry_timestamp=$(date -d "+$days days" +%s)
    
    echo "$password:$expiry_timestamp:$client_name" >> "$USER_DB"
    
    if [ -f "$CONFIG_FILE" ]; then
        current_config=$(cat "$CONFIG_FILE")
        echo "$current_config" | jq --arg pass "$password" '.auth.config += [$pass]' > "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi
    
    systemctl restart zivpn.service
    
    clear
    echo ""
    echo -e "${BLUE}"
    figlet -f small "SUCCESS" | lolcat
    echo -e "${NC}"
    
    echo -e "${BLUE}╔═════════════════════════╗${NC}"
    echo -e "${BLUE}║${WHITE} ✅ AKUN BERHASIL DIBUAT${NC}"
    echo -e "${BLUE}╠═════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC}"
    echo -e "${BLUE}║ ${WHITE} Nama client : ${CYAN}$client_name${WHITE}"
    echo -e "${BLUE}║${NC}"
    echo -e "${BLUE}║ ${WHITE} IP/Host     : ${CYAN}$HOST_NAME${WHITE}"
    echo -e "${BLUE}║${NC}"
    echo -e "${BLUE}║ ${WHITE} Password    : ${CYAN}$password${WHITE}"
    echo -e "${BLUE}║${NC}"
    echo -e "${BLUE}║ ${WHITE} Expiry Date : ${CYAN}$expiry_date${WHITE}"
    echo -e "${BLUE}║${NC}"
    echo -e "${BLUE}║ ${WHITE} Limit Device: ${CYAN}1 device${WHITE}"
    echo -e "${BLUE}║${NC}"
    echo -e "${BLUE}╠═════════════════════════╣${NC}"
    echo -e "${BLUE}║${RED}     ⚠️  PERINGATAN${NC}"
    echo -e "${BLUE}║${WHITE} Akun akan otomatis di-Band${NC}"
    echo -e "${BLUE}║${WHITE} jika IP melebihi ketentuan${NC}"
    echo -e "${BLUE}╠═════════════════════════╣${NC}"
    echo -e "${BLUE}║${WHITE} Terima kasih sudah order!${NC}"
    echo -e "${BLUE}║${WHITE} Bot: @bendakerep${NC}"
    echo -e "${BLUE}╚═════════════════════════╝${NC}"
    
    log_action "Created account: $client_name, expires: $expiry_date"
    
    echo ""
    read -p "Tekan Enter untuk kembali ke menu..."
}

create_trial_account() {
    clear
    echo ""
    echo -e "${BLUE}"
    figlet -f digital "TRIAL ACCOUNT" | lolcat
    echo -e "${NC}"
    
    echo -e "${BLUE}╔═══════════════════════════╗${NC}"
    echo -e "${WHITE}    🆓 BUAT AKUN TRIAL${NC}"
    echo -e "${BLUE}╚═══════════════════════════╝${NC}"
    
    echo ""
    read -p "Masukkan masa aktif (menit): " minutes
    
    if ! [[ "$minutes" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Masa aktif harus angka!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    password="trial$(shuf -i 10000-99999 -n 1)"
    client_name="Trial User"
    
    expiry_date=$(date -d "+$minutes minutes" +"%d %B %Y %H:%M")
    expiry_timestamp=$(date -d "+$minutes minutes" +%s)
    
    echo "$password:$expiry_timestamp:$client_name" >> "$USER_DB"
    
    if [ -f "$CONFIG_FILE" ]; then
        current_config=$(cat "$CONFIG_FILE")
        echo "$current_config" | jq --arg pass "$password" '.auth.config += [$pass]' > "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi
    
    systemctl restart zivpn.service
    
    clear
    echo ""
    echo -e "${BLUE}"
    figlet -f small "SUCCESS" | lolcat
    echo -e "${NC}"
    
    echo -e "${BLUE}╔═════════════════════════╗${NC}"
    echo -e "${BLUE}║${WHITE}✅ TRIAL BERHASIL DIBUAT${NC}"
    echo -e "${BLUE}╠═════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC}"
    echo -e "${BLUE}║ ${WHITE} Nama client : ${CYAN}$client_name${WHITE}"
    echo -e "${BLUE}║${NC}"
    echo -e "${BLUE}║ ${WHITE} IP/Host     : ${CYAN}$HOST_NAME${WHITE}"
    echo -e "${BLUE}║${NC}"
    echo -e "${BLUE}║ ${WHITE} Password    : ${CYAN}$password${WHITE}"
    echo -e "${BLUE}║${NC}"
    echo -e "${BLUE}║ ${WHITE} Expiry Date : ${CYAN}$expiry_date${WHITE}"
    echo -e "${BLUE}║${NC}"
    echo -e "${BLUE}║ ${WHITE} Limit Device: ${CYAN}1 device${WHITE}"
    echo -e "${BLUE}║${NC}"
    echo -e "${BLUE}╠═════════════════════════╣${NC}"
    echo -e "${BLue}║${RED}     ⚠️  PERINGATAN${NC}"
    echo -e "${BLUE}║${WHITE} Akun akan otomatis di-Band${NC}"
    echo -e "${BLUE}║${WHITE} jika IP melebihi ketentuan${NC}"
    echo -e "${BLUE}╠═════════════════════════╣${NC}"
    echo -e "${BLUE}║${WHITE} Terima kasih sudah order!${NC}"
    echo -e "${BLUE}║${WHITE} Bot: @bendakerep${NC}"
    echo -e "${BLUE}╚═════════════════════════╝${NC}"
    
    log_action "Created trial account: $password, expires: $expiry_date"
    
    echo ""
    read -p "Tekan Enter untuk kembali ke menu..."
}

renew_account() {
    clear
    echo ""
    echo -e "${BLUE}"
    figlet -f small "RENEW AKUN" | lolcat
    echo -e "${NC}"
    
    if [ ! -f "$USER_DB" ] || [ ! -s "$USER_DB" ]; then
        echo -e "${RED}Tidak ada akun yang tersedia!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    echo -e "${BLUE}╔═════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${WHITE}                      RENEW AKUN                     ${BLUE}║${NC}"
    echo -e "${BLUE}╚═════════════════════════════════════════════════════╝${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}No.   Nama Client           Password          Expired${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    
    count=1
    while IFS=':' read -r password expiry_timestamp client_name; do
        if [ -n "$password" ]; then
            expiry_date=$(date -d "@$expiry_timestamp" +"%m-%d-%Y")
            printf "${WHITE}%-4s  ${CYAN}%-20s${WHITE}  %-15s  %-10s${NC}\n" "$count." "$client_name" "$password" "$expiry_date"
            count=$((count + 1))
        fi
    done < "$USER_DB"
    
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""
    read -p "Pilih nomor untuk renew akun: " choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Pilihan tidak valid!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi

    selected_line=$(sed -n "${choice}p" "$USER_DB")
    if [ -z "$selected_line" ]; then
        echo -e "${RED}Akun tidak ditemukan!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi

    IFS=':' read -r password expiry_timestamp client_name <<< "$selected_line"

    echo ""
    read -p "Masukkan tambahan hari: " add_days

    if ! [[ "$add_days" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Hari harus angka!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi

    new_expiry_timestamp=$((expiry_timestamp + (add_days * 86400)))
    new_expiry_date=$(date -d "@$new_expiry_timestamp" +"%d %B %Y")

    sed -i "${choice}s/$expiry_timestamp/$new_expiry_timestamp/" "$USER_DB"

    echo ""
    echo -e "${GREEN}✅ Akun berhasil di-renew!${NC}"
    echo -e "${WHITE}Password: ${CYAN}$password${NC}"
    echo -e "${WHITE}Expiry baru: ${CYAN}$new_expiry_date${NC}"

    log_action "Renewed account: $password, added $add_days days"

    read -p "Tekan Enter untuk kembali ke menu..."
}

delete_account() {
    clear
    echo ""
    echo -e "${BLUE}"
    figlet -f small "HAPUS AKUN" | lolcat
    echo -e "${NC}"
    
    if [ ! -f "$USER_DB" ] || [ ! -s "$USER_DB" ]; then
        echo -e "${RED}Tidak ada akun yang tersedia!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    echo -e "${BLUE}╔═════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${WHITE}                      HAPUS AKUN                     ${BLUE}║${NC}"
    echo -e "${BLUE}╚═════════════════════════════════════════════════════╝${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}No.   Nama Client           Password          Expired${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    
    count=1
    while IFS=':' read -r password expiry_timestamp client_name; do
        if [ -n "$password" ]; then
            expiry_date=$(date -d "@$expiry_timestamp" +"%m-%d-%Y")
            printf "${WHITE}%-4s  ${CYAN}%-20s${WHITE}  %-15s  %-10s${NC}\n" "$count." "$client_name" "$password" "$expiry_date"
            count=$((count + 1))
        fi
    done < "$USER_DB"
    
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""
    read -p "Pilih nomor untuk hapus akun: " choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Pilihan tidak valid!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi

    selected_line=$(sed -n "${choice}p" "$USER_DB")
    if [ -z "$selected_line" ]; then
        echo -e "${RED}Akun tidak ditemukan!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi

    IFS=':' read -r password expiry_timestamp client_name <<< "$selected_line"

    echo ""
    read -p "Yakin hapus akun $client_name? (y/n): " confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}Dibatalkan!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi

    sed -i "${choice}d" "$USER_DB"

    if [ -f "$CONFIG_FILE" ]; then
        current_config=$(cat "$CONFIG_FILE")
        echo "$current_config" | jq --arg pass "$password" 'del(.auth.config[] | select(. == $pass))' > "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi

    systemctl restart zivpn.service

    echo ""
    echo -e "${GREEN}✅ Akun berhasil dihapus!${NC}"

    log_action "Deleted account: $client_name ($password)"

    read -p "Tekan Enter untuk kembali ke menu..."
}

check_expired_accounts() {
    if [ ! -f "$USER_DB" ] || [ ! -s "$USER_DB" ]; then
        return
    fi
    
    current_timestamp=$(date +%s)
    temp_file=$(mktemp)
    deleted_count=0
    
    while IFS=':' read -r password expiry_timestamp client_name; do
        if [ -n "$password" ] && [ "$expiry_timestamp" -lt "$current_timestamp" ]; then
            if [ -f "$CONFIG_FILE" ]; then
                current_config=$(cat "$CONFIG_FILE")
                echo "$current_config" | jq --arg pass "$password" 'del(.auth.config[] | select(. == $pass))' > "$CONFIG_FILE.tmp"
                mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
            fi
            deleted_count=$((deleted_count + 1))
            log_action "Auto-deleted expired account: $client_name ($password)"
        else
            echo "$password:$expiry_timestamp:$client_name" >> "$temp_file"
        fi
    done < "$USER_DB"
    
    mv "$temp_file" "$USER_DB"
    
    if [ $deleted_count -gt 0 ]; then
        systemctl restart zivpn.service > /dev/null 2>&1
        log_action "Auto-deleted $deleted_count expired accounts"
    fi
}

restart_service() {
    clear
    echo ""
    echo -e "${BLUE}"
    figlet -f small "RESTART" | lolcat
    echo -e "${NC}"
    
    echo -e "${YELLOW}Restarting ZIVPN service...${NC}"
    systemctl restart zivpn.service
    
    sleep 2
    
    if systemctl is-active --quiet zivpn.service; then
        echo -e "${GREEN}✅ Service berhasil di-restart!${NC}"
    else
        echo -e "${RED}❌ Gagal restart service!${NC}"
    fi
    
    log_action "Restarted ZIVPN service"
    
    read -p "Tekan Enter untuk kembali ke menu..."
}

bot_setting() {
    clear
    echo ""
    echo -e "${BLUE}"
    figlet -f digital "_BOT SETTING" | lolcat
    echo -e "${NC}"
    
    echo -e "${BLUE}╔═══════════════════════════╗${NC}"
    echo -e "${WHITE}    🤖 TELEGRAM BOT SETUP${NC}"
    echo -e "${BLUE}╚═══════════════════════════╝${NC}"
    
    echo ""
    echo -e "${CYAN}Instruksi:${NC}"
    echo "1. Buat bot via @BotFather"
    echo "2. Dapatkan bot token"
    echo "3. Dapatkan chat ID dari @userinfobot"
    echo ""
    
    read -p "Masukkan Bot Token: " bot_token
    read -p "Masukkan Chat ID  : " chat_id
    
    if [ -z "$bot_token" ] || [ -z "$chat_id" ]; then
        echo -e "${RED}Token dan Chat ID tidak boleh kosong!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    if [[ ! "$bot_token" =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}Format token salah!${NC}"
        echo -e "${YELLOW}Contoh: 1234567890:ABCdefGHIjklMNopQRSTuvwxyz${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    echo -e "${YELLOW}Testing bot token...${NC}"
    response=$(curl -s "https://api.telegram.org/bot${bot_token}/getMe")
    
    if echo "$response" | grep -q '"ok":true'; then
        bot_name=$(echo "$response" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
        echo -e "${GREEN}✅ Bot ditemukan: @${bot_name}${NC}"
    else
        echo -e "${RED}❌ Token bot tidak valid!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    mkdir -p "$CONFIG_DIR"
    echo "TELEGRAM_BOT_TOKEN=${bot_token}" > "$TELEGRAM_CONF"
    echo "TELEGRAM_CHAT_ID=${chat_id}" >> "$TELEGRAM_CONF"
    chmod 600 "$TELEGRAM_CONF"
    
    echo -e "${YELLOW}Mengirim pesan test...${NC}"
    
    message="✅ ZIVPN Telegram Bot Connected!
📅 $(date '+%Y-%m-%d %H:%M:%S')
🤖 Bot: @${bot_name}
📱 Ready to receive notifications!"
    
    curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
        -d "chat_id=${chat_id}" \
        --data-urlencode "text=${message}" \
        -d "parse_mode=Markdown" > /dev/null
    
    echo -e "${GREEN}✅ Telegram bot berhasil di-setup!${NC}"
    
    log_action "Telegram bot setup completed"
    
    read -p "Tekan Enter untuk kembali ke menu..."
}

backup_restore() {
    clear
    echo ""
    echo -e "${BLUE}"
    figlet -f digital "FEATURES MENU" | lolcat
    echo -e "${NC}"
    
    echo -e "${BLUE}╔═══════════════════════════╗${NC}"
    echo -e "${WHITE}    💾 MANAGEMENT SUB MENU${NC}"
    echo -e "${BLUE}╚═══════════════════════════╝${NC}"
    echo -e "${BLUE}╔═══════════════════════════╗${NC}"
    echo ""
    echo -e "${WHITE}  1)${CYAN}   BACKUP DATA${NC}"
    echo -e "${WHITE}  2)${CYAN}   RESTORE DATA${NC}"
    echo -e "${WHITE}  3)${CYAN}   AUTO BACKUP SETUP${NC}"
    echo -e "${WHITE}  4)${CYAN}   AUTO DELETE SETUP${NC}"
    echo -e "${WHITE}  5)${CYAN}   AUTO BLOCK SETUP${NC}"
    echo -e "${WHITE}  6)${CYAN}   VIEW BLOCKED LOG${NC}"
    echo -e "${WHITE}  0)${CYAN}   BACK TO MAIN MENU${NC}"
    echo ""
    echo -e "${BLUE}╚═══════════════════════════╝${NC}"
    read -p "Pilih menu [0-6]: " choice
    
    case $choice in
        1|2|3|4|5|6)
            echo -e "${YELLOW}Feature coming soon...${NC}"
            read -p "Press Enter..."
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}Pilihan tidak valid!${NC}"
            read -p "Tekan Enter untuk kembali..."
            ;;
    esac
}

show_menu_manager() {
    # Cek jika ZIVPN sudah terinstall
    if [ ! -f "$BINARY_PATH" ] || [ ! -f "$SERVICE_FILE" ]; then
        echo -e "${RED}ZIVPN belum terinstall!${NC}"
        echo ""
        read -p "Install ZIVPN sekarang? (y/n): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_zivpn "$1"
        else
            exit 0
        fi
    fi
    
    # Cek service status
    if ! systemctl is-active --quiet zivpn.service 2>/dev/null; then
        echo -e "${YELLOW}⚠️  ZIVPN service is not running${NC}"
        read -p "Start service now? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            systemctl start zivpn.service
            sleep 2
        fi
    fi
    
    # Main menu loop
    while true; do
        check_expired_accounts
        show_info_panel
        show_main_menu
        echo ""
        read -p "Pilih menu (0-7): " choice
        case $choice in
            1)
                create_account
                ;;
            2)
                create_trial_account
                ;;
            3)
                renew_account
                ;;
            4)
                restart_service
                ;;
            5)
                bot_setting
                ;;
            6)
                backup_restore
                ;;
            7)
                delete_account
                ;;
            0)
                clear
                echo ""
                figlet -f small "PONDOK VPN" | lolcat
                echo -e "${CYAN}YA ALLAH AMPUNILAH DOSAKU${NC}"
                echo -e "${WHITE}Telegram: @bendakerep${NC}"
                echo ""
                exit 0
                ;;
            *)
                echo -e "${RED}Pilihan tidak valid!${NC}"
                sleep 1
                ;;
        esac
    done
}

# ===========================================
#               MAIN PROGRAM
# ===========================================

# Cek root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Script must be run as root!${NC}"
    echo -e "${YELLOW}Use: sudo bash $0${NC}"
    exit 1
fi

# Handle arguments
case "$1" in
    "install"|"--install")
        install_zivpn "$2"
        ;;
    "menu"|"--menu")
        show_menu_manager
        ;;
    *)
        # Auto detect: jika belum install, tawarkan install
        if [ ! -f "$BINARY_PATH" ] || [ ! -f "$SERVICE_FILE" ]; then
            echo -e "${YELLOW}ZIVPN not detected!${NC}"
            read -p "Run installer now? (y/n): " -n 1 -r
            echo
            
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                install_zivpn
            else
                echo "Exiting..."
                exit 0
            fi
        else
            show_menu_manager
        fi
        ;;
esac
