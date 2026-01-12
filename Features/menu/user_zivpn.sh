#!/bin/bash
# ══════════════════════════════════════════════════════
# FILE: user_zivpn.sh
# FUNGSI: INSTALLER + MENU MANAGER ZIVPN (ALL IN ONE)
# CREATED  : PONDOK VPN (C) 2026-01-06
# TELEGRAM : @bendakerep
# EMAIL    : redzall55@gmail.com
# ══════════════════════════════════════════════════════

# ═══( Validasi warna )═══
RED='\033[0;31m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
BLUE='\033[0;94m'
CYAN='\033[0;96m'
PURPLE='\033[0;95m'
ORANGE='\033[38;5;214m'
LIGHT_CYAN='\033[1;96m'
WHITE='\033[1;37m'
NC='\033[0m'

# Paths
CONFIG_DIR="/etc/zivpn"
CONFIG_FILE="$CONFIG_DIR/config.json"
USER_DB="$CONFIG_DIR/users.db"
LOG_FILE="/var/log/zivpn_menu.log"
TELEGRAM_CONF="$CONFIG_DIR/telegram.conf"
BACKUP_DIR="/var/backups/zivpn"
SERVICE_FILE="/etc/systemd/system/zivpn.service"
BINARY_PATH="/usr/local/bin/zivpn-binary"

# ============================================
# FUNGSI INSTALL ZIVPN (TAMBAHAN BARU)
# ============================================

install_zivpn() {
    clear
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${CYAN}        INSTALL ZIVPN UDP TUNNEL         ${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${YELLOW}[1/8] Downloading binary...${NC}"
    
    # Download binary dari zahidbd2
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]] || [[ "$ARCH" == "amd64" ]]; then
        wget -q -O "$BINARY_PATH" "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
    elif [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
        wget -q -O "$BINARY_PATH" "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-arm64"
    else
        echo -e "${RED}❌ Architecture tidak didukung: $ARCH${NC}"
        exit 1
    fi
    
    chmod +x "$BINARY_PATH"
    echo -e "${GREEN}✅ Binary downloaded${NC}"
    
    echo -e "${YELLOW}[2/8] Creating configuration...${NC}"
    mkdir -p "$CONFIG_DIR"
    
    cat > "$CONFIG_FILE" << 'EOF'
{
  "listen": ":5667",
  "cert": "/etc/zivpn/zivpn.crt",
  "key": "/etc/zivpn/zivpn.key",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": ["zivpn123"]
  }
}
EOF
    
    echo -e "${YELLOW}[3/8] Generating SSL certificate...${NC}"
    openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
        -subj "/C=ID/O=ZIVPN/CN=zivpn-server" \
        -keyout "$CONFIG_DIR/zivpn.key" \
        -out "$CONFIG_DIR/zivpn.crt" 2>/dev/null
    
    echo -e "${YELLOW}[4/8] Creating user database...${NC}"
    echo "zivpn123:9999999999:Admin" > "$USER_DB"
    
    echo -e "${YELLOW}[5/8] Creating service...${NC}"
    cat > "$SERVICE_FILE" << 'EOF'
[Unit]
Description=ZIVPN UDP Tunnel Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/zivpn-binary server -c /etc/zivpn/config.json
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    
    echo -e "${YELLOW}[6/8] Opening firewall port...${NC}"
    iptables -I INPUT -p udp --dport 5667 -j ACCEPT 2>/dev/null
    iptables -I INPUT -p udp --dport 6000:19999 -j ACCEPT 2>/dev/null
    
    echo -e "${YELLOW}[7/8] Starting service...${NC}"
    systemctl daemon-reload
    systemctl enable zivpn.service
    systemctl start zivpn.service
    
    sleep 2
    
    echo -e "${YELLOW}[8/8] Setting up menu...${NC}"
    # Copy script ini sebagai menu manager
    cp "$0" /usr/local/bin/zivpn-menu
    chmod +x /usr/local/bin/zivpn-menu
    
    # Buat alias ZIVPN (BUKAN 'menu' biar gak tabrakan)
    if ! grep -q "alias zivpn=" /root/.bashrc; then
        echo "alias zivpn='/usr/local/bin/zivpn-menu'" >> /root/.bashrc
    fi
    
    # Tampilkan info
    IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ ZIVPN INSTALLATION COMPLETE!         ${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}SERVER INFO:${NC}"
    echo -e "  IP Address : $IP"
    echo -e "  Port       : 5667 UDP"
    echo -e "  Password   : zivpn123"
    echo ""
    echo -e "${CYAN}COMMANDS:${NC}"
    echo -e "  ${GREEN}zivpn${NC}      → Open ZIVPN menu"
    echo -e "  ${GREEN}zivpn-menu${NC} → Same as above"
    echo -e "  ${YELLOW}menu${NC}       → For SSH & Xray menu (different!)"
    echo ""
    echo -e "${YELLOW}NOTE: Using port 5667 UDP (no conflict with SSH/Xray)${NC}"
    
    # Auto lanjut ke menu
    echo ""
    echo -e "${YELLOW}Opening ZIVPN menu in 3 seconds...${NC}"
    sleep 3
}

# ============================================
# FUNGSI CEK INSTALLATION
# ============================================

check_installation() {
    # Jika dipanggil dengan argumen 'install'
    if [ "$1" == "install" ]; then
        install_zivpn
        # Lanjut ke menu setelah install
        main_menu
        exit 0
    fi
    
    # Jika ZIVPN belum terinstall, install otomatis
    if [ ! -f "$BINARY_PATH" ] || [ ! -f "$SERVICE_FILE" ]; then
        clear
        echo -e "${YELLOW}════════════════════════════════════════${NC}"
        echo -e "${RED}           ZIVPN NOT INSTALLED             ${NC}"
        echo -e "${YELLOW}════════════════════════════════════════${NC}"
        echo ""
        echo -e "ZIVPN is not installed on this server."
        echo ""
        read -p "Install ZIVPN now? (y/n): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_zivpn
            main_menu
        else
            echo -e "${RED}Installation cancelled.${NC}"
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
}

# ═══( Logging )═══
log_action() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# ═══( install figlet & lolcat )═══
check_and_install_figlet() {
    if ! command -v figlet &> /dev/null; then
        echo -e "${YELLOW}Installing figlet...${NC}"
        apt-get update > /dev/null 2>&1
        apt-get install -y figlet > /dev/null 2>&1
    fi
    
    if ! command -v lolcat &> /dev/null; then
        echo -e "${YELLOW}Installing lolcat...${NC}"
        apt-get install -y lolcat > /dev/null 2>&1
    fi
}

# ═══( Get system info )═══
get_system_info() {
    # IP Address
    IP_ADDRESS=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    # Host dari SSL
    if [ -f "$CONFIG_DIR/zivpn.crt" ]; then
        HOST_NAME=$(openssl x509 -in "$CONFIG_DIR/zivpn.crt" -noout -subject 2>/dev/null | sed -n 's/.*CN = //p')
        if [ "$HOST_NAME" = "zivpn" ] || [ -z "$HOST_NAME" ]; then
            HOST_NAME="$IP_ADDRESS"
        fi
    else
        HOST_NAME="$IP_ADDRESS"
    fi
    
    # OS Info
    OS_INFO=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "Unknown")
    OS_SHORT=$(echo "$OS_INFO" | awk '{print $1}')
    
    # ISP Info
    ISP_INFO=$(curl -s ipinfo.io/org 2>/dev/null | cut -d' ' -f2- | head -1 || echo "Unknown")
    ISP_SHORT=$(echo "$ISP_INFO" | awk '{print $1}')
    
    # RAM Info
    RAM_TOTAL=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "0")
    RAM_USED=$(free -m 2>/dev/null | awk '/^Mem:/{print $3}' || echo "0")
    
    if [ "$RAM_TOTAL" -gt 0 ] 2>/dev/null; then
        RAM_PERCENT=$((RAM_USED * 100 / RAM_TOTAL))
    else
        RAM_PERCENT=0
    fi
    
    RAM_INFO="${RAM_USED}MB/${RAM_TOTAL}MB"
    
    # CPU Info
    CPU_MODEL=$(lscpu 2>/dev/null | grep "Model name" | cut -d: -f2 | sed 's/^[ \t]*//' | head -1 || echo "Unknown")
    CPU_CORES=$(nproc 2>/dev/null || echo "1")
    CPU_INFO="$CPU_CORES cores"
    
    # License Info
    if [ -f "/etc/zivpn/.license_info" ]; then
        LICENSE_USER=$(head -1 /etc/zivpn/.license_info 2>/dev/null || echo "Unknown")
        LICENSE_EXP=$(tail -1 /etc/zivpn/.license_info 2>/dev/null || echo "Unknown")
    else
        LICENSE_USER="Unknown"
        LICENSE_EXP="Unknown"
    fi
    
    # Total Users
    TOTAL_USERS=$(wc -l < "$USER_DB" 2>/dev/null || echo "0")
    
    # Service Status
    if systemctl is-active --quiet zivpn.service; then
        SERVICE_STATUS="${GREEN}Active${NC}"
    else
        SERVICE_STATUS="${RED}stopped${NC}"
    fi
}

# ═══( Display info panel )═══
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

# ═══( Main menu )═══
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

# ═══( Create account )═══
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
    
    # Validasi
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
    
    # Generate expiry date
    expiry_date=$(date -d "+$days days" +"%d %B %Y")
    expiry_timestamp=$(date -d "+$days days" +%s)
    
    # Simpan ke database
    echo "$password:$expiry_timestamp:$client_name" >> "$USER_DB"
    
    # Update config.json
    if [ -f "$CONFIG_FILE" ]; then
        current_config=$(cat "$CONFIG_FILE")
        echo "$current_config" | jq --arg pass "$password" '.auth.config += [$pass]' > "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi
    
    # Restart service
    systemctl restart zivpn.service
    
    # Show success box
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

# ═══( Create trial Account )═══
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
    
    # Generate password
    password="trial$(shuf -i 10000-99999 -n 1)"
    client_name="Trial User"
    
    # Generate expiry date
    expiry_date=$(date -d "+$minutes minutes" +"%d %B %Y %H:%M")
    expiry_timestamp=$(date -d "+$minutes minutes" +%s)
    
    # Simpan ke database
    echo "$password:$expiry_timestamp:$client_name" >> "$USER_DB"
    
    # Update config.json
    if [ -f "$CONFIG_FILE" ]; then
        current_config=$(cat "$CONFIG_FILE")
        echo "$current_config" | jq --arg pass "$password" '.auth.config += [$pass]' > "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi
    
    # Restart service
    systemctl restart zivpn.service
    
    # Show success box
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
    echo -e "${BLUE}║${RED}     ⚠️  PERINGATAN${NC}"
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

# ═══( Renew Account )═══
renew_account() {
    clear
    echo ""
    echo -e "${BLUE}"
    figlet -f small "RENEW AKUN" | lolcat
    echo -e "${NC}"
    
    # Load accounts
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

    # Get selected account
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

    # Calculate new expiry
    new_expiry_timestamp=$((expiry_timestamp + (add_days * 86400)))
    new_expiry_date=$(date -d "@$new_expiry_timestamp" +"%d %B %Y")

    # Update database
    sed -i "${choice}s/$expiry_timestamp/$new_expiry_timestamp/" "$USER_DB"

    echo ""
    echo -e "${GREEN}✅ Akun berhasil di-renew!${NC}"
    echo -e "${WHITE}Password: ${CYAN}$password${NC}"
    echo -e "${WHITE}Expiry baru: ${CYAN}$new_expiry_date${NC}"

    log_action "Renewed account: $password, added $add_days days"

    read -p "Tekan Enter untuk kembali ke menu..."
}

# ═══( Delete Account )═══
delete_account() {
    clear
    echo ""
    echo -e "${BLUE}"
    figlet -f small "HAPUS AKUN" | lolcat
    echo -e "${NC}"
    
    # Load accounts
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
    
    # Display accounts dengan format tabel rapi
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

    # Get selected account
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

    # Remove from database
    sed -i "${choice}d" "$USER_DB"

    # Remove from config.json
    if [ -f "$CONFIG_FILE" ]; then
        current_config=$(cat "$CONFIG_FILE")
        echo "$current_config" | jq --arg pass "$password" 'del(.auth.config[] | select(. == $pass))' > "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi

    # Restart service
    systemctl restart zivpn.service

    echo ""
    echo -e "${GREEN}✅ Akun berhasil dihapus!${NC}"

    log_action "Deleted account: $client_name ($password)"

    read -p "Tekan Enter untuk kembali ke menu..."
}

# ═══( check and delete expired accounts )═══
check_expired_accounts() {
    if [ ! -f "$USER_DB" ] || [ ! -s "$USER_DB" ]; then
        return
    fi
    
    current_timestamp=$(date +%s)
    temp_file=$(mktemp)
    deleted_count=0
    
    while IFS=':' read -r password expiry_timestamp client_name; do
        if [ -n "$password" ] && [ "$expiry_timestamp" -lt "$current_timestamp" ]; then
            # Akun expired, hapus dari config.json
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

# ═══( Cron job delete expired )═══
delete_expired_cron() {
    if [ ! -f "$USER_DB" ] || [ ! -s "$USER_DB" ]; then
        return
    fi
    
    current_timestamp=$(date +%s)
    temp_file=$(mktemp)
    deleted_count=0
    
    while IFS=':' read -r password expiry_timestamp client_name; do
        if [ -n "$password" ] && [ "$expiry_timestamp" -lt "$current_timestamp" ]; then
            # Hapus dari config.json
            if [ -f "$CONFIG_FILE" ]; then
                current_config=$(cat "$CONFIG_FILE")
                echo "$current_config" | jq --arg pass "$password" 'del(.auth.config[] | select(. == $pass))' > "$CONFIG_FILE.tmp"
                mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
            fi
            deleted_count=$((deleted_count + 1))
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cron: Deleted $client_name ($password)" >> "$LOG_FILE"
        else
            echo "$password:$expiry_timestamp:$client_name" >> "$temp_file"
        fi
    done < "$USER_DB"
    
    mv "$temp_file" "$USER_DB"
    
    if [ $deleted_count -gt 0 ]; then
        systemctl restart zivpn.service > /dev/null 2>&1
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cron: Deleted $deleted_count expired accounts" >> "$LOG_FILE"
    fi
}

# ═══( Setup auto delete via cron )═══
auto_delete_setup() {
    echo -e "${YELLOW}Setup auto delete expired accounts...${NC}"
    
    echo -e "${CYAN}Pilihan interval:${NC}"
    echo "1. Setiap jam"
    echo "2. Setiap 6 jam"
    echo "3. Setiap 12 jam"
    echo "4. Setiap hari (00:00)"
    echo "5. Nonaktifkan"
    echo ""
    
    read -p "Pilih interval [1-5]: " interval_choice
    
    # Remove existing cron job
    (crontab -l 2>/dev/null | grep -v "# zivpn-auto-delete") | crontab -
    
    case $interval_choice in
        1)
            (crontab -l 2>/dev/null; echo "0 * * * * /usr/local/bin/zivpn_helper.sh delete_expired # zivpn-auto-delete") | crontab -
            echo -e "${GREEN}✅ Auto delete di-set setiap jam${NC}"
            ;;
        2)
            (crontab -l 2>/dev/null; echo "0 */6 * * * /usr/local/bin/zivpn_helper.sh delete_expired # zivpn-auto-delete") | crontab -
            echo -e "${GREEN}✅ Auto delete di-set setiap 6 jam${NC}"
            ;;
        3)
            (crontab -l 2>/dev/null; echo "0 */12 * * * /usr/local/bin/zivpn_helper.sh delete_expired # zivpn-auto-delete") | crontab -
            echo -e "${GREEN}✅ Auto delete di-set setiap 12 jam${NC}"
            ;;
        4)
            (crontab -l 2>/dev/null; echo "0 0 * * * /usr/local/bin/zivpn_helper.sh delete_expired # zivpn-auto-delete") | crontab -
            echo -e "${GREEN}✅ Auto delete di-set setiap hari jam 00:00${NC}"
            ;;
        5)
            echo -e "${YELLOW}Auto delete dimatikan${NC}"
            ;;
        *)
            echo -e "${RED}Pilihan tidak valid!${NC}"
            ;;
    esac
    
    read -p "Tekan Enter untuk kembali..."
}

# ═══ Restart service )═══
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

# ═══( Check and block multi-login )═══
check_multi_login() {
    # Cek apakah file konfigurasi ada
    if [ ! -f "$CONFIG_FILE" ]; then
        return 0
    fi
    
    # Cek apakah auto-block aktif
    if [ ! -f "$CONFIG_DIR/.auto_block" ]; then
        return 0
    fi
    
    mode=$(cat "$CONFIG_DIR/.auto_block" 2>/dev/null)
    if [ "$mode" != "STRICT" ] && [ "$mode" != "WARNING" ]; then
        return 0
    fi
    
    LOGIN_LOG="$CONFIG_DIR/login.log"
    # Buat file log jika belum ada
    touch "$LOGIN_LOG" 2>/dev/null
    
    # Ambil daftar user aktif dari config.json dengan error handling
    users=$(jq -r '.auth.config[]?' "$CONFIG_FILE" 2>/dev/null)
    if [ -z "$users" ] || [ "$users" = "null" ]; then
        return 0
    fi
    
    blocked_count=0
    
    for user in $users; do
        # Cek di database
        user_info=$(grep "^$user:" "$USER_DB" 2>/dev/null)
        if [ -n "$user_info" ]; then
            IFS=':' read -r password expiry_timestamp client_name <<< "$user_info"
            
            # Cek log login terakhir untuk user ini
            last_log=$(grep "LOGIN:$user:" "$LOGIN_LOG" 2>/dev/null | tail -1)
            
            if [ -n "$last_log" ]; then
                # Ekstrak IP dari log
                last_ip=$(echo "$last_log" | cut -d':' -f4 2>/dev/null)
                current_ip=$(curl -s ifconfig.me 2>/dev/null || echo "UNKNOWN")
                
                # Jika IP berbeda, blokir akun (hanya di STRICT mode)
                if [ "$last_ip" != "$current_ip" ] && [ "$last_ip" != "UNKNOWN" ] && [ "$current_ip" != "UNKNOWN" ]; then
                    if [ "$mode" = "STRICT" ]; then
                        # Hapus user dari config.json
                        current_config=$(cat "$CONFIG_FILE" 2>/dev/null)
                        if [ -n "$current_config" ]; then
                            echo "$current_config" | jq --arg pass "$user" 'del(.auth.config[] | select(. == $pass))' > "$CONFIG_FILE.tmp" 2>/dev/null
                            mv "$CONFIG_FILE.tmp" "$CONFIG_FILE" 2>/dev/null
                        fi
                        
                        # Log aksi blocking
                        echo "[$(date '+%Y-%m-%d %H:%M:%S')] BLOCKED: $client_name ($user) - Multi login. IP: $last_ip -> $current_ip" >> "$LOGIN_LOG"
                        log_action "Blocked multi-login: $client_name ($user)"
                        
                        blocked_count=$((blocked_count + 1))
                        echo "$current_ip:$user:$(date +%s):MULTI_LOGIN" >> "$CONFIG_DIR/blocked.log" 2>/dev/null
                    else
                        # WARNING mode: hanya log
                        echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $client_name ($user) - Multi login. IP: $last_ip -> $current_ip" >> "$LOGIN_LOG"
                    fi
                fi
            fi
            
            # Log login saat ini
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] LOGIN:$user:$(hostname 2>/dev/null):$current_ip:$client_name" >> "$LOGIN_LOG" 2>/dev/null
        fi
    done
    
    if [ $blocked_count -gt 0 ] && [ "$mode" = "STRICT" ]; then
        # Restart service untuk apply blocking
        systemctl restart zivpn.service > /dev/null 2>&1
        log_action "Blocked $blocked_count accounts for multi-login"
    fi
}

# ═══( Setup auto-Block )═══
auto_block_setup() {
    clear
    echo ""
    echo -e "${BLUE}"
    figlet -f digital "AUTO BLOCK" | lolcat
    echo -e "${NC}"
    
    echo -e "${BLUE}╔═══════════════════════════╗${NC}"
    echo -e "${WHITE}    🚫 AUTO BLOCK SETTINGS${NC}"
    echo -e "${BLUE}╚═══════════════════════════╝${NC}"
    
    echo ""
    echo -e "${YELLOW}CATATAN:${NC}"
    echo -e "• ${CYAN}STRICT Mode:${NC} Blokir otomatis jika >1 IP terdeteksi"
    echo -e "• ${CYAN}WARNING Mode:${NC} Hanya log, tidak memblokir"
    echo -e "• ${CYAN}Nonaktifkan:${NC} Tidak ada pengecekan multi-login"
    echo ""
    
    echo -e "${CYAN}Pilih mode auto block:${NC}"
    echo "1. STRICT Mode (Block multi login)"
    echo "2. WARNING Mode (Hanya log)"
    echo "3. Nonaktifkan Auto Block"
    echo ""
    
    read -p "Pilih mode [1-3]: " mode_choice
    
    case $mode_choice in
        1)
            echo "STRICT" > "$CONFIG_DIR/.auto_block"
            echo -e "${GREEN}✅ Strict Mode diaktifkan${NC}"
            echo -e "${YELLOW}Info:${NC} Akan memblokir IP ke-2 dan seterusnya"
            ;;
        2)
            echo "WARNING" > "$CONFIG_DIR/.auto_block"
            echo -e "${GREEN}✅ Warning Mode diaktifkan${NC}"
            echo -e "${YELLOW}Info:${NC} Hanya mencatat log, tidak memblokir"
            ;;
        3)
            rm -f "$CONFIG_DIR/.auto_block"
            echo -e "${YELLOW}❌ Auto Block dinonaktifkan${NC}"
            ;;
        *)
            echo -e "${RED}Pilihan tidak valid!${NC}"
            ;;
    esac
    
    read -p "Tekan Enter untuk kembali..."
}

# ═══( lihat log blocked )═══
view_blocked_log() {
    clear
    echo ""
    echo -e "${BLUE}"
    figlet -f small "BLOCKED LOG" | lolcat
    echo -e "${NC}"
    
    echo -e "${BLUE}╔═════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${WHITE}                  DAFTAR AKUN TERBLOKIR              ${BLUE}║${NC}"
    echo -e "${BLUE}╚═════════════════════════════════════════════════════╝${NC}"
    
    if [ ! -f "$CONFIG_DIR/blocked.log" ] || [ ! -s "$CONFIG_DIR/blocked.log" ]; then
        echo -e "${YELLOW}Tidak ada akun yang diblokir${NC}"
    else
        echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
        echo -e "${WHITE}IP Address       Username         Waktu           Alasan${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
        
        while IFS=':' read -r ip user block_time reason; do
            if [ -n "$ip" ]; then
                block_date=$(date -d "@$block_time" +"%d-%m-%Y %H:%M")
                printf "${RED}%-15s ${CYAN}%-15s ${YELLOW}%-15s ${WHITE}%-20s${NC}\n" "$ip" "$user" "$block_date" "$reason"
            fi
        done < "$CONFIG_DIR/blocked.log"
        
        echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    fi
    
    read -p "Tekan Enter untuk kembali..."
}

# ═══( Telegram setup )═══
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
    
    # Validasi format token
    if [[ ! "$bot_token" =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}Format token salah!${NC}"
        echo -e "${YELLOW}Contoh: 1234567890:ABCdefGHIjklMNopQRSTuvwxyz${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    # Test bot token
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
    
    # Save configuration
    mkdir -p "$CONFIG_DIR"
    echo "TELEGRAM_BOT_TOKEN=${bot_token}" > "$TELEGRAM_CONF"
    echo "TELEGRAM_CHAT_ID=${chat_id}" >> "$TELEGRAM_CONF"
    chmod 600 "$TELEGRAM_CONF"
    
    # Send test message
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

# ═══ Backup/Restore/Features )═══
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
        1)
            backup_data
            ;;
        2)
            restore_data
            ;;
        3)
            auto_backup_setup
            ;;
        4)
            auto_delete_setup
            ;;
        5)
            auto_block_setup
            ;;
        6)
            view_blocked_log
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

# ═══( Backup data )═══
backup_data() {
    echo -e "${YELLOW}Membuat backup...${NC}"
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Create backup file
    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_file="${BACKUP_DIR}/zivpn_backup_${timestamp}.tar.gz"
    
    tar -czf "$backup_file" -C /etc zivpn/ 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Backup berhasil: ${backup_file}${NC}"
    else
        echo -e "${RED}❌ Gagal membuat backup!${NC}"
    fi
    
    read -p "Tekan Enter untuk kembali..."
}

# ═══( Restore data )═══
restore_data() {
    echo -e "${YELLOW}Restoring data...${NC}"
    
    # List available backup
    backups=($(ls -1t "${BACKUP_DIR}/zivpn_backup_"*.tar.gz 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "${RED}Tidak ada backup yang tersedia!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    echo -e "${CYAN}Backup yang tersedia:${NC}"
    for i in "${!backups[@]}"; do
        echo "$((i+1)). $(basename ${backups[$i]})"
    done
    
    echo ""
    read -p "Pilih backup [1-${#backups[@]}]: " choice
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#backups[@]} ]; then
        echo -e "${RED}Pilihan tidak valid!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    backup_file="${backups[$((choice-1))]}"
    
    read -p "Yakin restore dari $(basename $backup_file)? (y/n): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}Dibatalkan!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    # Stop service
    systemctl stop zivpn.service
    
    # Restore
    tar -xzf "$backup_file" -C / 2>/dev/null
    
    # Start service
    systemctl start zivpn.service
    
    echo -e "${GREEN}✅ Restore berhasil!${NC}"
    
    log_action "Restored from backup: $(basename $backup_file)"
    
    read -p "Tekan Enter untuk kembali..."
}

# ═══( Auto backup setup )═══
auto_backup_setup() {
    echo -e "${YELLOW}Setup auto backup...${NC}"
    
    if [ ! -f "$TELEGRAM_CONF" ]; then
        echo -e "${RED}Telegram belum di-setup!${NC}"
        echo -e "${YELLOW}Setup Telegram terlebih dahulu di menu Bot Setting${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    read -p "Interval backup (jam, 0=disable): " interval
    
    if ! [[ "$interval" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Input tidak valid!${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    # Remove existing cron job
    (crontab -l 2>/dev/null | grep -v "# zivpn-auto-backup") | crontab -
    
    if [ "$interval" -gt 0 ]; then
        # Add new cron job
        (crontab -l 2>/dev/null; echo "0 */${interval} * * * /usr/local/bin/zivpn_helper.sh backup # zivpn-auto-backup") | crontab -
        echo -e "${GREEN}✅ Auto backup di-set setiap ${interval} jam${NC}"
    else
        echo -e "${YELLOW}Auto backup dimatikan${NC}"
    fi
    
    read -p "Tekan Enter untuk kembali..."
}

# ============================================
# MAIN MENU FUNCTION
# ============================================

main_menu() {
    while true; do
        check_expired_accounts
        check_multi_login
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

# ============================================
# MAIN PROGRAM
# ============================================

# Cek root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Script harus dijalankan sebagai root!${NC}"
    echo -e "${YELLOW}Gunakan: sudo bash $0${NC}"
    exit 1
fi

# Cek installation
check_installation "$1"

# Lanjut ke menu
main_menu