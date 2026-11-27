#!/bin/bash

# Load config from .env if available
ENV_FILE=".env"
if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    export PHP_VERSION="8.3"
    export DEFAULT_NODE_PORT=3000
    export DEFAULT_DOCROOT_BASE=/var/www
    export NGINX_TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/templates"
    export DOCKER_TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/templates/docker"
    export DEFAULT_DOCKER_PORT=5678
fi

# Load modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/modules/utils.sh"
source "$SCRIPT_DIR/modules/server.sh"
source "$SCRIPT_DIR/modules/user.sh"
source "$SCRIPT_DIR/modules/domain.sh"
source "$SCRIPT_DIR/modules/docker.sh"
source "$SCRIPT_DIR/modules/database.sh"
source "$SCRIPT_DIR/modules/tcp_proxy.sh"

# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}This script must be run as root. Use sudo to run the script.${NC}"
    exit 1
fi
# Parse CLI arguments
NON_INTERACTIVE=0
if [ "$#" -gt 0 ]; then
    MODULE=$1
    ACTION=$2
    shift 2

    # Parse flags
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --non-interactive) NON_INTERACTIVE=1; shift ;;
            --domain) export DOMAIN="$2"; shift 2 ;;
            --stack) export STACK_TYPE="$2"; shift 2 ;;
            --php) export PHP_VERSION="$2"; shift 2 ;;
            --docroot) export DOCROOT="$2"; shift 2 ;;
            --owner) export DOMAIN_OWNER="$2"; shift 2 ;;
            --user) export USERNAME="$2"; shift 2 ;;
            --proxy-port) export PROXY_PORT="$2"; shift 2 ;;
            --db-name) export DB_NAME="$2"; shift 2 ;;
            --db-user) export DB_USER="$2"; shift 2 ;;
            --db-pass) export DB_PASS="$2"; shift 2 ;;
            --db-engine) export DB_ENGINE="$2"; shift 2 ;;
            --docker-app) export DOCKER_APP="$2"; shift 2 ;;
            --docker-port) export DOCKER_PORT="$2"; shift 2 ;;
            *) echo "Unknown parameter passed: $1"; exit 1 ;;
        esac
    done
    export NON_INTERACTIVE

    # Execute specific module action
    case $MODULE in
        server)
            case $ACTION in
                install-lemp) install_lemp_stack ;;
                install-node) install_node ;;
                install-docker) install_docker ;;
                *) echo -e "${RED}Unknown server action: $ACTION${NC}"; exit 1 ;;
            esac
            ;;
        domain)
            case $ACTION in
                add) add_domain ;;
                delete) delete_domain ;;
                modify) modify_domain ;;
                add-subdir) add_subdirectory ;;
                list) list_domains ;;
                *) echo -e "${RED}Unknown domain action: $ACTION${NC}"; exit 1 ;;
            esac
            ;;
        user)
            case $ACTION in
                add) create_user ;;
                add-sudo) add_user_to_sudo ;;
                *) echo -e "${RED}Unknown user action: $ACTION${NC}"; exit 1 ;;
            esac
            ;;
        docker)
            case $ACTION in
                setup) setup_docker_app_standalone ;;
                restart) restart_docker_app ;;
                remove) remove_docker_app ;;
                status) check_docker_container_status ;;
                *) echo -e "${RED}Unknown docker action: $ACTION${NC}"; exit 1 ;;
            esac
            ;;
        database)
            case $ACTION in
                install) install_mysql ;;
                create) create_database ;;
                list) list_databases ;;
                delete) delete_database ;;
                backup) backup_database ;;
                restore) restore_database ;;
                optimize) optimize_database ;;
                status) show_database_status ;;
                *) echo -e "${RED}Unknown database action: $ACTION${NC}"; exit 1 ;;
            esac
            ;;
        tcp)
            case $ACTION in
                add) add_tcp_proxy ;;
                delete) delete_tcp_proxy ;;
                list) list_tcp_proxies ;;
                *) echo -e "${RED}Unknown TCP action: $ACTION${NC}"; exit 1 ;;
            esac
            ;;
        *)
            echo -e "${RED}Unknown module: $MODULE${NC}"
            echo "Available modules: server, domain, user, docker, database, tcp"
            exit 1
            ;;
    esac
    exit 0
fi

# Main menu (fallback)
while true; do
    unset DOMAIN STACK_TYPE DOCROOT DOMAIN_OWNER USERNAME PROXY_PORT DB_NAME DB_USER DB_PASS DB_ENGINE DOCKER_APP DOCKER_PORT NODE_PORT
    echo -e "${CYAN}========= QuickVPS Setup Menu =========${NC}"
    echo "1) Server Setup"
    echo "2) User Setup"
    echo "3) Domain Setup"
    echo "4) Docker Management"
    echo "5) Database Management"
    echo "6) TCP/Stream Proxy Management"
    echo "7) Exit"
    read -rp "Select an option [1-7]: " MAIN_OPTION
    case $MAIN_OPTION in
        1) show_server_menu ;;
        2) show_user_menu ;;
        3) 
            echo "1) Add Domain"
            echo "2) Delete Domain"
            echo "3) Modify Domain"
            echo "4) Add Subdirectory/Path to Domain"
            echo "5) List Domains"
            read -rp "Choose domain task [1-5]: " DOMAIN_OPTION
            case $DOMAIN_OPTION in
                1) add_domain ;;
                2) delete_domain ;;
                3) modify_domain ;;
                4) add_subdirectory ;;
                5) list_domains ;;
                *) echo -e "${YELLOW}Invalid option.${NC}" ;;
            esac
            ;;
        4) show_docker_menu ;;
        5) show_database_menu ;;
        6) show_tcp_menu ;;
        7) echo -e "${GREEN}Goodbye!${NC}"; break ;;
        *) echo -e "${YELLOW}Invalid option. Please select 1-7.${NC}" ;;
    esac
done