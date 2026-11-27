#!/bin/bash

# Pick a Docker app template. Uses $DOCKER_APP if already set (e.g. --docker-app).
select_docker_app() {
    local apps=() dir
    for dir in "$DOCKER_TEMPLATE_DIR"/*/; do
        [ -f "$dir/docker-compose.yml" ] && apps+=("$(basename "$dir")")
    done

    if [ "${#apps[@]}" -eq 0 ]; then
        echo -e "${RED}❌ No Docker app templates found in $DOCKER_TEMPLATE_DIR${NC}"
        return 1
    fi

    if [[ -n "$DOCKER_APP" ]]; then
        if [[ " ${apps[*]} " != *" $DOCKER_APP "* ]]; then
            echo -e "${RED}❌ Unknown Docker app: $DOCKER_APP (available: ${apps[*]})${NC}"
            return 1
        fi
        return 0
    fi
    if [[ "$NON_INTERACTIVE" == "1" ]]; then
        echo -e "${RED}❌ --docker-app is required in non-interactive mode (available: ${apps[*]})${NC}"
        return 1
    fi

    echo -e "${CYAN}Available Docker Apps:${NC}"
    local i
    for i in "${!apps[@]}"; do
        echo "$((i + 1))) ${apps[$i]}"
    done
    local choice
    read -rp "Choose Docker app [1-${#apps[@]}]: " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#apps[@]}" ]; then
        echo -e "${YELLOW}Invalid choice. Aborting.${NC}"
        return 1
    fi
    DOCKER_APP="${apps[$((choice - 1))]}"
}

# Deploy $DOCKER_APP into target directory $1 and start it. Sets STACK_PORT.
deploy_docker_app() {
    local target="$1"
    local template_dir="$DOCKER_TEMPLATE_DIR/$DOCKER_APP"

    prompt_value DOCKER_PORT "Enter app exposed port" "$DEFAULT_DOCKER_PORT"
    if ! validate_port "$DOCKER_PORT"; then
        echo -e "${RED}❌ Invalid port: $DOCKER_PORT${NC}"
        return 1
    fi
    STACK_PORT="$DOCKER_PORT"

    mkdir -p "$target"
    sed "s|__PORT__|$DOCKER_PORT|g" "$template_dir/docker-compose.yml" > "$target/docker-compose.yml"

    # Handle .env.example → .env
    if [ -f "$template_dir/.env.example" ]; then
        if [ -f "$target/.env" ]; then
            if ask_yes_no ".env already exists in $target. Overwrite with .env.example?" n; then
                cp "$template_dir/.env.example" "$target/.env"
                echo -e "${GREEN}✅ .env updated from .env.example${NC}"
            else
                echo -e "${YELLOW}⚠️ Skipped overwriting .env${NC}"
            fi
        else
            cp "$template_dir/.env.example" "$target/.env"
            echo -e "${GREEN}✅ .env created from .env.example${NC}"
        fi
    fi

    chown -R "${DOMAIN_OWNER:-$WEB_USER}":"$WEB_GROUP" "$target"

    echo -e "${CYAN}Starting Docker app ($DOCKER_APP) in $target...${NC}"
    if (cd "$target" && docker compose up -d); then
        log "Docker app $DOCKER_APP started in $target on port $DOCKER_PORT"
    else
        echo -e "${RED}❌ docker compose up failed in $target${NC}"
        return 1
    fi
}

setup_docker_app_standalone() {
    select_docker_app || return 1

    prompt_value DOCROOT "Enter install directory" "$DEFAULT_DOCROOT_BASE/$DOCKER_APP"
    DOCROOT=$(realpath -m "$DOCROOT")
    if ! is_safe_path "$DOCROOT"; then
        echo -e "${RED}❌ Refusing to use $DOCROOT (system or top-level directory).${NC}"
        return 1
    fi
    if [ -f "$DOCROOT/docker-compose.yml" ] && ! ask_yes_no "$DOCROOT/docker-compose.yml exists. Overwrite?" n; then
        echo -e "${YELLOW}Aborted.${NC}"
        return 1
    fi

    deploy_docker_app "$DOCROOT"
}

check_docker_container_status() {
    local dir="${DOCROOT:-}"
    if [[ -z "$dir" ]]; then
        if ! prompt_value DOMAIN "Enter domain or app name"; then
            echo -e "${RED}❌ Domain or app name is required.${NC}"
            return 1
        fi
        if [[ ! "$DOMAIN" =~ ^[A-Za-z0-9._-]+$ ]]; then
            echo -e "${RED}❌ Invalid name: $DOMAIN${NC}"
            return 1
        fi
        dir="$DEFAULT_DOCROOT_BASE/$DOMAIN"
    fi

    if [ ! -f "$dir/docker-compose.yml" ]; then
        echo -e "${YELLOW}No docker-compose.yml found in $dir${NC}"
        return 1
    fi

    echo -e "${CYAN}Showing Docker container status for $dir...${NC}"
    (cd "$dir" && docker compose ps)
}

container_exists() {
    docker ps -a --format '{{.Names}}' | grep -qxF -- "$1"
}

restart_docker_app() {
    if ! prompt_value CONTAINER_NAME "Enter container name to restart"; then
        echo -e "${RED}❌ Container name is required.${NC}"
        return 1
    fi
    if container_exists "$CONTAINER_NAME"; then
        echo -e "${CYAN}Restarting container: $CONTAINER_NAME...${NC}"
        docker restart "$CONTAINER_NAME" && echo -e "${GREEN}✅ Container restarted.${NC}"
    else
        echo -e "${RED}❌ No container found with name $CONTAINER_NAME.${NC}"
        return 1
    fi
}

remove_docker_app() {
    if ! prompt_value CONTAINER_NAME "Enter container name to remove"; then
        echo -e "${RED}❌ Container name is required.${NC}"
        return 1
    fi
    if ! container_exists "$CONTAINER_NAME"; then
        echo -e "${RED}❌ No container found with name $CONTAINER_NAME.${NC}"
        return 1
    fi

    local remove_all=0
    ask_yes_no "Also remove its image and volumes?" n && remove_all=1
    echo -e "${RED}Container $CONTAINER_NAME will be stopped and removed.${NC}"
    confirm_action || return 1

    # Collect image and volumes before the container is gone
    local image_id volumes=()
    image_id=$(docker inspect -f '{{.Image}}' "$CONTAINER_NAME" 2>/dev/null)
    mapfile -t volumes < <(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{"\n"}}{{end}}{{end}}' "$CONTAINER_NAME" 2>/dev/null | sed '/^$/d')

    echo -e "${CYAN}Stopping and removing container: $CONTAINER_NAME...${NC}"
    docker stop "$CONTAINER_NAME" >/dev/null
    docker rm "$CONTAINER_NAME" >/dev/null

    if [[ "$remove_all" == "1" ]]; then
        [[ -n "$image_id" ]] && docker rmi "$image_id"
        [[ "${#volumes[@]}" -gt 0 ]] && docker volume rm "${volumes[@]}"
    fi
    echo -e "${GREEN}✅ Container $CONTAINER_NAME removed.${NC}"
    log "Docker container $CONTAINER_NAME removed (image/volumes: $remove_all)"
}

show_docker_menu() {
    echo -e "${CYAN}--- Docker Setup ---${NC}"
    echo "1) Check Docker container status"
    echo "2) Setup Dockerized App"
    echo "3) Restart Dockerized App"
    echo "4) Remove Dockerized App"
    read -rp "Choose Docker task [1-4]: " DOCKER_OPTION
    case $DOCKER_OPTION in
        1) check_docker_container_status ;;
        2) setup_docker_app_standalone ;;
        3) restart_docker_app ;;
        4) remove_docker_app ;;
        *) echo -e "${YELLOW}Invalid option.${NC}" ;;
    esac
}
