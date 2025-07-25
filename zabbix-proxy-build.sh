#!/usr/bin/env bash
#
# zabbix‑proxy‑build.sh
#
# This script automates the creation of a custom AlmaLinux ISO
# preloaded with Zabbix Proxy and its dependencies.
#
# Prerequisites:
#   - Run on an AlmaLinux minimal VM (or equivalent RHEL‑9/Alma‑9).
#   - Network access to the Internet to download packages and scripts.
#   - Sufficient disk space under /root for downloads and result ISO.
#
# Usage:
#
#   curl -fsSL -o zabbix-kickstart.cfg https://raw.githubusercontent.com/marcgauthier/zabbix-proxy/refs/heads/main/zabbix-kickstart.cfg
#   curl -fsSL -o zabbix-proxy-build.sh https://raw.githubusercontent.com/marcgauthier/zabbix-proxy/refs/heads/main/zabbix-proxy-build.sh
#   chmod +x zabbix‑proxy‑build.sh
#   ./zabbix‑proxy‑build.sh
#
set -euo pipefail
IFS=$'\n\t'


#------------------------------------------------------------------------------
# GLOBAL CONFIGURATION VARIABLES
#------------------------------------------------------------------------------
# URL of the AlmaLinux minimal ISO to download if missing.
# Adjust the URL to point to the desired AlmaLinux 9 minimal ISO.
ALMA_ISO_URL="https://repo.almalinux.org/almalinux/9.6/isos/x86_64/AlmaLinux-9.6-x86_64-minimal.iso"
#
# Path to the AlmaLinux minimal ISO you have downloaded.
ALMA_ISO_PATH="/root/downloads/AlmaLinux-9-x86_64-minimal.iso"
#
# URL of the Zabbix RPM repository package to install.
# Adjust version (7.4) and AlmaLinux major (9) as needed.
ZABBIX_REPO_RPM="https://repo.zabbix.com/zabbix/7.4/release/alma/9/noarch/zabbix-release-latest-7.4.el9.noarch.rpm"

# Directory under which to stash downloaded Zabbix RPMs
PKG_DIR="/root/zabbix-pkgs"
# Kickstart file location
KS_FILE="/root/zabbix-kickstart.cfg"
# Directories for ISO build
RESULT_DIR="/root/custom-iso"
TMP_DIR="/tmp/lmc"

#------------------------------------------------------------------------------
# VERIFY GLOBAL VARIABLES
#------------------------------------------------------------------------------
echo "ALMA_ISO_URL   = $ALMA_ISO_URL"
echo "ALMA_ISO_PATH is set to:   $ALMA_ISO_PATH"
echo "ZABBIX_REPO_RPM is set to: $ZABBIX_REPO_RPM"
echo

#------------------------------------------------------------------------------
# 0. Ensure ISO is present (download if missing)
#------------------------------------------------------------------------------
echo "==> Step 0: Ensure AlmaLinux ISO"
if [[ ! -f "$ALMA_ISO_PATH" ]]; then
  echo "AlmaLinux ISO not found at $ALMA_ISO_PATH"
  echo "Downloading from $ALMA_ISO_URL..."
  mkdir -p "$(dirname "$ALMA_ISO_PATH")"
  curl -fsSL -o "$ALMA_ISO_PATH" "$ALMA_ISO_URL"
  echo "Downloaded ISO to $ALMA_ISO_PATH"
else
  echo "Found ISO at $ALMA_ISO_PATH"
fi
echo

#------------------------------------------------------------------------------
# 1. Prepare the Base System
#    - Enable EPEL repository for extra packages
#------------------------------------------------------------------------------
echo "==> Step 1: Prepare base system"
echo "Installing EPEL repository..."
dnf install -y epel-release

#------------------------------------------------------------------------------
# 2. Download Zabbix and Dependencies (no installation)
#    - Add the Zabbix RPM repository
#    - Clean DNF cache and download required RPMs into PKG_DIR
#------------------------------------------------------------------------------
echo "==> Step 2: Download Zabbix RPMs (offline cache)"
echo "Adding Zabbix repository package from $ZABBIX_REPO_RPM..."
rpm -Uvh --quiet "$ZABBIX_REPO_RPM"

echo "Cleaning DNF metadata and refreshing cache..."
dnf clean all
dnf makecache

echo "Creating package download directory: $PKG_DIR"
mkdir -p "$PKG_DIR"

echo "Downloading Zabbix Proxy (MySQL) and Agent RPMs into $PKG_DIR..."
dnf install --downloadonly \
    --downloaddir="$PKG_DIR" \
    zabbix-proxy-mysql \
    zabbix-agent2

#------------------------------------------------------------------------------
# 3. Install Tools for Custom ISO Creation
#    - lorax, livecd-creator, pykickstart, Anaconda installer, Development Tools
#------------------------------------------------------------------------------
echo "==> Step 3: Install ISO build tools"
echo "Installing 'Development Tools' group for compilers, make, etc..."
dnf groupinstall -y "Development Tools"

echo "Installing lorax, anaconda, and pykickstart..."
dnf install -y lorax anaconda-tui python3-kickstart


#------------------------------------------------------------------------------
# 4. Build the Custom ISO with livemedia-creator
#    - Inject RPM cache and use kickstart to automate install
#------------------------------------------------------------------------------
echo "==> Step 5: Build custom AlmaLinux ISO"
if [[ ! -f "$ALMA_ISO_PATH" ]]; then
  echo "ERROR: AlmaLinux ISO not found at $ALMA_ISO_PATH"
  echo "Please download the minimal ISO into that path and re-run."
  exit 1
fi

echo "Preparing result ($RESULT_DIR) and temp ($TMP_DIR) directories..."
mkdir -p "$RESULT_DIR" "$TMP_DIR"

echo "Starting ISO build with livemedia-creator..."
livemedia-creator \
  --make-iso \
  --iso="$ALMA_ISO_PATH" \
  --ks="$KS_FILE" \
  --initrd-inject="$PKG_DIR:/build/zabbix-pkgs" \
  --title="Alma-Zabbix-Proxy" \
  --releasever=9 \
  --tmp="$TMP_DIR" \
  --resultdir="$RESULT_DIR"

echo "Custom ISO build complete!"
echo "Your new ISO is located in: $RESULT_DIR"
