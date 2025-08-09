#!/bin/bash

select_stack_type() {
    echo -e "${CYAN}Select Stack Type:${NC}"
    echo "1) PHP (Native)"
    echo "2) Laravel"
    echo "3) WordPress"
    echo "4) Static Site"
    echo "5) Node.js (Express)"
    echo "6) Dockerized App"
    read -rp "Choose stack type [1-6]: " STACK_OPTION
    case $STACK_OPTION in
        1) STACK_TYPE="php" ;;
        2) STACK_TYPE="laravel" ;;
        3) STACK_TYPE="wordpress" ;;
        4) STACK_TYPE="static" ;;
        5) STACK_TYPE="node" ;;
        6) STACK_TYPE="docker" ;;
        *) echo -e "${YELLOW}Invalid option. Defaulting to PHP.${NC}"; STACK_TYPE="php" ;;
    esac
}


setup_git_clone() {
    read -rp "Clone project from Git repository? [y/N]: " USE_GIT
    if [[ "$USE_GIT" =~ ^[Yy]$ ]]; then
        read -rp "Enter Git repository URL: " GIT_URL
        if [ -n "$GIT_URL" ]; then
            echo -e "${CYAN}Cloning repository...${NC}"

            # Convert SSH URL to HTTPS if needed
            if [[ "$GIT_URL" =~ ^git@github\.com: ]]; then
                HTTPS_URL=$(echo "$GIT_URL" | sed 's/git@github\.com:/https:\/\/github.com\//' | sed 's/\.git$//')
                echo -e "${YELLOW}SSH URL detected. Converting to HTTPS: $HTTPS_URL${NC}"
                read -rp "Use HTTPS URL instead? [Y/n]: " USE_HTTPS
                if [[ ! "$USE_HTTPS" =~ ^[Nn]$ ]]; then
                    GIT_URL="$HTTPS_URL"
                fi
            fi

            # Check if directory exists and is not empty
            if [ -d "$DOCROOT" ] && [ "$(ls -A "$DOCROOT" 2>/dev/null)" ]; then
                echo -e "${YELLOW}Directory $DOCROOT is not empty.${NC}"
                read -rp "Remove existing files and clone fresh? [y/N]: " REMOVE_EXISTING
                if [[ "$REMOVE_EXISTING" =~ ^[Yy]$ ]]; then
                    rm -rf "$DOCROOT"/*
                    rm -rf "$DOCROOT"/.[!.]*  # Remove hidden files but keep . and ..
                else
                    echo -e "${YELLOW}Skipping git clone. Using existing directory.${NC}"
                    return
                fi
            fi

            # Create directory if it doesn't exist
            mkdir -p "$DOCROOT"

            # Clone repository
            echo -e "${CYAN}Attempting to clone: $GIT_URL${NC}"
            if git clone "$GIT_URL" "$DOCROOT/temp_clone" 2>/dev/null; then
                # Move files from temp directory to docroot
                mv "$DOCROOT/temp_clone"/* "$DOCROOT/" 2>/dev/null
                mv "$DOCROOT/temp_clone"/.[!.]* "$DOCROOT/" 2>/dev/null  # Move hidden files
                rmdir "$DOCROOT/temp_clone"

                chown -R www-data:www-data "$DOCROOT"
                echo -e "${GREEN}✅ Successfully cloned repository to $DOCROOT${NC}"

                # Setup Laravel specific requirements if it's a Laravel project
                if [ "$STACK_TYPE" = "laravel" ]; then
                    setup_laravel_project "$DOCROOT"
                fi
            else
                echo -e "${RED}❌ Failed to clone repository.${NC}"
                echo -e "${YELLOW}Possible solutions:${NC}"
                echo -e "${YELLOW}1. Use HTTPS URL instead of SSH ${NC}"
                echo -e "${YELLOW}2. Add SSH key to VPS and configure GitHub access${NC}"
                echo -e "${YELLOW}3. Make repository public temporarily${NC}"

                read -rp "Try with different URL? [y/N]: " RETRY
                if [[ "$RETRY" =~ ^[Yy]$ ]]; then
                    read -rp "Enter alternative repository URL: " ALT_GIT_URL
                    if [ -n "$ALT_GIT_URL" ]; then
                        echo -e "${CYAN}Attempting to clone: $ALT_GIT_URL${NC}"
                        if git clone "$ALT_GIT_URL" "$DOCROOT/temp_clone"; then
                            mv "$DOCROOT/temp_clone"/* "$DOCROOT/" 2>/dev/null
                            mv "$DOCROOT/temp_clone"/.[!.]* "$DOCROOT/" 2>/dev/null
                            rmdir "$DOCROOT/temp_clone"
                            chown -R www-data:www-data "$DOCROOT"
                            echo -e "${GREEN}✅ Successfully cloned repository to $DOCROOT${NC}"

                            if [ "$STACK_TYPE" = "laravel" ]; then
                                setup_laravel_project "$DOCROOT"
                            fi
                        else
                            echo -e "${RED}❌ Alternative clone also failed.${NC}"
                            return 1
                        fi
                    fi
                else
                    return 1
                fi
            fi
        fi
    fi
}

setup_docker_app() {
    echo -e "${CYAN}Available Docker Apps:${NC}"
    DOCKER_APPS=()
    index=1
    for dir in "$DOCKER_TEMPLATE_DIR"/*/; do
        APP_NAME=$(basename "$dir")
        echo "$index) $APP_NAME"
        DOCKER_APPS+=("$APP_NAME")
        ((index++))
    done

    if [ "${#DOCKER_APPS[@]}" -eq 0 ]; then
        echo -e "${RED}❌ No Docker app templates found in $DOCKER_TEMPLATE_DIR${NC}"
        return
    fi

    read -rp "Choose Docker app [1-${#DOCKER_APPS[@]}]: " CHOICE
    if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "${#DOCKER_APPS[@]}" ]; then
        echo -e "${YELLOW}Invalid choice. Aborting.${NC}"
        return
    fi

    DOCKER_APP="${DOCKER_APPS[$((CHOICE - 1))]}"
    DOCKER_TEMPLATE_DIR_PATH="$DOCKER_TEMPLATE_DIR/$DOCKER_APP"
    DOCKER_COMPOSE_TEMPLATE="$DOCKER_TEMPLATE_DIR_PATH/docker-compose.yml"

    read -rp "Enter app exposed port (default $DEFAULT_DOCKER_PORT): " DOCKER_PORT
    DOCKER_PORT=${DOCKER_PORT:-$DEFAULT_DOCKER_PORT}

    mkdir -p "$DOCROOT"
    cp "$DOCKER_COMPOSE_TEMPLATE" "$DOCROOT/docker-compose.yml"
    sed -i "s|__PORT__|$DOCKER_PORT|g" "$DOCROOT/docker-compose.yml"

    # Handle .env.example → .env
    if [ -f "$DOCKER_TEMPLATE_DIR_PATH/.env.example" ]; then
        if [ -f "$DOCROOT/.env" ]; then
            read -rp ".env already exists in $DOCROOT. Overwrite with .env.example? [y/N]: " OVERWRITE
            if [[ "$OVERWRITE" =~ ^[Yy]$ ]]; then
                cp "$DOCKER_TEMPLATE_DIR_PATH/.env.example" "$DOCROOT/.env"
                echo -e "${GREEN}✅ .env updated from .env.example${NC}"
            else
                echo -e "${YELLOW}⚠️ Skipped overwriting .env${NC}"
            fi
        else
            cp "$DOCKER_TEMPLATE_DIR_PATH/.env.example" "$DOCROOT/.env"
            echo -e "${GREEN}✅ .env created from .env.example${NC}"
        fi
    fi

    chown -R www-data:www-data "$DOCROOT"

    echo -e "${CYAN}Starting Docker app ($DOCKER_APP) using docker-compose...${NC}"
    (cd "$DOCROOT" && docker compose up -d)
}


setup_express_app() {
    local docroot="$1"
    local port="$2"
    local template_file="templates/express_app.js.template"

    if ! command -v pm2 &>/dev/null; then
        echo -e "${CYAN}Installing PM2 process manager...${NC}"
        npm install -g pm2
    fi

    echo -e "${CYAN}Setting up Express.js app at $docroot on port $port...${NC}"

    if [ ! -f "$docroot/app.js" ]; then
        mkdir -p "$docroot/public"
        echo "<h1>Hello from $docroot/public</h1>" > "$docroot/public/index.html"

        if [ -f "$template_file" ]; then
            sed "s|__PORT__|$port|g" "$template_file" > "$docroot/app.js"
        else
            echo -e "${RED}❌ Express template not found: $template_file${NC}"
            return
        fi

        cd "$docroot" && npm init -y && npm install express
    fi

    pm2 start "$docroot/app.js" --name "express-$port"
    pm2 save
}

setup_static_site() {
    local docroot="$1"
    local template_file="templates/static_index.html"
    mkdir -p "$docroot"
    local target_file="$docroot/index.html"
    if [ -f "$target_file" ]; then
        read -rp "index.html already exists in $docroot. Overwrite? [y/N]: " OVERWRITE
        if [[ ! "$OVERWRITE" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}⚠️ Skipped overwriting index.html${NC}"
            return
        fi
    fi
    if [ -f "$template_file" ]; then
        cp "$template_file" "$target_file"
    else
        echo -e "${YELLOW}⚠️ Template for static site not found: $template_file${NC}"
    fi
    chown -R www-data:www-data "$docroot"
}

setup_php_site() {
    local docroot="$1"
    local template_file="templates/php_index.php"
    mkdir -p "$docroot"
    local target_file="$docroot/index.php"
    if [ -f "$target_file" ]; then
        read -rp "index.php already exists in $docroot. Overwrite? [y/N]: " OVERWRITE
        if [[ ! "$OVERWRITE" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}⚠️ Skipped overwriting index.php${NC}"
            return
        fi
    fi
    if [ -f "$template_file" ]; then
        cp "$template_file" "$target_file"
    else
        echo -e "${YELLOW}⚠️ Template for PHP site not found: $template_file${NC}"
    fi
    chown -R www-data:www-data "$docroot"
}

add_domain() {
    read -rp "Enter domain name: " DOMAIN
    if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        echo -e "${RED}❌ Invalid domain format.${NC}"
        return
    fi

    read -rp "Support www.$DOMAIN? [y/N]: " ENABLE_WWW
    WWW_DOMAIN=""
    if [[ "$ENABLE_WWW" =~ ^[Yy]$ ]]; then
        WWW_DOMAIN="www.$DOMAIN"
    fi

    read -rp "Enter document root (default: $DEFAULT_DOCROOT_BASE/$DOMAIN): " DOCROOT
    DOCROOT=${DOCROOT:-$DEFAULT_DOCROOT_BASE/$DOMAIN}
    DOCROOT=$(realpath -m "$DOCROOT")

    select_stack_type

    echo -e "${CYAN}Creating Nginx config for $DOMAIN... (Stack: $STACK_TYPE)${NC}"
    log "Creating domain $DOMAIN with root $DOCROOT and stack $STACK_TYPE"

    if confirm_action; then
        mkdir -p "$DOCROOT"
        chown -R www-data:www-data "$DOCROOT"

        setup_logging_for_domain "$DOMAIN"
        setup_git_clone

        case $STACK_TYPE in
            php)
                TEMPLATE_PATH="$NGINX_TEMPLATE_DIR/nginx_basic.conf.template"
                setup_php_site "$DOCROOT" ;;
            laravel)
                TEMPLATE_PATH="$NGINX_TEMPLATE_DIR/nginx_laravel.conf.template" ;;
            wordpress)
                TEMPLATE_PATH="$NGINX_TEMPLATE_DIR/nginx_wordpress.conf.template" ;;
            static)
                TEMPLATE_PATH="$NGINX_TEMPLATE_DIR/nginx_static.conf.template"
                setup_static_site "$DOCROOT" ;;
            node)
                TEMPLATE_PATH="$NGINX_TEMPLATE_DIR/nginx_node.conf.template"
                read -rp "Enter port for Node.js app (default $DEFAULT_NODE_PORT): " NODE_PORT
                STACK_PORT=${NODE_PORT:-$DEFAULT_NODE_PORT}
                setup_express_app "$DOCROOT" "$STACK_PORT" ;;
            docker)
                TEMPLATE_PATH="$NGINX_TEMPLATE_DIR/nginx_docker.conf.template"
                setup_docker_app ;;
        esac

        CONFIG_PATH="/etc/nginx/sites-available/$DOMAIN"
        if [ ! -f "$TEMPLATE_PATH" ]; then
            echo -e "${RED}Template file not found: $TEMPLATE_PATH${NC}"
            log "Template file not found for $STACK_TYPE"
            return
        fi

        sed -e "s|__DOMAIN__|$DOMAIN|g" \
            -e "s|__DOCROOT__|$DOCROOT|g" \
            -e "s|__PHP_VERSION__|$PHP_VERSION|g" \
            -e "s|__LOG_ACCESS__|/var/log/nginx/$DOMAIN/access.log|g" \
            -e "s|__LOG_ERROR__|/var/log/nginx/$DOMAIN/error.log|g" \
            -e "s|__PORT__|$STACK_PORT|g" \
            -e "s|__SERVER_NAME__|$DOMAIN $WWW_DOMAIN|g" \
            "$TEMPLATE_PATH" > "$CONFIG_PATH"

        if [ ! -L "/etc/nginx/sites-enabled/$DOMAIN" ]; then
            ln -s "$CONFIG_PATH" "/etc/nginx/sites-enabled/"
        fi

        if nginx -t; then
            systemctl reload nginx
            echo -e "${GREEN}✅ Domain $DOMAIN added with root $DOCROOT.${NC}"
            log "Domain $DOMAIN added and nginx reloaded."

            read -rp "Enable SSL with Let's Encrypt? [y/N]: " ENABLE_SSL
            if [[ "$ENABLE_SSL" =~ ^[Yy]$ ]]; then
                if ! command -v certbot &>/dev/null; then
                    echo -e "${YELLOW}Certbot not found. Installing...${NC}"
                    apt update
                    apt install -y certbot python3-certbot-nginx
                fi

                if [[ -n "$WWW_DOMAIN" ]]; then
                    certbot --nginx -d "$DOMAIN" -d "$WWW_DOMAIN"
                else
                    certbot --nginx -d "$DOMAIN"
                fi

                echo -e "${GREEN}✅ SSL enabled for $DOMAIN${NC}"
                log "SSL enabled for $DOMAIN"
            fi
        else
            echo -e "${RED}❌ Nginx config test failed. Please check manually.${NC}"
            log "Nginx config test failed for $DOMAIN"
        fi
    fi
}

list_domains() {
    echo -e "${CYAN}Configured domains:${NC}"
    ls /etc/nginx/sites-available
}

modify_domain() {
    read -rp "Enter domain to modify: " DOMAIN
    if [ ! -f "/etc/nginx/sites-available/$DOMAIN" ]; then
        echo -e "${RED}Domain $DOMAIN does not exist.${NC}"
        return
    fi
    read -rp "Enter new document root (leave blank to keep existing): " NEW_DOCROOT
    if confirm_action; then
        if [ -n "$NEW_DOCROOT" ]; then
            sed -i "s|root .*;|root $NEW_DOCROOT;|" "/etc/nginx/sites-available/$DOMAIN"
            mkdir -p "$NEW_DOCROOT"
            chown -R www-data:www-data "$NEW_DOCROOT"
        fi
        if nginx -t; then
            systemctl reload nginx
            echo -e "${GREEN}✅ Domain $DOMAIN updated.${NC}"
        else
            echo -e "${RED}❌ Nginx config test failed.${NC}"
        fi
    fi
}

delete_domain() {
    read -rp "Enter domain name to delete: " DOMAIN
    CONFIG_PATH="/etc/nginx/sites-available/$DOMAIN"
    ENABLED_PATH="/etc/nginx/sites-enabled/$DOMAIN"

    if [ ! -f "$CONFIG_PATH" ]; then
        echo -e "${RED}❌ Domain config not found: $DOMAIN${NC}"
        return
    fi

    read -rp "Also delete document root? [y/N]: " DELETE_ROOT
    if [[ "$DELETE_ROOT" =~ ^[Yy]$ ]]; then
        ROOT_DIR=$(grep "root" "$CONFIG_PATH" | awk '{print $2}' | sed 's/;//')
        if [ -d "$ROOT_DIR" ]; then
            rm -rf "$ROOT_DIR"
            echo -e "${GREEN}✅ Document root deleted: $ROOT_DIR${NC}"
        fi
    fi

    rm -f "$ENABLED_PATH" "$CONFIG_PATH"
    systemctl reload nginx
    echo -e "${GREEN}✅ Domain $DOMAIN deleted.${NC}"
    log "Domain $DOMAIN deleted."
}

show_domain_menu() {
    echo -e "${CYAN}--- Domain Setup ---${NC}"
    echo "1) List Domain"
    echo "2) Add Domain"
    echo "3) Modify Domain"
    echo "4) Delete Domain"
    read -rp "Choose domain task [1-4]: " DOMAIN_OPTION
    case $DOMAIN_OPTION in
        1) list_domains ;;
        2) add_domain ;;
        3) modify_domain ;;
        4) delete_domain ;;
        *) echo -e "${YELLOW}Invalid option.${NC}" ;;
    esac
}

setup_laravel_project() {
    local docroot="$1"

    echo -e "${CYAN}Setting up Laravel project...${NC}"

    # Check if composer is installed
    if ! command -v composer &>/dev/null; then
        echo -e "${YELLOW}Composer not found. Installing...${NC}"
        # Install composer system-wide but safely
        curl -sS https://getcomposer.org/installer | php
        mv composer.phar /usr/local/bin/composer
        chmod +x /usr/local/bin/composer

        # Set composer to not run as root warning
        export COMPOSER_ALLOW_SUPERUSER=1
    fi

    cd "$docroot"

    # Set proper ownership first
    chown -R www-data:www-data "$docroot"

    # Install dependencies as www-data user (not root)
    echo -e "${CYAN}Installing Composer dependencies (running as www-data user)...${NC}"
    if sudo -u www-data composer install --no-dev --optimize-autoloader --no-interaction; then
        echo -e "${GREEN}✅ Composer dependencies installed successfully${NC}"
    else
        echo -e "${YELLOW}⚠️ Composer install failed as www-data, trying with fallback method...${NC}"
        # Fallback: run as root but with explicit permission
        COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction
        echo -e "${YELLOW}⚠️ Composer ran as root (not recommended, but necessary as fallback)${NC}"
        # Re-fix ownership after root composer run
        chown -R www-data:www-data "$docroot"
    fi

    # Setup .env file
    if [ -f ".env.example" ] && [ ! -f ".env" ]; then
        sudo -u www-data cp .env.example .env
        echo -e "${GREEN}✅ .env file created from .env.example${NC}"
    fi

    # Generate application key (run as www-data if possible)
    if [ -f ".env" ]; then
        if sudo -u www-data php artisan key:generate --no-interaction 2>/dev/null; then
            echo -e "${GREEN}✅ Application key generated (as www-data)${NC}"
        else
            # Fallback to root if www-data doesn't have proper permissions
            php artisan key:generate --no-interaction
            echo -e "${YELLOW}⚠️ Application key generated as root${NC}"
        fi
    fi

    # Set proper permissions
    chown -R www-data:www-data "$docroot"
    chmod -R 755 "$docroot"

    # Laravel specific directory permissions
    if [ -d "$docroot/storage" ]; then
        chmod -R 775 "$docroot/storage"
    fi
    if [ -d "$docroot/bootstrap/cache" ]; then
        chmod -R 775 "$docroot/bootstrap/cache"
    fi

    # Clear and cache config (run as www-data if possible)
    echo -e "${CYAN}Optimizing Laravel application...${NC}"

    # Try to run artisan commands as www-data
    if sudo -u www-data php artisan config:clear --no-interaction 2>/dev/null && \
       sudo -u www-data php artisan cache:clear --no-interaction 2>/dev/null; then
        echo -e "${GREEN}✅ Cache cleared (as www-data)${NC}"

        # Try to cache configs as www-data
        if sudo -u www-data php artisan config:cache --no-interaction 2>/dev/null && \
           sudo -u www-data php artisan route:cache --no-interaction 2>/dev/null && \
           sudo -u www-data php artisan view:cache --no-interaction 2>/dev/null; then
            echo -e "${GREEN}✅ Application optimized (as www-data)${NC}"
        else
            echo -e "${YELLOW}⚠️ Some optimization commands failed as www-data, skipping caching${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️ Running artisan commands as root (not recommended)${NC}"
        php artisan config:clear --no-interaction
        php artisan cache:clear --no-interaction
        # Skip caching when running as root to avoid permission issues
        echo -e "${YELLOW}⚠️ Skipping config caching to avoid permission issues${NC}"
    fi

    # Final ownership fix
    chown -R www-data:www-data "$docroot"

    echo -e "${GREEN}✅ Laravel project setup completed${NC}"
    echo -e "${CYAN}ℹ️  Note: Composer and artisan commands were run with appropriate user permissions${NC}"
}
