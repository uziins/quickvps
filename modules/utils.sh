#!/bin/bash

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Log file location
LOG_FILE="/var/log/vps-setup.log"

# Logging function
log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" >> "$LOG_FILE"
}

# OS Detection
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        echo -e "${RED}Cannot detect OS. /etc/os-release not found.${NC}"
        exit 1
    fi

    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        OS_FAMILY="debian"
        PKG_MANAGER="apt"
        PKG_INSTALL="apt install -y"
        PKG_UPDATE="apt update"
        WEB_USER="www-data"
        WEB_GROUP="www-data"
        NGINX_CONF_DIR="/etc/nginx/sites-available"
        NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
    elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "almalinux" || "$OS" == "rocky" || "$OS" == "fedora" ]]; then
        OS_FAMILY="rhel"
        if command -v dnf &>/dev/null; then
            PKG_MANAGER="dnf"
        else
            PKG_MANAGER="yum"
        fi
        PKG_INSTALL="$PKG_MANAGER install -y"
        PKG_UPDATE="$PKG_MANAGER check-update"
        WEB_USER="nginx"
        WEB_GROUP="nginx"
        NGINX_CONF_DIR="/etc/nginx/conf.d"
        NGINX_ENABLED_DIR="/etc/nginx/conf.d"
    else
        echo -e "${RED}Unsupported OS: $OS${NC}"
        exit 1
    fi
}

# Run OS Detection
detect_os

# Confirmation prompt
confirm_action() {
    if [[ "$NON_INTERACTIVE" == "1" ]]; then
        return 0
    fi
    read -rp "Are you sure you want to proceed? [y/N]: " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}❌ Action cancelled.${NC}"
        return 1
    fi
    return 0
}

# Logging setup per domain
setup_logging_for_domain() {
    local domain="$1"
    mkdir -p "/var/log/nginx/$domain"
    touch "/var/log/nginx/$domain/access.log"
    touch "/var/log/nginx/$domain/error.log"
    chown -R "$WEB_USER":"$WEB_GROUP" "/var/log/nginx/$domain"
}

# Smart Ownership
get_smart_owner() {
    local docroot="$1"
    if [ -n "$DOMAIN_OWNER" ]; then
        echo "$DOMAIN_OWNER"
        return
    fi
    
    # Try to find parent directory that exists
    local check_dir="$docroot"
    while [ ! -d "$check_dir" ] && [ "$check_dir" != "/" ]; do
        check_dir=$(dirname "$check_dir")
    done
    
    local parent_owner=$(stat -c '%U' "$check_dir" 2>/dev/null)
    if [ -z "$parent_owner" ] || [ "$parent_owner" == "root" ]; then
        echo "$WEB_USER"
    else
        echo "$parent_owner"
    fi
}

set_docroot_permissions() {
    local docroot="$1"
    local owner="$2"
    
    chown -R "$owner":"$WEB_GROUP" "$docroot"
    chmod -R 775 "$docroot"
    # Ensure setgid on directory so new files inherit group
    find "$docroot" -type d -exec chmod g+s {} + 2>/dev/null || true
}