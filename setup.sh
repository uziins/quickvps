#!/bin/bash

# Resolve the real script location, even when invoked through a symlink
# (e.g. /usr/local/bin/quickvps -> /opt/quickvps/setup.sh)
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
export SCRIPT_DIR

# Defaults (can be overridden by .env and CLI flags)
PHP_VERSION="8.3"
DEFAULT_NODE_PORT=3000
DEFAULT_DOCROOT_BASE=/var/www
NGINX_TEMPLATE_DIR="templates"
DOCKER_TEMPLATE_DIR="templates/docker"
DEFAULT_DOCKER_PORT=5678

# Load config from .env next to this script (KEY=VALUE lines only, never executed)
ENV_FILE="$SCRIPT_DIR/.env"
if [ -f "$ENV_FILE" ]; then
    while IFS='=' read -r key value || [ -n "$key" ]; do
        key="${key//[[:space:]]/}"
        [[ -z "$key" || "$key" == \#* ]] && continue
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        # Strip surrounding quotes and trailing CR
        value="${value%$'\r'}"
        value="${value#\"}"; value="${value%\"}"
        value="${value#\'}"; value="${value%\'}"
        printf -v "$key" '%s' "$value"
    done < "$ENV_FILE"
fi

# Relative directories are relative to the script, not the current directory
[[ "$NGINX_TEMPLATE_DIR" != /* ]] && NGINX_TEMPLATE_DIR="$SCRIPT_DIR/$NGINX_TEMPLATE_DIR"
[[ "$DOCKER_TEMPLATE_DIR" != /* ]] && DOCKER_TEMPLATE_DIR="$SCRIPT_DIR/$DOCKER_TEMPLATE_DIR"
export PHP_VERSION DEFAULT_NODE_PORT DEFAULT_DOCROOT_BASE NGINX_TEMPLATE_DIR DOCKER_TEMPLATE_DIR DEFAULT_DOCKER_PORT

# Check if the script is run as root (before loading modules, which touch system files)
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Use sudo to run the script."
    exit 1
fi

# Load modules
source "$SCRIPT_DIR/modules/utils.sh"
source "$SCRIPT_DIR/modules/server.sh"
source "$SCRIPT_DIR/modules/user.sh"
source "$SCRIPT_DIR/modules/domain.sh"
source "$SCRIPT_DIR/modules/docker.sh"
source "$SCRIPT_DIR/modules/database.sh"
source "$SCRIPT_DIR/modules/tcp_proxy.sh"
source "$SCRIPT_DIR/modules/auth.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [<module> <action> [options]]

Run without arguments for the interactive menu.

Modules and actions:
  server    install-lemp | install-node | install-docker
  domain    add | delete | modify | add-subdir | list
  user      add | add-sudo
  docker    setup | restart | remove | status
  database  install | create | list | delete | backup | restore | optimize | status
  tcp       add | delete | list
  auth      enable | disable | add-user | delete-user | status

Options:
  --non-interactive        Never prompt; use flags/defaults, answer "no" to optional questions
  --domain <name>          Domain name
  --www                    Also serve www.<domain>
  --stack <type>           php | laravel | wordpress | static | node | docker | proxy
  --php <version>          PHP version (e.g. 8.3)
  --docroot <path>         Document root
  --owner <user>           Owner of the document root
  --git-url <url>          Clone this repository into the document root
  --node-port <port>       Port for a Node.js app
  --proxy-port <port>      Port to reverse-proxy to
  --ssl                    Request a Let's Encrypt certificate
  --email <address>        Email for Let's Encrypt (used with --ssl)
  --force                  Overwrite an existing domain config
  --delete-root            (domain delete) Also delete the document root
  --path <path>            (domain add-subdir, auth) Location path, e.g. /api/ (trailing slash added automatically)
  --sub-stack <type>       (domain add-subdir) proxy | php | static
  --strip-prefix           (add-subdir proxy) Backend gets /users for /api/users (default)
  --keep-prefix            (add-subdir proxy) Backend gets /api/users unchanged
  --user <name>            System username, or HTTP auth username (auth module)
  --pass-stdin             (auth) Read the user's password from stdin instead of generating one
  --db-name / --db-user / --db-pass / --db-engine <mysql|mariadb>
  --backup-file <path>     (database restore) Backup file to restore
  --docker-app <name>      Docker template name (e.g. n8n, ghost)
  --docker-port <port>     Host port for the Docker app
  --container <name>       (docker restart/remove) Container name
  --listen-port <port>     (tcp) Public listen port
  --destination <host:port> (tcp) Upstream destination
  --ssl-domain <name>      (tcp add) Domain whose certificate is used for TLS
  -h, --help               Show this help
EOF
}

# Variables filled from flags/prompts. Clear them first: some come from the environment
# (sudo and login shells set USERNAME, for example), which would silently skip prompts.
reset_input_vars() {
    unset DOMAIN STACK_TYPE DOCROOT DOMAIN_OWNER USERNAME PROXY_PORT DB_NAME DB_USER DB_PASS DB_ENGINE \
          DOCKER_APP DOCKER_PORT NODE_PORT STACK_PORT WWW_DOMAIN ENABLE_WWW ENABLE_SSL GIT_URL FORCE \
          DELETE_ROOT SUBDIR_PATH SUB_STACK STRIP_PREFIX PASS_STDIN CONTAINER_NAME LISTEN_PORT DESTINATION \
          SSL_DOMAIN BACKUP_FILE SSL_EMAIL
}
reset_input_vars

# Parse CLI arguments
NON_INTERACTIVE=0
if [ "$#" -gt 0 ]; then
    case "$1" in
        -h|--help) usage; exit 0 ;;
    esac
    if [ "$#" -lt 2 ] || [[ "$2" == -* ]]; then
        echo -e "${RED}Missing action for module '$1'.${NC}"
        usage
        exit 1
    fi
    MODULE=$1
    ACTION=$2
    shift 2

    require_value() {
        if [ -z "$2" ] || [[ "$2" == --* ]]; then
            echo -e "${RED}Option $1 requires a value.${NC}"
            exit 1
        fi
    }

    # Parse flags
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --non-interactive) NON_INTERACTIVE=1; shift; continue ;;
            --www) export ENABLE_WWW="y"; shift; continue ;;
            --ssl) export ENABLE_SSL="y"; shift; continue ;;
            --force) export FORCE=1; shift; continue ;;
            --delete-root) export DELETE_ROOT="y"; shift; continue ;;
            --strip-prefix) export STRIP_PREFIX="y"; shift; continue ;;
            --keep-prefix) export STRIP_PREFIX="n"; shift; continue ;;
            --pass-stdin) export PASS_STDIN=1; shift; continue ;;
            -h|--help) usage; exit 0 ;;
        esac
        require_value "$1" "$2"
        case $1 in
            --domain) export DOMAIN="$2" ;;
            --stack) export STACK_TYPE="$2" ;;
            --php) export PHP_VERSION="$2" ;;
            --docroot) export DOCROOT="$2" ;;
            --owner) export DOMAIN_OWNER="$2" ;;
            --git-url) export GIT_URL="$2" ;;
            --node-port) export NODE_PORT="$2" ;;
            --proxy-port) export PROXY_PORT="$2" ;;
            --email) export SSL_EMAIL="$2" ;;
            --path) export SUBDIR_PATH="$2" ;;
            --sub-stack) export SUB_STACK="$2" ;;
            --user) export USERNAME="$2" ;;
            --db-name) export DB_NAME="$2" ;;
            --db-user) export DB_USER="$2" ;;
            --db-pass) export DB_PASS="$2" ;;
            --db-engine) export DB_ENGINE="$2" ;;
            --backup-file) export BACKUP_FILE="$2" ;;
            --docker-app) export DOCKER_APP="$2" ;;
            --docker-port) export DOCKER_PORT="$2" ;;
            --container) export CONTAINER_NAME="$2" ;;
            --listen-port) export LISTEN_PORT="$2" ;;
            --destination) export DESTINATION="$2" ;;
            --ssl-domain) export SSL_DOMAIN="$2" ;;
            *) echo -e "${RED}Unknown parameter passed: $1${NC}"; usage; exit 1 ;;
        esac
        shift 2
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
        auth)
            case $ACTION in
                enable) auth_enable ;;
                disable) auth_disable ;;
                add-user) auth_add_user ;;
                delete-user) auth_delete_user ;;
                status) auth_status ;;
                *) echo -e "${RED}Unknown auth action: $ACTION${NC}"; exit 1 ;;
            esac
            ;;
        *)
            echo -e "${RED}Unknown module: $MODULE${NC}"
            echo "Available modules: server, domain, user, docker, database, tcp, auth"
            exit 1
            ;;
    esac
    exit $?
fi

# Main menu (fallback)
while true; do
    reset_input_vars
    cd "$SCRIPT_DIR" || exit 1
    echo -e "${CYAN}========= QuickVPS Setup Menu =========${NC}"
    echo "1) Server Setup"
    echo "2) User Setup"
    echo "3) Domain Setup"
    echo "4) Docker Management"
    echo "5) Database Management"
    echo "6) TCP/Stream Proxy Management"
    echo "7) HTTP Basic Auth"
    echo "8) Exit"
    read -rp "Select an option [1-8]: " MAIN_OPTION
    case $MAIN_OPTION in
        1) show_server_menu ;;
        2) show_user_menu ;;
        3) show_domain_menu ;;
        4) show_docker_menu ;;
        5) show_database_menu ;;
        6) show_tcp_menu ;;
        7) show_auth_menu ;;
        8) echo -e "${GREEN}Goodbye!${NC}"; break ;;
        *) echo -e "${YELLOW}Invalid option. Please select 1-8.${NC}" ;;
    esac
done
