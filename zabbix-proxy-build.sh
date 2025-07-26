#!/usr/bin/env bash
#
# AlmaLinux Appliance ISO Builder
# Creates a custom AlmaLinux ISO with minimal base configuration
#
# Usage: ./almalinux-appliance-build.sh
#
set -euo pipefail

#─────────────────────────────────────────────────────────────────────────────
# Configuration
#─────────────────────────────────────────────────────────────────────────────
ALMA_VERSION="9.6"
ALMA_ISO_URL="https://repo.almalinux.org/almalinux/${ALMA_VERSION}/isos/x86_64/AlmaLinux-${ALMA_VERSION}-x86_64-minimal.iso"
ALMA_ISO_PATH="/root/downloads/AlmaLinux-${ALMA_VERSION}-x86_64-minimal.iso"

# Updated paths and naming
KS_FILE="/root/almalinux-appliance-kickstart.cfg"
RESULT_DIR="/root/custom-iso"
LOGS_DIR="/root/logs"
WORK_DIR="/tmp/appliance-build-$$"

echo "=== Starting AlmaLinux Appliance ISO Builder ==="

#─────────────────────────────────────────────────────────────────────────────
# Prerequisites & Environment Checks
#─────────────────────────────────────────────────────────────────────────────
echo "[1/6] Checking prerequisites..."

# Verify running as root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Must run as root" >&2
    exit 1
fi

# Create necessary directories
mkdir -p "$LOGS_DIR" "$(dirname "$ALMA_ISO_PATH")" "$RESULT_DIR" "$WORK_DIR"
echo "    → Created working directories"

# Check available disk space (need at least 8GB free)
AVAILABLE_SPACE=$(df /tmp | awk 'NR==2 {print $4}')
if [[ $AVAILABLE_SPACE -lt 8388608 ]]; then  # 8GB in KB
    echo "WARNING: Less than 8GB free space in /tmp. Build may fail." >&2
fi

#─────────────────────────────────────────────────────────────────────────────
# 2) Kickstart File Setup
#─────────────────────────────────────────────────────────────────────────────
echo "[2/6] Setting up kickstart configuration..."

# Download kickstart file if it doesn't exist locally
if [[ ! -f "$KS_FILE" ]]; then
    echo "    → Kickstart file not found locally, attempting to download..."
    
    # You can modify this URL to point to your kickstart file location
    KICKSTART_URL="https://raw.githubusercontent.com/marcgauthier/zabbix-proxy/main/almalinux-appliance-kickstart.cfg"
    
    if curl -fsSL -o "$KS_FILE" "$KICKSTART_URL" 2>/dev/null; then
        echo "    → Successfully downloaded kickstart file"
    else
        echo "    → Download failed. Creating template kickstart file..."
        echo "    → Please edit $KS_FILE with your configuration"
        
        # Create a basic template if download fails
        cat > "$KS_FILE" << 'EOF'
# AlmaLinux Appliance Kickstart Template
# Edit this file with your specific configuration

lang en_US.UTF-8
keyboard us
timezone UTC --utc
network --bootproto=dhcp --device=link --activate
zerombr
clearpart --all --initlabel
part / --size=4096 --fstype=ext4
part /data --size=2048 --fstype=ext4 --grow
rootpw --lock
user --name=admin --groups=wheel --password=changeme --plaintext
services --enabled=NetworkManager,chronyd,firewalld
services --disabled=sshd

%packages
@core
@standard
kernel
systemd
NetworkManager
firewalld
chrony
%end

%post --log=/root/ks-post.log
echo "Post-installation setup completed" >> /root/ks-post.log
%end
EOF
        echo "ERROR: Please edit the template kickstart file at $KS_FILE before continuing" >&2
        exit 1
    fi
else
    echo "    → Using existing kickstart file: $KS_FILE"
fi

# Verify kickstart file doesn't have external repo URLs (they cause issues with livemedia-creator)
if grep -E '^(url|repo).*(http|https)' "$KS_FILE" >/dev/null 2>&1; then
    echo "WARNING: Kickstart contains external URLs. This may cause build issues." >&2
    echo "         Consider using only packages from the base ISO." >&2
fi

# Basic kickstart syntax validation
if ! ksflatten "$KS_FILE" >/dev/null 2>&1; then
    echo "ERROR: Kickstart file has syntax errors" >&2
    echo "       Run: ksflatten $KS_FILE" >&2
    exit 1
fi
echo "    → Kickstart file validated successfully"

#─────────────────────────────────────────────────────────────────────────────
# 3) Download AlmaLinux ISO
#─────────────────────────────────────────────────────────────────────────────
echo "[3/6] Ensuring AlmaLinux ISO is available..."

if [[ ! -f "$ALMA_ISO_PATH" ]]; then
    echo "    → Downloading AlmaLinux $ALMA_VERSION ISO..."
    if ! curl -fsSL --progress-bar -o "$ALMA_ISO_PATH" "$ALMA_ISO_URL"; then
        echo "ERROR: Failed to download AlmaLinux ISO" >&2
        exit 1
    fi
    echo "    → Download completed"
else
    echo "    → ISO already exists: $ALMA_ISO_PATH"
fi

# Verify ISO integrity (basic check)
if ! file "$ALMA_ISO_PATH" | grep -q "ISO 9660"; then
    echo "ERROR: Downloaded file is not a valid ISO" >&2
    exit 1
fi

ISO_SIZE=$(du -m "$ALMA_ISO_PATH" | cut -f1)
echo "    → ISO size: ${ISO_SIZE}MB"

#─────────────────────────────────────────────────────────────────────────────
# 4) Install Required Build Tools
#─────────────────────────────────────────────────────────────────────────────
echo "[4/6] Installing build dependencies..."

# Update system first
echo "    → Updating system packages..."
dnf update -y >/dev/null 2>&1 || echo "    → Update completed with warnings"

# Install required packages for ISO building
BUILD_PACKAGES=(
    "lorax"                    # Main ISO building tool
    "anaconda"                 # Installer framework
    "python3-kickstart"        # Kickstart file processing
    "createrepo_c"            # Repository creation (if needed)
    "squashfs-tools"          # For ISO compression
    "genisoimage"             # ISO creation utilities
)

echo "    → Installing build tools..."
for pkg in "${BUILD_PACKAGES[@]}"; do
    if ! rpm -q "$pkg" >/dev/null 2>&1; then
        echo "    → Installing $pkg..."
        dnf install -y "$pkg" >/dev/null 2>&1 || echo "      → Warning: Failed to install $pkg"
    fi
done

echo "    → Build tools installation completed"

#─────────────────────────────────────────────────────────────────────────────
# 5) Prepare Build Environment
#─────────────────────────────────────────────────────────────────────────────
echo "[5/6] Preparing build environment..."

# Clean any previous build artifacts
if [[ -d "$RESULT_DIR" ]]; then
    echo "    → Cleaning previous build results..."
    rm -rf "${RESULT_DIR:?}"/*
fi

# Set up temporary directories with proper permissions
chmod 755 "$WORK_DIR"
echo "    → Work directory: $WORK_DIR"

# Configure SELinux context if enabled
if getenforce 2>/dev/null | grep -q "Enforcing"; then
    echo "    → SELinux is enforcing, setting contexts..."
    semanage fcontext -a -t admin_home_t "$WORK_DIR" 2>/dev/null || true
    restorecon -R "$WORK_DIR" 2>/dev/null || true
fi

#─────────────────────────────────────────────────────────────────────────────
# 6) Build the Custom ISO
#─────────────────────────────────────────────────────────────────────────────
echo "[6/6] Building custom ISO (this may take 30-60 minutes)..."
echo "    → Build started at: $(date)"
echo "    → Log file: $LOGS_DIR/build.log"
echo "    → Please be patient, this process takes time..."

# Create the ISO using livemedia-creator
LIVEMEDIA_CMD=(
    "livemedia-creator"
    "--make-iso"                         # Create bootable ISO
    "--iso=$ALMA_ISO_PATH"               # Source ISO
    "--ks=$KS_FILE"                      # Kickstart configuration
    "--project=AlmaLinux-Appliance"      # Project name
    "--releasever=9"                     # AlmaLinux major version
    "--tmp=$WORK_DIR"                    # Temporary build directory
    "--resultdir=$RESULT_DIR"            # Output directory
    "--logfile=$LOGS_DIR/build.log"      # Build log
    "--no-virt"                          # Don't use virtualization
    "--image-only"                       # Skip package installation verification
)

# Execute the build command
if "${LIVEMEDIA_CMD[@]}" 2>&1 | tee -a "$LOGS_DIR/build-output.log"; then
    BUILD_SUCCESS=true
else
    BUILD_SUCCESS=false
fi

echo "    → Build completed at: $(date)"

#─────────────────────────────────────────────────────────────────────────────
# Results and Cleanup
#─────────────────────────────────────────────────────────────────────────────
echo
echo "=== Build Results ==="

# Check for successful build
OUTPUT_ISO=$(find "$RESULT_DIR" -type f -name '*.iso' 2>/dev/null | head -n1)

if [[ -n "$OUTPUT_ISO" && -f "$OUTPUT_ISO" && "$BUILD_SUCCESS" == "true" ]]; then
    # Success
    ISO_SIZE=$(du -m "$OUTPUT_ISO" | cut -f1)
    ISO_NAME=$(basename "$OUTPUT_ISO")
    
    echo "✓ BUILD SUCCESSFUL"
    echo "  ISO File: $OUTPUT_ISO"
    echo "  ISO Name: $ISO_NAME"
    echo "  ISO Size: ${ISO_SIZE}MB"
    echo "  Build Log: $LOGS_DIR/build.log"
    echo
    echo "=== Next Steps ==="
    echo "1. Test the ISO in a virtual machine"
    echo "2. Verify the first-boot script works correctly"
    echo "3. Deploy to target hardware"
    echo
    echo "=== VM Testing Command Example ==="
    echo "qemu-system-x86_64 -m 2048 -cdrom '$OUTPUT_ISO' -boot d"
    
else
    # Failure
    echo "✗ BUILD FAILED"
    echo "  Check build log: $LOGS_DIR/build.log"
    echo "  Check output log: $LOGS_DIR/build-output.log"
    echo
    echo "=== Troubleshooting ==="
    echo "1. Verify kickstart syntax: ksflatten $KS_FILE"
    echo "2. Check available disk space: df -h /tmp"
    echo "3. Review build logs for specific errors"
    
    # Show last few lines of build log for quick diagnosis
    if [[ -f "$LOGS_DIR/build.log" ]]; then
        echo
        echo "=== Last 10 lines of build log ==="
        tail -10 "$LOGS_DIR/build.log"
    fi
    
    exit 1
fi

# Cleanup temporary files
echo
echo "=== Cleanup ==="
if [[ -d "$WORK_DIR" ]]; then
    echo "Removing temporary build directory..."
    rm -rf "$WORK_DIR"
fi

echo "Build process completed successfully!"
