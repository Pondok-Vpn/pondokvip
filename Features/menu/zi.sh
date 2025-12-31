#!/bin/bash
# Zivpn UDP Module Manager
# Modified by: PONDOK VPN
# Contact: 082147725445
# Telegram: @bendakerep
# redzall55@gmail.com

# --- UI Definitions ---
PINK='\033[0;95m'
PURPLE='\033[0;35m'
MAGENTA='\033[0;95m'
CYAN='\033[0;96m'
LIGHT_CYAN='\033[1;96m'
LIGHT_GREEN='\033[1;92m'
LIGHT_BLUE='\033[1;94m'
LIGHT_YELLOW='\033[1;93m'
LIGHT_RED='\033[1;91m'
YELLOW='\033[0;93m'
RED='\033[0;91m'
GREEN='\033[0;92m'
BLUE='\033[0;94m'
WHITE='\033[1;97m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

# --- License Info ---
LICENSE_URL="https://raw.githubusercontent.com/Pondok-Vpn/pondokvip/main/register"
LICENSE_INFO_FILE="/etc/zivpn/.license_info"

# --- User Database with Device Limit ---
USER_DB="/etc/zivpn/users.db"
DEVICE_DB="/etc/zivpn/devices.db"
CONFIG_JSON="/etc/zivpn/config.json"

# --- Check Installation Function ---
function check_zivpn_installed() {
    if [ -f "/etc/systemd/system/zivpn.service" ] || [ -d "/etc/zivpn" ]; then
        return 0  # Installed
    else
        return 1  # Not installed
    fi
}

# --- Auto Install Function ---
function install_zivpn() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║          ${LIGHT_CYAN}INSTALLING ZIVPN${PURPLE}           ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    if check_zivpn_installed; then
        echo -e "${LIGHT_YELLOW}ZIVPN sudah terinstall!${NC}"
        echo -e "${LIGHT_CYAN}Menuju ke menu ZIVPN...${NC}"
        sleep 2
        return
    fi
    
    echo -e "${LIGHT_BLUE}Menginstall ZIVPN...${NC}"
    echo -e "${LIGHT_YELLOW}Proses ini mungkin memakan waktu beberapa menit...${NC}"
    echo ""
    
    # Start installation
    main
}

# --- Start ZIVPN from Main Menu ---
function start_zivpn() {
    if ! check_zivpn_installed; then
        install_zivpn
    fi
    main
}

# --- Pre-flight Checks ---
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo or run as root user." >&2
  exit 1
fi

# --- License Verification Function ---
function verify_license() {
    echo "Verifying check skipped"
    local SERVER_IP
    SERVER_IP=$(curl -s ifconfig.me)
    if [ -z "$SERVER_IP" ]; then
        echo -e "${RED}Failed to retrieve server IP. Please check your internet connection.${NC}"
        exit 1
    fi

    local license_data
    license_data=$(curl -s "$LICENSE_URL")
    if [ $? -ne 0 ] || [ -z "$license_data" ]; then
        echo -e "${RED}Gagal terhubung ke server lisensi. Mohon periksa koneksi internet Anda.${NC}"
        exit 1
    fi

    local license_entry
    license_entry=$(echo "$license_data" | grep -w "$SERVER_IP")

    if [ -z "$license_entry" ]; then
        echo -e "${RED}Verifikasi Lisensi Gagal! IP Anda tidak terdaftar. IP: ${SERVER_IP}${NC}"
        exit 1
    fi

    local client_name
    local expiry_date_str
    client_name=$(echo "$license_entry" | awk '{print $1}')
    expiry_date_str=$(echo "$license_entry" | awk '{print $2}')

    local expiry_timestamp
    expiry_timestamp=$(date -d "$expiry_date_str" +%s)
    local current_timestamp
    current_timestamp=$(date +%s)

    if [ "$expiry_timestamp" -le "$current_timestamp" ]; then
        echo -e "${RED}Verifikasi Lisensi Gagal! Lisensi untuk IP ${SERVER_IP} telah kedaluwarsa. Tanggal Kedaluwarsa: ${expiry_date_str}${NC}"
        exit 1
    fi
    
    echo -e "${LIGHT_GREEN}Verifikasi Lisensi Berhasil! Client: ${client_name}, IP: ${SERVER_IP}${NC}"
    sleep 2 # Brief pause to show the message
    
    mkdir -p /etc/zivpn
    echo "CLIENT_NAME=${client_name}" > "$LICENSE_INFO_FILE"
    echo "EXPIRY_DATE=${expiry_date_str}" >> "$LICENSE_INFO_FILE"
}

# --- Utility Functions ---
function restart_zivpn() {
    echo "Restarting ZIVPN service..."
    systemctl restart zivpn.service
    echo "Service restarted."
}

# --- Device Limit Management Functions ---
function check_device_limit() {
    local username="$1"
    local max_devices="$2"
    local current_ip="$3"
    
    # Initialize device database if not exists
    if [ ! -f "$DEVICE_DB" ]; then
        touch "$DEVICE_DB"
    fi
    
    # Get current device count for this user
    local device_count=$(grep -c "^${username}:" "$DEVICE_DB" 2>/dev/null || echo "0")
    
    if [ "$device_count" -ge "$max_devices" ]; then
        # Check if current IP is already registered
        if ! grep -q "^${username}:${current_ip}" "$DEVICE_DB"; then
            return 1  # Device limit exceeded
        fi
    fi
    
    return 0  # Device limit not exceeded or IP already registered
}

function register_device() {
    local username="$1"
    local ip_address="$2"
    
    # Remove any existing entry for this username with same IP
    sed -i "/^${username}:${ip_address}/d" "$DEVICE_DB" 2>/dev/null
    
    # Add new entry with timestamp
    local timestamp=$(date +%s)
    echo "${username}:${ip_address}:${timestamp}" >> "$DEVICE_DB"
}

function clear_expired_devices() {
    local current_time=$(date +%s)
    local expiry_time=$((current_time - 86400)) # 24 hours ago
    
    if [ -f "$DEVICE_DB" ]; then
        # Create temporary file
        local temp_file=$(mktemp)
        
        while IFS=':' read -r username ip timestamp; do
            if [ "$timestamp" -gt "$expiry_time" ]; then
                echo "${username}:${ip}:${timestamp}" >> "$temp_file"
            fi
        done < "$DEVICE_DB"
        
        mv "$temp_file" "$DEVICE_DB"
    fi
}

# --- Domain Management Functions ---
function add_domain() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║         ${LIGHT_CYAN}TAMBAH DOMAIN BARU${PURPLE}          ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "Masukkan domain baru (contoh: vpn.pondok.com): " new_domain
    if [ -z "$new_domain" ]; then
        echo -e "${RED}Domain tidak boleh kosong!${NC}"
        sleep 2
        return
    fi
    
    # Validasi format domain
    if [[ ! "$new_domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo -e "${RED}Format domain tidak valid!${NC}"
        sleep 2
        return
    fi
    
    echo ""
    echo -e "${LIGHT_BLUE}Membuat sertifikat SSL untuk domain: ${WHITE}${new_domain}${NC}"
    echo -e "${YELLOW}Proses ini mungkin memakan waktu beberapa detik...${NC}"
    
    # Buat direktori jika belum ada
    mkdir -p /etc/zivpn/ssl
    
    # Generate SSL certificate
    openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
        -subj "/C=ID/ST=Jakarta/L=Jakarta/O=PONDOK VPN/OU=VPN Service/CN=${new_domain}" \
        -keyout "/etc/zivpn/ssl/${new_domain}.key" \
        -out "/etc/zivpn/ssl/${new_domain}.crt" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Sertifikat SSL berhasil dibuat untuk ${new_domain}${NC}"
        
        # Update config.json dengan domain baru
        if [ -f "/etc/zivpn/config.json" ]; then
            # Backup config lama
            cp /etc/zivpn/config.json /etc/zivpn/config.json.backup
            
            # Update config
            jq --arg domain "$new_domain" '.tls.sni = $domain' /etc/zivpn/config.json > /tmp/config.json.tmp
            if [ $? -eq 0 ]; then
                mv /tmp/config.json.tmp /etc/zivpn/config.json
                
                # Copy sertifikat ke lokasi utama
                cp "/etc/zivpn/ssl/${new_domain}.key" /etc/zivpn/zivpn.key
                cp "/etc/zivpn/ssl/${new_domain}.crt" /etc/zivpn/zivpn.crt
                
                echo -e "${LIGHT_GREEN}Domain ${new_domain} berhasil ditambahkan!${NC}"
                
                # Restart service
                restart_zivpn
                
                echo ""
                echo -e "${LIGHT_GREEN}╔══════════════════════════════════════════╗${NC}"
                echo -e "${LIGHT_GREEN}║       ${WHITE}✅ DOMAIN BERHASIL DITAMBAHKAN${LIGHT_GREEN}    ║${NC}"
                echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
                echo -e "${LIGHT_GREEN}║                                          ║${NC}"
                echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Domain: ${WHITE}${new_domain}${LIGHT_GREEN}              ║${NC}"
                echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Status: ${WHITE}Aktif${LIGHT_GREEN}                      ║${NC}"
                echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 SSL: ${WHITE}Valid (365 hari)${LIGHT_GREEN}             ║${NC}"
                echo -e "${LIGHT_GREEN}║                                          ║${NC}"
                echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
                echo -e "${LIGHT_GREEN}║   ${LIGHT_YELLOW}Service ZIVPN telah di-restart${LIGHT_GREEN}    ║${NC}"
                echo -e "${LIGHT_GREEN}╚══════════════════════════════════════════╝${NC}"
            else
                echo -e "${RED}Gagal update config.json!${NC}"
                # Restore backup
                cp /etc/zivpn/config.json.backup /etc/zivpn/config.json
            fi
        fi
    else
        echo -e "${RED}Gagal membuat sertifikat SSL!${NC}"
    fi
    
    echo ""
    read -p "Tekan Enter untuk kembali ke menu..."
}

function change_domain() {
    clear
    
    # Cek domain saat ini
    local current_domain=""
    if [ -f "/etc/zivpn/zivpn.crt" ]; then
        current_domain=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p')
    fi
    
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║         ${LIGHT_CYAN}GANTI DOMAIN${PURPLE}                ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ -n "$current_domain" ]; then
        echo -e "${LIGHT_BLUE}Domain saat ini: ${WHITE}${current_domain}${NC}"
        echo ""
    fi
    
    read -p "Masukkan domain baru (contoh: vpn.pondok.com): " domain
    if [ -z "$domain" ]; then
        echo -e "${RED}Domain tidak boleh kosong!${NC}"
        sleep 2
        return
    fi
    
    # Validasi format domain
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo -e "${RED}Format domain tidak valid!${NC}"
        sleep 2
        return
    fi
    
    echo ""
    echo -e "${LIGHT_BLUE}Membuat sertifikat SSL untuk domain: ${WHITE}${domain}${NC}"
    echo -e "${YELLOW}Proses ini mungkin memakan waktu beberapa detik...${NC}"
    
    # Generate SSL certificate
    openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
        -subj "/C=ID/ST=Jakarta/L=Jakarta/O=PONDOK VPN/OU=VPN Service/CN=${domain}" \
        -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Sertifikat SSL berhasil dibuat untuk ${domain}${NC}"
        
        # Update config.json
        if [ -f "/etc/zivpn/config.json" ]; then
            # Backup config lama
            cp /etc/zivpn/config.json /etc/zivpn/config.json.backup
            
            # Update config
            jq --arg domain "$domain" '.tls.sni = $domain' /etc/zivpn/config.json > /tmp/config.json.tmp
            if [ $? -eq 0 ]; then
                mv /tmp/config.json.tmp /etc/zivpn/config.json
                
                echo -e "${LIGHT_GREEN}Domain berhasil diganti ke ${domain}${NC}"
                
                # Restart service
                restart_zivpn
                
                echo ""
                echo -e "${LIGHT_GREEN}╔══════════════════════════════════════════╗${NC}"
                echo -e "${LIGHT_GREEN}║        ${WHITE}✅ DOMAIN BERHASIL DIGANTI${LIGHT_GREEN}      ║${NC}"
                echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
                echo -e "${LIGHT_GREEN}║                                          ║${NC}"
                echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Domain Lama: ${WHITE}${current_domain:-"Tidak ada"}${LIGHT_GREEN} ║${NC}"
                echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Domain Baru: ${WHITE}${domain}${LIGHT_GREEN}              ║${NC}"
                echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Status: ${WHITE}Aktif${LIGHT_GREEN}                      ║${NC}"
                echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 SSL: ${WHITE}Valid (365 hari)${LIGHT_GREEN}             ║${NC}"
                echo -e "${LIGHT_GREEN}║                                          ║${NC}"
                echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
                echo -e "${LIGHT_GREEN}║   ${LIGHT_YELLOW}Service ZIVPN telah di-restart${LIGHT_GREEN}    ║${NC}"
                echo -e "${LIGHT_GREEN}╚══════════════════════════════════════════╝${NC}"
            else
                echo -e "${RED}Gagal update config.json!${NC}"
                # Restore backup
                cp /etc/zivpn/config.json.backup /etc/zivpn/config.json
            fi
        fi
    else
        echo -e "${RED}Gagal membuat sertifikat SSL!${NC}"
    fi
    
    echo ""
    read -p "Tekan Enter untuk kembali ke menu..."
}

function list_domains() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║         ${LIGHT_CYAN}DAFTAR DOMAIN${PURPLE}               ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    # Cek domain aktif
    if [ -f "/etc/zivpn/zivpn.crt" ]; then
        local current_domain
        current_domain=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p')
        local expiry_date
        expiry_date=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -enddate | cut -d= -f2)
        
        echo -e "${LIGHT_BLUE}╔══════════════════════════════════════════╗${NC}"
        echo -e "${LIGHT_BLUE}║     ${WHITE}DOMAIN AKTIF SAAT INI${LIGHT_BLUE}          ║${NC}"
        echo -e "${LIGHT_BLUE}╠══════════════════════════════════════════╣${NC}"
        echo -e "${LIGHT_BLUE}║                                          ║${NC}"
        echo -e "${LIGHT_BLUE}║  ${LIGHT_GREEN}🔹 Domain: ${WHITE}${current_domain}${LIGHT_BLUE}           ║${NC}"
        echo -e "${LIGHT_BLUE}║  ${LIGHT_GREEN}🔹 Expire: ${WHITE}${expiry_date}${LIGHT_BLUE}              ║${NC}"
        echo -e "${LIGHT_BLUE}║  ${LIGHT_GREEN}🔹 File: ${WHITE}/etc/zivpn/zivpn.crt${LIGHT_BLUE}     ║${NC}"
        echo -e "${LIGHT_BLUE}║                                          ║${NC}"
        echo -e "${LIGHT_BLUE}╚══════════════════════════════════════════╝${NC}"
    else
        echo -e "${YELLOW}Tidak ada domain aktif.${NC}"
    fi
    
    # Cek domain di folder ssl
    echo ""
    if [ -d "/etc/zivpn/ssl" ]; then
        local ssl_files=$(ls /etc/zivpn/ssl/*.crt 2>/dev/null | wc -l)
        if [ $ssl_files -gt 0 ]; then
            echo -e "${LIGHT_BLUE}╔══════════════════════════════════════════╗${NC}"
            echo -e "${LIGHT_BLUE}║     ${WHITE}DOMAIN TERSIMPAN${LIGHT_BLUE}               ║${NC}"
            echo -e "${LIGHT_BLUE}╠══════════════════════════════════════════╣${NC}"
            
            for cert_file in /etc/zivpn/ssl/*.crt; do
                local domain_name
                domain_name=$(basename "$cert_file" .crt)
                local cert_expiry
                cert_expiry=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
                
                if [ -n "$cert_expiry" ]; then
                    echo -e "${LIGHT_BLUE}║  ${LIGHT_GREEN}🔸 ${domain_name}${LIGHT_BLUE}                    ║${NC}"
                    echo -e "${LIGHT_BLUE}║     ${WHITE}Expire: ${cert_expiry}${LIGHT_BLUE}        ║${NC}"
                fi
            done
            echo -e "${LIGHT_BLUE}╚══════════════════════════════════════════╝${NC}"
        fi
    fi
    
    echo ""
    read -p "Tekan Enter untuk kembali ke menu..."
}

function domain_menu() {
    while true; do
        clear
        echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║         ${LIGHT_CYAN}MANAJEMEN DOMAIN${PURPLE}           ║${NC}"
        echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${LIGHT_BLUE}╔══════════════════════════════════════════╗${NC}"
        echo -e "${LIGHT_BLUE}║                                          ║${NC}"
        echo -e "${LIGHT_BLUE}║   ${WHITE}1) ${LIGHT_GREEN}Tambah Domain Baru${LIGHT_BLUE}               ║${NC}"
        echo -e "${LIGHT_BLUE}║   ${WHITE}2) ${LIGHT_GREEN}Ganti Domain Aktif${LIGHT_BLUE}               ║${NC}"
        echo -e "${LIGHT_BLUE}║   ${WHITE}3) ${LIGHT_GREEN}Lihat Daftar Domain${LIGHT_BLUE}              ║${NC}"
        echo -e "${LIGHT_BLUE}║   ${WHITE}0) ${LIGHT_GREEN}Kembali ke Menu Utama${LIGHT_BLUE}           ║${NC}"
        echo -e "${LIGHT_BLUE}║                                          ║${NC}"
        echo -e "${LIGHT_BLUE}╚══════════════════════════════════════════╝${NC}"
        echo ""
        read -p "Pilih menu [0-3]: " domain_choice
        
        case $domain_choice in
            1) add_domain ;;
            2) change_domain ;;
            3) list_domains ;;
            0) break ;;
            *) echo -e "${RED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

# --- Telegram Bot Functions ---
function setup_telegram_bot() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║        ${LIGHT_CYAN}TELEGRAM BOT SETUP${PURPLE}           ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "Masukkan Bot Token Telegram: " bot_token
    read -p "Masukkan Chat ID Telegram: " chat_id
    
    if [ -z "$bot_token" ] || [ -z "$chat_id" ]; then
        echo -e "${RED}Token dan Chat ID tidak boleh kosong!${NC}"
        sleep 2
        return
    fi
    
    echo "TELEGRAM_BOT_TOKEN=${bot_token}" > /etc/zivpn/telegram.conf
    echo "TELEGRAM_CHAT_ID=${chat_id}" >> /etc/zivpn/telegram.conf
    echo "TELEGRAM_ENABLED=true" >> /etc/zivpn/telegram.conf
    
    echo -e "${GREEN}Bot Telegram berhasil diatur!${NC}"
    echo -e "${LIGHT_BLUE}Token: ${WHITE}${bot_token:0:10}...${NC}"
    echo -e "${LIGHT_BLUE}Chat ID: ${WHITE}${chat_id}${NC}"
    
    # Create bot script
    create_telegram_bot_script
    sleep 3
}

function change_bot_token() {
    clear
    if [ ! -f "/etc/zivpn/telegram.conf" ]; then
        echo -e "${RED}Bot Telegram belum diatur!${NC}"
        sleep 2
        return
    fi
    
    source /etc/zivpn/telegram.conf
    echo -e "${LIGHT_BLUE}Token saat ini: ${WHITE}${TELEGRAM_BOT_TOKEN:0:10}...${NC}"
    echo -e "${LIGHT_BLUE}Chat ID saat ini: ${WHITE}${TELEGRAM_CHAT_ID}${NC}"
    echo ""
    
    read -p "Masukkan Bot Token baru: " new_token
    read -p "Masukkan Chat ID baru: " new_chat_id
    
    echo "TELEGRAM_BOT_TOKEN=${new_token}" > /etc/zivpn/telegram.conf
    echo "TELEGRAM_CHAT_ID=${new_chat_id}" >> /etc/zivpn/telegram.conf
    echo "TELEGRAM_ENABLED=true" >> /etc/zivpn/telegram.conf
    
    echo -e "${GREEN}Token berhasil diubah!${NC}"
    sleep 2
}

function show_admin_info() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║           ${LIGHT_CYAN}INFORMASI ADMIN${PURPLE}            ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${LIGHT_GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_GREEN}║        ${WHITE}HUBUNGI ADMIN UNTUK BANTUAN${LIGHT_GREEN}       ║${NC}"
    echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${LIGHT_GREEN}║                                          ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}WHATSAPP: ${WHITE}082147725445${LIGHT_GREEN}              ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}TELEGRAM: ${WHITE}@bendakerep${LIGHT_GREEN}               ║${NC}"
    echo -e "${LIGHT_GREEN}║                                          ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_YELLOW}PONDOK VPN${LIGHT_GREEN}                               ║${NC}"
    echo -e "${LIGHT_GREEN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    read -p "Tekan Enter untuk kembali..."
}

function create_telegram_bot_script() {
    cat > /etc/zivpn/telegram_bot.sh << 'EOF'
#!/bin/bash
# Telegram Bot for PONDOK VPN

TELEGRAM_CONF="/etc/zivpn/telegram.conf"
USER_DB="/etc/zivpn/users.db"
CONFIG_JSON="/etc/zivpn/config.json"

if [ ! -f "$TELEGRAM_CONF" ]; then
    exit 0
fi

source "$TELEGRAM_CONF"

send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=Markdown" > /dev/null
}

create_account_via_bot() {
    local password="$1"
    local days="$2"
    
    local expiry_date
    expiry_date=$(date -d "+$days days" +%s)
    echo "${password}:${expiry_date}" >> "$USER_DB"
    
    jq --arg pass "$password" '.auth.config += [$pass]' "$CONFIG_JSON" > /tmp/config.json.tmp && mv /tmp/config.json.tmp "$CONFIG_JSON"
    systemctl restart zivpn.service
    
    local HOST
    HOST=$(curl -s ifconfig.me)
    local CERT_CN
    CERT_CN=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p' 2>/dev/null || echo "")
    if [ "$CERT_CN" != "zivpn" ] && [ -n "$CERT_CN" ]; then
        HOST="$CERT_CN"
    fi
    
    local EXPIRE_FORMATTED
    EXPIRE_FORMATTED=$(date -d "@$expiry_date" +"%d %B %Y")
    
    local message="✅ *AKUN BARU DIBUAT*
    
🔹 *Host:* \`${HOST}\`
🔹 *Password:* \`${password}\`
🔹 *Expire:* ${EXPIRE_FORMATTED}
🔹 *Masa Aktif:* ${days} hari

📱 *PONDOK VPN*
☎️ 082147725445"
    
    send_telegram "$message"
}

# Main bot logic
case "$1" in
    "create")
        create_account_via_bot "$2" "$3"
        ;;
    "notification")
        send_telegram "$2"
        ;;
esac
EOF
    
    chmod +x /etc/zivpn/telegram_bot.sh
}

function telegram_bot_menu() {
    while true; do
        clear
        echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║         ${LIGHT_CYAN}TELEGRAM BOT MENU${PURPLE}          ║${NC}"
        echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${LIGHT_BLUE}╔══════════════════════════════════════════╗${NC}"
        echo -e "${LIGHT_BLUE}║                                          ║${NC}"
        echo -e "${LIGHT_BLUE}║   ${WHITE}1) ${LIGHT_GREEN}Add Bot Token/ID${LIGHT_BLUE}                   ║${NC}"
        echo -e "${LIGHT_BLUE}║   ${WHITE}2) ${LIGHT_GREEN}Ganti Bot Token${LIGHT_BLUE}                    ║${NC}"
        echo -e "${LIGHT_BLUE}║   ${WHITE}3) ${LIGHT_GREEN}Hubungi Admin${LIGHT_BLUE}                      ║${NC}"
        echo -e "${LIGHT_BLUE}║   ${WHITE}0) ${LIGHT_GREEN}Exit${LIGHT_BLUE}                               ║${NC}"
        echo -e "${LIGHT_BLUE}║                                          ║${NC}"
        echo -e "${LIGHT_BLUE}╚══════════════════════════════════════════╝${NC}"
        echo ""
        read -p "Pilih menu [0-3]: " bot_choice
        
        case $bot_choice in
            1) setup_telegram_bot ;;
            2) change_bot_token ;;
            3) show_admin_info ;;
            0) break ;;
            *) echo -e "${RED}Pilihan tidak valid!${NC}"; sleep 1 ;;
        esac
    done
}

# --- Modified Account Creation with Device Limit ---
function create_manual_account() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║       ${LIGHT_CYAN}BUAT AKUN ZIVPN${PURPLE}              ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "Masukkan password: " password
    if [ -z "$password" ]; then
        echo -e "${RED}Password tidak boleh kosong.${NC}"
        return
    fi

    read -p "Masukkan masa aktif (hari): " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Jumlah hari tidak valid.${NC}"
        return
    fi

    read -p "Masukkan limit device (default: 2): " max_devices
    if [ -z "$max_devices" ]; then
        max_devices=2
    elif ! [[ "$max_devices" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Jumlah device tidak valid, menggunakan default: 2${NC}"
        max_devices=2
    fi

    local db_file="/etc/zivpn/users.db"
    if grep -q "^${password}:" "$db_file"; then
        echo -e "${YELLOW}Password '${password}' sudah ada.${NC}"
        return
    fi

    local expiry_date
    expiry_date=$(date -d "+$days days" +%s)
    echo "${password}:${expiry_date}:${max_devices}" >> "$db_file"
    
    jq --arg pass "$password" '.auth.config += [$pass]' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json
    
    local CERT_CN
    CERT_CN=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p')
    local HOST
    if [ "$CERT_CN" == "zivpn" ]; then
        HOST=$(curl -s ifconfig.me)
    else
        HOST=$CERT_CN
    fi

    local EXPIRE_FORMATTED
    EXPIRE_FORMATTED=$(date -d "@$expiry_date" +"%d %B %Y")
    
    clear
    echo -e "${LIGHT_GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_GREEN}║     ${WHITE}✅ AKUN BERHASIL DIBUAT${LIGHT_GREEN}      ║${NC}"
    echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${LIGHT_GREEN}║                                          ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Host: ${WHITE}$HOST${LIGHT_GREEN}                   ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Password: ${WHITE}$password${LIGHT_GREEN}           ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Expire: ${WHITE}$EXPIRE_FORMATTED${LIGHT_GREEN}     ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Masa Aktif: ${WHITE}$days hari${LIGHT_GREEN}        ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Limit Device: ${WHITE}$max_devices device${LIGHT_GREEN}   ║${NC}"
    echo -e "${LIGHT_GREEN}║                                          ║${NC}"
    echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${LIGHT_GREEN}║                                          ║${NC}"
    echo -e "${LIGHT_GREEN}║   ${LIGHT_YELLOW}⚠️  PERHATIAN:${LIGHT_GREEN}                           ║${NC}"
    echo -e "${LIGHT_GREEN}║   ${WHITE}Akun akan di-lock jika melebihi${LIGHT_GREEN}           ║${NC}"
    echo -e "${LIGHT_GREEN}║   ${WHITE}$max_devices device yang terdaftar${LIGHT_GREEN}        ║${NC}"
    echo -e "${LIGHT_GREEN}║                                          ║${NC}"
    echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${LIGHT_GREEN}║   ${LIGHT_CYAN}Terima kasih sudah order!${LIGHT_GREEN}            ║${NC}"
    echo -e "${LIGHT_GREEN}║   ${LIGHT_YELLOW}PONDOK VPN${LIGHT_GREEN}                           ║${NC}"
    echo -e "${LIGHT_GREEN}║   ${LIGHT_CYAN}☎️ 082147725445${LIGHT_GREEN}                       ║${NC}"
    echo -e "${LIGHT_GREEN}╚══════════════════════════════════════════╝${NC}"
    
    restart_zivpn
    read -p "Tekan Enter untuk kembali ke menu..."
}

function create_trial_account() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║       ${LIGHT_CYAN}BUAT AKUN TRIAL${PURPLE}               ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "Masukkan masa aktif (menit): " minutes
    if ! [[ "$minutes" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Jumlah menit tidak valid.${NC}"
        return
    fi

    local password="trial$(shuf -i 10000-99999 -n 1)"
    local max_devices=1  # Trial hanya 1 device
    local db_file="/etc/zivpn/users.db"

    local expiry_date
    expiry_date=$(date -d "+$minutes minutes" +%s)
    echo "${password}:${expiry_date}:${max_devices}" >> "$db_file"
    
    jq --arg pass "$password" '.auth.config += [$pass]' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json
    
    local CERT_CN
    CERT_CN=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p')
    local HOST
    if [ "$CERT_CN" == "zivpn" ]; then
        HOST=$(curl -s ifconfig.me)
    else
        HOST=$CERT_CN
    fi

    local EXPIRE_FORMATTED
    EXPIRE_FORMATTED=$(date -d "@$expiry_date" +"%d %B %Y %H:%M:%S")
    
    clear
    echo -e "${LIGHT_GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_GREEN}║     ${WHITE}✅ AKUN TRIAL BERHASIL${LIGHT_GREEN}      ║${NC}"
    echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${LIGHT_GREEN}║                                          ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Host: ${WHITE}$HOST${LIGHT_GREEN}                   ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Password: ${WHITE}$password${LIGHT_GREEN}           ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Expire: ${WHITE}$EXPIRE_FORMATTED${LIGHT_GREEN}     ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Limit Device: ${WHITE}$max_devices device${LIGHT_GREEN}   ║${NC}"
    echo -e "${LIGHT_GREEN}║                                          ║${NC}"
    echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${LIGHT_GREEN}║                                          ║${NC}"
    echo -e "${LIGHT_GREEN}║   ${LIGHT_YELLOW}⚠️  AKUN TRIAL:${LIGHT_GREEN}                         ║${NC}"
    echo -e "${LIGHT_GREEN}║   ${WHITE}Hanya 1 device yang diperbolehkan${LIGHT_GREEN}       ║${NC}"
    echo -e "${LIGHT_GREEN}║                                          ║${NC}"
    echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${LIGHT_GREEN}║   ${LIGHT_CYAN}Terima kasih sudah mencoba!${LIGHT_GREEN}         ║${NC}"
    echo -e "${LIGHT_GREEN}║   ${LIGHT_YELLOW}PONDOK VPN${LIGHT_GREEN}                           ║${NC}"
    echo -e "${LIGHT_GREEN}║   ${LIGHT_CYAN}☎️ 082147725445${LIGHT_GREEN}                       ║${NC}"
    echo -e "${LIGHT_GREEN}╚══════════════════════════════════════════╝${NC}"
    
    restart_zivpn
    read -p "Tekan Enter untuk kembali ke menu..."
}

# --- Modified Delete Account with Numbered List ---
function delete_account() {
    clear
    local db_file="/etc/zivpn/users.db"
    
    if [ ! -f "$db_file" ] || [ ! -s "$db_file" ]; then
        echo -e "${YELLOW}Tidak ada akun yang ditemukan.${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║       ${LIGHT_CYAN}HAPUS AKUN ZIVPN${PURPLE}              ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    # Display numbered list of accounts
    echo -e "${LIGHT_BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_BLUE}║  ${WHITE}No.  Password             Device${LIGHT_BLUE}   ║${NC}"
    echo -e "${LIGHT_BLUE}╠══════════════════════════════════════════╣${NC}"
    
    local count=0
    while IFS=':' read -r password expiry_date max_devices; do
        if [[ -n "$password" ]]; then
            count=$((count + 1))
            local remaining_seconds=$((expiry_date - $(date +%s)))
            local remaining_days=$((remaining_seconds / 86400))
            if [ $remaining_days -gt 0 ]; then
                echo -e "${LIGHT_BLUE}║  ${WHITE}$(printf "%2d" $count). ${password:0:18} $(printf "%3s" $max_devices) device${LIGHT_BLUE} ║${NC}"
            else
                echo -e "${LIGHT_BLUE}║  ${WHITE}$(printf "%2d" $count). ${password:0:18} ${RED}Expired${WHITE}${LIGHT_BLUE}  ║${NC}"
            fi
        fi
    done < "$db_file"
    
    echo -e "${LIGHT_BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ $count -eq 0 ]; then
        echo -e "${YELLOW}Tidak ada akun yang ditemukan.${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    read -p "Masukkan nomor akun yang akan dihapus [1-$count]: " account_number
    
    if ! [[ "$account_number" =~ ^[0-9]+$ ]] || [ "$account_number" -lt 1 ] || [ "$account_number" -gt "$count" ]; then
        echo -e "${RED}Nomor akun tidak valid!${NC}"
        sleep 2
        return
    fi
    
    # Get the password for the selected account number
    local selected_password=""
    local current=0
    while IFS=':' read -r password expiry_date max_devices; do
        if [[ -n "$password" ]]; then
            current=$((current + 1))
            if [ $current -eq $account_number ]; then
                selected_password=$password
                break
            fi
        fi
    done < "$db_file"
    
    if [ -z "$selected_password" ]; then
        echo -e "${RED}Akun tidak ditemukan!${NC}"
        sleep 2
        return
    fi
    
    # Confirm deletion
    echo ""
    echo -e "${YELLOW}Apakah Anda yakin ingin menghapus akun:${NC}"
    echo -e "${WHITE}$selected_password${NC}"
    read -p "Konfirmasi (y/n): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y"]]; then
        echo -e "${YELLOW}Penghapusan dibatalkan.${NC}"
        sleep 1
        return
    fi
    
    # Delete the account
    sed -i "/^${selected_password}:/d" "$db_file"
    
    # Also delete from device database
    sed -i "/^${selected_password}:/d" "$DEVICE_DB" 2>/dev/null
    
    echo -e "${GREEN}Akun '${selected_password}' berhasil dihapus.${NC}"
    
    jq --arg pass "$selected_password" 'del(.auth.config[] | select(. == $pass))' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json
    restart_zivpn
    
    sleep 2
}

# --- Modified Renew Account with Numbered List ---
function renew_account() {
    clear
    local db_file="/etc/zivpn/users.db"
    
    if [ ! -f "$db_file" ] || [ ! -s "$db_file" ]; then
        echo -e "${YELLOW}Tidak ada akun yang ditemukan.${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║       ${LIGHT_CYAN}RENEW AKUN ZIVPN${PURPLE}              ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    # Display numbered list of accounts
    echo -e "${LIGHT_BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_BLUE}║  ${WHITE}No.  Password             Device${LIGHT_BLUE}   ║${NC}"
    echo -e "${LIGHT_BLUE}╠══════════════════════════════════════════╣${NC}"
    
    local count=0
    while IFS=':' read -r password expiry_date max_devices; do
        if [[ -n "$password" ]]; then
            count=$((count + 1))
            local remaining_seconds=$((expiry_date - $(date +%s)))
            local remaining_days=$((remaining_seconds / 86400))
            if [ $remaining_days -gt 0 ]; then
                echo -e "${LIGHT_BLUE}║  ${WHITE}$(printf "%2d" $count). ${password:0:18} $(printf "%3s" $max_devices) device${LIGHT_BLUE} ║${NC}"
            else
                echo -e "${LIGHT_BLUE}║  ${WHITE}$(printf "%2d" $count). ${password:0:18} ${RED}Expired${WHITE}${LIGHT_BLUE}  ║${NC}"
            fi
        fi
    done < "$db_file"
    
    echo -e "${LIGHT_BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ $count -eq 0 ]; then
        echo -e "${YELLOW}Tidak ada akun yang ditemukan.${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    read -p "Masukkan nomor akun yang akan di-renew [1-$count]: " account_number
    
    if ! [[ "$account_number" =~ ^[0-9]+$ ]] || [ "$account_number" -lt 1 ] || [ "$account_number" -gt "$count" ]; then
        echo -e "${RED}Nomor akun tidak valid!${NC}"
        sleep 2
        return
    fi
    
    # Get the password for the selected account number
    local selected_password=""
    local current_expiry_date=0
    local current_max_devices=0
    local current=0
    while IFS=':' read -r password expiry_date max_devices; do
        if [[ -n "$password" ]]; then
            current=$((current + 1))
            if [ $current -eq $account_number ]; then
                selected_password=$password
                current_expiry_date=$expiry_date
                current_max_devices=$max_devices
                break
            fi
        fi
    done < "$db_file"
    
    if [ -z "$selected_password" ]; then
        echo -e "${RED}Akun tidak ditemukan!${NC}"
        sleep 2
        return
    fi
    
    # Show renew options
    echo ""
    echo -e "${LIGHT_GREEN}Akun yang dipilih: ${WHITE}$selected_password${NC}"
    echo -e "${LIGHT_BLUE}1) ${WHITE}Tambah masa aktif${NC}"
    echo -e "${LIGHT_BLUE}2) ${WHITE}Ganti password${NC}"
    echo -e "${LIGHT_BLUE}3) ${WHITE}Ubah limit device${NC}"
    echo ""
    read -p "Pilih opsi [1-3]: " renew_option
    
    case $renew_option in
        1)
            read -p "Masukkan jumlah hari untuk ditambahkan: " days
            if ! [[ "$days" =~ ^[1-9][0-9]*$ ]]; then
                echo -e "${RED}Jumlah hari tidak valid!${NC}"
                sleep 2
                return
            fi
            
            local seconds_to_add=$((days * 86400))
            local new_expiry_date=$((current_expiry_date + seconds_to_add))
            
            sed -i "s/^${selected_password}:.*/${selected_password}:${new_expiry_date}:${current_max_devices}/" "$db_file"
            
            local new_expiry_formatted
            new_expiry_formatted=$(date -d "@$new_expiry_date" +"%d %B %Y")
            echo -e "${GREEN}Masa aktif akun '${selected_password}' ditambah ${days} hari.${NC}"
            echo -e "${LIGHT_BLUE}Expire baru: ${WHITE}${new_expiry_formatted}${NC}"
            
            # Reset device tracking for renewed account
            sed -i "/^${selected_password}:/d" "$DEVICE_DB" 2>/dev/null
            echo -e "${LIGHT_GREEN}Device tracking telah di-reset!${NC}"
            ;;
        2)
            read -p "Masukkan password baru: " new_password
            if [ -z "$new_password" ]; then
                echo -e "${RED}Password tidak boleh kosong!${NC}"
                sleep 2
                return
            fi
            
            # Check if new password already exists
            if grep -q "^${new_password}:" "$db_file"; then
                echo -e "${RED}Password '${new_password}' sudah ada!${NC}"
                sleep 2
                return
            fi
            
            # Update in database
            sed -i "s/^${selected_password}:.*/${new_password}:${current_expiry_date}:${current_max_devices}/" "$db_file"
            
            # Update device database
            sed -i "s/^${selected_password}:/${new_password}:/" "$DEVICE_DB" 2>/dev/null
            
            # Update in config.json
            jq --arg old "$selected_password" --arg new "$new_password" '.auth.config |= map(if . == $old then $new else . end)' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json
            
            echo -e "${GREEN}Password akun berhasil diganti!${NC}"
            echo -e "${LIGHT_BLUE}Password lama: ${WHITE}${selected_password}${NC}"
            echo -e "${LIGHT_BLUE}Password baru: ${WHITE}${new_password}${NC}"
            ;;
        3)
            echo -e "${LIGHT_BLUE}Limit device saat ini: ${WHITE}${current_max_devices}${NC}"
            read -p "Masukkan limit device baru: " new_max_devices
            
            if ! [[ "$new_max_devices" =~ ^[0-9]+$ ]] || [ "$new_max_devices" -lt 1 ]; then
                echo -e "${RED}Limit device tidak valid!${NC}"
                sleep 2
                return
            fi
            
            # Update in database
            sed -i "s/^${selected_password}:.*/${selected_password}:${current_expiry_date}:${new_max_devices}/" "$db_file"
            
            echo -e "${GREEN}Limit device berhasil diubah!${NC}"
            echo -e "${LIGHT_BLUE}Limit lama: ${WHITE}${current_max_devices} device${NC}"
            echo -e "${LIGHT_BLUE}Limit baru: ${WHITE}${new_max_devices} device${NC}"
            
            # Reset device tracking if reducing limit
            if [ "$new_max_devices" -lt "$current_max_devices" ]; then
                sed -i "/^${selected_password}:/d" "$DEVICE_DB" 2>/dev/null
                echo -e "${LIGHT_GREEN}Device tracking telah di-reset!${NC}"
            fi
            ;;
        *)
            echo -e "${RED}Pilihan tidak valid!${NC}"
            sleep 2
            return
            ;;
    esac
    
    restart_zivpn
    sleep 2
}

function _display_accounts() {
    local db_file="/etc/zivpn/users.db"

    if [ ! -f "$db_file" ] || [ ! -s "$db_file" ]; then
        echo "No accounts found."
        return
    fi

    local current_date
    current_date=$(date +%s)
    printf "%-20s | %-10s | %s\n" "Password" "Device" "Expires in (days)"
    echo "----------------------------------------------------"
    while IFS=':' read -r password expiry_date max_devices; do
        if [[ -n "$password" ]]; then
            local remaining_seconds=$((expiry_date - current_date))
            if [ $remaining_seconds -gt 0 ]; then
                local remaining_days=$((remaining_seconds / 86400))
                printf "%-20s | %-10s | %s days\n" "$password" "$max_devices" "$remaining_days"
            else
                printf "%-20s | %-10s | Expired\n" "$password" "$max_devices"
            fi
        fi
    done < "$db_file"
    echo "----------------------------------------------------"
}

function list_accounts() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║       ${LIGHT_CYAN}DAFTAR AKUN AKTIF${PURPLE}             ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    _display_accounts
    echo ""
    read -p "Tekan Enter untuk kembali ke menu..."
}

function format_kib_to_human() {
    local kib=$1
    if ! [[ "$kib" =~ ^[0-9]+$ ]] || [ -z "$kib" ]; then
        kib=0
    fi
    
    # Using awk for floating point math
    if [ "$kib" -lt 1048576 ]; then
        awk -v val="$kib" 'BEGIN { printf "%.2f MiB", val / 1024 }'
    else
        awk -v val="$kib" 'BEGIN { printf "%.2f GiB", val / 1048576 }'
    fi
}

function get_main_interface() {
    # Find the default network interface using the IP route. This is the most reliable method.
    ip -o -4 route show to default | awk '{print $5}' | head -n 1
}

function _draw_info_panel() {
    # --- Fetch Data ---
    local os_info isp_info ip_info host_info bw_today bw_month client_name license_exp

    os_info=$( (hostnamectl 2>/dev/null | grep "Operating System" | cut -d: -f2 | sed 's/^[ \t]*//') || echo "N/A" )
    os_info=${os_info:-"N/A"}

    local ip_data
    ip_data=$(curl -s ipinfo.io)
    ip_info=$(echo "$ip_data" | jq -r '.ip // "N/A"')
    isp_info=$(echo "$ip_data" | jq -r '.org // "N/A"')
    ip_info=${ip_info:-"N/A"}
    isp_info=${isp_info:-"N/A"}

    local CERT_CN
    CERT_CN=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p' 2>/dev/null || echo "")
    if [ "$CERT_CN" == "zivpn" ] || [ -z "$CERT_CN" ]; then
        host_info=$ip_info
    else
        host_info=$CERT_CN
    fi
    host_info=${host_info:-"N/A"}

    if command -v vnstat &> /dev/null; then
        local iface
        iface=$(get_main_interface)
        local current_year current_month current_day
        current_year=$(date +%Y)
        current_month=$(date +%-m) # Use %-m to avoid leading zero
        current_day=$(date +%-d) # Use %-d to avoid leading zero for days < 10

        # Daily
        local today_total_kib=0
        local vnstat_daily_json
        vnstat_daily_json=$(vnstat --json d 2>/dev/null)
        if [[ -n "$vnstat_daily_json" && "$vnstat_daily_json" == "{"* ]]; then
            today_total_kib=$(echo "$vnstat_daily_json" | jq --arg iface "$iface" --argjson year "$current_year" --argjson month "$current_month" --argjson day "$current_day" '((.interfaces[] | select(.name == $iface) | .traffic.days // [])[] | select(.date.year == $year and .date.month == $month and .date.day == $day) | .total) // 0' | head -n 1)
        fi
        today_total_kib=${today_total_kib:-0}
        bw_today=$(format_kib_to_human "$today_total_kib")

        # Monthly
        local month_total_kib=0
        local vnstat_monthly_json
        vnstat_monthly_json=$(vnstat --json m 2>/dev/null)
        if [[ -n "$vnstat_monthly_json" && "$vnstat_monthly_json" == "{"* ]]; then
            month_total_kib=$(echo "$vnstat_monthly_json" | jq --arg iface "$iface" --argjson year "$current_year" --argjson month "$current_month" '((.interfaces[] | select(.name == $iface) | .traffic.months // [])[] | select(.date.year == $year and .date.month == $month) | .total) // 0' | head -n 1)
        fi
        month_total_kib=${month_total_kib:-0}
        bw_month=$(format_kib_to_human "$month_total_kib")

    else
        bw_today="N/A"
        bw_month="N/A"
    fi

    # --- License Info ---
    if [ -f "$LICENSE_INFO_FILE" ]; then
        source "$LICENSE_INFO_FILE" # Loads CLIENT_NAME and EXPIRY_DATE
        client_name=${CLIENT_NAME:-"N/A"}
        
        if [ -n "$EXPIRY_DATE" ]; then
            local expiry_timestamp
            expiry_timestamp=$(date -d "$EXPIRY_DATE" +%s)
            local current_timestamp
            current_timestamp=$(date +%s)
            local remaining_seconds=$((expiry_timestamp - current_timestamp))
            if [ $remaining_seconds -gt 0 ]; then
                license_exp="$((remaining_seconds / 86400)) days"
            else
                license_exp="Expired"
            fi
        else
            license_exp="N/A"
        fi
    else
        client_name="N/A"
        license_exp="N/A"
    fi

    # --- Print Panel ---
    printf "  ${PINK}%-7s${WHITE}%-18s ${PINK}%-6s${WHITE}%-19s${NC}\n" "OS:" "${os_info}" "ISP:" "${isp_info}"
    printf "  ${PINK}%-7s${WHITE}%-18s ${PINK}%-6s${WHITE}%-19s${NC}\n" "IP:" "${ip_info}" "Host:" "${host_info}"
    printf "  ${PINK}%-7s${WHITE}%-18s ${PINK}%-6s${WHITE}%-19s${NC}\n" "Client:" "${client_name}" "EXP:" "${license_exp}"
    printf "  ${PINK}%-7s${WHITE}%-18s ${PINK}%-6s${WHITE}%-19s${NC}\n" "Today:" "${bw_today}" "Month:" "${bw_month}"
}

function _draw_service_status() {
    local status_text status_color status_output
    local service_status
    service_status=$(systemctl is-active zivpn.service 2>/dev/null)

    if [ "$service_status" = "active" ]; then
        status_text="Running"
        status_color="${LIGHT_GREEN}"
    elif [ "$service_status" = "inactive" ]; then
        status_text="Stopped"
        status_color="${LIGHT_RED}"
    elif [ "$service_status" = "failed" ]; then
        status_text="Error"
        status_color="${LIGHT_RED}"
    else
        status_text="Unknown"
        status_color="${LIGHT_RED}"
    fi

    status_output="${LIGHT_CYAN}Service: ${status_color}${status_text}${NC}"
    
    # Center the text
    local menu_width=55  # Total width of the menu box including borders
    local text_len_visible
    text_len_visible=$(echo -e "$status_output" | sed 's/\x1b\[[0-9;]*m//g' | wc -c)
    text_len_visible=$((text_len_visible - 1))

    local padding_total=$((menu_width - text_len_visible))
    local padding_left=$((padding_total / 2))
    local padding_right=$((padding_total - padding_left))
    
    echo -e "${PURPLE}╠════════════════════════════════════════════════════╣${NC}"
    echo -e "$(printf '%*s' $padding_left)${status_output}$(printf '%*s' $padding_right)"
    echo -e "${PURPLE}╠════════════════════════════════════════════════════╣${NC}"
}

function setup_auto_backup() {
    echo "--- Configure Auto Backup ---"
    if [ ! -f "/etc/zivpn/telegram.conf" ]; then
        echo "Telegram is not configured. Please run a manual backup once to set it up."
        return
    fi

    read -p "Enter backup interval in hours (e.g., 6, 12, 24). Enter 0 to disable: " interval
    if ! [[ "$interval" =~ ^[0-9]+$ ]]; then
        echo "Invalid input. Please enter a number."
        return
    fi

    (crontab -l 2>/dev/null | grep -v "# zivpn-auto-backup") | crontab -

    if [ "$interval" -gt 0 ]; then
        local cron_schedule="0 */${interval} * * *"
        (crontab -l 2>/dev/null; echo "${cron_schedule} /usr/local/bin/zivpn_helper.sh backup >/dev/null 2>&1 # zivpn-auto-backup") | crontab -
        echo "Auto backup scheduled to run every ${interval} hour(s)."
    else
        echo "Auto backup has been disabled."
    fi
}

function create_account() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║        ${LIGHT_CYAN}BUAT AKUN ZIVPN${PURPLE}             ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${LIGHT_BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_BLUE}║                                          ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}1) ${LIGHT_GREEN}Buat Akun Biasa${LIGHT_BLUE}                    ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}2) ${LIGHT_GREEN}Buat Akun Trial${LIGHT_BLUE}                    ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}0) ${LIGHT_GREEN}Kembali ke Menu Utama${LIGHT_BLUE}             ║${NC}"
    echo -e "${LIGHT_BLUE}║                                          ║${NC}"
    echo -e "${LIGHT_BLUE}╚══════════════════════════════════════════╝${NC}"
    
    read -p "Pilih menu [0-2]: " choice

    case $choice in
        1) create_manual_account ;;
        2) create_trial_account ;;
        0) return ;;
        *) echo -e "${RED}Pilihan tidak valid!${NC}"; sleep 1 ;;
    esac
}

function show_backup_menu() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║       ${LIGHT_CYAN}BACKUP & RESTORE${PURPLE}             ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${LIGHT_BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_BLUE}║                                          ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}1) ${LIGHT_GREEN}Backup Data${LIGHT_BLUE}                         ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}2) ${LIGHT_GREEN}Restore Data${LIGHT_BLUE}                        ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}3) ${LIGHT_GREEN}Auto Backup${LIGHT_BLUE}                         ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}4) ${LIGHT_GREEN}Reset Notif Telegram${LIGHT_BLUE}               ║${NC}"
    echo -e "${LIGHT_BLUE}║   ${WHITE}0) ${LIGHT_GREEN}Kembali ke Menu Utama${LIGHT_BLUE}              ║${NC}"
    echo -e "${LIGHT_BLUE}║                                          ║${NC}"
    echo -e "${LIGHT_BLUE}╚══════════════════════════════════════════╝${NC}"
    
    read -p "Pilih menu [0-4]: " choice
    
    case $choice in
        1) /usr/local/bin/zivpn_helper.sh backup ;;
        2) /usr/local/bin/zivpn_helper.sh restore ;;
        3) setup_auto_backup ;;
        4) /usr/local/bin/zivpn_helper.sh setup-telegram ;;
        0) return ;;
        *) echo -e "${RED}Pilihan tidak valid!${NC}"; sleep 1 ;;
    esac
}

function show_expired_message_and_exit() {
    clear
    echo -e "\n${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║   ${LIGHT_RED}LISENSI ANDA TELAH KEDALUWARSA!${PURPLE}   ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}\n"
    echo -e "${WHITE}Akses ke layanan ZIVPN di server anda telah dihentikan."
    echo -e "Segala aktivitas VPN tidak akan berfungsi lagi.\n"
    echo -e "Untuk memperpanjang lisensi dan mengaktifkan kembali layanan,"
    echo -e "silakan hubungi admin PONDOK VPN\n"
    echo -e "${LIGHT_BLUE}WHATSAPP: 082147725445${NC}"
    echo -e "${LIGHT_BLUE}TELEGRAM: @bendakerep${NC}\n"
    echo -e "${LIGHT_GREEN}Setelah diperpanjang, layanan akan aktif kembali secara otomatis.${NC}\n"
    exit 0
}

function show_menu() {
    if [ -f "/etc/zivpn/.expired" ]; then
        show_expired_message_and_exit
    fi

    clear
    if command -v figlet &> /dev/null && command -v lolcat &> /dev/null; then
        figlet "PONDOK VPN" | lolcat
    else
        echo -e "${LIGHT_CYAN}╔══════════════════════════════════════════╗${NC}"
        echo -e "${LIGHT_CYAN}║           ${WHITE}PONDOK VPN${LIGHT_CYAN}               ║${NC}"
        echo -e "${LIGHT_CYAN}╚══════════════════════════════════════════╝${NC}"
    fi
    
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║           ${LIGHT_CYAN}PONDOK VPN${PURPLE}               ║${NC}"
    echo -e "${PURPLE}╠══════════════════════════════════════════╣${NC}"
    _draw_info_panel
    _draw_service_status
    echo -e "${PURPLE}║                                          ║${NC}"
    echo -e "${PURPLE}║   ${WHITE}1) ${LIGHT_GREEN}Buat Akun${PURPLE}                             ║${NC}"
    echo -e "${PURPLE}║   ${WHITE}2) ${LIGHT_GREEN}Renew Akun${PURPLE}                            ║${NC}"
    echo -e "${PURPLE}║   ${WHITE}3) ${LIGHT_GREEN}Hapus Akun${PURPLE}                            ║${NC}"
    echo -e "${PURPLE}║   ${WHITE}4) ${LIGHT_GREEN}Ganti Domain${PURPLE}                          ║${NC}"
    echo -e "${PURPLE}║   ${WHITE}5) ${LIGHT_GREEN}List Akun${PURPLE}                             ║${NC}"
    echo -e "${PURPLE}║   ${WHITE}6) ${LIGHT_GREEN}Backup/Restore${PURPLE}                        ║${NC}"
    echo -e "${PURPLE}║   ${WHITE}7) ${LIGHT_GREEN}Bot Telegram${PURPLE}                          ║${NC}"
    echo -e "${PURPLE}║   ${WHITE}8) ${LIGHT_GREEN}Manajemen Domain${PURPLE}                      ║${NC}"
    echo -e "${PURPLE}║   ${WHITE}0) ${LIGHT_GREEN}Exit${PURPLE}                                  ║${NC}"
    echo -e "${PURPLE}║                                          ║${NC}"
    echo -e "${PURPLE}╠══════════════════════════════════════════╣${NC}"
    echo -e "${PURPLE}║   ${LIGHT_YELLOW}☎️ 082147725445${PURPLE}                     ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    
    read -p "Pilih menu [0-8]: " choice

    case $choice in
        1) create_account ;;
        2) renew_account ;;
        3) delete_account ;;
        4) change_domain ;;
        5) list_accounts ;;
        6) show_backup_menu ;;
        7) telegram_bot_menu ;;
        8) domain_menu ;;
        0) exit 0 ;;
        *) echo -e "${RED}Pilihan tidak valid!${NC}"; sleep 1 ;;
    esac
}

# --- Main Installation and Setup Logic ---
function run_setup() {
    verify_license # <-- VERIFY LICENSE HERE

    # --- Run Base Installation ---
    echo "--- Starting Base Installation ---"
    wget -O zi.sh https://raw.githubusercontent.com/Pondok-Vpn/udp-zivpn/main/zi.sh
    if [ $? -ne 0 ]; then echo "Failed to download base installer. Aborting."; exit 1; fi
    chmod +x zi.sh
    ./zi.sh
    if [ $? -ne 0 ]; then echo "Base installation script failed. Aborting."; exit 1; fi
    rm zi.sh
    echo "--- Base Installation Complete ---"

    # --- Setting up Advanced Management ---
    echo "--- Setting up Advanced Management ---"

    if ! command -v jq &> /dev/null || ! command -v curl &> /dev/null || ! command -v zip &> /dev/null || ! command -v figlet &> /dev/null || ! command -v lolcat &> /dev/null || ! command -v vnstat &> /dev/null; then
        echo "Installing dependencies (jq, curl, zip, figlet, lolcat, vnstat)..."
        apt-get update && apt-get install -y jq curl zip figlet lolcat vnstat
    fi

    # --- vnstat setup ---
    echo "Configuring vnstat for bandwidth monitoring..."
    local net_interface
    net_interface=$(ip -o -4 route show to default | awk '{print $5}' | head -n 1)
    if [ -n "$net_interface" ]; then
        echo "Detected network interface: $net_interface"
        # Wait for the service to be available after installation
        sleep 2
        systemctl stop vnstat
        vnstat -u -i "$net_interface" --force
        systemctl enable vnstat
        systemctl start vnstat
        echo "vnstat setup complete for interface $net_interface."
    else
        echo "Warning: Could not automatically detect network interface for vnstat."
    fi
    
    # Download helper script from repository
    echo "Downloading helper script..."
    wget -O /usr/local/bin/zivpn_helper.sh https://raw.githubusercontent.com/Pondok-Vpn/udp-zivpn/main/zivpn_helper.sh
    if [ $? -ne 0 ]; then
        echo "Failed to download helper script. Aborting."
        exit 1
    fi
    chmod +x /usr/local/bin/zivpn_helper.sh

    echo "Clearing initial password(s) set during base installation..."
    jq '.auth.config = []' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json

    touch /etc/zivpn/users.db
    touch /etc/zivpn/devices.db

    RANDOM_PASS="zivpn$(shuf -i 10000-99999 -n 1)"
    EXPIRY_DATE=$(date -d "+1 day" +%s)
    MAX_DEVICES=2

    echo "Creating a temporary initial account..."
    echo "${RANDOM_PASS}:${EXPIRY_DATE}:${MAX_DEVICES}" >> /etc/zivpn/users.db
    jq --arg pass "$RANDOM_PASS" '.auth.config += [$pass]' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json

    echo "Setting up expiry check cron job..."
    cat <<'EOF' > /etc/zivpn/expire_check.sh
#!/bin/bash
DB_FILE="/etc/zivpn/users.db"
DEVICE_DB="/etc/zivpn/devices.db"
CONFIG_FILE="/etc/zivpn/config.json"
TMP_DB_FILE="${DB_FILE}.tmp"
CURRENT_DATE=$(date +%s)
SERVICE_RESTART_NEEDED=false

if [ ! -f "$DB_FILE" ]; then exit 0; fi
> "$TMP_DB_FILE"

while IFS=':' read -r password expiry_date max_devices; do
    if [[ -z "$password" ]]; then continue; fi

    if [ "$expiry_date" -le "$CURRENT_DATE" ]; then
        echo "User '${password}' has expired. Deleting permanently."
        jq --arg pass "$password" 'del(.auth.config[] | select(. == $pass))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        # Also delete from device database
        sed -i "/^${password}:/d" "$DEVICE_DB" 2>/dev/null
        SERVICE_RESTART_NEEDED=true
    else
        echo "${password}:${expiry_date}:${max_devices}" >> "$TMP_DB_FILE"
    fi
done < "$DB_FILE"

mv "$TMP_DB_FILE" "$DB_FILE"

if [ "$SERVICE_RESTART_NEEDED" = true ]; then
    echo "Restarting zivpn service due to user removal."
    systemctl restart zivpn.service
fi

# Clear expired device entries (older than 24 hours)
CLEAN_TIME=$((CURRENT_DATE - 86400))
if [ -f "$DEVICE_DB" ]; then
    TEMP_DEVICE_DB=$(mktemp)
    while IFS=':' read -r username ip timestamp; do
        if [ "$timestamp" -gt "$CLEAN_TIME" ]; then
            echo "${username}:${ip}:${timestamp}" >> "$TEMP_DEVICE_DB"
        fi
    done < "$DEVICE_DB"
    mv "$TEMP_DEVICE_DB" "$DEVICE_DB"
fi

exit 0
EOF
    chmod +x /etc/zivpn/expire_check.sh
    CRON_JOB_EXPIRY="* * * * * /etc/zivpn/expire_check.sh # zivpn-expiry-check"
    (crontab -l 2>/dev/null | grep -v "# zivpn-expiry-check") | crontab -
    (crontab -l 2>/dev/null; echo "$CRON_JOB_EXPIRY") | crontab -

    echo "Setting up license check script and cron job..."
    cat <<'EOF' > /etc/zivpn/license_checker.sh
#!/bin/bash
# Zivpn License Checker
# This script is run by a cron job to periodically check the license status.

# --- Configuration ---
LICENSE_URL="https://raw.githubusercontent.com/Pondok-Vpn/pondokvip/main/register"
LICENSE_INFO_FILE="/etc/zivpn/.license_info"
EXPIRED_LOCK_FILE="/etc/zivpn/.expired"
TELEGRAM_CONF="/etc/zivpn/telegram.conf"
LOG_FILE="/var/log/zivpn_license.log"

# --- Logging ---
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# --- Helper Functions ---
function get_host() {
    local CERT_CN
    CERT_CN=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p' 2>/dev/null || echo "")
    if [ "$CERT_CN" == "zivpn" ] || [ -z "$CERT_CN" ]; then
        curl -s ifconfig.me
    else
        echo "$CERT_CN"
    fi
}

function get_isp() {
    curl -s ipinfo.io | jq -r '.org // "N/A"'
}


# --- Telegram Notification Function ---
send_telegram_message() {
    local message="$1"
    
    if [ ! -f "$TELEGRAM_CONF" ]; then
        log "Telegram config not found, skipping notification."
        return
    fi
    
    source "$TELEGRAM_CONF"
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        local api_url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
        curl -s -X POST "$api_url" -d "chat_id=${TELEGRAM_CHAT_ID}" --data-urlencode "text=${message}" -d "parse_mode=Markdown" > /dev/null
        log "Simple telegram notification sent."
    else
        log "Telegram config found but token or chat ID is missing."
    fi
}

# --- Main Logic ---
log "Starting license check..."

# 1. Get Server IP
SERVER_IP=$(curl -s ifconfig.me)
if [ -z "$SERVER_IP" ]; then
    log "Error: Failed to retrieve server IP. Exiting."
    exit 1
fi

# 2. Get Local License Info
if [ ! -f "$LICENSE_INFO_FILE" ]; then
    log "Error: Local license info file not found. Exiting."
    exit 1
fi
source "$LICENSE_INFO_FILE" # This loads CLIENT_NAME and EXPIRY_DATE

# 3. Fetch Remote License Data
license_data=$(curl -s "$LICENSE_URL")
if [ $? -ne 0 ] || [ -z "$license_data" ]; then
    log "Error: Failed to connect to license server. Exiting."
    exit 1
fi

# 4. Check License Status from Remote
license_entry=$(echo "$license_data" | grep -w "$SERVER_IP")

if [ -z "$license_entry" ]; then
    # IP not found in remote list (Revoked)
    if [ ! -f "$EXPIRED_LOCK_FILE" ]; then
        log "License for IP ${SERVER_IP} has been REVOKED."
        systemctl stop zivpn.service
        touch "$EXPIRED_LOCK_FILE"
        local MSG="Notifikasi Otomatis: Lisensi untuk Klien \`${CLIENT_NAME}\` dengan IP \`${SERVER_IP}\` telah dicabut (REVOKED). Layanan zivpn telah dihentikan."
        send_telegram_message "$MSG"
    fi
    exit 0
fi

# 5. IP Found, Check for Expiry or Renewal
client_name_remote=$(echo "$license_entry" | awk '{print $1}')
expiry_date_remote=$(echo "$license_entry" | awk '{print $2}')
expiry_timestamp_remote=$(date -d "$expiry_date_remote" +%s)
current_timestamp=$(date +%s)

# Update local license info file with the latest from server
if [ "$expiry_date_remote" != "$EXPIRY_DATE" ]; then
    log "Remote license has a different expiry date (${expiry_date_remote}). Updating local file."
    echo "CLIENT_NAME=${client_name_remote}" > "$LICENSE_INFO_FILE"
    echo "EXPIRY_DATE=${expiry_date_remote}" >> "$LICENSE_INFO_FILE"
    CLIENT_NAME=$client_name_remote
    EXPIRY_DATE=$expiry_date_remote
fi

if [ "$expiry_timestamp_remote" -le "$current_timestamp" ]; then
    # License is EXPIRED
    if [ ! -f "$EXPIRED_LOCK_FILE" ]; then
        log "License for IP ${SERVER_IP} has EXPIRED."
        systemctl stop zivpn.service
        touch "$EXPIRED_LOCK_FILE"
        local host
        host=$(get_host)
        local isp
        isp=$(get_isp)
        log "Sending rich expiry notification via helper script..."
        /usr/local/bin/zivpn_helper.sh expiry-notification "$host" "$SERVER_IP" "$CLIENT_NAME" "$isp" "$EXPIRY_DATE"
    fi
else
    # License is ACTIVE (potentially renewed)
    if [ -f "$EXPIRED_LOCK_FILE" ]; then
        log "License for IP ${SERVER_IP} has been RENEWED/ACTIVATED."
        rm "$EXPIRED_LOCK_FILE"
        systemctl start zivpn.service
        local host
        host=$(get_host)
        local isp
        isp=$(get_isp)
        log "Sending rich renewed notification via helper script..."
        /usr/local/bin/zivpn_helper.sh renewed-notification "$host" "$SERVER_IP" "$CLIENT_NAME" "$isp" "$expiry_timestamp_remote"
    else
        log "License is active and valid. No action needed."
    fi
fi

log "License check finished."
exit 0
EOF
    chmod +x /etc/zivpn/license_checker.sh

    CRON_JOB_LICENSE="*/5 * * * * /etc/zivpn/license_checker.sh # zivpn-license-check"
    (crontab -l 2>/dev/null | grep -v "# zivpn-license-check") | crontab -
    (crontab -l 2>/dev/null; echo "$CRON_JOB_LICENSE") | crontab -

    # --- Telegram Notification Setup ---
    if [ ! -f "/etc/zivpn/telegram.conf" ]; then
        echo ""
        read -p "Apakah Anda ingin mengatur notifikasi Telegram untuk status lisensi? (y/n): " confirm
        if [[ "$confirm" == [yY] || "$confirm" == [yY][eE][sS] ]]; then
            /usr/local/bin/zivpn_helper.sh setup-telegram
        else
            echo "Anda dapat mengaturnya nanti melalui menu Backup/Restore."
        fi
    fi

    restart_zivpn

    # --- System Integration ---
    echo "--- Integrating management script into the system ---"
    cp "$0" /usr/local/bin/zivpn-manager
    chmod +x /usr/local/bin/zivpn-manager

    PROFILE_FILE="/root/.bashrc"
    if [ -f "/root/.bash_profile" ]; then PROFILE_FILE="/root/.bash_profile"; fi
    
    ALIAS_CMD="alias menu='/usr/local/bin/zivpn-manager'"
    AUTORUN_CMD="/usr/local/bin/zivpn-manager"

    grep -qF "$ALIAS_CMD" "$PROFILE_FILE" || echo "$ALIAS_CMD" >> "$PROFILE_FILE"
    grep -qF "$AUTORUN_CMD" "$PROFILE_file" || echo "$AUTORUN_CMD" >> "$PROFILE_FILE"

    echo "The 'menu' command is now available."
    echo "The management menu will now open automatically on login."
    
    echo "-----------------------------------------------------"
    echo "Advanced management setup complete."
    echo "Password for temporary account (expires 24h): ${RANDOM_PASS}"
    echo "Device limit: ${MAX_DEVICES} devices"
    echo "-----------------------------------------------------"
    read -p "Press Enter to continue to the management menu..."
}

# --- Main Script ---
function main() {
    if [ ! -f "/etc/systemd/system/zivpn.service" ]; then
        run_setup
    fi

    while true; do
        show_menu
    done
}

# Execute main function only when script is run directly, not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check if called from menu (for SSH Xray menu integration)
    if [ "$1" = "start" ]; then
        start_zivpn
    else
        main
    fi
fi
