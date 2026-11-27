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

# Read a value into the variable named $1 unless it is already set.
# In non-interactive mode the default ($3) is used instead of prompting.
# Returns 1 if the variable is still empty afterwards.
prompt_value() {
    local __var="$1" __prompt="$2" __default="${3:-}" __input=""
    if [[ -n "${!__var}" ]]; then
        return 0
    fi
    if [[ "$NON_INTERACTIVE" != "1" ]]; then
        if [[ -n "$__default" ]]; then
            read -rp "$__prompt [default: $__default]: " __input
        else
            read -rp "$__prompt: " __input
        fi
    fi
    printf -v "$__var" '%s' "${__input:-$__default}"
    [[ -n "${!__var}" ]]
}

# Yes/no question. Usage: ask_yes_no "Question" <default y|n> [preset answer]
# A preset (usually from a CLI flag) wins; non-interactive mode uses the default.
ask_yes_no() {
    local prompt="$1" default="${2:-n}" answer="${3:-}" hint="[y/N]"
    [[ "$default" =~ ^[Yy]$ ]] && hint="[Y/n]"
    if [[ -z "$answer" ]]; then
        if [[ "$NON_INTERACTIVE" == "1" ]]; then
            answer="$default"
        else
            read -rp "$prompt $hint: " answer
            answer="${answer:-$default}"
        fi
    fi
    [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

validate_domain() {
    [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]
}

validate_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

# Escape a string for use as the replacement part of sed "s|...|...|"
sed_escape() {
    printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'
}

# Refuse to operate recursively on system or top-level directories.
is_safe_path() {
    local path
    path=$(realpath -m "$1" 2>/dev/null) || return 1
    [[ -z "$path" || "$path" != /* ]] && return 1

    local base
    base=$(realpath -m "${DEFAULT_DOCROOT_BASE:-/var/www}")
    case "$path" in
        /|/bin|/boot|/dev|/etc|/home|/lib|/lib32|/lib64|/media|/mnt|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var|/var/www|/var/lib|/var/log|/var/cache|/var/spool|/var/mail|/snap)
            return 1 ;;
        /bin/*|/boot/*|/dev/*|/etc/*|/lib/*|/lib32/*|/lib64/*|/proc/*|/run/*|/sbin/*|/sys/*|/usr/*|/var/lib/*|/var/log/*|/var/cache/*|/var/spool/*|/root/*|/snap/*)
            return 1 ;;
    esac
    [[ "$path" == "$base" ]] && return 1
    # A user's home directory itself (/home/<user>) is not a docroot
    [[ "$path" =~ ^/home/[^/]+$ ]] && return 1
    return 0
}

# Test nginx config and reload. On failure, run the given rollback command.
nginx_test_and_reload() {
    local rollback="${1:-}"
    if nginx -t; then
        systemctl reload nginx
        return 0
    fi
    if [[ -n "$rollback" ]]; then
        echo -e "${YELLOW}Rolling back configuration change...${NC}"
        eval "$rollback"
        nginx -t &>/dev/null && systemctl reload nginx
    fi
    return 1
}

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
    
    local parent_owner
    parent_owner=$(stat -c '%U' "$check_dir" 2>/dev/null)
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