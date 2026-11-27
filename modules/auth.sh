#!/bin/bash

# HTTP Basic Auth Module
# Protects a whole domain or one location path with nginx auth_basic.
# Users are stored per domain in $AUTH_DIR/<domain> (SHA-512 crypt hashes).

AUTH_DIR="${AUTH_DIR:-/etc/nginx/htpasswd}"

htpasswd_file() {
    echo "$AUTH_DIR/$1"
}

valid_auth_user() {
    [[ "$1" =~ ^[A-Za-z0-9._@-]{1,64}$ ]]
}

# Read the password for a new/updated user into the variable named $1.
# --pass-stdin reads one line from stdin; non-interactive mode generates one;
# otherwise the user is prompted (empty input generates one).
read_auth_password() {
    local __var="$1" __pass="" __confirm=""
    if [[ "$PASS_STDIN" == "1" ]]; then
        IFS= read -r __pass
    elif [[ "$NON_INTERACTIVE" != "1" ]]; then
        read -rsp "Enter password (leave blank to generate): " __pass
        echo
        if [[ -n "$__pass" ]]; then
            read -rsp "Confirm password: " __confirm
            echo
            if [[ "$__pass" != "$__confirm" ]]; then
                echo -e "${RED}❌ Passwords do not match${NC}"
                return 1
            fi
        fi
    fi
    if [[ -z "$__pass" ]]; then
        __pass=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-20)
        echo -e "${GREEN}Generated password: $__pass${NC}"
    fi
    printf -v "$__var" '%s' "$__pass"
}

# Add or update user $2 in the htpasswd file of domain $1
auth_set_user() {
    local domain="$1" user="$2" file pass hash tmp
    file=$(htpasswd_file "$domain")

    if ! command -v openssl &>/dev/null; then
        echo -e "${RED}❌ openssl is required to hash passwords.${NC}"
        return 1
    fi
    read_auth_password pass || return 1
    # Password goes through stdin, never the command line
    hash=$(printf '%s\n' "$pass" | openssl passwd -6 -stdin) || return 1

    install -d -m 750 -o root -g "$WEB_GROUP" "$AUTH_DIR"
    tmp=$(mktemp "$AUTH_DIR/.${domain}.XXXXXX") || return 1
    if [ -f "$file" ]; then
        awk -F: -v u="$user" '$1 != u' "$file" > "$tmp"
    fi
    printf '%s:%s\n' "$user" "$hash" >> "$tmp"
    chmod 640 "$tmp"
    chown root:"$WEB_GROUP" "$tmp"
    mv -f "$tmp" "$file"
}

auth_user_count() {
    local file
    file=$(htpasswd_file "$1")
    if [ -f "$file" ]; then
        grep -c ':' "$file" || true
    else
        echo 0
    fi
}

auth_user_exists() {
    local file
    file=$(htpasswd_file "$1")
    [ -f "$file" ] && awk -F: -v u="$2" '$1 == u { found = 1 } END { exit !found }' "$file"
}

# Resolve DOMAIN to its config path (into variable $1), prompting if needed
auth_resolve_domain() {
    if ! prompt_value DOMAIN "Enter domain name"; then
        echo -e "${RED}❌ Domain name is required.${NC}"
        return 1
    fi
    resolve_domain_config "$1" "$DOMAIN"
}

# Marker tag for a scope: "server" for the whole domain, otherwise the path
auth_scope_tag() {
    if [[ -n "$SUBDIR_PATH" ]]; then echo "$SUBDIR_PATH"; else echo "server"; fi
}

auth_scope_enabled() {
    grep -qxF "$(auth_marker_line begin "$2")" <(sed 's/^[[:space:]]*//' "$1")
}

auth_marker_line() {
    echo "# quickvps-auth-$1 $2"
}

auth_add_user() {
    local config_path
    auth_resolve_domain config_path || return 1
    if ! prompt_value USERNAME "Enter username"; then
        echo -e "${RED}❌ Username is required.${NC}"
        return 1
    fi
    if ! valid_auth_user "$USERNAME"; then
        echo -e "${RED}❌ Invalid username (letters, digits, . _ @ -; max 64).${NC}"
        return 1
    fi
    local action="added"
    auth_user_exists "$DOMAIN" "$USERNAME" && action="updated"
    auth_set_user "$DOMAIN" "$USERNAME" || return 1
    echo -e "${GREEN}✅ User '$USERNAME' $action for $DOMAIN.${NC}"
    log "HTTP auth user $USERNAME $action for $DOMAIN"
    if ! grep -q "quickvps-auth-begin" "$config_path"; then
        echo -e "${YELLOW}ℹ️  Auth is not enabled on $DOMAIN yet. Run: quickvps auth enable --domain $DOMAIN${NC}"
    fi
}

auth_delete_user() {
    local config_path file
    auth_resolve_domain config_path || return 1
    file=$(htpasswd_file "$DOMAIN")
    if ! prompt_value USERNAME "Enter username to delete"; then
        echo -e "${RED}❌ Username is required.${NC}"
        return 1
    fi
    if ! auth_user_exists "$DOMAIN" "$USERNAME"; then
        echo -e "${RED}❌ User '$USERNAME' not found for $DOMAIN.${NC}"
        return 1
    fi
    if [[ "$(auth_user_count "$DOMAIN")" -le 1 ]] && grep -q "quickvps-auth-begin" "$config_path"; then
        echo -e "${YELLOW}⚠️ This is the last user. Nobody will be able to log in until a user is added or auth is disabled.${NC}"
    fi
    confirm_action || return 1

    local tmp
    tmp=$(mktemp "$AUTH_DIR/.${DOMAIN}.XXXXXX") || return 1
    awk -F: -v u="$USERNAME" '$1 != u' "$file" > "$tmp"
    chmod 640 "$tmp"
    chown root:"$WEB_GROUP" "$tmp"
    mv -f "$tmp" "$file"
    echo -e "${GREEN}✅ User '$USERNAME' removed from $DOMAIN.${NC}"
    log "HTTP auth user $USERNAME removed from $DOMAIN"
}

auth_enable() {
    local config_path
    auth_resolve_domain config_path || return 1
    if [[ -n "$SUBDIR_PATH" ]]; then
        normalize_location_path SUBDIR_PATH || return 1
    fi
    local tag
    tag=$(auth_scope_tag)

    if auth_scope_enabled "$config_path" "$tag"; then
        echo -e "${YELLOW}HTTP auth is already enabled for $DOMAIN ${SUBDIR_PATH:-(whole domain)}.${NC}"
        return 0
    fi

    # Basic auth sends credentials base64-encoded: only acceptable over HTTPS
    if ! grep -qE '^[[:space:]]*listen[[:space:]].*443' "$config_path"; then
        echo -e "${RED}⚠️ $DOMAIN has no HTTPS server block. Basic auth over plain HTTP exposes passwords.${NC}"
        if [[ "$FORCE" != "1" ]] && ! ask_yes_no "Enable anyway?" n; then
            echo -e "${YELLOW}Aborted. Enable SSL first, or pass --force.${NC}"
            return 1
        fi
    fi

    # Find where to insert: after the opening line of the location or server block
    local insert_after indent
    if [[ -n "$SUBDIR_PATH" ]]; then
        local path_re="${SUBDIR_PATH//./\\.}"
        insert_after=$(grep -nE "^[[:space:]]*location[[:space:]]+(\^~[[:space:]]+)?$path_re[[:space:]]*\{[[:space:]]*$" "$config_path" | head -n 1 | cut -d: -f1)
        if [[ -z "$insert_after" ]]; then
            echo -e "${RED}❌ No 'location $SUBDIR_PATH' block in $config_path.${NC}"
            echo -e "${YELLOW}Add it first with: quickvps domain add-subdir --domain $DOMAIN --path $SUBDIR_PATH${NC}"
            return 1
        fi
        indent="        "
    else
        if ! insert_after=$(find_target_server_block "$config_path"); then
            echo -e "${RED}❌ Could not find a server block in $config_path.${NC}"
            return 1
        fi
        indent="    "
    fi

    # Make sure somebody can log in
    if [[ "$(auth_user_count "$DOMAIN")" -eq 0 ]]; then
        echo -e "${CYAN}No users yet for $DOMAIN. Creating the first one.${NC}"
        if ! prompt_value USERNAME "Enter username"; then
            echo -e "${RED}❌ A username is required (--user) before enabling auth.${NC}"
            return 1
        fi
        if ! valid_auth_user "$USERNAME"; then
            echo -e "${RED}❌ Invalid username (letters, digits, . _ @ -; max 64).${NC}"
            return 1
        fi
        echo -e "${CYAN}Enabling HTTP auth for $DOMAIN ${SUBDIR_PATH:-(whole domain)} with user '$USERNAME'.${NC}"
        confirm_action || return 1
        auth_set_user "$DOMAIN" "$USERNAME" || return 1
    else
        echo -e "${CYAN}Enabling HTTP auth for $DOMAIN ${SUBDIR_PATH:-(whole domain)} ($(auth_user_count "$DOMAIN") user(s)).${NC}"
        confirm_action || return 1
    fi

    local snippet_file backup
    snippet_file=$(mktemp)
    {
        echo "$indent$(auth_marker_line begin "$tag")"
        echo "${indent}auth_basic \"Restricted\";"
        echo "${indent}auth_basic_user_file $(htpasswd_file "$DOMAIN");"
        if [[ "$tag" == "server" ]]; then
            # Keep Let's Encrypt HTTP-01 challenges reachable (webroot renewals)
            echo "${indent}location ^~ /.well-known/acme-challenge/ {"
            echo "${indent}    auth_basic off;"
            echo "${indent}}"
        fi
        echo "$indent$(auth_marker_line end "$tag")"
    } > "$snippet_file"

    backup="$config_path.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "$config_path" "$backup"
    local tmp
    tmp=$(mktemp)
    awk -v n="$insert_after" -v f="$snippet_file" '
        { print }
        NR == n { while ((getline l < f) > 0) print l }
    ' "$config_path" > "$tmp" && cat "$tmp" > "$config_path"
    rm -f "$tmp" "$snippet_file"

    if nginx_test_and_reload "mv -f $(printf '%q' "$backup") $(printf '%q' "$config_path")"; then
        rm -f "$backup"
        echo -e "${GREEN}✅ HTTP auth enabled for $DOMAIN ${SUBDIR_PATH:-(whole domain)}.${NC}"
        log "HTTP auth enabled for $DOMAIN scope $tag"
    else
        echo -e "${RED}❌ Nginx config test failed. The change was rolled back.${NC}"
        return 1
    fi
}

auth_disable() {
    local config_path
    auth_resolve_domain config_path || return 1
    if [[ -n "$SUBDIR_PATH" ]]; then
        normalize_location_path SUBDIR_PATH || return 1
    fi
    local tag
    tag=$(auth_scope_tag)

    if ! auth_scope_enabled "$config_path" "$tag"; then
        echo -e "${YELLOW}HTTP auth is not enabled for $DOMAIN ${SUBDIR_PATH:-(whole domain)}.${NC}"
        return 0
    fi
    echo -e "${CYAN}Disabling HTTP auth for $DOMAIN ${SUBDIR_PATH:-(whole domain)}.${NC}"
    confirm_action || return 1

    local backup tmp
    backup="$config_path.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "$config_path" "$backup"
    tmp=$(mktemp)
    BEGIN_MARK="$(auth_marker_line begin "$tag")" END_MARK="$(auth_marker_line end "$tag")" awk '
        { t = $0; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t) }
        t == ENVIRON["BEGIN_MARK"] { skip = 1; next }
        skip && t == ENVIRON["END_MARK"] { skip = 0; next }
        !skip { print }
    ' "$config_path" > "$tmp" && cat "$tmp" > "$config_path"
    rm -f "$tmp"

    if nginx_test_and_reload "mv -f $(printf '%q' "$backup") $(printf '%q' "$config_path")"; then
        rm -f "$backup"
        echo -e "${GREEN}✅ HTTP auth disabled for $DOMAIN ${SUBDIR_PATH:-(whole domain)}.${NC}"
        if ! grep -q "quickvps-auth-begin" "$config_path"; then
            echo -e "${YELLOW}ℹ️  Users are kept in $(htpasswd_file "$DOMAIN") for re-enabling.${NC}"
        fi
        log "HTTP auth disabled for $DOMAIN scope $tag"
    else
        echo -e "${RED}❌ Nginx config test failed. The change was rolled back.${NC}"
        return 1
    fi
}

auth_status() {
    local config_path file
    auth_resolve_domain config_path || return 1
    file=$(htpasswd_file "$DOMAIN")

    echo -e "${CYAN}HTTP auth for $DOMAIN ($config_path):${NC}"
    local scopes
    scopes=$(sed -n 's/^[[:space:]]*# quickvps-auth-begin //p' "$config_path")
    if [[ -n "$scopes" ]]; then
        echo "  Protected:"
        echo "$scopes" | sed -e 's/^server$/whole domain/' -e 's/^/    /'
    else
        echo "  Protected: nothing"
    fi
    if grep -qE '^[[:space:]]*auth_basic[[:space:]]' <(grep -v 'quickvps-auth' "$config_path") && [[ -z "$scopes" ]]; then
        echo -e "  ${YELLOW}Note: the config contains auth_basic directives not managed by QuickVPS.${NC}"
    fi
    echo "  Users ($file):"
    if [ -s "$file" ]; then
        cut -d: -f1 "$file" | sed 's/^/    /'
    else
        echo "    none"
    fi
}

show_auth_menu() {
    echo -e "${CYAN}--- HTTP Basic Auth ---${NC}"
    echo "1) Enable auth (whole domain or path)"
    echo "2) Disable auth"
    echo "3) Add / update user"
    echo "4) Delete user"
    echo "5) Show status"
    read -rp "Choose auth task [1-5]: " AUTH_OPTION
    case $AUTH_OPTION in
        1|2)
            if [[ -z "$SUBDIR_PATH" ]]; then
                read -rp "Path to protect (leave blank for whole domain, e.g. /admin/): " SUBDIR_PATH
            fi
            if [[ "$AUTH_OPTION" == "1" ]]; then auth_enable; else auth_disable; fi
            ;;
        3) auth_add_user ;;
        4) auth_delete_user ;;
        5) auth_status ;;
        *) echo -e "${YELLOW}Invalid option.${NC}" ;;
    esac
}
