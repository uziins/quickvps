# Changelog

All notable changes to QuickVPS will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2024-08-09

### Added
- Initial release of QuickVPS
- Server setup and configuration module
- User management with SSH key support
- Domain management with multiple stack support
- Laravel application deployment with proper security
- WordPress deployment with database setup
- Node.js application deployment with PM2
- Docker application templates (Ghost, n8n)
- Static site deployment
- Automatic SSL/TLS with Let's Encrypt
- Security hardening with UFW firewall
- Nginx configuration templates for all stacks

### Security
- Composer and artisan commands run as www-data user (not root)
- Proper file permissions and ownership
- Security headers in all Nginx configurations
- SSH key-based authentication setup
- Fail2ban integration for brute force protection

### Features
- Git repository cloning with SSH to HTTPS conversion
- Automatic Laravel project setup (composer, .env, key generation)
- Interactive domain and stack selection
- Fallback mechanisms for permission issues
- Comprehensive error handling and logging
- Color-coded output for better user experience

### Templates
- Nginx configuration templates for Laravel, WordPress, Node.js, Docker, Static
- Docker Compose templates for Ghost and n8n
- Default PHP and HTML files for quick testing

## [Unreleased]

### Planned
- MySQL/MariaDB automatic setup for WordPress and Laravel
- PostgreSQL support
- Redis support for Laravel caching
- Backup and restore functionality
- Monitoring setup (Prometheus, Grafana)
- More Docker application templates
- CI/CD pipeline integration
- Multi-server management support
