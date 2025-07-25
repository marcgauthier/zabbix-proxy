```bash
#!/usr/bin/env bash
#
# build-almalinux-zabbix-iso.sh
#
# This script automates the creation of a custom AlmaLinux ISO
# preloaded with Zabbix Proxy and its dependencies.
#
# Prerequisites:
#   - Run on an AlmaLinux minimal VM (or equivalent RHEL‑9/CentOS‑stream‑9).
#   - Network access to the Internet to download packages and scripts.
#   - Sufficient disk space under /root for downloads and result ISO.
#
# Usage:
#   sudo bash build-almalinux-zabbix-iso.sh
#

set -euo pipefail
IFS=$'\n\t'

#------------------------------------------------------------------------------
# 1. Prepare the Base System
#    - Enable EPEL repository for extra packages
#    - Download and execute the custom build helper script
#------------------------------------------------------------------------------

echo "==> Step 1: Prepare base system"

# Install Extra Packages for Enterprise Linux
echo "Installing EPEL repository..."
dnf install -y epel-release

# Fetch the build helper script from GitHub and execute it
echo "Downloading build.sh helper script..."
curl -fsSL -o build.sh \
  https://raw.githubusercontent.com/marcgauthier/zabbix-proxy/refs/heads/main/build.sh

echo "Making build.sh executable and running it..."
chmod +x build.sh
./build.sh

#------------------------------------------------------------------------------
# 2. Download Zabbix and Dependencies (no installation)
#    - Add the Zabbix official RPM repository
#    - Clean DNF cache and refresh metadata
#    - Download required RPMs into a local directory
#------------------------------------------------------------------------------

echo "==> Step 2: Download Zabbix RPMs (offline cache)"

# Configure Zabbix repository (adjust version/OS release as needed)
echo "Adding Zabbix 7.4 repository for AlmaLinux 9..."
rpm -Uvh --quiet \
  https://repo.zabbix.com/zabbix/7.4/release/alma/9/noarch/zabbix-release-latest-7.4.el9.noarch.rpm

echo "Cleaning DNF metadata and building cache..."
dnf clean all
dnf makecache

# Directory where RPMs will be downloaded
PKG_DIR="/root/zabbix-pkgs"

echo "Creating package download directory: $PKG_DIR"
mkdir -p "$PKG_DIR"

# Download Zabbix Proxy (MySQL) and Agent RPMs without installing
echo "Downloading Zabbix Proxy and Agent RPMs to $PKG_DIR..."
dnf install --downloadonly \
    --downloaddir="$PKG_DIR" \
    zabbix-proxy-mysql \
    zabbix-agent

#------------------------------------------------------------------------------
# 3. Install Tools for Custom ISO Creation
#    - Install lorax, livecd-creator, pykickstart, Anaconda installer
#    - Groupinstall development tools for building ISO
#------------------------------------------------------------------------------

echo "==> Step 3: Install ISO build tools"

# Install group of development tools (compilers, make, etc.)
echo "Installing Development Tools group..."
dnf groupinstall -y "Development Tools"

# Install ISO creation utilities
echo "Installing lorax, anaconda, and pykickstart..."
dnf install -y lorax anaconda pykickstart

#------------------------------------------------------------------------------
# 4. Download Kickstart Configuration
#    - Retrieve the ks.cfg (or zabbix.cfg) kickstart file from GitHub
#------------------------------------------------------------------------------

echo "==> Step 4: Download Kickstart file"

KS_FILE="/root/ks.cfg"

echo "Fetching custom kickstart file to $KS_FILE..."
curl -fsSL -o "$KS_FILE" \
  https://raw.githubusercontent.com/marcgauthier/zabbix-proxy/refs/heads/main/zabbix.cfg

#------------------------------------------------------------------------------
# 5. Build the Custom ISO with livemedia-creator
#    - Inject RPM cache and use kickstart to automate install
#    - Adjust paths (ISO source, result directory) as needed
#------------------------------------------------------------------------------

echo "==> Step 5: Build custom AlmaLinux ISO"

# Paths (customize if necessary)
DOWNLOAD_DIR="/root/downloads"
SOURCE_ISO="$DOWNLOAD_DIR/AlmaLinux-10-x86_64-minimal.iso"
RESULT_DIR="/root/custom-iso"
TMP_DIR="/tmp/lmc"

# Ensure source ISO is present
if [[ ! -f "$SOURCE_ISO" ]]; then
  echo "ERROR: Source ISO not found at $SOURCE_ISO"
  echo "Please download the AlmaLinux minimal ISO into $DOWNLOAD_DIR first."
  exit 1
fi

# Create result and temporary directories
mkdir -p "$RESULT_DIR" "$TMP_DIR"

# Build the ISO
livemedia-creator \
  --make-iso \
  --iso="$SOURCE_ISO" \
  --ks="$KS_FILE" \
  --initrd-inject="$PKG_DIR:/build/zabbix-pkgs" \
  --title="Alma-Zabbix-Proxy" \
  --releasever=10 \
  --tmp="$TMP_DIR" \
  --resultdir="$RESULT_DIR"

echo "Custom ISO build complete!"
echo "Find your ISO in: $RESULT_DIR"
```
