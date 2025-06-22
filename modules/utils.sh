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

# Confirmation prompt
confirm_action() {
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
    chown -R www-data:www-data "/var/log/nginx/$domain"
}