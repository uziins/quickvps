# QuickVPS - VPS Configuration Tool

A comprehensive bash script collection for automating VPS server setup and configuration. QuickVPS provides an interactive menu-driven interface to set up LEMP stack, manage users, configure domains, and deploy various web applications with ease and speed.

## 🚀 Features

- **Server Setup**: Automated installation of LEMP stack, Node.js, Docker, and SSL certificates
- **User Management**: Create users and manage sudo privileges
- **Domain Configuration**: Set up domains with various stack types (PHP, Laravel, WordPress, Static, Node.js, Docker)
- **Docker Management**: Deploy and manage containerized applications
- **Template System**: Pre-configured templates for different web stacks
- **SSL Support**: Automatic SSL certificate generation with Certbot
- **Logging**: Comprehensive logging system for all operations

## 📋 Prerequisites

- Ubuntu/Debian-based VPS
- Root access (sudo privileges)
- Basic familiarity with command line

## 🛠 Installation

1. Clone this repository to your VPS:
```bash
git clone <your-repo-url> /opt/vps-config
cd /opt/vps-config
```

2. Make the script executable:
```bash
chmod +x setup.sh
```

3. Run the setup script:
```bash
sudo ./setup.sh
```

## 📁 Project Structure

```
vps-config/
├── setup.sh                    # Main script with interactive menu
├── modules/                    # Modular functionality
│   ├── utils.sh                # Utility functions and color codes
│   ├── server.sh               # Server installation functions
│   ├── user.sh                 # User management functions
│   ├── domain.sh               # Domain setup and configuration
│   └── docker.sh               # Docker management functions
└── templates/                  # Configuration templates
    ├── nginx_basic.conf.template
    ├── nginx_laravel.conf.template
    ├── nginx_wordpress.conf.template
    ├── nginx_static.conf.template
    ├── nginx_node.conf.template
    ├── nginx_docker.conf.template
    ├── express_app.js.template
    ├── php_index.php
    ├── static_index.html
    └── docker/                 # Docker compose templates
        ├── ghost/
        └── n8n/
```

## 🔧 Configuration

### Environment Variables

Create a `.env` file in the root directory to customize default settings:

```bash
PHP_VERSION=8.3
DEFAULT_NODE_PORT=3000
DEFAULT_DOCROOT_BASE=/var/www
NGINX_TEMPLATE_DIR=templates
DOCKER_TEMPLATE_DIR=templates/docker
DEFAULT_DOCKER_PORT=5678
```

## 📖 Usage Guide

### Main Menu Options

1. **Server Setup**
   - Install LEMP Stack (Linux, Nginx, MySQL, PHP)
   - Install Node.js (LTS version)
   - Install Certbot for SSL certificates
   - Install Docker and Docker Compose

2. **User Setup**
   - Create new system users
   - Add users to sudo group

3. **Domain Setup**
   - Configure domains with various stack types
   - Set up Nginx virtual hosts
   - Configure SSL certificates
   - Clone projects from Git repositories

4. **Docker Management**
   - Deploy standalone Docker applications
   - Check container status
   - Manage Docker services

### Supported Stack Types

#### 1. PHP (Native)
- Basic PHP application setup
- Nginx configuration for PHP-FPM
- Document root at `/var/www/domain.com`

#### 2. Laravel
- Optimized for Laravel applications
- Proper routing configuration
- Public directory setup

#### 3. WordPress
- WordPress-specific Nginx rules
- PHP configuration optimized for WordPress
- Support for permalinks and uploads

#### 4. Static Site
- Simple static file serving
- Optimized for HTML/CSS/JS sites
- Fast delivery with Nginx

#### 5. Node.js (Express)
- Reverse proxy setup for Node.js applications
- Default port configuration
- Express.js template included

#### 6. Dockerized Applications
- Container-based deployment
- Available templates: Ghost, n8n
- Docker Compose integration

## 🔐 Security Features

- SSL certificate automation with Let's Encrypt
- Secure Nginx configurations
- User privilege management
- Log file monitoring at `/var/log/vps-setup.log`

## 📝 Logging

All operations are logged to `/var/log/vps-setup.log` with timestamps. Domain-specific logs are created in `/var/log/nginx/domain.com/`.

## 🚀 Quick Start Examples

### Setting up a Laravel application:
1. Run `sudo ./setup.sh`
2. Choose "1) Server Setup" → Install LEMP Stack
3. Choose "3) Domain Setup" → Add new domain
4. Select "2) Laravel" as stack type
5. Enter your domain name
6. Optionally clone from Git repository
7. Configure SSL certificate

### Deploying a Docker application:
1. Run `sudo ./setup.sh`
2. Choose "1) Server Setup" → Install Docker
3. Choose "4) Docker Management" → Setup Docker App
4. Choose from available templates (Ghost, n8n)
5. Configure domain and ports

## 🛡️ Error Handling

The script includes comprehensive error handling:
- Confirmation prompts for destructive operations
- Validation of user inputs
- Detailed error messages with color coding
- Rollback capabilities for failed operations

## 🎨 Color Coding

- 🔵 **Cyan**: Information and menu headers
- 🟢 **Green**: Success messages
- 🟡 **Yellow**: Warnings and invalid inputs
- 🔴 **Red**: Errors and critical issues

## 🔄 Updating

To update the tool:
```bash
cd /opt/vps-config
git pull origin main
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly on a clean VPS
5. Submit a pull request

## 📞 Support

For issues and questions:
- Check the log files in `/var/log/vps-setup.log`
- Review Nginx error logs for domain-specific issues
- Ensure all prerequisites are met

## ⚠️ Important Notes

- Always run as root (use sudo)
- Test in a staging environment before production
- Backup your server before running major operations
- Review generated configurations before going live

## 📄 License

This project is open source. Please ensure compliance with your organization's policies before use.

---

**Made with ❤️ for simplified VPS management**
