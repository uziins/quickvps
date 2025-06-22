check_docker_container_status() {
    read -rp "Enter domain name to check Docker status: " DOMAIN
    COMPOSE_FILE="/var/www/$DOMAIN/docker-compose.yml"

    if [ ! -f "$COMPOSE_FILE" ]; then
        echo -e "${YELLOW}No docker-compose.yml found for $DOMAIN${NC}"
        return
    fi

    echo -e "${CYAN}Showing Docker container status for $DOMAIN...${NC}"
    (cd "/var/www/$DOMAIN" && docker compose ps)
}

setup_docker_app_standalone() {
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
    TEMPLATE_PATH="$DOCKER_TEMPLATE_DIR/$DOCKER_APP/docker-compose.yml"

    read -rp "Enter app exposed port (default $DEFAULT_DOCKER_PORT): " DOCKER_PORT
    DOCKER_PORT=${DOCKER_PORT:-$DEFAULT_DOCKER_PORT}

    cp "$TEMPLATE_PATH" "$DOCROOT/docker-compose.yml"
    chown -R www-data:www-data "$DOCROOT"

    echo -e "${CYAN}Starting Docker app ($DOCKER_APP) using docker-compose...${NC}"
    (cd "$DOCROOT" && docker compose up -d)
}

restart_docker_app() {
    read -rp "Enter container name to restart: " CONTAINER_NAME
    if docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
        echo -e "${CYAN}Restarting container: $CONTAINER_NAME...${NC}"
        docker restart "$CONTAINER_NAME"
        echo -e "${GREEN}✅ Container restarted.${NC}"
    else
        echo -e "${RED}❌ No container found with name $CONTAINER_NAME.${NC}"
    fi
}

remove_docker_app() {
    read -rp "Enter container name to remove: " CONTAINER_NAME
    if docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
        read -rp "Also remove image and volume (if any)? [y/N]: " REMOVE_ALL
        echo -e "${CYAN}Stopping and removing container: $CONTAINER_NAME...${NC}"
        docker stop "$CONTAINER_NAME"
        docker rm "$CONTAINER_NAME"
        if [[ "$REMOVE_ALL" =~ ^[Yy]$ ]]; then
            IMAGE_ID=$(docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep "$CONTAINER_NAME" | awk '{print $2}')
            if [ -n "$IMAGE_ID" ]; then
                docker rmi "$IMAGE_ID"
            fi
            docker volume rm $(docker volume ls -qf "name=$CONTAINER_NAME") 2>/dev/null
        fi
        echo -e "${GREEN}✅ Container $CONTAINER_NAME removed.${NC}"
    else
        echo -e "${RED}❌ No container found with name $CONTAINER_NAME.${NC}"
    fi
}

show_docker_menu() {
    echo -e "${CYAN}--- Docker Setup ---${NC}"
    echo "1) Check Docker container status"
    echo "2) Setup Dockerized App"
    echo "3) Restart Dockerized App"
    echo "4) Remove Dockerized App"
    read -rp "Choose Docker task [1-2]: " DOCKER_OPTION
    case $DOCKER_OPTION in
        1) check_docker_container_status ;;
        2) setup_docker_app_standalone ;;
        3) restart_docker_app ;;
        4) remove_docker_app ;;
        *) echo -e "${YELLOW}Invalid option.${NC}" ;;
    esac
}