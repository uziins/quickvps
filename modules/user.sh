#!/bin/bash

create_user() {
    if [[ -z "$USERNAME" ]]; then
        read -rp "Enter new username: " USERNAME
    fi
    if id "$USERNAME" &>/dev/null; then
        echo -e "${YELLOW}User '$USERNAME' already exists.${NC}"
    else
        echo -e "${CYAN}Creating user '$USERNAME'...${NC}"
        if confirm_action; then
            if command -v adduser &>/dev/null && [[ "$OS_FAMILY" == "debian" ]]; then
                adduser "$USERNAME"
            else
                useradd -m -s /bin/bash "$USERNAME"
                passwd "$USERNAME"
            fi
            echo -e "${GREEN}✅ User '$USERNAME' created.${NC}"
        fi
    fi
}

add_user_to_sudo() {
    if [[ -z "$USERNAME" ]]; then
        read -rp "Enter username to add to sudo group: " USERNAME
    fi
    if id "$USERNAME" &>/dev/null; then
        echo -e "${CYAN}Adding '$USERNAME' to sudo group...${NC}"
        if confirm_action; then
            if [[ "$OS_FAMILY" == "debian" ]]; then
                usermod -aG sudo "$USERNAME"
            else
                usermod -aG wheel "$USERNAME"
            fi
            echo -e "${GREEN}✅ User '$USERNAME' added to sudo group.${NC}"
        fi
    else
        echo -e "${RED}User '$USERNAME' does not exist.${NC}"
    fi
}

show_user_menu() {
    echo -e "${CYAN}--- User Setup ---${NC}"
    echo "1) Create a new user"
    echo "2) Add user to sudo group"
    read -rp "Choose user task [1-2]: " USER_OPTION
    case $USER_OPTION in
        1) create_user ;;
        2) add_user_to_sudo ;;
        *) echo -e "${YELLOW}Invalid option.${NC}" ;;
    esac
}
