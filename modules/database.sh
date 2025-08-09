#!/bin/bash

# Database Management Module for QuickVPS
# Supports MySQL/MariaDB installation, configuration, and management

install_mysql() {
    echo -e "${CYAN}Installing MySQL/MariaDB...${NC}"

    # Check if MySQL/MariaDB is already installed
    if command -v mysql &>/dev/null || command -v mariadb &>/dev/null; then
        echo -e "${YELLOW}MySQL/MariaDB is already installed${NC}"
        return
    fi

    echo -e "${CYAN}Select database engine:${NC}"
    echo "1) MySQL 8.0"
    echo "2) MariaDB (Recommended)"
    read -rp "Choose database engine [1-2]: " DB_ENGINE

    case $DB_ENGINE in
        1)
            echo -e "${CYAN}Installing MySQL 8.0...${NC}"
            apt update
            apt install -y mysql-server mysql-client
            systemctl start mysql
            systemctl enable mysql
            DB_TYPE="mysql"
            ;;
        2)
            echo -e "${CYAN}Installing MariaDB...${NC}"
            apt update
            apt install -y mariadb-server mariadb-client
            systemctl start mariadb
            systemctl enable mariadb
            DB_TYPE="mariadb"
            ;;
        *)
            echo -e "${YELLOW}Invalid option. Installing MariaDB as default...${NC}"
            apt update
            apt install -y mariadb-server mariadb-client
            systemctl start mariadb
            systemctl enable mariadb
            DB_TYPE="mariadb"
            ;;
    esac

    echo -e "${GREEN}✅ $DB_TYPE installed successfully${NC}"

    # Secure installation
    read -rp "Run secure installation? [Y/n]: " SECURE_INSTALL
    if [[ ! "$SECURE_INSTALL" =~ ^[Nn]$ ]]; then
        echo -e "${CYAN}Running secure installation...${NC}"
        if [[ "$DB_TYPE" == "mysql" ]]; then
            mysql_secure_installation
        else
            mariadb-secure-installation
        fi
    fi

    log "Database engine $DB_TYPE installed and configured"
}

create_database() {
    echo -e "${CYAN}Creating new database...${NC}"

    # Check if MySQL/MariaDB is installed
    if ! command -v mysql &>/dev/null && ! command -v mariadb &>/dev/null; then
        echo -e "${RED}❌ MySQL/MariaDB is not installed. Please install it first.${NC}"
        return 1
    fi

    read -rp "Enter database name: " DB_NAME
    if [[ ! "$DB_NAME" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "${RED}❌ Invalid database name. Use only letters, numbers, and underscores.${NC}"
        return 1
    fi

    read -rp "Enter database username: " DB_USER
    if [[ ! "$DB_USER" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "${RED}❌ Invalid username. Use only letters, numbers, and underscores.${NC}"
        return 1
    fi

    # Generate or ask for password
    echo -e "${CYAN}Password options:${NC}"
    echo "1) Generate random password"
    echo "2) Enter custom password"
    read -rp "Choose password option [1-2]: " PASS_OPTION

    case $PASS_OPTION in
        1)
            DB_PASS=$(openssl rand -base64 16)
            echo -e "${GREEN}Generated password: $DB_PASS${NC}"
            ;;
        2)
            read -rsp "Enter password: " DB_PASS
            echo
            read -rsp "Confirm password: " DB_PASS_CONFIRM
            echo
            if [[ "$DB_PASS" != "$DB_PASS_CONFIRM" ]]; then
                echo -e "${RED}❌ Passwords do not match${NC}"
                return 1
            fi
            ;;
        *)
            echo -e "${RED}❌ Invalid option${NC}"
            return 1
            ;;
    esac

    # Get root password
    read -rsp "Enter MySQL/MariaDB root password: " ROOT_PASS
    echo

    # Create database and user
    mysql -u root -p"$ROOT_PASS" -e "
        CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
        GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
        FLUSH PRIVILEGES;
    " 2>/dev/null

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ Database created successfully${NC}"
        echo -e "${CYAN}Database details:${NC}"
        echo "  Database: $DB_NAME"
        echo "  Username: $DB_USER"
        echo "  Password: $DB_PASS"
        echo "  Host: localhost"

        # Save to file
        DB_INFO_FILE="/root/db_credentials_$DB_NAME.txt"
        cat > "$DB_INFO_FILE" << EOF
Database Credentials for $DB_NAME
================================
Database: $DB_NAME
Username: $DB_USER
Password: $DB_PASS
Host: localhost
Port: 3306

Connection String Examples:
MySQL CLI: mysql -u $DB_USER -p'$DB_PASS' $DB_NAME
Laravel .env:
  DB_CONNECTION=mysql
  DB_HOST=127.0.0.1
  DB_PORT=3306
  DB_DATABASE=$DB_NAME
  DB_USERNAME=$DB_USER
  DB_PASSWORD=$DB_PASS

Created: $(date)
EOF
        echo -e "${GREEN}✅ Credentials saved to: $DB_INFO_FILE${NC}"
        log "Database $DB_NAME created for user $DB_USER"
    else
        echo -e "${RED}❌ Failed to create database. Please check root password and try again.${NC}"
        return 1
    fi
}

list_databases() {
    echo -e "${CYAN}Listing databases...${NC}"

    read -rsp "Enter MySQL/MariaDB root password: " ROOT_PASS
    echo

    echo -e "${CYAN}Databases:${NC}"
    mysql -u root -p"$ROOT_PASS" -e "SHOW DATABASES;" 2>/dev/null | grep -v "information_schema\|performance_schema\|mysql\|sys\|Database"

    echo -e "\n${CYAN}Users:${NC}"
    mysql -u root -p"$ROOT_PASS" -e "SELECT User, Host FROM mysql.user WHERE User != 'root' AND User != 'debian-sys-maint' AND User != 'mysql.session' AND User != 'mysql.sys';" 2>/dev/null
}

delete_database() {
    echo -e "${CYAN}Deleting database...${NC}"
    echo -e "${RED}⚠️  WARNING: This action cannot be undone!${NC}"

    read -rp "Enter database name to delete: " DB_NAME
    if [[ -z "$DB_NAME" ]]; then
        echo -e "${RED}❌ Database name cannot be empty${NC}"
        return 1
    fi

    read -rp "Enter database username to delete: " DB_USER

    read -rp "Are you sure you want to delete database '$DB_NAME' and user '$DB_USER'? [y/N]: " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Operation cancelled${NC}"
        return
    fi

    read -rsp "Enter MySQL/MariaDB root password: " ROOT_PASS
    echo

    # Delete database and user
    mysql -u root -p"$ROOT_PASS" -e "
        DROP DATABASE IF EXISTS \`$DB_NAME\`;
        DROP USER IF EXISTS '$DB_USER'@'localhost';
        FLUSH PRIVILEGES;
    " 2>/dev/null

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ Database '$DB_NAME' and user '$DB_USER' deleted successfully${NC}"

        # Remove credentials file if exists
        DB_INFO_FILE="/root/db_credentials_$DB_NAME.txt"
        if [[ -f "$DB_INFO_FILE" ]]; then
            rm "$DB_INFO_FILE"
            echo -e "${GREEN}✅ Credentials file removed${NC}"
        fi

        log "Database $DB_NAME and user $DB_USER deleted"
    else
        echo -e "${RED}❌ Failed to delete database. Please check root password and database name.${NC}"
        return 1
    fi
}

backup_database() {
    echo -e "${CYAN}Creating database backup...${NC}"

    read -rp "Enter database name to backup: " DB_NAME
    if [[ -z "$DB_NAME" ]]; then
        echo -e "${RED}❌ Database name cannot be empty${NC}"
        return 1
    fi

    read -rp "Enter database username: " DB_USER
    read -rsp "Enter database password: " DB_PASS
    echo

    # Create backup directory
    BACKUP_DIR="/root/db_backups"
    mkdir -p "$BACKUP_DIR"

    # Generate backup filename with timestamp
    BACKUP_FILE="$BACKUP_DIR/${DB_NAME}_$(date +%Y%m%d_%H%M%S).sql"

    echo -e "${CYAN}Creating backup...${NC}"
    mysqldump -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$BACKUP_FILE" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        # Compress backup
        gzip "$BACKUP_FILE"
        BACKUP_FILE="${BACKUP_FILE}.gz"

        echo -e "${GREEN}✅ Database backup created successfully${NC}"
        echo "  File: $BACKUP_FILE"
        echo "  Size: $(du -h "$BACKUP_FILE" | cut -f1)"

        log "Database $DB_NAME backed up to $BACKUP_FILE"
    else
        echo -e "${RED}❌ Failed to create backup. Please check credentials and database name.${NC}"
        return 1
    fi
}

restore_database() {
    echo -e "${CYAN}Restoring database from backup...${NC}"

    # List available backups
    BACKUP_DIR="/root/db_backups"
    if [[ -d "$BACKUP_DIR" ]] && [[ -n "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        echo -e "${CYAN}Available backups:${NC}"
        ls -la "$BACKUP_DIR"/*.sql.gz 2>/dev/null | awk '{print $9, $5, $6, $7, $8}' | sed 's|.*/||'
    else
        echo -e "${YELLOW}No backups found in $BACKUP_DIR${NC}"
    fi

    read -rp "Enter full path to backup file: " BACKUP_FILE
    if [[ ! -f "$BACKUP_FILE" ]]; then
        echo -e "${RED}❌ Backup file not found: $BACKUP_FILE${NC}"
        return 1
    fi

    read -rp "Enter target database name: " DB_NAME
    read -rp "Enter database username: " DB_USER
    read -rsp "Enter database password: " DB_PASS
    echo

    read -rp "This will overwrite existing data in '$DB_NAME'. Continue? [y/N]: " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Operation cancelled${NC}"
        return
    fi

    echo -e "${CYAN}Restoring database...${NC}"

    # Check if file is compressed
    if [[ "$BACKUP_FILE" == *.gz ]]; then
        zcat "$BACKUP_FILE" | mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" 2>/dev/null
    else
        mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$BACKUP_FILE" 2>/dev/null
    fi

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ Database restored successfully${NC}"
        log "Database $DB_NAME restored from $BACKUP_FILE"
    else
        echo -e "${RED}❌ Failed to restore database. Please check credentials and backup file.${NC}"
        return 1
    fi
}

optimize_database() {
    echo -e "${CYAN}Optimizing database performance...${NC}"

    read -rsp "Enter MySQL/MariaDB root password: " ROOT_PASS
    echo

    # Create optimized configuration
    CONFIG_FILE="/etc/mysql/conf.d/99-quickvps-optimization.cnf"

    # Get system memory
    TOTAL_MEM=$(free -m | awk 'NR==2{printf "%.0f", $2}')
    INNODB_BUFFER_POOL_SIZE=$((TOTAL_MEM * 70 / 100))  # 70% of total memory

    if [[ $INNODB_BUFFER_POOL_SIZE -lt 128 ]]; then
        INNODB_BUFFER_POOL_SIZE=128
    fi

    cat > "$CONFIG_FILE" << EOF
[mysqld]
# QuickVPS Database Optimization
# Generated on $(date)

# InnoDB Settings
innodb_buffer_pool_size = ${INNODB_BUFFER_POOL_SIZE}M
innodb_log_file_size = 256M
innodb_log_buffer_size = 16M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT

# Query Cache (for MariaDB < 10.10 or MySQL < 8.0)
query_cache_type = 1
query_cache_size = 64M
query_cache_limit = 2M

# Connection Settings
max_connections = 151
max_connect_errors = 1000000

# Buffer Settings
key_buffer_size = 32M
table_open_cache = 4000
table_definition_cache = 4000

# Slow Query Log
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 2

# Binary Log (for replication)
expire_logs_days = 7
max_binlog_size = 100M

# Security
local_infile = 0
EOF

    echo -e "${GREEN}✅ Optimization configuration created: $CONFIG_FILE${NC}"

    # Restart MySQL/MariaDB
    read -rp "Restart MySQL/MariaDB to apply optimizations? [Y/n]: " RESTART
    if [[ ! "$RESTART" =~ ^[Nn]$ ]]; then
        if systemctl restart mysql 2>/dev/null || systemctl restart mariadb 2>/dev/null; then
            echo -e "${GREEN}✅ Database service restarted successfully${NC}"
        else
            echo -e "${RED}❌ Failed to restart database service${NC}"
            return 1
        fi
    fi

    log "Database optimized with configuration in $CONFIG_FILE"
}

show_database_status() {
    echo -e "${CYAN}Database Status${NC}"
    echo "=============="

    # Service status
    if systemctl is-active mysql &>/dev/null; then
        echo -e "MySQL Service: ${GREEN}Running${NC}"
        DB_SERVICE="mysql"
    elif systemctl is-active mariadb &>/dev/null; then
        echo -e "MariaDB Service: ${GREEN}Running${NC}"
        DB_SERVICE="mariadb"
    else
        echo -e "Database Service: ${RED}Not Running${NC}"
        return 1
    fi

    # Version info
    if command -v mysql &>/dev/null; then
        echo "Version: $(mysql --version)"
    fi

    # Process info
    echo "Processes: $(pgrep -c mysqld || pgrep -c mariadbd)"

    # Port status
    if ss -tlnp | grep -q ":3306"; then
        echo -e "Port 3306: ${GREEN}Listening${NC}"
    else
        echo -e "Port 3306: ${RED}Not Listening${NC}"
    fi

    # Memory usage
    if pgrep mysqld &>/dev/null || pgrep mariadbd &>/dev/null; then
        MEMORY_USAGE=$(ps aux | grep -E "(mysqld|mariadbd)" | grep -v grep | awk '{sum+=$6} END {printf "%.0f", sum/1024}')
        echo "Memory Usage: ${MEMORY_USAGE}MB"
    fi

    # Configuration files
    echo "Configuration:"
    echo "  Main config: /etc/mysql/my.cnf"
    if [[ -f "/etc/mysql/conf.d/99-quickvps-optimization.cnf" ]]; then
        echo -e "  Optimization: ${GREEN}Applied${NC}"
    else
        echo -e "  Optimization: ${YELLOW}Not Applied${NC}"
    fi

    # Log files
    echo "Log Files:"
    echo "  Error Log: /var/log/mysql/error.log"
    echo "  Slow Query Log: /var/log/mysql/slow.log"
}

show_database_menu() {
    echo -e "${CYAN}--- Database Management ---${NC}"
    echo "1) Install MySQL/MariaDB"
    echo "2) Create Database"
    echo "3) List Databases"
    echo "4) Delete Database"
    echo "5) Backup Database"
    echo "6) Restore Database"
    echo "7) Optimize Database"
    echo "8) Database Status"
    read -rp "Choose database task [1-8]: " DB_OPTION

    case $DB_OPTION in
        1) install_mysql ;;
        2) create_database ;;
        3) list_databases ;;
        4) delete_database ;;
        5) backup_database ;;
        6) restore_database ;;
        7) optimize_database ;;
        8) show_database_status ;;
        *) echo -e "${YELLOW}Invalid option.${NC}" ;;
    esac
}
