# Changelog

All notable changes to QuickVPS will be documented in this file.

## [1.0.0] - 2025-08-07

### Added
- Initial release of QuickVPS - VPS Configuration Tool
- Interactive menu-driven interface
- Modular architecture with separate modules for different functionalities
- Server setup automation (LEMP stack, Node.js, Docker, Certbot)
- User management system
- Domain configuration with multiple stack support
- Docker application deployment
- Template system for various web stacks
- Comprehensive logging system
- SSL certificate automation
- Color-coded output for better user experience
- Confirmation prompts for destructive operations

### Features
- **Server Management**
  - LEMP stack installation with configurable PHP version
  - Node.js LTS installation
  - Docker and Docker Compose setup
  - Certbot for SSL certificates

- **User Management**
  - Create new system users
  - Add users to sudo group

- **Domain Setup**
  - PHP (Native) applications
  - Laravel applications
  - WordPress sites
  - Static websites
  - Node.js (Express) applications
  - Dockerized applications

- **Docker Management**
  - Standalone Docker app deployment
  - Container status checking
  - Pre-configured templates (Ghost, n8n)

- **Templates Included**
  - Nginx configurations for all supported stacks
  - Express.js application template
  - Docker Compose templates
  - Sample PHP and HTML files

### Technical Details
- Environment variable configuration support
- Comprehensive error handling and validation
- Automatic logging to `/var/log/vps-setup.log`
- Domain-specific log directories
- Git integration for project cloning
- Secure file permissions and ownership management

---

## How to Update This Changelog

When making changes to the tool, please update this file with:
- Version number following semantic versioning (MAJOR.MINOR.PATCH)
- Date of release
- List of added, changed, deprecated, removed, fixed, or security-related changes

### Change Categories
- **Added** for new features
- **Changed** for changes in existing functionality
- **Deprecated** for soon-to-be removed features
- **Removed** for now removed features
- **Fixed** for any bug fixes
- **Security** for vulnerability fixes
