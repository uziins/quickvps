#!/bin/bash

install_lemp_stack() {
    echo -e "${CYAN}Installing LEMP Stack (PHP $PHP_VERSION)...${NC}"
    log "Installing LEMP Stack (PHP $PHP_VERSION)..."
    if confirm_action; then
        local MYSQL_SERVICE
        if [[ "$OS_FAMILY" == "debian" ]]; then
            MYSQL_SERVICE="mysql"
        else
            MYSQL_SERVICE="mariadb"
        fi

        if [[ "$OS_FAMILY" == "debian" ]]; then
            if command -v add-apt-repository &>/dev/null; then
                add-apt-repository -y ppa:ondrej/php
            fi
            $PKG_UPDATE
            $PKG_INSTALL nginx $MYSQL_SERVICE \
                php$PHP_VERSION php$PHP_VERSION-fpm php$PHP_VERSION-mysql \
                php$PHP_VERSION-cli php$PHP_VERSION-curl php$PHP_VERSION-mbstring \
                php$PHP_VERSION-xml php$PHP_VERSION-zip unzip curl
        else
            $PKG_UPDATE
            if [[ "$PKG_MANAGER" == "dnf" ]]; then
                $PKG_INSTALL epel-release dnf-utils http://rpms.remirepo.net/enterprise/remi-release-$(rpm -E %rhel).rpm
                dnf module reset php -y
                dnf module enable php:remi-$PHP_VERSION -y
            fi
            $PKG_INSTALL nginx $MYSQL_SERVICE \
                php php-fpm php-mysqlnd \
                php-cli php-curl php-mbstring \
                php-xml php-zip unzip curl
        fi

        local PHP_FPM_SERVICE
        if [[ "$OS_FAMILY" == "debian" ]]; then
            PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"
        else
            PHP_FPM_SERVICE="php-fpm"
        fi

        systemctl enable --now nginx
        systemctl enable --now $MYSQL_SERVICE
        systemctl enable --now $PHP_FPM_SERVICE
        echo -e "${GREEN}✅ LEMP Stack with PHP $PHP_VERSION installed.${NC}"
        log "LEMP Stack with PHP $PHP_VERSION installed."
    fi
}

install_node() {
    echo -e "${CYAN}Installing Node.js (LTS)...${NC}"
    log "Installing Node.js..."
    if confirm_action; then
        if [[ "$OS_FAMILY" == "debian" ]]; then
            curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
        else
            curl -fsSL https://rpm.nodesource.com/setup_lts.x | bash -
        fi
        $PKG_INSTALL nodejs
        echo -e "${GREEN}✅ Node.js installed.${NC}"
        log "Node.js installed."
    fi
}

install_certbot() {
    echo -e "${CYAN}Installing Certbot and Nginx plugin...${NC}"
    log "Installing Certbot..."
    if confirm_action; then
        $PKG_UPDATE
        $PKG_INSTALL certbot python3-certbot-nginx
        echo -e "${GREEN}✅ Certbot installed.${NC}"
        log "Certbot installed."
    fi
}

install_docker() {
    if ! command -v docker &>/dev/null; then
        echo -e "${CYAN}Installing Docker...${NC}"
        if [[ "$OS_FAMILY" == "debian" ]]; then
            $PKG_UPDATE
            $PKG_INSTALL apt-transport-https ca-certificates curl software-properties-common
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
            add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
            $PKG_UPDATE
            $PKG_INSTALL docker-ce
        else
            $PKG_INSTALL yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            $PKG_INSTALL docker-ce docker-ce-cli containerd.io
        fi
        systemctl enable --now docker
        echo -e "${GREEN}✅ Docker installed.${NC}"
    fi

    if ! command -v docker-compose &>/dev/null && ! command -v docker compose &>/dev/null; then
        echo -e "${CYAN}Installing Docker Compose plugin...${NC}"
        $PKG_INSTALL docker-compose-plugin
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
