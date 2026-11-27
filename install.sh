#!/bin/bash

# QuickVPS Installation Script
# This script provides an easy way to install QuickVPS on a fresh server

set -e

REPO_URL="${QUICKVPS_REPO_URL:-https://github.com/uziins/quickvps.git}"
INSTALL_DIR="/opt/quickvps"

echo "🚀 QuickVPS Installer"
echo "===================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root"
   exit 1
fi

# Check OS
if [[ ! -f /etc/lsb-release ]] || ! grep -q "Ubuntu" /etc/lsb-release; then
    echo "⚠️  This installer is designed for Ubuntu. Proceed anyway? [y/N]"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "📥 Installing required packages..."
apt update
apt install -y git curl wget

echo "📁 Creating installation directory..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo "⬇️  Downloading QuickVPS..."
if [[ -d ".git" ]]; then
    echo "📦 Updating existing installation..."
    git pull --ff-only
else
    echo "🔄 Fresh installation..."
    git clone "$REPO_URL" .
fi

echo "🔧 Setting permissions..."
chmod +x setup.sh
chmod +x modules/*.sh

echo "🔗 Creating symlink..."
ln -sf "$INSTALL_DIR/setup.sh" /usr/local/bin/quickvps

echo "✅ Installation completed!"
echo ""
echo "🎯 Usage:"
echo "  quickvps          # Run from anywhere"
echo "  cd $INSTALL_DIR && ./setup.sh  # Run from install directory"
echo ""
echo "📖 Documentation: https://github.com/uziins/quickvps"
