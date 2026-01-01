#!/bin/bash
# PONDOKVPN PRO INSTALLER
# Premium VPN Setup Script

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Banner
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║                                                      ║"
    echo "║  ██████╗  ██████╗ ███╗   ██╗██████╗  ██████╗ ██╗  ██╗║"
    echo "║  ██╔══██╗██╔═══██╗████╗  ██║██╔══██╗██╔═══██╗██║ ██╔╝║"
    echo "║  ██████╔╝██║   ██║██╔██╗ ██║██║  ██║██║   ██║█████╔╝ ║"
    echo "║  ██╔═══╝ ██║   ██║██║╚██╗██║██║  ██║██║   ██║██╔═██╗ ║"
    echo "║  ██║     ╚██████╔╝██║ ╚████║██████╔╝╚██████╔╝██║  ██╗║"
    echo "║  ╚═╝      ╚═════╝ ╚═╝  ╚═══╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝║"
    echo "║                                                      ║"
    echo "║               P R E M I U M   V P N                  ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${YELLOW}           Fast | Secure | Reliable${NC}"
    echo -e "${WHITE}           ============================${NC}"
    echo ""
}

# Main function
main() {
    show_banner
    
    # Check root
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR] This script must be run as root${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}[1/6]${NC} System Update..."
    apt update -y && apt upgrade -y
    
    echo -e "${BLUE}[2/6]${NC} Installing Dependencies..."
    apt install -y curl wget git nano zip unzip figlet lolcat
    
    echo -e "${BLUE}[3/6]${NC} Setting PONDOKVPN Banner..."
    mkdir -p /usr/bin
    echo "PONDOKVPN" > /usr/bin/figlet_text
    
    echo -e "${BLUE}[4/6]${NC} Downloading PondokVPN..."
    if wget -q --spider https://raw.githubusercontent.com/Pondok-Vpn/pondokvip/main/install.sh; then
        wget -q -O pondokvpn-install.sh https://raw.githubusercontent.com/Pondok-Vpn/pondokvip/main/install.sh
        chmod +x pondokvpn-install.sh
    else
        echo -e "${RED}[ERROR] Cannot download installer${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}[5/6]${NC} Final Preparation..."
    echo -e "${GREEN}✓ System ready for installation${NC}"
    
    echo -e "${BLUE}[6/6]${NC} Starting Installation in 5 seconds..."
    echo -e "${YELLOW}Press Ctrl+C to cancel${NC}"
    sleep 5
    
    # Run installer
    ./pondokvpn-install.sh
}

# Run main function
main
