#!/bin/bash

# TCP / Stream Proxy Module

NGINX_STREAM_DIR="/etc/nginx/stream-available"
NGINX_STREAM_ENABLED_DIR="/etc/nginx/stream-enabled"

setup_nginx_stream_module() {
    mkdir -p "$NGINX_STREAM_DIR" "$NGINX_STREAM_ENABLED_DIR"

    # Check if nginx.conf has the stream block
    if [ -f /etc/nginx/nginx.conf ] && ! grep -q -E "^[[:space:]]*stream[[:space:]]*\{" /etc/nginx/nginx.conf; then
        echo -e "${YELLOW}Setting up Nginx Stream module...${NC}"
        local backup="/etc/nginx/nginx.conf.bak.$(date +%Y%m%d%H%M%S)"
        cp -p /etc/nginx/nginx.conf "$backup"
        cat <<EOF >> /etc/nginx/nginx.conf

# TCP/UDP Stream proxy configuration added by QuickVPS
stream {
    include /etc/nginx/stream-enabled/*.conf;
}
EOF
        if nginx_test_and_reload "mv -f '$backup' /etc/nginx/nginx.conf"; then
            echo -e "${GREEN}✅ Nginx Stream module configured.${NC}"
        else
            echo -e "${RED}❌ Nginx does not accept the stream block (is the stream module installed?). Reverted.${NC}"
            return 1
        fi
    fi
}

validate_destination() {
    # host:port (hostname, IPv4 or [IPv6]) or unix:/path
    [[ "$1" =~ ^([A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\]):[0-9]{1,5}$ || "$1" =~ ^unix:/[A-Za-z0-9._/-]+$ ]]
}

add_tcp_proxy() {
    prompt_value LISTEN_PORT "Enter listen port (public port, e.g. 8883)"
    if ! validate_port "$LISTEN_PORT"; then
        echo -e "${RED}❌ Invalid port.${NC}"
        return 1
    fi

    local config_path="$NGINX_STREAM_DIR/port_$LISTEN_PORT.conf"
    local enabled_path="$NGINX_STREAM_ENABLED_DIR/port_$LISTEN_PORT.conf"
    if [ -f "$config_path" ]; then
        echo -e "${YELLOW}Port $LISTEN_PORT is already configured as a TCP Proxy.${NC}"
        return 1
    fi

    prompt_value DESTINATION "Enter destination (e.g. 127.0.0.1:1884)"
    if ! validate_destination "$DESTINATION"; then
        echo -e "${RED}❌ Invalid destination. Use host:port or unix:/path.${NC}"
        return 1
    fi

    local template
    if ask_yes_no "Enable SSL/TLS Termination for this port?" n "$([[ -n "$SSL_DOMAIN" ]] && echo y)"; then
        prompt_value SSL_DOMAIN "Enter domain name for SSL certificate (e.g. mqtt.example.com)"
        if ! validate_domain "$SSL_DOMAIN"; then
            echo -e "${RED}❌ Invalid domain.${NC}"
            return 1
        fi
        if [ ! -f "/etc/letsencrypt/live/$SSL_DOMAIN/fullchain.pem" ]; then
            echo -e "${RED}❌ SSL certificate for $SSL_DOMAIN not found in /etc/letsencrypt/live/$SSL_DOMAIN/.${NC}"
            echo -e "${YELLOW}Please create the domain and setup SSL via Certbot first before enabling TCP SSL.${NC}"
            return 1
        fi
        template="$NGINX_TEMPLATE_DIR/stream_proxy_ssl.conf.template"
        echo -e "${CYAN}Creating SSL TCP Proxy on port $LISTEN_PORT -> $DESTINATION using $SSL_DOMAIN...${NC}"
    else
        SSL_DOMAIN=""
        template="$NGINX_TEMPLATE_DIR/stream_proxy.conf.template"
        echo -e "${CYAN}Creating TCP Proxy on port $LISTEN_PORT -> $DESTINATION...${NC}"
    fi
    confirm_action || return 1

    setup_nginx_stream_module || return 1

    sed -e "s|__LISTEN_PORT__|$LISTEN_PORT|g" \
        -e "s|__DESTINATION__|$(sed_escape "$DESTINATION")|g" \
        -e "s|__DOMAIN__|$SSL_DOMAIN|g" \
        "$template" > "$config_path"
    ln -sf "$config_path" "$enabled_path"

    if nginx_test_and_reload "rm -f '$enabled_path' '$config_path'"; then
        echo -e "${GREEN}✅ TCP Proxy for port $LISTEN_PORT successfully created and enabled.${NC}"
        log "TCP Proxy added: Port $LISTEN_PORT -> $DESTINATION (SSL: ${SSL_DOMAIN:-no})"
    else
        echo -e "${RED}❌ Nginx config test failed. The change was rolled back.${NC}"
        return 1
    fi
}

delete_tcp_proxy() {
    prompt_value LISTEN_PORT "Enter port to delete (e.g. 8883)"
    if ! validate_port "$LISTEN_PORT"; then
        echo -e "${RED}❌ Invalid port.${NC}"
        return 1
    fi

    local config_path="$NGINX_STREAM_DIR/port_$LISTEN_PORT.conf"
    local enabled_path="$NGINX_STREAM_ENABLED_DIR/port_$LISTEN_PORT.conf"

    if [ ! -f "$config_path" ]; then
        echo -e "${RED}❌ TCP Proxy for port $LISTEN_PORT not found.${NC}"
        return 1
    fi

    echo -e "${RED}TCP Proxy for port $LISTEN_PORT will be deleted.${NC}"
    confirm_action || return 1

    rm -f "$config_path" "$enabled_path"
    if nginx_test_and_reload; then
        echo -e "${GREEN}✅ TCP Proxy for port $LISTEN_PORT deleted.${NC}"
        log "TCP Proxy deleted for port $LISTEN_PORT"
    else
        echo -e "${RED}❌ Nginx reload failed after deletion.${NC}"
        return 1
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
