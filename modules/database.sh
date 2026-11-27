#!/bin/bash

# Database Management Module for QuickVPS
# Supports MySQL/MariaDB installation, configuration, and management

# Run the mysql/mysqldump client as the DB root user.
# Uses unix_socket auth when available (default on Ubuntu/Debian when run as root);
# otherwise asks for the root password once and passes it via MYSQL_PWD (not argv).
DB_ROOT_AUTH_OK=0
db_root_auth() {
    if [[ "$DB_ROOT_AUTH_OK" == "1" ]]; then
        return 0
    fi
    if mysql -u root -e "SELECT 1" &>/dev/null; then
        DB_ROOT_AUTH_OK=1
        return 0
    fi
    local pass="${MYSQL_ROOT_PASSWORD:-}"
    if [[ -z "$pass" ]]; then
        if [[ "$NON_INTERACTIVE" == "1" ]]; then
            echo -e "${RED}❌ Cannot log in as DB root via socket. Set MYSQL_ROOT_PASSWORD in the environment.${NC}"
            return 1
        fi
        read -rsp "Enter MySQL/MariaDB root password: " pass
        echo
    fi
    if ! MYSQL_PWD="$pass" mysql -u root -e "SELECT 1" &>/dev/null; then
        echo -e "${RED}❌ Could not log in as DB root. Check the password.${NC}"
        return 1
    fi
    export MYSQL_PWD="$pass"
    DB_ROOT_AUTH_OK=1
}

db_root() {
    mysql -u root "$@"
}

# Escape a value for use inside a single-quoted SQL string
sql_escape() {
    local v="${1//\\/\\\\}"
    printf '%s' "${v//\'/\\\'}"
}

install_mysql() {
    echo -e "${CYAN}Installing MySQL/MariaDB...${NC}"

    # Check if MySQL/MariaDB is already installed
    if command -v mysql &>/dev/null || command -v mariadb &>/dev/null; then
        echo -e "${YELLOW}MySQL/MariaDB is already installed${NC}"
        return
    fi

    if [[ -z "$DB_ENGINE" && "$NON_INTERACTIVE" != "1" ]]; then
        echo -e "${CYAN}Select database engine:${NC}"
        echo "1) MySQL 8.0"
        echo "2) MariaDB (Recommended)"
        read -rp "Choose database engine [1-2]: " DB_ENGINE
    fi

    case $DB_ENGINE in
        1|mysql)
            echo -e "${CYAN}Installing MySQL 8.0...${NC}"
            $PKG_UPDATE
            $PKG_INSTALL mysql-server mysql-client
            systemctl start mysqld || systemctl start mysql
            systemctl enable mysqld || systemctl enable mysql
            DB_TYPE="mysql"
            ;;
        *)
            if [[ -n "$DB_ENGINE" && "$DB_ENGINE" != "2" && "$DB_ENGINE" != "mariadb" ]]; then
                echo -e "${YELLOW}Invalid option. Installing MariaDB as default...${NC}"
            fi
            echo -e "${CYAN}Installing MariaDB...${NC}"
            $PKG_UPDATE
            $PKG_INSTALL mariadb-server mariadb-client
            systemctl start mariadb
            systemctl enable mariadb
            DB_TYPE="mariadb"
            ;;
    esac

    echo -e "${GREEN}✅ $DB_TYPE installed successfully${NC}"

    # Secure installation is interactive by nature; skipped in non-interactive mode
    if [[ "$NON_INTERACTIVE" != "1" ]] && ask_yes_no "Run secure installation?" y; then
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

    prompt_value DB_NAME "Enter database name"
    if [[ ! "$DB_NAME" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "${RED}❌ Invalid database name. Use only letters, numbers, and underscores.${NC}"
        return 1
    fi

    prompt_value DB_USER "Enter database username"
    if [[ ! "$DB_USER" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "${RED}❌ Invalid username. Use only letters, numbers, and underscores.${NC}"
        return 1
    fi

    if [[ -z "$DB_PASS" ]]; then
        local pass_option="1"
        if [[ "$NON_INTERACTIVE" != "1" ]]; then
            echo -e "${CYAN}Password options:${NC}"
            echo "1) Generate random password"
            echo "2) Enter custom password"
            read -rp "Choose password option [1-2]: " pass_option
        fi
        case $pass_option in
            1)
                DB_PASS=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
                echo -e "${GREEN}Generated password: $DB_PASS${NC}"
                ;;
            2)
                local confirm
                read -rsp "Enter password: " DB_PASS
                echo
                read -rsp "Confirm password: " confirm
                echo
                if [[ "$DB_PASS" != "$confirm" ]]; then
                    echo -e "${RED}❌ Passwords do not match${NC}"
                    return 1
                fi
                ;;
            *)
                echo -e "${RED}❌ Invalid option${NC}"
                return 1
                ;;
        esac
    fi

    db_root_auth || return 1

    if db_root -e "
        CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$(sql_escape "$DB_PASS")';
        GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
        FLUSH PRIVILEGES;
    "; then
        echo -e "${GREEN}✅ Database created successfully${NC}"
        echo -e "${CYAN}Database details:${NC}"
        echo "  Database: $DB_NAME"
        echo "  Username: $DB_USER"
        echo "  Password: $DB_PASS"
        echo "  Host: localhost"

        # Save to file (readable by root only)
        DB_INFO_FILE="/root/db_credentials_$DB_NAME.txt"
        (
            umask 077
            cat > "$DB_INFO_FILE" << EOF
Database Credentials for $DB_NAME
================================
Database: $DB_NAME
Username: $DB_USER
Password: $DB_PASS
Host: localhost
Port: 3306

Connection String Examples:
MySQL CLI: mysql -u $DB_USER -p $DB_NAME
Laravel .env:
  DB_CONNECTION=mysql
  DB_HOST=127.0.0.1
  DB_PORT=3306
  DB_DATABASE=$DB_NAME
  DB_USERNAME=$DB_USER
  DB_PASSWORD=$DB_PASS

Created: $(date)
EOF
        )
        echo -e "${GREEN}✅ Credentials saved to: $DB_INFO_FILE${NC}"
        log "Database $DB_NAME created for user $DB_USER"
    else
        echo -e "${RED}❌ Failed to create database.${NC}"
        return 1
    fi
}

list_databases() {
    echo -e "${CYAN}Listing databases...${NC}"
    db_root_auth || return 1

    echo -e "${CYAN}Databases:${NC}"
    db_root -N -e "SHOW DATABASES;" | grep -vxE "information_schema|performance_schema|mysql|sys"

    echo -e "\n${CYAN}Users:${NC}"
    db_root -e "SELECT User, Host FROM mysql.user WHERE User NOT IN ('root', 'debian-sys-maint', 'mysql.session', 'mysql.sys', 'mysql.infoschema', 'mariadb.sys');"
}

delete_database() {
    echo -e "${CYAN}Deleting database...${NC}"
    echo -e "${RED}⚠️  WARNING: This action cannot be undone!${NC}"

    prompt_value DB_NAME "Enter database name to delete"
    if [[ ! "$DB_NAME" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "${RED}❌ Invalid database name.${NC}"
        return 1
    fi

    if [[ -z "$DB_USER" && "$NON_INTERACTIVE" != "1" ]]; then
        read -rp "Enter database username to delete (leave blank to keep users): " DB_USER
    fi
    if [[ -n "$DB_USER" && ! "$DB_USER" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "${RED}❌ Invalid username.${NC}"
        return 1
    fi

    echo -e "${RED}Database '$DB_NAME'${DB_USER:+ and user '$DB_USER'} will be deleted.${NC}"
    confirm_action || return 1

    db_root_auth || return 1

    local sql="DROP DATABASE IF EXISTS \`$DB_NAME\`;"
    [[ -n "$DB_USER" ]] && sql+=" DROP USER IF EXISTS '$DB_USER'@'localhost';"
    sql+=" FLUSH PRIVILEGES;"

    if db_root -e "$sql"; then
        echo -e "${GREEN}✅ Database '$DB_NAME'${DB_USER:+ and user '$DB_USER'} deleted successfully${NC}"

        DB_INFO_FILE="/root/db_credentials_$DB_NAME.txt"
        if [[ -f "$DB_INFO_FILE" ]]; then
            rm -f "$DB_INFO_FILE"
            echo -e "${GREEN}✅ Credentials file removed${NC}"
        fi

        log "Database $DB_NAME deleted (user: ${DB_USER:-none})"
    else
        echo -e "${RED}❌ Failed to delete database.${NC}"
        return 1
    fi
}

backup_database() {
    echo -e "${CYAN}Creating database backup...${NC}"

    prompt_value DB_NAME "Enter database name to backup"
    if [[ ! "$DB_NAME" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "${RED}❌ Invalid database name.${NC}"
        return 1
    fi

    db_root_auth || return 1

    BACKUP_DIR="/root/db_backups"
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"

    local backup_file
    backup_file="$BACKUP_DIR/${DB_NAME}_$(date +%Y%m%d_%H%M%S).sql.gz"

    echo -e "${CYAN}Creating backup...${NC}"
    mysqldump -u root --single-transaction --routines --triggers "$DB_NAME" | gzip > "$backup_file"
    if [[ "${PIPESTATUS[0]}" -eq 0 ]]; then
        chmod 600 "$backup_file"
        echo -e "${GREEN}✅ Database backup created successfully${NC}"
        echo "  File: $backup_file"
        echo "  Size: $(du -h "$backup_file" | cut -f1)"
        log "Database $DB_NAME backed up to $backup_file"
    else
        rm -f -- "$backup_file"
        echo -e "${RED}❌ Failed to create backup. Please check the database name.${NC}"
        return 1
    fi
}

restore_database() {
    echo -e "${CYAN}Restoring database from backup...${NC}"

    BACKUP_DIR="/root/db_backups"
    if [[ -z "$BACKUP_FILE" && "$NON_INTERACTIVE" != "1" ]]; then
        if compgen -G "$BACKUP_DIR/*.sql*" >/dev/null; then
            echo -e "${CYAN}Available backups:${NC}"
            ls -lh "$BACKUP_DIR"/*.sql* | awk '{print $9, $5, $6, $7, $8}'
        else
            echo -e "${YELLOW}No backups found in $BACKUP_DIR${NC}"
        fi
    fi

    prompt_value BACKUP_FILE "Enter full path to backup file"
    if [[ ! -f "$BACKUP_FILE" ]]; then
        echo -e "${RED}❌ Backup file not found: $BACKUP_FILE${NC}"
        return 1
    fi

    prompt_value DB_NAME "Enter target database name"
    if [[ ! "$DB_NAME" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "${RED}❌ Invalid database name.${NC}"
        return 1
    fi

    echo -e "${RED}This will overwrite existing data in '$DB_NAME'.${NC}"
    confirm_action || return 1

    db_root_auth || return 1
    db_root -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || return 1

    echo -e "${CYAN}Restoring database...${NC}"
    local status
    if [[ "$BACKUP_FILE" == *.gz ]]; then
        zcat "$BACKUP_FILE" | db_root "$DB_NAME"
        status=$(( PIPESTATUS[0] | PIPESTATUS[1] ))
    else
        db_root "$DB_NAME" < "$BACKUP_FILE"
        status=$?
    fi

    if [[ "$status" -eq 0 ]]; then
        echo -e "${GREEN}✅ Database restored successfully${NC}"
        log "Database $DB_NAME restored from $BACKUP_FILE"
    else
        echo -e "${RED}❌ Failed to restore database. Please check the backup file.${NC}"
        return 1
    fi
}

optimize_database() {
    echo -e "${CYAN}Optimizing database performance...${NC}"

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
    if ask_yes_no "Restart MySQL/MariaDB to apply optimizations?" y; then
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
