# Changelog

All notable changes to QuickVPS will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- `quickvps` symlink: modules, templates and `.env` are now resolved relative to the real script location, not the current directory
- `--non-interactive` no longer prompts: all domain, database, docker, TCP and user actions honor CLI flags and fall back to safe defaults
- `domain delete` reads the docroot from a `# quickvps-docroot:` marker, validates the domain name and refuses to delete system/top-level directories
- `domain add` refuses unsafe docroots, no longer `chown -R`s existing non-empty directories without asking, and will not overwrite an existing config without `--force`
- Failed `nginx -t` after add/modify/add-subdir/delete/TCP changes now rolls the config back
- `domain add-subdir` inserts the location into the HTTPS server block after Certbot has split the config
- `docker setup` (standalone) no longer writes to `/docker-compose.yml`; it installs into a chosen directory and fills in the port
- `install.sh` points at the real repository URL
- Domain configs are found whether they are named `<domain>.conf`, `<domain>`, or only list the domain in `server_name`; ambiguous matches are reported instead of guessed
- `domain add` reuses an existing `<domain>` config (no duplicate `<domain>.conf`) and refuses to overwrite a shared config holding other sites
- `domain delete` removes every enabled symlink pointing at the config, whatever its name, and refuses to delete shared configs
- On conf.d layouts (RHEL) configs without `.conf` are flagged as inactive, and `domain add --force` replaces them with `<domain>.conf`
- `domain list` shows enabled/disabled status and the `server_name`s of each config
- `domain add-subdir` normalizes the path to a trailing slash (fixes `//x` upstream paths, `/api` matching `/apikey`, and the `alias` path traversal), uses `location ^~` so regex locations of the main site do not capture the subpath, and redirects `/api` to `/api/`
- PHP subdirectories no longer use `snippets/fastcgi-php.conf`, whose `try_files` breaks with `alias`

### Added
- `--strip-prefix` / `--keep-prefix` for proxied subdirectories; `X-Forwarded-Prefix` is sent when the prefix is stripped
- New flags: `--www`, `--ssl`, `--email`, `--force`, `--git-url`, `--node-port`, `--delete-root`, `--path`, `--sub-stack`, `--backup-file`, `--container`, `--listen-port`, `--destination`, `--ssl-domain`, `--help`
- Database commands use socket auth for root when available (password otherwise passed via `MYSQL_PWD`, not the command line)

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
