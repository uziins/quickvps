# QuickVPS - VPS Configuration Tool

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Platform](https://img.shields.io/badge/platform-Ubuntu%20%7C%20Debian%20%7C%20RHEL%20%7C%20CentOS-orange.svg)

A comprehensive bash script collection for quickly setting up and managing VPS servers with support for multiple web stacks including Laravel, WordPress, Node.js, Docker applications, and more.

## 🚀 Features

- **🖥️ Server Management**: System updates, security hardening, firewall configuration
- **👥 User Management**: Create/delete users, manage SSH keys, sudo permissions
- **🌐 Domain Management**: Multi-stack support with automatic Nginx configuration
- **🗄️ Database Management**: MySQL/MariaDB installation, database creation, backup/restore, optimization
- **🐳 Docker Support**: Pre-configured Docker applications (Ghost, n8n, etc.)
- **🔒 SSL/TLS**: Automatic Let's Encrypt certificate installation
- **📦 Stack Support**: Laravel, WordPress, Node.js, PHP, Static sites
- **🔐 Security**: Best practices with proper user permissions and security headers

## 📋 Requirements

- Ubuntu/Debian based OS or RHEL/CentOS based OS (AlmaLinux, Rocky, Fedora)
- Root or sudo access
- Internet connection

## 🛠️ Installation

```bash
# Clone the repository
git clone https://github.com/uziins/quickvps.git
cd quickvps

# Make the script executable
chmod +x setup.sh

# Run the setup
sudo ./setup.sh
```

## 🎯 Usage

QuickVPS can be run interactively or non-interactively using CLI arguments.

### Interactive Mode
Simply run the script without any arguments to open the interactive menu:
```bash
sudo ./setup.sh
```

### Main Menu Options

1. **Server Setup**: Initial server configuration, security hardening
2. **User Management**: Create/manage users and SSH access
3. **Domain Setup**: Configure domains with various web stacks
4. **Database Management**: MySQL/MariaDB installation, database creation, backup/restore
5. **Docker Apps**: Deploy pre-configured Docker applications

### Non-Interactive Mode (CLI Arguments)
You can bypass the interactive menus by passing arguments. This is perfect for CI/CD or automated provisioning tools like cloud-init.

```bash
# Example: Automatically setup LEMP server
sudo ./setup.sh server install-lemp --non-interactive

# Example: Automatically add a domain with Laravel stack, custom docroot, and owner
sudo ./setup.sh domain add --domain myapp.com --stack laravel --php 8.3 --docroot /home/budi/web --owner budi --non-interactive

# Example: Automatically add a reverse proxy (e.g. for Python/Go app)
sudo ./setup.sh domain add --domain api.myapp.com --stack proxy --proxy-port 8090 --non-interactive

# Example: Add a domain with www alias and Let's Encrypt SSL
sudo ./setup.sh domain add --domain myapp.com --www --stack php --ssl --email admin@myapp.com --non-interactive

# Example: Proxy a domain to another machine (e.g. an internal Zabbix server)
sudo ./setup.sh domain add --domain zbx.example.com --stack proxy --proxy-url http://172.16.90.101/zabbix/ --non-interactive

# Example: Same domain, different backends: / -> port 3000, /api/ -> port 8000
sudo ./setup.sh domain add --domain myapp.com --stack proxy --proxy-port 3000 --non-interactive
sudo ./setup.sh domain add-subdir --domain myapp.com --path /api/ --sub-stack proxy --proxy-port 8000 --keep-prefix --non-interactive

# Example: Create a database (password is generated when --db-pass is omitted)
sudo ./setup.sh database create --db-name app --db-user app --non-interactive

# Example: Deploy the n8n Docker template
sudo ./setup.sh docker setup --docker-app n8n --docker-port 5678 --docroot /var/www/n8n --non-interactive

# Example: Automatically create a new user
sudo ./setup.sh user add --user budi --non-interactive
```

For `add-subdir`, the path always gets a trailing slash (`/api` becomes `/api/`), the location uses `^~`
so the main site's regex locations (e.g. `\.php$`) cannot take over its requests, and `/api` redirects to `/api/`.
With a proxy, `--strip-prefix` (default) forwards `/api/users` as `/users` and sends `X-Forwarded-Prefix: /api`;
`--keep-prefix` forwards `/api/users` unchanged.

### HTTP Basic Auth

Protect a whole domain or a single path with a username/password (users are stored per domain in
`/etc/nginx/htpasswd/<domain>`, hashed with SHA-512 crypt):

```bash
# Protect the whole domain; creates the first user (password is prompted, or generated with --non-interactive)
sudo ./setup.sh auth enable --domain staging.myapp.com --user budi

# Protect only an existing path (add it first with `domain add-subdir`)
sudo ./setup.sh auth enable --domain myapp.com --path /admin/ --user budi

# Manage users (set a known password from stdin instead of generating one)
echo 'S3cret-pass' | sudo ./setup.sh auth add-user --domain myapp.com --user ani --pass-stdin --non-interactive
sudo ./setup.sh auth delete-user --domain myapp.com --user ani
sudo ./setup.sh auth status --domain myapp.com
sudo ./setup.sh auth disable --domain myapp.com --path /admin/
```

Basic auth only base64-encodes credentials, so enabling it on a domain without HTTPS requires `--force`.
Site-wide auth keeps `/.well-known/acme-challenge/` open for certificate renewals. Avoid it on APIs called
from browsers: CORS preflight requests carry no credentials and would get a 401.

`--proxy-url` accepts `http(s)://host[:port][/path/]` for the `proxy` stack, `add-subdir` and `domain modify`.
The upstream must be reachable from the VPS. A URL path replaces the matched location (e.g. `/` → `/zabbix/`), so
`--keep-prefix` cannot be combined with it. Use `--proxy-host-header upstream` when the upstream relies on
name-based virtual hosts and expects its own hostname instead of the public domain.

Run `sudo ./setup.sh --help` for the full list of modules, actions and flags. In non-interactive mode
optional questions are answered "no" (e.g. SSL is only requested with `--ssl`), and an existing domain
config is only overwritten with `--force`.

### Stack Types Supported

| Stack | Description | Features |
|-------|-------------|----------|
| **Laravel** | PHP Laravel Framework | Composer, .env setup, artisan commands, proper permissions |
| **WordPress** | WordPress CMS | MySQL/MariaDB integration, wp-config setup |
| **Node.js** | Express.js applications | PM2 process manager, automatic startup |
| **PHP** | Native PHP applications | PHP-FPM integration |
| **Static** | Static HTML/CSS/JS sites | Basic nginx configuration |
| **Docker** | Containerized applications | Docker Compose, volume management |
| **Proxy** | Reverse Proxy (Generic) | Proxy pass to any local port (e.g. Python/Go app) |

### Example: Setting up Laravel Application

```bash
sudo ./setup.sh
# Select: 3) Domain Setup
# Select: 2) Add Domain
# Enter domain: yourdomain.com
# Select stack: 2) Laravel
# Choose to clone from Git: y
# Enter repository URL: https://github.com/yourusername/laravel-app.git
```

## 🏗️ Project Structure

```
QuickVPS/
├── setup.sh                 # Main entry script
├── modules/
│   ├── server.sh            # Server configuration
│   ├── user.sh              # User management
│   ├── domain.sh            # Domain and stack setup
│   ├── docker.sh            # Docker applications
│   ├── auth.sh              # HTTP basic auth
│   └── utils.sh             # Utility functions
├── templates/
│   ├── nginx_*.conf.template # Nginx configuration templates
│   ├── *.php/.html          # Default files for stacks
│   └── docker/              # Docker compose templates
│       ├── ghost/
│       └── n8n/
├── README.md
└── CHANGELOG.md
```

## 🔧 Configuration Templates

### Nginx Templates
- `nginx_laravel.conf.template` - Laravel with proper rewrite rules
- `nginx_wordpress.conf.template` - WordPress with PHP-FPM
- `nginx_node.conf.template` - Node.js reverse proxy
- `nginx_docker.conf.template` - Docker container proxy
- `nginx_static.conf.template` - Static site serving

### Docker Applications
- **Ghost**: Blog platform with MySQL
- **n8n**: Workflow automation platform
- More templates can be added in `templates/docker/`

## 🔒 Security Features

- Automatic firewall (UFW) configuration
- SSH key-based authentication setup
- Fail2ban integration for brute force protection
- Security headers in Nginx configurations
- Non-root user execution for applications
- Proper file permissions and ownership

## 🚀 Quick Start Examples

### 1. Basic Server Setup
```bash
sudo ./setup.sh
# Select: 1) Server Setup
# Follow prompts for timezone, packages, firewall
```

### 2. Create New User with SSH Access
```bash
sudo ./setup.sh
# Select: 2) User Management
# Select: 1) Add User
# Enter username and configure SSH access
```

### 3. Deploy WordPress Site
```bash
sudo ./setup.sh
# Select: 3) Domain Setup
# Select: 2) Add Domain
# Enter domain name
# Select: 3) WordPress
# Configure database and admin user
```

### 4. Setup Database for Laravel
```bash
sudo ./setup.sh
# Select: 4) Database Management
# Select: 2) Create Database
# Enter database name: myapp_production
# Enter username: myapp_user
# Select: 1) Generate random password
# Credentials will be saved to /root/db_credentials_myapp_production.txt
```

### 5. Deploy Docker Application
```bash
sudo ./setup.sh
# Select: 4) Docker Apps
# Select application (Ghost, n8n, etc.)
# Configure ports and environment
```

## 🐛 Troubleshooting

### Common Issues

1. **Permission Denied (Git Clone)**
   - Use HTTPS URL instead of SSH: `https://github.com/user/repo.git`
   - Or setup SSH keys for the server

2. **Composer/Artisan Permission Issues**
   - Script automatically handles this by running as www-data user
   - Fallback to root with proper warnings if needed

3. **Nginx Configuration Issues**
   - Check `/var/log/nginx/error.log`
   - Verify domain DNS points to server IP

4. **SSL Certificate Issues**
   - Ensure domain is properly pointed to server
   - Check port 80/443 are open in firewall

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Nginx community for excellent documentation
- Laravel community for deployment best practices
- Docker community for containerization standards

## 📞 Support

If you encounter any issues or have questions:

1. Check the [Issues](https://github.com/yourusername/QuickVPS/issues) page
2. Create a new issue with detailed information
3. Include server OS, error messages, and steps to reproduce

---

**Made with ❤️ for the DevOps community**
