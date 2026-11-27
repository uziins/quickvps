#!/bin/bash

# Ensure template directory is set correctly (setup.sh normally sets an absolute path)
if [ -z "$NGINX_TEMPLATE_DIR" ]; then
    NGINX_TEMPLATE_DIR="$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")/templates"
fi

select_stack_type() {
    local valid="php laravel wordpress static node docker proxy"
    if [[ -n "$STACK_TYPE" ]]; then
        if [[ " $valid " != *" $STACK_TYPE "* ]]; then
            echo -e "${RED}❌ Invalid stack type: $STACK_TYPE (valid: $valid)${NC}"
            return 1
        fi
        return 0
    fi
    if [[ "$NON_INTERACTIVE" == "1" ]]; then
        echo -e "${YELLOW}No --stack given. Defaulting to PHP.${NC}"
        STACK_TYPE="php"
        return 0
    fi

    echo -e "${CYAN}Select Stack Type:${NC}"
    echo "1) PHP (Native)"
    echo "2) Laravel"
    echo "3) WordPress"
    echo "4) Static Site"
    echo "5) Node.js (Express)"
    echo "6) Dockerized App"
    echo "7) Reverse Proxy (Generic)"
    read -rp "Choose stack type [1-7]: " STACK_OPTION
    case $STACK_OPTION in
        1) STACK_TYPE="php" ;;
        2) STACK_TYPE="laravel" ;;
        3) STACK_TYPE="wordpress" ;;
        4) STACK_TYPE="static" ;;
        5) STACK_TYPE="node" ;;
        6) STACK_TYPE="docker" ;;
        7) STACK_TYPE="proxy" ;;
        *) echo -e "${YELLOW}Invalid option. Defaulting to PHP.${NC}"; STACK_TYPE="php" ;;
    esac
}

# Clone $1 into $DOCROOT via a temporary directory (keeps dotfiles).
clone_repo_into_docroot() {
    local url="$1" tmp
    tmp=$(mktemp -d) || return 1
    echo -e "${CYAN}Attempting to clone: $url${NC}"
    if ! git clone "$url" "$tmp/repo"; then
        rm -rf "$tmp"
        return 1
    fi
    (
        shopt -s dotglob nullglob
        mv "$tmp/repo"/* "$DOCROOT"/
    )
    rm -rf "$tmp"
    chown -R "${DOMAIN_OWNER:-$WEB_USER}":"$WEB_GROUP" "$DOCROOT"
    echo -e "${GREEN}✅ Successfully cloned repository to $DOCROOT${NC}"
    if [ "$STACK_TYPE" = "laravel" ]; then
        setup_laravel_project "$DOCROOT"
    fi
}

setup_git_clone() {
    if [[ -z "$GIT_URL" ]]; then
        [[ "$NON_INTERACTIVE" == "1" ]] && return 0
        ask_yes_no "Clone project from Git repository?" n || return 0
        read -rp "Enter Git repository URL: " GIT_URL
        [[ -z "$GIT_URL" ]] && return 0
    fi

    # Offer to convert a GitHub SSH URL to HTTPS (interactive only)
    if [[ "$GIT_URL" =~ ^git@github\.com: ]] && [[ "$NON_INTERACTIVE" != "1" ]]; then
        local https_url
        https_url=$(echo "$GIT_URL" | sed -e 's|^git@github\.com:|https://github.com/|' -e 's|\.git$||')
        echo -e "${YELLOW}SSH URL detected. HTTPS alternative: $https_url${NC}"
        if ask_yes_no "Use HTTPS URL instead?" y; then
            GIT_URL="$https_url"
        fi
    fi

    # Check if directory exists and is not empty
    if [ -d "$DOCROOT" ] && [ -n "$(ls -A "$DOCROOT" 2>/dev/null)" ]; then
        echo -e "${YELLOW}Directory $DOCROOT is not empty.${NC}"
        if ask_yes_no "Remove existing files and clone fresh?" n && is_safe_path "$DOCROOT"; then
            find "$DOCROOT" -mindepth 1 -delete
        else
            echo -e "${YELLOW}Skipping git clone. Using existing directory.${NC}"
            return 0
        fi
    fi
    mkdir -p "$DOCROOT"

    if clone_repo_into_docroot "$GIT_URL"; then
        return 0
    fi

    echo -e "${RED}❌ Failed to clone repository.${NC}"
    [[ "$NON_INTERACTIVE" == "1" ]] && return 1
    echo -e "${YELLOW}Possible solutions:${NC}"
    echo -e "${YELLOW}1. Use HTTPS URL instead of SSH ${NC}"
    echo -e "${YELLOW}2. Add SSH key to VPS and configure GitHub access${NC}"
    echo -e "${YELLOW}3. Make repository public temporarily${NC}"
    if ask_yes_no "Try with different URL?" n; then
        local alt_url
        read -rp "Enter alternative repository URL: " alt_url
        if [ -n "$alt_url" ] && clone_repo_into_docroot "$alt_url"; then
            return 0
        fi
        echo -e "${RED}❌ Alternative clone also failed.${NC}"
    fi
    return 1
}

setup_express_app() {
    local docroot="$1"
    local port="$2"
    local template_file="$NGINX_TEMPLATE_DIR/express_app.js.template"

    if ! command -v pm2 &>/dev/null; then
        echo -e "${CYAN}Installing PM2 process manager...${NC}"
        npm install -g pm2
    fi

    echo -e "${CYAN}Setting up Express.js app at $docroot on port $port...${NC}"

    if [ ! -f "$docroot/app.js" ]; then
        if [ ! -f "$template_file" ]; then
            echo -e "${RED}❌ Express template not found: $template_file${NC}"
            return 1
        fi
        mkdir -p "$docroot/public"
        echo "<h1>Hello from $docroot/public</h1>" > "$docroot/public/index.html"
        sed "s|__PORT__|$port|g" "$template_file" > "$docroot/app.js"
        # Subshell so the caller's working directory is not changed
        (cd "$docroot" && npm init -y && npm install express) || return 1
    fi

    pm2 start "$docroot/app.js" --name "express-$port"
    pm2 save
}

# Copy a starter file into the docroot. Usage: install_starter_file <docroot> <template> <target name>
install_starter_file() {
    local docroot="$1" template_file="$2" target_file="$1/$3"
    mkdir -p "$docroot"
    if [ -f "$target_file" ]; then
        if ! ask_yes_no "$3 already exists in $docroot. Overwrite?" n; then
            echo -e "${YELLOW}⚠️ Skipped overwriting $3${NC}"
            return 0
        fi
    fi
    if [ -f "$template_file" ]; then
        cp "$template_file" "$target_file"
        chown "${DOMAIN_OWNER:-$WEB_USER}":"$WEB_GROUP" "$target_file"
    else
        echo -e "${YELLOW}⚠️ Template not found: $template_file${NC}"
    fi
}

setup_static_site() {
    install_starter_file "$1" "$NGINX_TEMPLATE_DIR/static_index.html" "index.html"
}

setup_php_site() {
    install_starter_file "$1" "$NGINX_TEMPLATE_DIR/php_index.php" "index.php"
}

fastcgi_pass_target() {
    if [[ "$OS_FAMILY" == "debian" ]]; then
        echo "unix:/run/php/php${PHP_VERSION}-fpm.sock"
    else
        echo "unix:/run/php-fpm/www.sock"
    fi
}

fastcgi_config() {
    if [[ "$OS_FAMILY" == "debian" ]]; then
        echo "include snippets/fastcgi-php.conf; fastcgi_pass $(fastcgi_pass_target);"
    else
        echo "include fastcgi_params; fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name; fastcgi_pass $(fastcgi_pass_target);"
    fi
}

# List site config files in $NGINX_CONF_DIR (skips backups and editor/package leftovers)
list_config_files() {
    local f
    for f in "$NGINX_CONF_DIR"/*; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in
            *.bak|*.bak.*|*.dpkg-*|*.rpmnew|*.rpmsave|*.orig|*.save|*.swp|*~) continue ;;
        esac
        echo "$f"
    done
}

# Print every name from the server_name directives of config file $1, one per line
config_server_names() {
    awk '
        {
            line = $0; sub(/#.*/, "", line)
            # server_name may follow "{" or ";" on the same line
            while (match(line, /(^|[ \t{;])server_name[ \t]+[^;]*/)) {
                part = substr(line, RSTART, RLENGTH)
                sub(/^.*server_name[ \t]+/, "", part)
                n = split(part, a, /[ \t]+/)
                for (i = 1; i <= n; i++) if (a[i] != "") print tolower(a[i])
                line = substr(line, RSTART + RLENGTH)
            }
        }
    ' "$1"
}

# True if config file $1 has domain $2 as an exact name in a server_name directive
config_serves_domain() {
    config_server_names "$1" | grep -qxiF -- "$2"
}

# True if nginx actually loads config file $1
config_is_enabled() {
    local config="$1"
    if [ "$NGINX_CONF_DIR" == "$NGINX_ENABLED_DIR" ]; then
        # conf.d style (RHEL): only *.conf is included
        [[ "$config" == *.conf ]]
    else
        [ -n "$(find_enabled_links "$config")" ]
    fi
}

# Print every entry in $NGINX_ENABLED_DIR that is a symlink to config file $1, whatever its name
find_enabled_links() {
    local target link
    [ "$NGINX_CONF_DIR" == "$NGINX_ENABLED_DIR" ] && return 0
    target=$(readlink -f "$1")
    for link in "$NGINX_ENABLED_DIR"/*; do
        [ -L "$link" ] || continue
        [ "$(readlink -f "$link")" == "$target" ] && echo "$link"
    done
}

# Find the nginx config file of a domain, named "<domain>.conf" or "<domain>",
# or otherwise the single file whose server_name lists the domain.
# Prints the path. Returns 1 if not found, 2 if ambiguous (details on stderr).
find_domain_config() {
    local domain="$1" f
    validate_domain "$domain" || return 1

    local by_name=()
    [ -f "$NGINX_CONF_DIR/$domain.conf" ] && by_name+=("$NGINX_CONF_DIR/$domain.conf")
    [ -f "$NGINX_CONF_DIR/$domain" ] && by_name+=("$NGINX_CONF_DIR/$domain")
    if [ "${#by_name[@]}" -eq 1 ]; then
        echo "${by_name[0]}"
        return 0
    elif [ "${#by_name[@]}" -gt 1 ]; then
        echo -e "${RED}❌ Both $domain.conf and $domain exist in $NGINX_CONF_DIR. Merge or remove one first.${NC}" >&2
        return 2
    fi

    local by_server_name=()
    while IFS= read -r f; do
        config_serves_domain "$f" "$domain" && by_server_name+=("$f")
    done < <(list_config_files)
    if [ "${#by_server_name[@]}" -eq 1 ]; then
        echo "${by_server_name[0]}"
        return 0
    elif [ "${#by_server_name[@]}" -gt 1 ]; then
        echo -e "${RED}❌ $domain appears in server_name of several configs:${NC}" >&2
        printf '   %s\n' "${by_server_name[@]}" >&2
        return 2
    fi
    return 1
}

# Resolve an existing domain config into the variable named $1. Prints errors.
resolve_domain_config() {
    local __var="$1" domain="$2" __path __rc
    __path=$(find_domain_config "$domain")
    __rc=$?
    if [ "$__rc" -eq 1 ]; then
        echo -e "${RED}❌ Domain config not found: $domain${NC}"
        return 1
    elif [ "$__rc" -ne 0 ]; then
        return 1
    fi
    if ! config_is_enabled "$__path"; then
        if [ "$NGINX_CONF_DIR" == "$NGINX_ENABLED_DIR" ]; then
            echo -e "${YELLOW}⚠️ $__path does not end in .conf, so nginx does not load it.${NC}"
        else
            echo -e "${YELLOW}⚠️ $__path is not enabled (no link in $NGINX_ENABLED_DIR).${NC}"
        fi
    fi
    printf -v "$__var" '%s' "$__path"
}

# True if config $1 is named after domain $2 (so it is safe to overwrite as a whole)
config_named_after_domain() {
    local name
    name=$(basename "$1")
    [[ "$name" == "$2" || "$name" == "$2.conf" ]]
}

# Determine a domain's document root from its config.
# Prefers the "# quickvps-docroot:" marker written by add_domain.
get_domain_docroot() {
    local config="$1" root
    root=$(sed -n 's/^# quickvps-docroot: //p' "$config" | head -n 1)
    if [[ -z "$root" ]]; then
        # First top-level "root" directive (ignores fastcgi_param ... $realpath_root etc.)
        root=$(awk '$1 == "root" { v = $2; sub(/;$/, "", v); print v; exit }' "$config")
        # Laravel serves /public; the project root is its parent
        if [[ "$root" == */public && -f "${root%/public}/artisan" ]]; then
            root="${root%/public}"
        fi
    fi
    echo "$root"
}

add_domain() {
    if ! prompt_value DOMAIN "Enter domain name"; then
        echo -e "${RED}❌ Domain name is required.${NC}"
        return 1
    fi
    if ! validate_domain "$DOMAIN"; then
        echo -e "${RED}❌ Invalid domain format.${NC}"
        return 1
    fi

    # Reuse an existing config for this domain (with or without .conf) instead of adding a second one
    local config_path existing_rc
    config_path=$(find_domain_config "$DOMAIN")
    existing_rc=$?
    if [ "$existing_rc" -eq 2 ]; then
        return 1
    elif [ "$existing_rc" -eq 0 ]; then
        if ! config_named_after_domain "$config_path" "$DOMAIN"; then
            echo -e "${RED}❌ $DOMAIN is already served by $config_path, which is not named after it (it may hold other sites).${NC}"
            echo -e "${YELLOW}Edit that file manually, or remove $DOMAIN from it first.${NC}"
            return 1
        fi
        echo -e "${YELLOW}⚠️ Config already exists: $config_path (any SSL settings in it would be lost).${NC}"
        if [[ "$FORCE" != "1" ]] && ! ask_yes_no "Overwrite existing config?" n; then
            echo -e "${YELLOW}Aborted. Use 'Modify Domain' or pass --force to overwrite.${NC}"
            return 1
        fi
    else
        config_path="$NGINX_CONF_DIR/$DOMAIN.conf"
    fi
    local enabled_path="$NGINX_ENABLED_DIR/$(basename "$config_path")"

    WWW_DOMAIN=""
    if ask_yes_no "Support www.$DOMAIN?" n "$ENABLE_WWW"; then
        WWW_DOMAIN="www.$DOMAIN"
    fi

    prompt_value DOCROOT "Enter document root" "$DEFAULT_DOCROOT_BASE/$DOMAIN"
    DOCROOT=$(realpath -m "$DOCROOT")
    if ! is_safe_path "$DOCROOT"; then
        echo -e "${RED}❌ Refusing to use $DOCROOT as document root (system or top-level directory).${NC}"
        return 1
    fi

    if [[ -z "$DOMAIN_OWNER" ]]; then
        local smart_owner
        smart_owner=$(get_smart_owner "$DOCROOT")
        prompt_value DOMAIN_OWNER "Enter owner for this domain" "$smart_owner"
    fi
    if ! id "$DOMAIN_OWNER" &>/dev/null; then
        echo -e "${RED}❌ User '$DOMAIN_OWNER' does not exist.${NC}"
        return 1
    fi

    select_stack_type || return 1

    local template_path
    case $STACK_TYPE in
        php)       template_path="$NGINX_TEMPLATE_DIR/nginx_basic.conf.template" ;;
        laravel)   template_path="$NGINX_TEMPLATE_DIR/nginx_laravel.conf.template" ;;
        wordpress) template_path="$NGINX_TEMPLATE_DIR/nginx_wordpress.conf.template" ;;
        static)    template_path="$NGINX_TEMPLATE_DIR/nginx_static.conf.template" ;;
        node)      template_path="$NGINX_TEMPLATE_DIR/nginx_node.conf.template" ;;
        docker)    template_path="$NGINX_TEMPLATE_DIR/nginx_docker.conf.template" ;;
        proxy)     template_path="$NGINX_TEMPLATE_DIR/nginx_proxy.conf.template" ;;
    esac
    if [ ! -f "$template_path" ]; then
        echo -e "${RED}Template file not found: $template_path${NC}"
        log "Template file not found for $STACK_TYPE"
        return 1
    fi

    echo -e "${CYAN}Creating Nginx config for $DOMAIN... (Stack: $STACK_TYPE, root: $DOCROOT, owner: $DOMAIN_OWNER)${NC}"
    confirm_action || return 1
    log "Creating domain $DOMAIN with root $DOCROOT and stack $STACK_TYPE"

    # Only change ownership recursively for new/empty directories
    if [ -d "$DOCROOT" ] && [ -n "$(ls -A "$DOCROOT" 2>/dev/null)" ]; then
        echo -e "${YELLOW}$DOCROOT already contains files.${NC}"
        if ask_yes_no "Change ownership of all existing files to $DOMAIN_OWNER:$WEB_GROUP?" n; then
            chown -R "$DOMAIN_OWNER":"$WEB_GROUP" "$DOCROOT"
        fi
    else
        mkdir -p "$DOCROOT"
        chown "$DOMAIN_OWNER":"$WEB_GROUP" "$DOCROOT"
    fi

    setup_logging_for_domain "$DOMAIN"
    setup_git_clone

    case $STACK_TYPE in
        php)
            setup_php_site "$DOCROOT" ;;
        static)
            setup_static_site "$DOCROOT" ;;
        node)
            prompt_value NODE_PORT "Enter port for Node.js app" "$DEFAULT_NODE_PORT"
            if ! validate_port "$NODE_PORT"; then
                echo -e "${RED}❌ Invalid port: $NODE_PORT${NC}"
                return 1
            fi
            STACK_PORT="$NODE_PORT"
            setup_express_app "$DOCROOT" "$STACK_PORT" ;;
        docker)
            select_docker_app || return 1
            deploy_docker_app "$DOCROOT" || return 1 ;;
        proxy)
            prompt_value PROXY_PORT "Enter proxy port (e.g. 8090)" "8080"
            if ! validate_port "$PROXY_PORT"; then
                echo -e "${RED}❌ Invalid port: $PROXY_PORT${NC}"
                return 1
            fi
            STACK_PORT="$PROXY_PORT" ;;
    esac

    # conf.d style (RHEL) only loads *.conf: replace an inactive "<domain>" file with "<domain>.conf"
    local old_inactive=""
    if [ "$NGINX_CONF_DIR" == "$NGINX_ENABLED_DIR" ] && [[ "$config_path" != *.conf ]]; then
        old_inactive="$config_path"
        config_path="$NGINX_CONF_DIR/$DOMAIN.conf"
    fi

    # Back up an existing config so it can be restored if the new one is invalid
    local backup=""
    if [ -f "$config_path" ]; then
        backup="$config_path.bak.$(date +%Y%m%d%H%M%S)"
        cp -p "$config_path" "$backup"
    fi

    {
        echo "# Managed by QuickVPS"
        echo "# quickvps-docroot: $DOCROOT"
        echo "# quickvps-stack: $STACK_TYPE"
        sed -e "s|__DOMAIN__|$(sed_escape "$DOMAIN")|g" \
            -e "s|__DOCROOT__|$(sed_escape "$DOCROOT")|g" \
            -e "s|__PHP_VERSION__|$(sed_escape "$PHP_VERSION")|g" \
            -e "s|__FASTCGI_CONFIG__|$(sed_escape "$(fastcgi_config)")|g" \
            -e "s|__LOG_ACCESS__|/var/log/nginx/$DOMAIN/access.log|g" \
            -e "s|__LOG_ERROR__|/var/log/nginx/$DOMAIN/error.log|g" \
            -e "s|__PORT__|$STACK_PORT|g" \
            -e "s|__SERVER_NAME__|$(sed_escape "$DOMAIN $WWW_DOMAIN")|g" \
            "$template_path"
    } > "$config_path"

    local rollback
    if [[ -n "$backup" ]]; then
        rollback="mv -f $(printf '%q' "$backup") $(printf '%q' "$config_path")"
    else
        rollback="rm -f $(printf '%q' "$config_path")"
    fi

    # Enable the site unless some link (under any name) already points to it
    if [ "$NGINX_CONF_DIR" != "$NGINX_ENABLED_DIR" ] && [ -z "$(find_enabled_links "$config_path")" ]; then
        local enabled_path="$NGINX_ENABLED_DIR/$(basename "$config_path")"
        if [ -e "$enabled_path" ] && [ ! -L "$enabled_path" ]; then
            echo -e "${RED}❌ $enabled_path is a regular file, not a link. Remove or rename it first.${NC}"
            eval "$rollback"
            return 1
        fi
        if [ -L "$enabled_path" ]; then
            # A stale/dangling link with the same name: replace it, restore it on rollback
            rollback+="; ln -sfn $(printf '%q' "$(readlink "$enabled_path")") $(printf '%q' "$enabled_path")"
        else
            rollback+="; rm -f $(printf '%q' "$enabled_path")"
        fi
        ln -sfn "$config_path" "$enabled_path"
    fi

    if ! nginx_test_and_reload "$rollback"; then
        echo -e "${RED}❌ Nginx config test failed. The change was rolled back.${NC}"
        log "Nginx config test failed for $DOMAIN (rolled back)"
        return 1
    fi
    [[ -n "$backup" ]] && rm -f "$backup"
    if [[ -n "$old_inactive" ]]; then
        mv -f "$old_inactive" "$old_inactive.bak.$(date +%Y%m%d%H%M%S)"
        echo -e "${YELLOW}ℹ️  Replaced inactive $old_inactive with $config_path (old file kept as .bak).${NC}"
    fi

    echo -e "${GREEN}✅ Domain $DOMAIN added with root $DOCROOT.${NC}"
    log "Domain $DOMAIN added and nginx reloaded."

    if ask_yes_no "Enable SSL with Let's Encrypt?" n "$ENABLE_SSL"; then
        enable_ssl_for_domain "$DOMAIN" "$WWW_DOMAIN"
    fi
}

enable_ssl_for_domain() {
    local domain="$1" www="$2"
    if ! command -v certbot &>/dev/null; then
        echo -e "${YELLOW}Certbot not found. Installing...${NC}"
        $PKG_UPDATE
        $PKG_INSTALL certbot python3-certbot-nginx
    fi

    local args=(--nginx -d "$domain")
    [[ -n "$www" ]] && args+=(-d "$www")
    if [[ "$NON_INTERACTIVE" == "1" ]]; then
        args+=(--non-interactive --agree-tos)
        if [[ -n "$SSL_EMAIL" ]]; then
            args+=(-m "$SSL_EMAIL")
        else
            args+=(--register-unsafely-without-email)
        fi
    elif [[ -n "$SSL_EMAIL" ]]; then
        args+=(-m "$SSL_EMAIL")
    fi

    if certbot "${args[@]}"; then
        echo -e "${GREEN}✅ SSL enabled for $domain${NC}"
        log "SSL enabled for $domain"
    else
        echo -e "${RED}❌ Certbot failed for $domain. Check DNS and try again.${NC}"
        log "Certbot failed for $domain"
        return 1
    fi
}

list_domains() {
    echo -e "${CYAN}Configured sites in $NGINX_CONF_DIR:${NC}"
    local f name status names found=0
    while IFS= read -r f; do
        name=$(basename "$f")
        [[ "$name" == "default" || "$name" == "default.conf" ]] && continue
        found=1
        if config_is_enabled "$f"; then
            status="${GREEN}enabled${NC} "
        elif [ "$NGINX_CONF_DIR" == "$NGINX_ENABLED_DIR" ]; then
            status="${YELLOW}inactive${NC}"   # conf.d only loads *.conf
        else
            status="${YELLOW}disabled${NC}"
        fi
        names=$(config_server_names "$f" | sort -u | paste -sd ' ' -)
        echo -e "  $status  ${name%.conf}  (${names:-no server_name}) [$name]"
    done < <(list_config_files)
    [[ "$found" == "0" ]] && echo "No domains found."
    return 0
}

modify_domain() {
    if ! prompt_value DOMAIN "Enter domain to modify"; then
        echo -e "${RED}❌ Domain name is required.${NC}"
        return 1
    fi
    local config_path
    resolve_domain_config config_path "$DOMAIN" || return 1

    local old_docroot new_docroot="${DOCROOT:-}"
    old_docroot=$(get_domain_docroot "$config_path")
    if [[ -z "$new_docroot" && "$NON_INTERACTIVE" != "1" ]]; then
        read -rp "Enter new document root (leave blank to keep ${old_docroot:-existing}): " new_docroot
    fi
    if [[ -n "$new_docroot" ]]; then
        new_docroot=$(realpath -m "$new_docroot")
        if ! is_safe_path "$new_docroot"; then
            echo -e "${RED}❌ Refusing to use $new_docroot as document root.${NC}"
            return 1
        fi
        if [[ -z "$old_docroot" ]]; then
            echo -e "${RED}❌ Could not determine the current document root in $config_path.${NC}"
            return 1
        fi
    fi

    local current_port new_port=""
    current_port=$(grep -oE 'proxy_pass http://127\.0\.0\.1:[0-9]+' "$config_path" | head -n 1 | grep -oE '[0-9]+$')
    if [[ -n "$current_port" ]]; then
        new_port="${PROXY_PORT:-}"
        if [[ -z "$new_port" && "$NON_INTERACTIVE" != "1" ]]; then
            read -rp "Enter new proxy port (leave blank to keep $current_port): " new_port
        fi
        if [[ -n "$new_port" ]] && ! validate_port "$new_port"; then
            echo -e "${RED}❌ Invalid port: $new_port${NC}"
            return 1
        fi
    fi

    if [[ -z "$new_docroot" && -z "$new_port" ]]; then
        echo -e "${YELLOW}Nothing to change.${NC}"
        return 0
    fi

    confirm_action || return 1

    local backup
    backup="$config_path.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "$config_path" "$backup"

    if [[ -n "$new_docroot" ]]; then
        # Replace only "root" directives pointing at the old docroot (or its /public)
        local tmp
        tmp=$(mktemp)
        OLD="$old_docroot" NEW="$new_docroot" awk '
            $1 == "root" {
                v = $2; sub(/;$/, "", v)
                indent = substr($0, 1, index($0, "root") - 1)
                if (v == ENVIRON["OLD"])           { print indent "root " ENVIRON["NEW"] ";"; next }
                if (v == ENVIRON["OLD"] "/public") { print indent "root " ENVIRON["NEW"] "/public;"; next }
            }
            /^# quickvps-docroot: / { print "# quickvps-docroot: " ENVIRON["NEW"]; next }
            { print }
        ' "$config_path" > "$tmp" && cat "$tmp" > "$config_path"
        rm -f "$tmp"

        mkdir -p "$new_docroot"
        local smart_owner
        smart_owner=$(get_smart_owner "$new_docroot")
        prompt_value DOMAIN_OWNER "Enter new owner" "$smart_owner"
        set_docroot_permissions "$new_docroot" "$DOMAIN_OWNER"
    fi

    if [[ -n "$new_port" ]]; then
        sed -i "s|proxy_pass http://127\.0\.0\.1:$current_port\([;/]\)|proxy_pass http://127.0.0.1:$new_port\1|g" "$config_path"
    fi

    if nginx_test_and_reload "mv -f '$backup' '$config_path'"; then
        rm -f "$backup"
        echo -e "${GREEN}✅ Domain $DOMAIN updated.${NC}"
        log "Domain $DOMAIN modified (docroot: ${new_docroot:-unchanged}, port: ${new_port:-unchanged})"
    else
        echo -e "${RED}❌ Nginx config test failed. The change was rolled back.${NC}"
        return 1
    fi
}

delete_domain() {
    if ! prompt_value DOMAIN "Enter domain name to delete"; then
        echo -e "${RED}❌ Domain name is required.${NC}"
        return 1
    fi
    local config_path
    resolve_domain_config config_path "$DOMAIN" || return 1
    if ! config_named_after_domain "$config_path" "$DOMAIN"; then
        echo -e "${RED}❌ $DOMAIN is served by $config_path, which is not named after it and may hold other sites.${NC}"
        echo -e "${YELLOW}Remove the $DOMAIN server block from that file manually.${NC}"
        return 1
    fi
    # All links to this config in the enabled dir, whatever their names
    local enabled_links=()
    mapfile -t enabled_links < <(find_enabled_links "$config_path")

    local root_dir="" delete_root=0
    if ask_yes_no "Also delete document root?" n "$DELETE_ROOT"; then
        root_dir=$(get_domain_docroot "$config_path")
        if [[ -z "$root_dir" ]]; then
            echo -e "${YELLOW}⚠️ Could not determine document root; it will not be deleted.${NC}"
        elif ! is_safe_path "$root_dir"; then
            echo -e "${RED}❌ Refusing to delete $root_dir (system or top-level directory). Delete it manually if intended.${NC}"
            return 1
        elif [ -d "$root_dir" ]; then
            delete_root=1
        fi
    fi

    echo -e "${RED}This will delete the nginx config for $DOMAIN${NC}"
    [[ "$delete_root" == "1" ]] && echo -e "${RED}and permanently delete $root_dir${NC}"
    confirm_action || return 1

    local tmp_conf rollback link
    tmp_conf=$(mktemp)
    cp -p "$config_path" "$tmp_conf"
    rollback="cp -p $(printf '%q' "$tmp_conf") $(printf '%q' "$config_path")"
    for link in "${enabled_links[@]}"; do
        rollback+="; ln -sfn $(printf '%q' "$(readlink "$link")") $(printf '%q' "$link")"
    done

    rm -f "$config_path" "${enabled_links[@]}"
    if ! nginx_test_and_reload "$rollback"; then
        rm -f "$tmp_conf"
        echo -e "${RED}❌ Nginx config test failed after removing $DOMAIN. The config was restored.${NC}"
        return 1
    fi
    rm -f "$tmp_conf"

    # Warn about other configs that still mention this domain (copies, leftovers)
    local leftover
    while IFS= read -r leftover; do
        config_serves_domain "$leftover" "$DOMAIN" && \
            echo -e "${YELLOW}⚠️ $leftover still lists $DOMAIN in server_name.${NC}"
    done < <(list_config_files; [ "$NGINX_CONF_DIR" != "$NGINX_ENABLED_DIR" ] && \
             find "$NGINX_ENABLED_DIR" -maxdepth 1 -type f 2>/dev/null)

    if [[ "$delete_root" == "1" ]]; then
        rm -rf -- "$root_dir"
        echo -e "${GREEN}✅ Document root deleted: $root_dir${NC}"
    fi

    echo -e "${GREEN}✅ Domain $DOMAIN deleted.${NC}"
    if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        echo -e "${YELLOW}ℹ️  The SSL certificate still exists. Remove it with: certbot delete --cert-name $DOMAIN${NC}"
    fi
    log "Domain $DOMAIN deleted (docroot removed: $([[ $delete_root == 1 ]] && echo "$root_dir" || echo no))."
}

show_domain_menu() {
    echo -e "${CYAN}--- Domain Setup ---${NC}"
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
}

setup_laravel_project() {
    local docroot="$1"

    echo -e "${CYAN}Setting up Laravel project...${NC}"

    # Check if composer is installed
    if ! command -v composer &>/dev/null; then
        echo -e "${YELLOW}Composer not found. Installing...${NC}"
        (
            cd "$(mktemp -d)" || exit 1
            curl -sS https://getcomposer.org/installer | php && \
                mv composer.phar /usr/local/bin/composer && \
                chmod +x /usr/local/bin/composer
        )
    fi

    # Subshell so the caller's working directory is not changed
    (
        cd "$docroot" || exit 1

        echo -e "${CYAN}Installing Composer dependencies...${NC}"
        composer install --no-dev --optimize-autoloader

        if [ -f ".env.example" ] && [ ! -f ".env" ]; then
            cp .env.example .env
            echo -e "${GREEN}✅ .env file created from .env.example${NC}"
        fi

        if [ -f ".env" ]; then
            php artisan key:generate
            echo -e "${GREEN}✅ Application key generated${NC}"
        fi

        chown -R "${DOMAIN_OWNER:-$WEB_USER}":"$WEB_GROUP" "$docroot"
        chmod -R 755 "$docroot"
        chmod -R 775 "$docroot/storage"
        chmod -R 775 "$docroot/bootstrap/cache"

        php artisan config:clear
        php artisan cache:clear
        php artisan config:cache
        php artisan route:cache
        php artisan view:cache
    ) || return 1

    echo -e "${GREEN}✅ Laravel project setup completed${NC}"
}

# Insert the snippet file $2 into nginx config $1, inside the HTTPS server block
# (one with "listen ... 443") if present, otherwise the first server block.
insert_location_snippet() {
    local config="$1" snippet_file="$2" tmp
    tmp=$(mktemp)
    if SNIPPET_FILE="$snippet_file" awk '
        function count(s, re,   t) { t = s; return gsub(re, "", t) }
        {
            lines[NR] = $0
            line = $0; sub(/#.*/, "", line)
            if (depth == 0 && !inblk && line ~ /^[ \t]*server[ \t]*(\{.*)?$/) { inblk = 1; has443 = 0 }
            if (inblk && line ~ /^[ \t]*listen[ \t].*443/) has443 = 1
            depth += count(line, "[{]") - count(line, "[}]")
            if (inblk && depth == 0 && line ~ /[}]/) { inblk = 0; n++; ends[n] = NR; ssl[n] = has443 }
        }
        END {
            target = 0
            for (i = 1; i <= n; i++) if (ssl[i]) { target = ends[i]; break }
            if (!target && n) target = ends[1]
            if (!target) exit 2
            while ((getline l < ENVIRON["SNIPPET_FILE"]) > 0) snip = snip l "\n"
            for (i = 1; i <= NR; i++) { if (i == target) printf "%s", snip; print lines[i] }
        }
    ' "$config" > "$tmp"; then
        cat "$tmp" > "$config"
        rm -f "$tmp"
        return 0
    fi
    rm -f "$tmp"
    return 1
}

add_subdirectory() {
    if ! prompt_value DOMAIN "Enter existing domain name"; then
        echo -e "${RED}❌ Domain name is required.${NC}"
        return 1
    fi
    local config_path
    resolve_domain_config config_path "$DOMAIN" || return 1

    prompt_value SUBDIR_PATH "Enter subdirectory path (e.g. /api/ or /blog/)"
    # Normalize to exactly one trailing slash: "/api", "/api/" and "/api//" all become "/api/".
    # Without it, "location /api" + alias/proxy_pass ".../" maps /api/x to //x, also matches
    # /apikey, and with alias allows /api../ to escape the directory.
    while [[ "$SUBDIR_PATH" == */ && "$SUBDIR_PATH" != "/" ]]; do
        SUBDIR_PATH="${SUBDIR_PATH%/}"
    done
    if [[ ! "$SUBDIR_PATH" =~ ^(/[A-Za-z0-9_~-][A-Za-z0-9._~-]*)+$ ]] || [[ "$SUBDIR_PATH" =~ /\.\.?(/|$) ]]; then
        echo -e "${RED}❌ Invalid path. Use something like /api or /blog/v1 (letters, digits, . _ ~ -; not / alone).${NC}"
        return 1
    fi
    local path_noslash="$SUBDIR_PATH"
    SUBDIR_PATH="$SUBDIR_PATH/"
    local path_re="${path_noslash//./\\.}"
    if grep -qE "^[[:space:]]*location[[:space:]]+(\^~[[:space:]]+|=[[:space:]]+)?$path_re/?[[:space:]]*\{" "$config_path"; then
        echo -e "${RED}❌ A location for $SUBDIR_PATH already exists in $config_path.${NC}"
        return 1
    fi

    if [[ -z "$SUB_STACK" && "$NON_INTERACTIVE" != "1" ]]; then
        echo -e "${CYAN}Choose stack type for this path:${NC}"
        echo "1) Proxy (Generic/Docker/Node)"
        echo "2) PHP (Native)"
        echo "3) Static HTML"
        read -rp "Select stack [1-3]: " SUB_STACK
    fi
    case "$SUB_STACK" in
        1|proxy) SUB_STACK="proxy" ;;
        2|php) SUB_STACK="php" ;;
        3|static) SUB_STACK="static" ;;
        *) echo -e "${RED}❌ Invalid selection.${NC}"; return 1 ;;
    esac

    local snippet_content="" sub_docroot=""
    if [[ "$SUB_STACK" == "proxy" ]]; then
        prompt_value PROXY_PORT "Enter proxy port (e.g. 8090)"
        if ! validate_port "$PROXY_PORT"; then
            echo -e "${RED}❌ Invalid port: $PROXY_PORT${NC}"
            return 1
        fi
        # Strip: /api/users -> backend /users.  Keep: /api/users -> backend /api/users.
        local trailing_slash="/" strip_filter="s| # __STRIP_ONLY__||"
        if [[ "$NON_INTERACTIVE" != "1" && -z "$STRIP_PREFIX" ]]; then
            echo -e "${CYAN}Strip: ${SUBDIR_PATH}users → backend gets /users. Keep: backend gets ${SUBDIR_PATH}users.${NC}"
        fi
        if ! ask_yes_no "Strip $path_noslash prefix from requests to backend?" y "$STRIP_PREFIX"; then
            trailing_slash=""
            strip_filter="/__STRIP_ONLY__/d"   # X-Forwarded-Prefix only makes sense when stripping
        fi
        snippet_content=$(sed -e "$strip_filter" \
            -e "s|__PATH_NOSLASH__|$path_noslash|g" -e "s|__PATH__|$SUBDIR_PATH|g" -e "s|__PORT__|$PROXY_PORT|g" \
            -e "s|__TRAILING_SLASH__|$trailing_slash|g" "$NGINX_TEMPLATE_DIR/location_proxy.conf.template")
    else
        sub_docroot="${DOCROOT:-}"
        if ! prompt_value sub_docroot "Enter document root for this path"; then
            echo -e "${RED}❌ Document root is required.${NC}"
            return 1
        fi
        sub_docroot=$(realpath -m "$sub_docroot")
        if ! is_safe_path "$sub_docroot"; then
            echo -e "${RED}❌ Refusing to use $sub_docroot as document root.${NC}"
            return 1
        fi
        if [[ "$SUB_STACK" == "php" ]]; then
            snippet_content=$(sed -e "s|__PATH_NOSLASH__|$path_noslash|g" -e "s|__PATH__|$SUBDIR_PATH|g" \
                -e "s|__DOCROOT__|$(sed_escape "$sub_docroot")|g" \
                -e "s|__FASTCGI_PASS__|$(sed_escape "$(fastcgi_pass_target)")|g" "$NGINX_TEMPLATE_DIR/location_php.conf.template")
        else
            snippet_content=$(sed -e "s|__PATH_NOSLASH__|$path_noslash|g" -e "s|__PATH__|$SUBDIR_PATH|g" \
                -e "s|__DOCROOT__|$(sed_escape "$sub_docroot")|g" "$NGINX_TEMPLATE_DIR/location_static.conf.template")
        fi
    fi

    echo -e "${CYAN}Adding $SUBDIR_PATH ($SUB_STACK) to $DOMAIN...${NC}"
    confirm_action || return 1

    if [[ -n "$sub_docroot" ]]; then
        mkdir -p "$sub_docroot"
        local smart_owner sub_owner="${DOMAIN_OWNER:-}"
        smart_owner=$(get_smart_owner "$sub_docroot")
        prompt_value sub_owner "Enter owner" "$smart_owner"
        set_docroot_permissions "$sub_docroot" "$sub_owner"
        if [[ "$SUB_STACK" == "php" && ! -f "$sub_docroot/index.php" ]]; then
            cp "$NGINX_TEMPLATE_DIR/php_index.php" "$sub_docroot/index.php"
            chown "$sub_owner":"$WEB_GROUP" "$sub_docroot/index.php"
        elif [[ "$SUB_STACK" == "static" && ! -f "$sub_docroot/index.html" ]]; then
            cp "$NGINX_TEMPLATE_DIR/static_index.html" "$sub_docroot/index.html"
            chown "$sub_owner":"$WEB_GROUP" "$sub_docroot/index.html"
        fi
    fi

    local backup snippet_file
    backup="$config_path.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "$config_path" "$backup"
    snippet_file=$(mktemp)
    printf '\n%s\n' "$snippet_content" > "$snippet_file"

    if ! insert_location_snippet "$config_path" "$snippet_file"; then
        rm -f "$snippet_file" "$backup"
        echo -e "${RED}❌ Could not find a server block in $config_path.${NC}"
        return 1
    fi
    rm -f "$snippet_file"

    if nginx_test_and_reload "mv -f '$backup' '$config_path'"; then
        rm -f "$backup"
        echo -e "${GREEN}✅ Subdirectory $SUBDIR_PATH added to $DOMAIN.${NC}"
        log "Subdirectory $SUBDIR_PATH ($SUB_STACK) added to $DOMAIN"
    else
        echo -e "${RED}❌ Nginx config test failed. The change was rolled back.${NC}"
        return 1
    fi
}
