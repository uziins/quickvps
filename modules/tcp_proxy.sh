#!/bin/bash

# TCP / Stream Proxy Module

NGINX_STREAM_DIR="/etc/nginx/stream-available"
NGINX_STREAM_ENABLED_DIR="/etc/nginx/stream-enabled"

setup_nginx_stream_module() {
    # Check if stream directory exists
    if [ ! -d "$NGINX_STREAM_DIR" ]; then
        mkdir -p "$NGINX_STREAM_DIR"
        mkdir -p "$NGINX_STREAM_ENABLED_DIR"
    fi

    # Check if nginx.conf has the stream block
    if [ -f /etc/nginx/nginx.conf ] && ! grep -q -E "stream[[:space:]]*\{" /etc/nginx/nginx.conf; then
        echo -e "${YELLOW}Setting up Nginx Stream module...${NC}"
        cat <<EOF >> /etc/nginx/nginx.conf

# TCP/UDP Stream proxy configuration added by QuickVPS
stream {
    include /etc/nginx/stream-enabled/*.conf;
}
EOF
        echo -e "${GREEN}✅ Nginx Stream module configured.${NC}"
        systemctl reload nginx 2>/dev/null || true
    fi
}

add_tcp_proxy() {
    setup_nginx_stream_module
    
    read -rp "Enter listen port (public port, e.g. 8883): " LISTEN_PORT
    if [[ ! "$LISTEN_PORT" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}❌ Invalid port format.${NC}"
        return
    fi
    
    if [ -f "$NGINX_STREAM_DIR/port_$LISTEN_PORT.conf" ]; then
        echo -e "${YELLOW}Port $LISTEN_PORT is already configured as a TCP Proxy.${NC}"
        return
    fi

    read -rp "Enter destination (e.g. 127.0.0.1:1884): " DESTINATION
    if [[ -z "$DESTINATION" ]]; then
        echo -e "${RED}❌ Destination cannot be empty.${NC}"
        return
    fi

    read -rp "Enable SSL/TLS Termination for this port? [y/N]: " ENABLE_SSL
    
    local CONFIG_PATH="$NGINX_STREAM_DIR/port_$LISTEN_PORT.conf"
    local ENABLED_PATH="$NGINX_STREAM_ENABLED_DIR/port_$LISTEN_PORT.conf"

    if [[ "$ENABLE_SSL" =~ ^[Yy]$ ]]; then
        read -rp "Enter domain name for SSL certificate (e.g. mqtt.iluzi.id): " SSL_DOMAIN
        
        # Verify cert exists
        if [ ! -f "/etc/letsencrypt/live/$SSL_DOMAIN/fullchain.pem" ]; then
            echo -e "${RED}❌ SSL certificate for $SSL_DOMAIN not found in Let's Encrypt directory (/etc/letsencrypt/live/$SSL_DOMAIN/).${NC}"
            echo -e "${YELLOW}Please create the domain and setup SSL via Certbot first before enabling TCP SSL.${NC}"
            return
        fi

        echo -e "${CYAN}Creating SSL TCP Proxy on port $LISTEN_PORT -> $DESTINATION using $SSL_DOMAIN...${NC}"
        if confirm_action; then
            sed -e "s|__LISTEN_PORT__|$LISTEN_PORT|g" \
                -e "s|__DESTINATION__|$DESTINATION|g" \
                -e "s|__DOMAIN__|$SSL_DOMAIN|g" \
                "$SCRIPT_DIR/templates/stream_proxy_ssl.conf.template" > "$CONFIG_PATH"
        else
            return
        fi
    else
        echo -e "${CYAN}Creating TCP Proxy on port $LISTEN_PORT -> $DESTINATION...${NC}"
        if confirm_action; then
            sed -e "s|__LISTEN_PORT__|$LISTEN_PORT|g" \
                -e "s|__DESTINATION__|$DESTINATION|g" \
                "$SCRIPT_DIR/templates/stream_proxy.conf.template" > "$CONFIG_PATH"
        else
            return
        fi
    fi

    ln -sf "$CONFIG_PATH" "$ENABLED_PATH"

    if nginx -t; then
        systemctl reload nginx
        echo -e "${GREEN}✅ TCP Proxy for port $LISTEN_PORT successfully created and enabled.${NC}"
        log "TCP Proxy added: Port $LISTEN_PORT -> $DESTINATION (SSL: $ENABLE_SSL)"
    else
        echo -e "${RED}❌ Nginx config test failed. Please check $CONFIG_PATH manually.${NC}"
        rm -f "$ENABLED_PATH"
    fi
}

delete_tcp_proxy() {
    read -rp "Enter port to delete (e.g. 8883): " LISTEN_PORT
    if [[ ! "$LISTEN_PORT" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}❌ Invalid port format.${NC}"
        return
    fi
    
    local CONFIG_PATH="$NGINX_STREAM_DIR/port_$LISTEN_PORT.conf"
    local ENABLED_PATH="$NGINX_STREAM_ENABLED_DIR/port_$LISTEN_PORT.conf"

    if [ ! -f "$CONFIG_PATH" ]; then
        echo -e "${RED}❌ TCP Proxy for port $LISTEN_PORT not found.${NC}"
        return
    fi

    echo -e "${RED}Are you sure you want to delete TCP Proxy for port $LISTEN_PORT?${NC}"
    if confirm_action; then
        rm -f "$CONFIG_PATH"
        rm -f "$ENABLED_PATH"
        
        if nginx -t; then
            systemctl reload nginx
            echo -e "${GREEN}✅ TCP Proxy for port $LISTEN_PORT deleted.${NC}"
            log "TCP Proxy deleted for port $LISTEN_PORT"
        else
            echo -e "${RED}❌ Nginx reload failed after deletion.${NC}"
        fi
    fi
}

list_tcp_proxies() {
    echo -e "${CYAN}Configured TCP Proxies in $NGINX_STREAM_DIR:${NC}"
    if [ -d "$NGINX_STREAM_DIR" ]; then
        ls -1 "$NGINX_STREAM_DIR" 2>/dev/null | grep "\.conf$" || echo "No TCP proxies found."
    else
        echo "No TCP proxies found."
    fi
}

show_tcp_menu() {
    echo -e "${CYAN}--- TCP/Stream Proxy Setup ---${NC}"
    echo "1) Add TCP Proxy"
    echo "2) Delete TCP Proxy"
    echo "3) List TCP Proxies"
    read -rp "Choose TCP task [1-3]: " TCP_OPTION
    case $TCP_OPTION in
        1) add_tcp_proxy ;;
        2) delete_tcp_proxy ;;
        3) list_tcp_proxies ;;
        *) echo -e "${YELLOW}Invalid option.${NC}" ;;
    esac
}
