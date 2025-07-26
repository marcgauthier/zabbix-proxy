#!/usr/bin/env bash
#
# Simple Zabbix Proxy ISO Builder
# Creates a custom AlmaLinux ISO with Zabbix Proxy preinstalled
#
# Usage: ./zabbix-proxy-build.sh
#
set -e

# Configuration
ALMA_ISO_URL="https://repo.almalinux.org/almalinux/9.6/isos/x86_64/AlmaLinux-9.6-x86_64-minimal.iso"
ALMA_ISO_PATH="/root/downloads/AlmaLinux-9-x86_64-minimal.iso"
ZABBIX_REPO_RPM="https://repo.zabbix.com/zabbix/7.4/release/alma/9/noarch/zabbix-release-latest-7.4.el9.noarch.rpm"
PKG_DIR="/root/zabbix-pkgs"
KS_FILE="/root/zabbix-kickstart.cfg"
RESULT_DIR="/root/custom-iso"

echo "=== Starting Zabbix Proxy ISO Builder ==="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# Download kickstart file
echo "Downloading kickstart configuration..."
curl -fsSL -o "$KS_FILE" \
    https://raw.githubusercontent.com/marcgauthier/zabbix-proxy/refs/heads/main/zabbix-kickstart.cfg

# Download AlmaLinux ISO if not exists
if [[ ! -f "$ALMA_ISO_PATH" ]]; then
    echo "Downloading AlmaLinux ISO..."
    mkdir -p "$(dirname "$ALMA_ISO_PATH")"
    curl -fsSL -o "$ALMA_ISO_PATH" "$ALMA_ISO_URL"
fi

# Install base packages and repositories
echo "Installing base packages..."
dnf install -y epel-release
dnf clean all && dnf makecache

# Setup Zabbix repository
echo "Setting up Zabbix repository..."
if ! rpm -q zabbix-release &>/dev/null; then
    rpm -Uvh --quiet "$ZABBIX_REPO_RPM"
    dnf clean all && dnf makecache
else
    echo "Zabbix repository already installed, skipping..."
fi

# Download Zabbix packages
echo "Downloading Zabbix packages and dependencies..."
mkdir -p "$PKG_DIR"

# Check if we already have packages downloaded
if [[ $(find "$PKG_DIR" -name "*.rpm" | wc -l) -gt 0 ]]; then
    echo "Found existing packages in $PKG_DIR, checking if we need to download more..."
    # Still run the download commands but allow them to skip existing files
else
    echo "No existing packages found, downloading all packages..."
fi

# Download Zabbix packages and all their dependencies
echo "Downloading Zabbix proxy and agent packages..."
dnf download --resolve --alldeps --downloaddir="$PKG_DIR" \
    zabbix-proxy-mysql zabbix-agent2 || {
    echo "Warning: Some Zabbix packages may already exist or failed to download"
}

# Download additional required packages for the kickstart
echo "Downloading additional required packages..."
dnf download --resolve --alldeps --downloaddir="$PKG_DIR" \
    mariadb-server acl bind-utils wget curl tar gzip || {
    echo "Warning: Some additional packages may already exist or failed to download"
}

echo "Total packages in repository: $(find "$PKG_DIR" -name "*.rpm" | wc -l)"

# Install build tools
echo "Installing build tools..."
# Check if Development Tools group is already installed
if ! dnf group list installed | grep -q "Development Tools"; then
    echo "Installing Development Tools group..."
    dnf groupinstall -y "Development Tools"
else
    echo "Development Tools already installed, skipping..."
fi

# Install individual packages, allowing them to be skipped if already installed
echo "Installing required build packages..."
dnf install -y lorax anaconda-tui python3-kickstart createrepo_c || {
    echo "Some build tools may already be installed"
}

# Create local repository
echo "Creating/updating local repository..."
createrepo_c "$PKG_DIR" || {
    echo "Repository creation failed, but continuing..."
}

# Create repository configuration file
cat > "$PKG_DIR/zabbix-local.repo" << EOF
[zabbix-local]
name=Local Zabbix Repository
baseurl=file://$PKG_DIR
enabled=1
gpgcheck=0
EOF

# Prepare temporary directory
TMP_DIR=$(mktemp -d)
echo "Using temporary directory: $TMP_DIR"

# Create modified kickstart file with local repository
MODIFIED_KS="$TMP_DIR/modified-kickstart.cfg"
cp "$KS_FILE" "$MODIFIED_KS"

cat >> "$MODIFIED_KS" << EOF

# Local Zabbix repository
repo --name="zabbix-local" --baseurl="file://$PKG_DIR"
EOF

# Clean up existing result directory more thoroughly
echo "Cleaning up existing result directory..."
if [[ -d "$RESULT_DIR" ]]; then
    echo "Removing existing $RESULT_DIR"
    rm -rf "$RESULT_DIR"
fi

# Ensure the result directory doesn't exist and wait a moment
sleep 1

# Verify the directory is gone
if [[ -d "$RESULT_DIR" ]]; then
    echo "ERROR: Failed to remove $RESULT_DIR completely"
    echo "Please manually remove it and try again:"
    echo "  rm -rf '$RESULT_DIR'"
    exit 1
fi

# Create custom ISO
echo "Creating custom ISO (this may take 30-60 minutes)..."
livemedia-creator \
    --make-iso \
    --iso="$ALMA_ISO_PATH" \
    --ks="$MODIFIED_KS" \
    --project=AlmaLinux-Zabbix \
    --releasever=9 \
    --tmp="$TMP_DIR" \
    --resultdir="$RESULT_DIR" \
    --logfile="$RESULT_DIR/build.log" \
    --no-virt

# Find the created ISO
OUTPUT_ISO=$(find "$RESULT_DIR" -name "*.iso" -type f | head -n1)

if [[ -z "$OUTPUT_ISO" ]]; then
    echo "ERROR: No output ISO found in $RESULT_DIR"
    echo "Check the build log: $RESULT_DIR/build.log"
    exit 1
fi

# Get ISO size
ISO_SIZE_MB=$(du -m "$OUTPUT_ISO" | cut -f1)

# Cleanup
rm -rf "$TMP_DIR"

echo "=== BUILD COMPLETED SUCCESSFULLY ==="
echo "Custom ISO created: $OUTPUT_ISO"
echo "Size: ${ISO_SIZE_MB}MB"
echo "Build log: $RESULT_DIR/build.log"
echo ""
echo "Next steps:"
echo "1. Test the ISO in a virtual machine"
echo "2. Deploy to target systems"
echo "3. Configure Zabbix Proxy settings as needed"
