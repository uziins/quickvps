#!/bin/bash

install_lemp_stack() {
    echo -e "${CYAN}Installing LEMP Stack (PHP $PHP_VERSION)...${NC}"
    log "Installing LEMP Stack (PHP $PHP_VERSION)..."
    if confirm_action; then
        add-apt-repository -y ppa:ondrej/php
        apt update
        apt install -y nginx mysql-server \
            php$PHP_VERSION php$PHP_VERSION-fpm php$PHP_VERSION-mysql \
            php$PHP_VERSION-cli php$PHP_VERSION-curl php$PHP_VERSION-mbstring \
            php$PHP_VERSION-xml php$PHP_VERSION-zip unzip curl

        systemctl enable nginx
        systemctl enable mysql
        echo -e "${GREEN}✅ LEMP Stack with PHP $PHP_VERSION installed.${NC}"
        log "LEMP Stack with PHP $PHP_VERSION installed."
    fi
}

install_node() {
    echo -e "${CYAN}Installing Node.js (LTS)...${NC}"
    log "Installing Node.js..."
    if confirm_action; then
        curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
        apt install -y nodejs
        echo -e "${GREEN}✅ Node.js installed.${NC}"
        log "Node.js installed."
    fi
}

install_certbot() {
    echo -e "${CYAN}Installing Certbot and Nginx plugin...${NC}"
    log "Installing Certbot..."
    if confirm_action; then
        apt update
        apt install -y certbot python3-certbot-nginx
        echo -e "${GREEN}✅ Certbot installed.${NC}"
        log "Certbot installed."
    fi
}

install_docker() {
    if ! command -v docker &>/dev/null; then
        echo -e "${CYAN}Installing Docker...${NC}"
        apt update
        apt install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        apt update
        apt install -y docker-ce
        systemctl enable docker
        echo -e "${GREEN}✅ Docker installed.${NC}"
    fi

    if ! command -v docker-compose &>/dev/null && ! command -v docker compose &>/dev/null; then
        echo -e "${CYAN}Installing Docker Compose plugin...${NC}"
        apt install -y docker-compose-plugin
        echo -e "${GREEN}✅ Docker Compose plugin installed.${NC}"
    fi
}

show_server_menu() {
    echo -e "${CYAN}--- Server Setup ---${NC}"
    echo "1) Install LEMP Stack"
    echo "2) Install Node.js"
    echo "3) Install Docker"
    read -rp "Choose server task [1-2]: " SERVER_OPTION
    case $SERVER_OPTION in
        1) install_lemp_stack ;;
        2) install_node ;;
        3) install_docker ;;
        *) echo -e "${YELLOW}Invalid option.${NC}" ;;
    esac
}
