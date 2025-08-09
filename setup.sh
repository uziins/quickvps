#!/bin/bash

# Load config from .env if available
ENV_FILE=".env"
if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    PHP_VERSION="8.3"
    DEFAULT_NODE_PORT=3000
    DEFAULT_DOCROOT_BASE=/var/www
    NGINX_TEMPLATE_DIR=templates
    DOCKER_TEMPLATE_DIR=templates/docker
    DEFAULT_DOCKER_PORT=5678
fi

# Load modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/modules/utils.sh"
source "$SCRIPT_DIR/modules/server.sh"
source "$SCRIPT_DIR/modules/user.sh"
source "$SCRIPT_DIR/modules/domain.sh"
source "$SCRIPT_DIR/modules/database.sh"
source "$SCRIPT_DIR/modules/docker.sh"

# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}This script must be run as root. Use sudo to run the script.${NC}"
    exit 1
fi

# Main menu
while true; do
    echo -e "${CYAN}========= QuickVPS Setup Menu =========${NC}"
    echo "1) Server Setup"
    echo "2) User Setup"
    echo "3) Domain Setup"
    echo "4) Database Management"
    echo "5) Docker Management"
    echo "6) Exit"
    read -rp "Select an option [1-6]: " MAIN_OPTION
    case $MAIN_OPTION in
        1) show_server_menu ;;
        2) show_user_menu ;;
        3) show_domain_menu ;;
        4) show_database_menu ;;
        5) show_docker_menu ;;
        6) echo -e "${GREEN}Goodbye!${NC}"; break ;;
        *) echo -e "${YELLOW}Invalid option. Please select 1-6.${NC}" ;;
    esac
done