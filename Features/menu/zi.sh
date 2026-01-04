#!/bin/bash
# =============================
# ZIVPN MANAGER - SSH/XRAY INTEGRATION
# =============================

# --- VALIDASI WARNA ---
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
NC='\033[0m'

# --- Path Configuration ---
ZIVPN_DIR="/etc/zivpn"
USER_DB="$ZIVPN_DIR/users.db"
DEVICE_DB="$ZIVPN_DIR/devices.db"
CONFIG_JSON="$ZIVPN_DIR/config.json"
SERVICE_NAME="zivpn.service"
INSTALL_PATH="/usr/local/bin/menu-zivpn"

# --- Pre-flight Checks ---
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}❌ Script harus dijalankan sebagai root!${NC}"
  echo -e "${YELLOW}Gunakan: sudo bash $0${NC}"
  exit 1
fi

# =============================
# HELPER FUNCTIONS
# =============================

function check_dependencies() {
    echo -e "${BLUE}🔍 Mengecek dependencies...${NC}"
    
    local deps=("jq" "openssl" "curl" "unzip" "bc")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Menginstall: ${missing[*]}${NC}"
        apt-get update > /dev/null 2>&1
        for dep in "${missing[@]}"; do
            apt-get install -y "$dep" > /dev/null 2>&1 && \
            echo -e "${GREEN}✅ $dep terinstall${NC}" || \
            echo -e "${RED}❌ Gagal install $dep${NC}"
        done
    else
        echo -e "${GREEN}✅ Semua dependencies tersedia${NC}"
    fi
}

function check_zivpn_installed() {
    if [ -f "/etc/systemd/system/$SERVICE_NAME" ] && [ -d "$ZIVPN_DIR" ]; then
        return 0
    else
        return 1
    fi
}

function restart_zivpn_service() {
    echo -e "${BLUE}🔄 Restarting service...${NC}"
    if systemctl restart "$SERVICE_NAME" 2>/dev/null; then
        echo -e "${GREEN}✅ Service restarted${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  Gagal restart, mencoba start...${NC}"
        if systemctl start "$SERVICE_NAME" 2>/dev/null; then
            echo -e "${GREEN}✅ Service started${NC}"
            return 0
        else
            echo -e "${RED}❌ Gagal start service${NC}"
            return 1
        fi
    fi
}

function validate_domain() {
    local domain="$1"
    if [[ "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# =============================
# INSTALLATION FUNCTIONS
# =============================

function install_zivpn() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║         ${LIGHT_CYAN}INSTALL ZIVPN${PURPLE}               ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    if check_zivpn_installed; then
        echo -e "${YELLOW}⚠️  ZIVPN sudah terinstall!${NC}"
        read -p "Ingin reinstall? (y/n): " reinstall
        if [[ "$reinstall" != "y" && "$reinstall" != "Y" ]]; then
            return
        fi
    fi
    
    check_dependencies
    
    echo -e "${BLUE}📥 Mengunduh installer ZIVPN...${NC}"
    
    local installer_url="https://raw.githubusercontent.com/Pondok-Vpn/pondokvip/main/zi.sh"
    local installer_path="/tmp/zivpn-installer-$$.sh"
    
    if ! curl -s --max-time 60 --retry 2 --retry-delay 3 -o "$installer_path" "$installer_url"; then
        echo -e "${RED}❌ Gagal mengunduh installer!${NC}"
        echo -e "${YELLOW}Periksa koneksi internet atau repository.${NC}"
        return 1
    fi
    
    if [ ! -s "$installer_path" ]; then
        echo -e "${RED}❌ File installer kosong!${NC}"
        return 1
    fi
    
    chmod +x "$installer_path"
    echo -e "${GREEN}✅ Installer siap${NC}"
    echo -e "${YELLOW}⏳ Proses install dimulai...${NC}"
    echo ""
    
    if bash "$installer_path"; then
        echo ""
        if check_zivpn_installed; then
            echo -e "${GREEN}════════════════════════════════════════════${NC}"
            echo -e "${GREEN}✅ INSTALASI BERHASIL!${NC}"
            echo -e "${GREEN}════════════════════════════════════════════${NC}"
            
            sleep 2
            setup_initial_config
            
            echo ""
            echo -e "${LIGHT_GREEN}ZIVPN siap digunakan!${NC}"
            echo -e "${YELLOW}Silakan buat akun pertama Anda.${NC}"
            sleep 3
            return 0
        else
            echo -e "${RED}❌ Instalasi gagal - service tidak terdeteksi${NC}"
            return 1
        fi
    else
        echo -e "${RED}❌ Proses instalasi gagal!${NC}"
        return 1
    fi
}

function setup_initial_config() {
    echo -e "${BLUE}🔧 Setup konfigurasi awal...${NC}"
    
    mkdir -p "$ZIVPN_DIR"
    touch "$USER_DB" "$DEVICE_DB"
    chmod 600 "$USER_DB" "$DEVICE_DB"
    
    setup_cron_job
    
    echo -e "${GREEN}✅ Setup selesai${NC}"
}

function setup_cron_job() {
    local cron_script="$ZIVPN_DIR/expire_check.sh"
    
    cat > "$cron_script" << 'EOF'
#!/bin/bash
DB_FILE="/etc/zivpn/users.db"
DEVICE_DB="/etc/zivpn/devices.db"
CONFIG_FILE="/etc/zivpn/config.json"
CURRENT_DATE=$(date +%s)
SERVICE_RESTART_NEEDED=false

if [ ! -f "$DB_FILE" ]; then
    exit 0
fi

TMP_DB_FILE=$(mktemp)
while IFS=':' read -r password expiry_date max_devices; do
    if [[ -z "$password" ]]; then
        continue
    fi

    if [ "$expiry_date" -le "$CURRENT_DATE" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'): User '$password' expired"
        if [ -f "$CONFIG_FILE" ]; then
            jq --arg pass "$password" 'del(.auth.config[] | select(. == $pass))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && \
            mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        fi
        sed -i "/^${password}:/d" "$DEVICE_DB" 2>/dev/null
        SERVICE_RESTART_NEEDED=true
    else
        echo "${password}:${expiry_date}:${max_devices}" >> "$TMP_DB_FILE"
    fi
done < "$DB_FILE"

mv "$TMP_DB_FILE" "$DB_FILE"

if [ -f "$DEVICE_DB" ]; then
    CLEAN_TIME=$((CURRENT_DATE - 86400))
    TEMP_DEVICE_DB=$(mktemp)
    while IFS=':' read -r username ip timestamp; do
        if [[ -n "$username" && -n "$timestamp" && "$timestamp" -gt "$CLEAN_TIME" ]]; then
            echo "${username}:${ip}:${timestamp}" >> "$TEMP_DEVICE_DB"
        fi
    done < "$DEVICE_DB"
    mv "$TEMP_DEVICE_DB" "$DEVICE_DB"
fi

if [ "$SERVICE_RESTART_NEEDED" = true ]; then
    systemctl restart zivpn.service 2>/dev/null
fi

exit 0
EOF
    
    chmod +x "$cron_script"
    
    (crontab -l 2>/dev/null | grep -v "zivpn-expiry-check") | crontab -
    (crontab -l 2>/dev/null; echo "* * * * * $cron_script # zivpn-expiry-check") | crontab -
    
    echo -e "${GREEN}✅ Cron job terpasang${NC}"
}

# =============================
# ACCOUNT MANAGEMENT
# =============================

function create_zivpn_account() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║       ${LIGHT_CYAN}BUAT AKUN ZIVPN${PURPLE}              ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    while true; do
        read -p "Masukkan password (min 3 karakter): " password
        if [ -z "$password" ]; then
            echo -e "${RED}❌ Password tidak boleh kosong${NC}"
        elif [ ${#password} -lt 3 ]; then
            echo -e "${RED}❌ Password minimal 3 karakter${NC}"
        else
            break
        fi
    done
    
    if grep -q "^${password}:" "$USER_DB" 2>/dev/null; then
        echo -e "${YELLOW}⚠️  Password '$password' sudah ada${NC}"
        read -p "Lanjutkan? (y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            return
        fi
    fi
    
    while true; do
        read -p "Masukkan masa aktif (hari): " days
        if [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -gt 0 ]; then
            break
        else
            echo -e "${RED}❌ Masukkan angka yang valid${NC}"
        fi
    done
    
    read -p "Masukkan limit device (default: 2): " max_devices
    if [ -z "$max_devices" ] || ! [[ "$max_devices" =~ ^[0-9]+$ ]]; then
        max_devices=2
        echo -e "${YELLOW}Menggunakan default: 2 device${NC}"
    fi
    
    local expiry_date=$(date -d "+$days days" +%s)
    
    echo "${password}:${expiry_date}:${max_devices}" >> "$USER_DB"
    
    if [ -f "$CONFIG_JSON" ]; then
        jq --arg pass "$password" '.auth.config += [$pass]' "$CONFIG_JSON" > /tmp/config.json.tmp && \
        mv /tmp/config.json.tmp "$CONFIG_JSON"
    fi
    
    local HOST=""
    if [ -f "/etc/zivpn/zivpn.crt" ]; then
        local CERT_CN=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject 2>/dev/null | sed -n 's/.*CN = \([^,]*\).*/\1/p')
        if [ "$CERT_CN" == "zivpn" ]; then
            HOST=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "SERVER_IP")
        else
            HOST="$CERT_CN"
        fi
    else
        HOST=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "SERVER_IP")
    fi
    
    local EXPIRE_FORMATTED=$(date -d "@$expiry_date" +"%d %B %Y")
    
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
    echo -e "${LIGHT_GREEN}║   ${LIGHT_CYAN}Terima kasih sudah order!${LIGHT_GREEN}            ║${NC}"
    echo -e "${LIGHT_GREEN}╚══════════════════════════════════════════╝${NC}"
    
    restart_zivpn_service
    
    echo ""
    read -p "Tekan Enter untuk kembali ke menu..."
}

function create_trial_account() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║       ${LIGHT_CYAN}TRIAL ZIVPN${PURPLE}                  ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    while true; do
        read -p "Masukkan masa aktif (menit, min 5): " minutes
        if [[ "$minutes" =~ ^[0-9]+$ ]] && [ "$minutes" -ge 5 ]; then
            break
        else
            echo -e "${RED}❌ Minimal 5 menit${NC}"
        fi
    done
    
    local password="trial$(shuf -i 10000-99999 -n 1)"
    local max_devices=1
    local expiry_date=$(date -d "+$minutes minutes" +%s)
    
    echo "${password}:${expiry_date}:${max_devices}" >> "$USER_DB"
    
    if [ -f "$CONFIG_JSON" ]; then
        jq --arg pass "$password" '.auth.config += [$pass]' "$CONFIG_JSON" > /tmp/config.json.tmp && \
        mv /tmp/config.json.tmp "$CONFIG_JSON"
    fi
    
    local HOST=""
    if [ -f "/etc/zivpn/zivpn.crt" ]; then
        local CERT_CN=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject 2>/dev/null | sed -n 's/.*CN = \([^,]*\).*/\1/p')
        if [ "$CERT_CN" == "zivpn" ]; then
            HOST=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "SERVER_IP")
        else
            HOST="$CERT_CN"
        fi
    else
        HOST=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "SERVER_IP")
    fi
    
    local EXPIRE_FORMATTED=$(date -d "@$expiry_date" +"%d %B %Y %H:%M:%S")
    
    clear
    echo -e "${LIGHT_GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_GREEN}║     ${WHITE}✅ TRIAL BERHASIL${LIGHT_GREEN}            ║${NC}"
    echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${LIGHT_GREEN}║                                          ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Host: ${WHITE}$HOST${LIGHT_GREEN}                   ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Password: ${WHITE}$password${LIGHT_GREEN}           ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Expire: ${WHITE}$EXPIRE_FORMATTED${LIGHT_GREEN}     ║${NC}"
    echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Limit Device: ${WHITE}$max_devices device${LIGHT_GREEN}   ║${NC}"
    echo -e "${LIGHT_GREEN}║                                          ║${NC}"
    echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${LIGHT_GREEN}║   ${LIGHT_CYAN}Terima kasih sudah mencoba!${LIGHT_GREEN}         ║${NC}"
    echo -e "${LIGHT_GREEN}╚══════════════════════════════════════════╝${NC}"
    
    restart_zivpn_service
    
    echo ""
    read -p "Tekan Enter untuk kembali ke menu..."
}

function list_accounts() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║       ${LIGHT_CYAN}DAFTAR AKUN AKTIF${PURPLE}             ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ ! -f "$USER_DB" ] || [ ! -s "$USER_DB" ]; then
        echo -e "${YELLOW}Tidak ada akun ditemukan.${NC}"
        echo ""
        read -p "Tekan Enter untuk kembali..."
        return
    fi

    local current_date=$(date +%s)
    local count=0
    
    echo -e "${LIGHT_BLUE}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${LIGHT_BLUE}║ ${WHITE}No.  Password             Expired        Device${LIGHT_BLUE} ║${NC}"
    echo -e "${LIGHT_BLUE}╠═══════════════════════════════════════════════════════╣${NC}"
    
    while IFS=':' read -r password expiry_date max_devices; do
        if [[ -n "$password" ]]; then
            count=$((count + 1))
            local remaining_seconds=$((expiry_date - current_date))
            
            if [ $remaining_seconds -gt 0 ]; then
                local remaining_days=$((remaining_seconds / 86400))
                local expired_str=$(date -d "@$expiry_date" +"%d-%m-%Y")
                if [ $remaining_days -lt 1 ]; then
                    expired_str="$remaining_seconds detik"
                fi
                echo -e "${LIGHT_BLUE}║ ${WHITE}$(printf "%2d" $count). ${password:0:18} $(printf "%12s" "$expired_str") $(printf "%4s" $max_devices)${LIGHT_BLUE} ║${NC}"
            else
                echo -e "${LIGHT_BLUE}║ ${WHITE}$(printf "%2d" $count). ${password:0:18} ${RED}EXPIRED${WHITE}            $(printf "%4s" $max_devices)${LIGHT_BLUE} ║${NC}"
            fi
        fi
    done < "$USER_DB"
    
    echo -e "${LIGHT_BLUE}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${LIGHT_GREEN}Total akun: $count${NC}"
    echo ""
    read -p "Tekan Enter untuk kembali ke menu..."
}

function renew_account() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║       ${LIGHT_CYAN}RENEW AKUN ZIVPN${PURPLE}              ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ ! -f "$USER_DB" ] || [ ! -s "$USER_DB" ]; then
        echo -e "${YELLOW}Tidak ada akun yang ditemukan.${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    echo -e "${LIGHT_BLUE}Daftar Akun:${NC}"
    echo -e "${WHITE}══════════════════════════════════════════${NC}"
    
    local accounts=()
    local count=0
    
    while IFS=':' read -r password expiry_date max_devices; do
        if [[ -n "$password" ]]; then
            count=$((count + 1))
            accounts+=("$password:$expiry_date:$max_devices")
            local expired_str=$(date -d "@$expiry_date" +"%d-%m-%Y")
            echo -e "${WHITE}$count. ${password} (exp: ${expired_str}, device: ${max_devices})${NC}"
        fi
    done < "$USER_DB"
    
    if [ $count -eq 0 ]; then
        echo -e "${YELLOW}Tidak ada akun yang ditemukan.${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    echo -e "${WHITE}══════════════════════════════════════════${NC}"
    echo ""
    
    while true; do
        read -p "Masukkan nomor akun [1-$count]: " account_number
        if [[ "$account_number" =~ ^[0-9]+$ ]] && [ "$account_number" -ge 1 ] && [ "$account_number" -le "$count" ]; then
            break
        else
            echo -e "${RED}❌ Masukkan angka 1-$count${NC}"
        fi
    done
    
    local selected_data="${accounts[$((account_number-1))]}"
    IFS=':' read -r selected_password current_expiry max_devices <<< "$selected_data"
    
    while true; do
        read -p "Masukkan jumlah hari untuk ditambahkan: " days
        if [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -gt 0 ]; then
            break
        else
            echo -e "${RED}❌ Masukkan angka yang valid${NC}"
        fi
    done
    
    local seconds_to_add=$((days * 86400))
    local new_expiry_date=$((current_expiry + seconds_to_add))
    
    sed -i "s/^${selected_password}:.*/${selected_password}:${new_expiry_date}:${max_devices}/" "$USER_DB"
    sed -i "/^${selected_password}:/d" "$DEVICE_DB" 2>/dev/null
    
    local new_expiry_formatted=$(date -d "@$new_expiry_date" +"%d %B %Y")
    echo ""
    echo -e "${GREEN}✅ Masa aktif akun berhasil diperpanjang${NC}"
    echo -e "${LIGHT_BLUE}Password: ${WHITE}${selected_password}${NC}"
    echo -e "${LIGHT_BLUE}Expire baru: ${WHITE}${new_expiry_formatted}${NC}"
    echo -e "${LIGHT_GREEN}Device tracking telah direset${NC}"
    
    restart_zivpn_service
    
    echo ""
    read -p "Tekan Enter untuk kembali ke menu..."
}

function delete_account() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║       ${LIGHT_CYAN}HAPUS AKUN ZIVPN${PURPLE}              ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ ! -f "$USER_DB" ] || [ ! -s "$USER_DB" ]; then
        echo -e "${YELLOW}Tidak ada akun yang ditemukan.${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    echo -e "${LIGHT_BLUE}Daftar Akun:${NC}"
    echo -e "${WHITE}══════════════════════════════════════════${NC}"
    
    local accounts=()
    local count=0
    
    while IFS=':' read -r password expiry_date max_devices; do
        if [[ -n "$password" ]]; then
            count=$((count + 1))
            accounts+=("$password:$expiry_date:$max_devices")
            echo -e "${WHITE}$count. ${password} (device: ${max_devices})${NC}"
        fi
    done < "$USER_DB"
    
    if [ $count -eq 0 ]; then
        echo -e "${YELLOW}Tidak ada akun yang ditemukan.${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    echo -e "${WHITE}══════════════════════════════════════════${NC}"
    echo ""
    
    while true; do
        read -p "Masukkan nomor akun [1-$count]: " account_number
        if [[ "$account_number" =~ ^[0-9]+$ ]] && [ "$account_number" -ge 1 ] && [ "$account_number" -le "$count" ]; then
            break
        else
            echo -e "${RED}❌ Masukkan angka 1-$count${NC}"
        fi
    done
    
    local selected_data="${accounts[$((account_number-1))]}"
    IFS=':' read -r selected_password expiry_date max_devices <<< "$selected_data"
    
    echo ""
    echo -e "${YELLOW}⚠️  Anda akan menghapus akun:${NC}"
    echo -e "${WHITE}Password: ${selected_password}${NC}"
    echo -e "${WHITE}Max Devices: ${max_devices}${NC}"
    echo ""
    read -p "Konfirmasi penghapusan? (y/n): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}Penghapusan dibatalkan.${NC}"
        sleep 1
        return
    fi
    
    sed -i "/^${selected_password}:/d" "$USER_DB"
    sed -i "/^${selected_password}:/d" "$DEVICE_DB" 2>/dev/null
    
    if [ -f "$CONFIG_JSON" ]; then
        jq --arg pass "$selected_password" 'del(.auth.config[] | select(. == $pass))' "$CONFIG_JSON" > /tmp/config.json.tmp && \
        mv /tmp/config.json.tmp "$CONFIG_JSON"
    fi
    
    echo -e "${GREEN}✅ Akun '${selected_password}' berhasil dihapus.${NC}"
    
    restart_zivpn_service
    
    sleep 2
}

function change_domain() {
    clear
    
    local current_domain=""
    if [ -f "/etc/zivpn/zivpn.crt" ]; then
        current_domain=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject 2>/dev/null | sed -n 's/.*CN = \([^,]*\).*/\1/p')
    fi
    
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║         ${LIGHT_CYAN}GANTI DOMAIN${PURPLE}                ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ -n "$current_domain" ]; then
        echo -e "${LIGHT_BLUE}Domain saat ini: ${WHITE}${current_domain}${NC}"
        echo ""
    fi
    
    while true; do
        read -p "Masukkan domain baru (contoh: vpn.pondok.com): " domain
        if validate_domain "$domain"; then
            break
        else
            echo -e "${RED}❌ Format domain tidak valid!${NC}"
            echo -e "${YELLOW}Contoh: vpn.pondok.com, server.domain.com${NC}"
        fi
    done
    
    echo ""
    echo -e "${BLUE}🔧 Membuat sertifikat SSL...${NC}"
    
    if openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
        -subj "/C=ID/ST=Jakarta/L=Jakarta/O=PONDOK VPN/OU=VPN Service/CN=${domain}" \
        -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" 2>/dev/null; then
        
        echo -e "${GREEN}✅ Sertifikat SSL berhasil dibuat${NC}"
        
        if [ -f "$CONFIG_JSON" ]; then
            if jq --arg domain "$domain" '.tls.sni = $domain' "$CONFIG_JSON" > /tmp/config.json.tmp 2>/dev/null; then
                mv /tmp/config.json.tmp "$CONFIG_JSON"
                echo -e "${GREEN}✅ Config.json diperbarui${NC}"
                
                restart_zivpn_service
                
                echo ""
                echo -e "${LIGHT_GREEN}╔══════════════════════════════════════════╗${NC}"
                echo -e "${LIGHT_GREEN}║        ${WHITE}✅ DOMAIN BERHASIL DIGANTI${LIGHT_GREEN}      ║${NC}"
                echo -e "${LIGHT_GREEN}╠══════════════════════════════════════════╣${NC}"
                echo -e "${LIGHT_GREEN}║                                          ║${NC}"
                echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Domain Baru: ${WHITE}${domain}${LIGHT_GREEN}              ║${NC}"
                echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 Status: ${WHITE}Aktif${LIGHT_GREEN}                      ║${NC}"
                echo -e "${LIGHT_GREEN}║  ${LIGHT_BLUE}🔹 SSL: ${WHITE}Valid (365 hari)${LIGHT_GREEN}             ║${NC}"
                echo -e "${LIGHT_GREEN}║                                          ║${NC}"
                echo -e "${LIGHT_GREEN}╚══════════════════════════════════════════╝${NC}"
            else
                echo -e "${RED}❌ Gagal update config.json${NC}"
            fi
        else
            echo -e "${RED}❌ File config.json tidak ditemukan${NC}"
        fi
    else
        echo -e "${RED}❌ Gagal membuat sertifikat SSL${NC}"
    fi
    
    echo ""
    read -p "Tekan Enter untuk kembali ke menu..."
}

# =============================
# SERVICE MANAGEMENT
# =============================

function service_status() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║       ${LIGHT_CYAN}STATUS SERVICE${PURPLE}               ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    if check_zivpn_installed; then
        echo -e "${BLUE}🔍 Mengecek status ZIVPN...${NC}"
        echo ""
        
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            echo -e "${GREEN}✅ Service Status: ${WHITE}Aktif${NC}"
        else
            echo -e "${RED}❌ Service Status: ${WHITE}Nonaktif${NC}"
        fi
        
        echo -e "${BLUE}📁 Konfigurasi:${NC}"
        if [ -f "$USER_DB" ]; then
            local user_count=$(wc -l < "$USER_DB" 2>/dev/null || echo "0")
            echo -e "${WHITE}  • User database: ${user_count} akun${NC}"
        else
            echo -e "${YELLOW}  • User database: Tidak ditemukan${NC}"
        fi
        
        if [ -f "$CONFIG_JSON" ]; then
            echo -e "${WHITE}  • Config.json: OK${NC}"
        else
            echo -e "${YELLOW}  • Config.json: Tidak ditemukan${NC}"
        fi
        
        if [ -f "/etc/zivpn/zivpn.crt" ]; then
            local domain=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject 2>/dev/null | sed -n 's/.*CN = \([^,]*\).*/\1/p')
            echo -e "${BLUE}🌐 Domain: ${WHITE}${domain}${NC}"
        fi
        
        if [ -f "$CONFIG_JSON" ]; then
            local port=$(jq -r '.listen' "$CONFIG_JSON" 2>/dev/null | cut -d':' -f2)
            if [ -n "$port" ] && [ "$port" != "null" ]; then
                echo -e "${BLUE}🔌 Port: ${WHITE}${port}${NC}"
            fi
        fi
        
    else
        echo -e "${RED}❌ ZIVPN tidak terinstall${NC}"
    fi
    
    echo ""
    read -p "Tekan Enter untuk kembali ke menu..."
}

function uninstall_zivpn() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║       ${LIGHT_CYAN}UNINSTALL ZIVPN${PURPLE}               ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    if ! check_zivpn_installed; then
        echo -e "${YELLOW}ZIVPN tidak terinstall${NC}"
        read -p "Tekan Enter untuk kembali..."
        return
    fi
    
    echo -e "${RED}⚠️  ⚠️  ⚠️  PERINGATAN! ⚠️  ⚠️  ⚠️${NC}"
    echo -e "${RED}Ini akan menghapus ZIVPN dan semua datanya!${NC}"
    echo ""
    echo -e "${YELLOW}Yang akan dihapus:${NC}"
    echo -e "${WHITE}• Service ZIVPN${NC}"
    echo -e "${WHITE}• Semua akun pengguna${NC}"
    echo -e "${WHITE}• File konfigurasi${NC}"
    echo -e "${WHITE}• Database devices${NC}"
    echo -e "${WHITE}• Sertifikat SSL${NC}"
    echo ""
    
    read -p "Apakah Anda yakin? (ketik 'YA' untuk konfirmasi): " confirm
    
    if [ "$confirm" != "YA" ]; then
        echo -e "${YELLOW}Uninstall dibatalkan.${NC}"
        return
    fi
    
    echo -e "${BLUE}🔄 Menghentikan service...${NC}"
    systemctl stop "$SERVICE_NAME" 2>/dev/null
    systemctl disable "$SERVICE_NAME" 2>/dev/null
    
    echo -e "${BLUE}🗑️  Menghapus file...${NC}"
    rm -rf "$ZIVPN_DIR"
    rm -f "/etc/systemd/system/$SERVICE_NAME"
    
    (crontab -l 2>/dev/null | grep -v "zivpn-expiry-check") | crontab -
    
    echo -e "${GREEN}✅ ZIVPN berhasil diuninstall${NC}"
    echo ""
    read -p "Tekan Enter untuk kembali..."
}

# =============================
# MAIN MENU
# =============================

function show_main_menu() {
    while true; do
        clear
        
        echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║         ${LIGHT_CYAN}ZIVPN MANAGER${PURPLE}                 ║${NC}"
        echo -e "${PURPLE}╠══════════════════════════════════════════╣${NC}"
        
        if check_zivpn_installed; then
            echo -e "${PURPLE}║   ${GREEN}✅ ZIVPN Terinstall${PURPLE}                   ║${NC}"
        else
            echo -e "${PURPLE}║   ${RED}❌ ZIVPN Belum Terinstall${PURPLE}              ║${NC}"
        fi
        
        echo -e "${PURPLE}╠══════════════════════════════════════════╣${NC}"
        echo -e "${PURPLE}║                                          ║${NC}"
        
        if check_zivpn_installed; then
            echo -e "${PURPLE}║   ${WHITE}1) ${LIGHT_GREEN}Buat Akun${PURPLE}                        ║${NC}"
            echo -e "${PURPLE}║   ${WHITE}2) ${LIGHT_GREEN}Trial Akun${PURPLE}                       ║${NC}"
            echo -e "${PURPLE}║   ${WHITE}3) ${LIGHT_GREEN}Renew Akun${PURPLE}                       ║${NC}"
            echo -e "${PURPLE}║   ${WHITE}4) ${LIGHT_GREEN}Hapus Akun${PURPLE}                       ║${NC}"
            echo -e "${PURPLE}║   ${WHITE}5) ${LIGHT_GREEN}List Akun${PURPLE}                        ║${NC}"
            echo -e "${PURPLE}║   ${WHITE}6) ${LIGHT_GREEN}Ganti Domain${PURPLE}                     ║${NC}"
            echo -e "${PURPLE}║   ${WHITE}7) ${LIGHT_GREEN}Service Status${PURPLE}                   ║${NC}"
            echo -e "${PURPLE}║   ${WHITE}8) ${LIGHT_GREEN}Restart Service${PURPLE}                  ║${NC}"
            echo -e "${PURPLE}║   ${WHITE}9) ${LIGHT_GREEN}Uninstall ZIVPN${PURPLE}                 ║${NC}"
        else
            echo -e "${PURPLE}║   ${WHITE}1) ${LIGHT_GREEN}Install ZIVPN${PURPLE}                    ║${NC}"
        fi
        
        echo -e "${PURPLE}║   ${WHITE}0) ${LIGHT_GREEN}Keluar${PURPLE}                            ║${NC}"
        echo -e "${PURPLE}║                                          ║${NC}"
        echo -e "${PURPLE}╠══════════════════════════════════════════╣${NC}"
        echo -e "${PURPLE}║   ${LIGHT_YELLOW}Telegram: @bendakerep${PURPLE}                  ║${NC}"
        echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
        echo ""
        
        read -p "Pilih menu: " choice
        
        case $choice in
            1)
                if check_zivpn_installed; then
                    create_zivpn_account
                else
                    install_zivpn
                fi
                ;;
            2)
                if check_zivpn_installed; then
                    create_trial_account
                else
                    echo -e "${RED}❌ Install ZIVPN terlebih dahulu!${NC}"
                    sleep 2
                fi
                ;;
            3)
                if check_zivpn_installed; then
                    renew_account
                else
                    echo -e "${RED}❌ Install ZIVPN terlebih dahulu!${NC}"
                    sleep 2
                fi
                ;;
            4)
                if check_zivpn_installed; then
                    delete_account
                else
                    echo -e "${RED}❌ Install ZIVPN terlebih dahulu!${NC}"
                    sleep 2
                fi
                ;;
            5)
                if check_zivpn_installed; then
                    list_accounts
                else
                    echo -e "${RED}❌ Install ZIVPN terlebih dahulu!${NC}"
                    sleep 2
                fi
                ;;
            6)
                if check_zivpn_installed; then
                    change_domain
                else
                    echo -e "${RED}❌ Install ZIVPN terlebih dahulu!${NC}"
                    sleep 2
                fi
                ;;
            7)
                if check_zivpn_installed; then
                    service_status
                else
                    echo -e "${RED}❌ Install ZIVPN terlebih dahulu!${NC}"
                    sleep 2
                fi
                ;;
            8)
                if check_zivpn_installed; then
                    restart_zivpn_service
                    read -p "Tekan Enter untuk kembali..."
                else
                    echo -e "${RED}❌ Install ZIVPN terlebih dahulu!${NC}"
                    sleep 2
                fi
                ;;
            9)
                if check_zivpn_installed; then
                    uninstall_zivpn
                else
                    echo -e "${RED}❌ ZIVPN belum terinstall!${NC}"
                    sleep 2
                fi
                ;;
            0)
                echo -e "${GREEN}Terima kasih!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Pilihan tidak valid!${NC}"
                sleep 1
                ;;
        esac
    done
}

# =============================
# INITIAL SETUP
# =============================

function initial_setup() {
    # Copy this script to system
    cp "$0" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
    
    # Create symlink
    ln -sf "$INSTALL_PATH" /usr/bin/menu-zivpn 2>/dev/null
    
    echo -e "${GREEN}✅ ZIVPN Manager telah diinstall${NC}"
    echo -e "${YELLOW}Untuk menjalankan: menu-zivpn${NC}"
    echo -e "${CYAN}Atau pilih menu 10 di menu SSH/Xray${NC}"
    echo ""
    
    # Check dependencies
    check_dependencies
    
    # Start main menu
    show_main_menu
}

# =============================
# EXECUTION
# =============================

# If called directly, start the initial setup
if [ "$0" = "$BASH_SOURCE" ]; then
    initial_setup
fi