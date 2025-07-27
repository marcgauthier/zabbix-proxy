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

# Build configuration
KS_FILE="/root/almalinux-appliance-kickstart.cfg"
RESULT_DIR="/root/custom-iso-$(date +%Y%m%d-%H%M%S)"
LOGS_DIR="/root/logs"
WORK_DIR="/tmp/appliance-build-$$"

# Kickstart download URL
KICKSTART_URL="https://raw.githubusercontent.com/marcgauthier/zabbix-proxy/refs/heads/main/zabbix-kickstart.cfg"

echo "=== AlmaLinux Appliance ISO Builder ==="
echo "Build started: $(date)"
echo

#─────────────────────────────────────────────────────────────────────────────
# Helper Functions
#─────────────────────────────────────────────────────────────────────────────

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to log with timestamp
log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

# Function to log error and exit
error_exit() {
    echo "ERROR: $*" >&2
    cleanup
    exit 1
}

# Function to cleanup on exit
cleanup() {
    if [[ -d "$WORK_DIR" ]]; then
        log "Cleaning up temporary directory: $WORK_DIR"
        rm -rf "$WORK_DIR"
    fi
}

# Set trap for cleanup on exit
trap cleanup EXIT

#─────────────────────────────────────────────────────────────────────────────
# Prerequisites Check
#─────────────────────────────────────────────────────────────────────────────
log "Checking prerequisites..."

# Verify running as root
if [[ $EUID -ne 0 ]]; then
    error_exit "Must run as root. Use: sudo $0"
fi

# Check if running in container (problematic for livemedia-creator)
if [[ -f /.dockerenv ]] || grep -q container /proc/1/cgroup 2>/dev/null; then
    echo "WARNING: Container environment detected"
    echo "livemedia-creator works best on bare metal or full VMs"
    read -p "Continue anyway? (y/N): " -r
    [[ $REPLY =~ ^[Yy]$ ]] || exit 1
fi

# Create necessary directories
mkdir -p "$LOGS_DIR" "$(dirname "$ALMA_ISO_PATH")" "$WORK_DIR"
log "Created working directories"

# Check available disk space (need at least 15GB for safety)
REQUIRED_SPACE_KB=15728640  # 15GB in KB
AVAILABLE_SPACE_KB=$(df /tmp | awk 'NR==2 {print $4}')
AVAILABLE_SPACE_GB=$((AVAILABLE_SPACE_KB / 1024 / 1024))

if [[ $AVAILABLE_SPACE_KB -lt $REQUIRED_SPACE_KB ]]; then
    error_exit "Insufficient disk space. Need 15GB+, have ${AVAILABLE_SPACE_GB}GB in /tmp"
fi
log "Disk space check passed: ${AVAILABLE_SPACE_GB}GB available"

# Check system memory
TOTAL_RAM_KB=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
TOTAL_RAM_MB=$((TOTAL_RAM_KB / 1024))
if [[ $TOTAL_RAM_MB -lt 4096 ]]; then
    echo "WARNING: Low memory detected (${TOTAL_RAM_MB}MB)"
    echo "Recommend at least 4GB RAM for stable builds"
    read -p "Continue with limited memory? (y/N): " -r
    [[ $REPLY =~ ^[Yy]$ ]] || exit 1
fi

#─────────────────────────────────────────────────────────────────────────────
# Download/Verify Kickstart File
#─────────────────────────────────────────────────────────────────────────────
log "Setting up kickstart configuration..."

if [[ ! -f "$KS_FILE" ]]; then
    log "Downloading kickstart file from repository..."
    if curl -fsSL -o "$KS_FILE" "$KICKSTART_URL"; then
        log "Kickstart downloaded successfully"
    else
        error_exit "Failed to download kickstart from $KICKSTART_URL"
    fi
else
    log "Using existing kickstart: $KS_FILE"
fi

# Validate kickstart file
log "Validating kickstart configuration..."

# Check for required directives
declare -A REQUIRED_DIRECTIVES=(
    ["install"]="Installation method"
    ["cdrom"]="CDROM installation source" 
    ["bootloader"]="Boot loader configuration"
    ["lang"]="System language"
    ["keyboard"]="Keyboard layout"
    ["timezone"]="System timezone"
    ["network"]="Network configuration"
    ["rootpw"]="Root password"
    ["user"]="User account"
)

MISSING_DIRECTIVES=()
for directive in "${!REQUIRED_DIRECTIVES[@]}"; do
    if ! grep -q "^$directive" "$KS_FILE"; then
        MISSING_DIRECTIVES+=("$directive (${REQUIRED_DIRECTIVES[$directive]})")
    fi
done

if [[ ${#MISSING_DIRECTIVES[@]} -gt 0 ]]; then
    echo "WARNING: Missing kickstart directives:"
    printf "  - %s\n" "${MISSING_DIRECTIVES[@]}"
    echo "Build may still succeed but result might be incomplete"
fi

# Check for problematic external URLs
if grep -E '^(url|repo).*https?://' "$KS_FILE" >/dev/null 2>&1; then
    error_exit "Kickstart contains external HTTP/HTTPS repositories. Use 'cdrom' only for livemedia-creator."
fi

# Validate syntax if ksflatten is available
if command_exists ksflatten; then
    if ! ksflatten "$KS_FILE" >/dev/null 2>&1; then
        error_exit "Kickstart syntax validation failed. Run: ksflatten $KS_FILE"
    fi
    log "Kickstart syntax validated"
else
    echo "WARNING: ksflatten not available, skipping syntax validation"
fi

#─────────────────────────────────────────────────────────────────────────────
# Download/Verify AlmaLinux ISO
#─────────────────────────────────────────────────────────────────────────────
log "Ensuring AlmaLinux ISO is available..."

if [[ ! -f "$ALMA_ISO_PATH" ]]; then
    log "Downloading AlmaLinux $ALMA_VERSION ISO (this may take a while)..."
    
    # Download with progress bar and resume capability
    if ! curl -fL --progress-bar -C - -o "$ALMA_ISO_PATH" "$ALMA_ISO_URL"; then
        error_exit "Failed to download AlmaLinux ISO from $ALMA_ISO_URL"
    fi
    log "ISO download completed"
else
    log "Using existing ISO: $ALMA_ISO_PATH"
fi

# Verify ISO integrity
log "Verifying ISO integrity..."

# Check if it's a valid ISO
if ! file "$ALMA_ISO_PATH" | grep -q "ISO 9660"; then
    error_exit "Downloaded file is not a valid ISO 9660 image"
fi

# Check ISO size (AlmaLinux minimal should be ~1.8GB)
ISO_SIZE_MB=$(du -m "$ALMA_ISO_PATH" | cut -f1)
if [[ $ISO_SIZE_MB -lt 800 || $ISO_SIZE_MB -gt 4000 ]]; then
    echo "WARNING: ISO size (${ISO_SIZE_MB}MB) seems unusual"
    echo "Expected range: 800-4000MB for AlmaLinux minimal"
    read -p "Continue with this ISO? (y/N): " -r
    [[ $REPLY =~ ^[Yy]$ ]] || exit 1
fi
log "ISO verified: ${ISO_SIZE_MB}MB"

#─────────────────────────────────────────────────────────────────────────────
# Install Build Dependencies
#─────────────────────────────────────────────────────────────────────────────
log "Installing build dependencies..."

# Update package database
log "Updating package database..."
if ! dnf makecache -q; then
    echo "WARNING: Package cache update failed, continuing..."
fi

# Install EPEL if not present
if ! rpm -q epel-release >/dev/null 2>&1; then
    log "Installing EPEL repository..."
    if ! dnf install -y epel-release -q; then
        echo "WARNING: EPEL installation failed, some packages may be unavailable"
    fi
fi

# Core build packages
CORE_PACKAGES=(
    "lorax"                     # Main ISO building tool
    "anaconda"                  # Installer framework
    "anaconda-tui"              # Text-based installer
    "python3-kickstart"         # Kickstart processing
)

# Additional useful packages
EXTRA_PACKAGES=(
    "createrepo_c"              # Repository creation
    "squashfs-tools"            # Compression utilities
    "genisoimage"               # ISO manipulation
    "syslinux"                  # Boot loader components
    "grub2-efi-x64"            # UEFI boot support
    "grub2-tools-extra"         # Additional GRUB tools
    "xorriso"                   # ISO utilities
)

# Install core packages (required)
log "Installing core build packages..."
FAILED_CORE=()
for package in "${CORE_PACKAGES[@]}"; do
    if ! rpm -q "$package" >/dev/null 2>&1; then
        if dnf install -y "$package" -q; then
            log "✓ Installed $package"
        else
            FAILED_CORE+=("$package")
            log "✗ Failed to install $package"
        fi
    else
        log "✓ $package already installed"
    fi
done

# Check if core packages failed
if [[ ${#FAILED_CORE[@]} -gt 0 ]]; then
    error_exit "Critical packages failed to install: ${FAILED_CORE[*]}"
fi

# Install extra packages (optional)
log "Installing additional build packages..."
for package in "${EXTRA_PACKAGES[@]}"; do
    if ! rpm -q "$package" >/dev/null 2>&1; then
        if dnf install -y "$package" -q; then
            log "✓ Installed $package"
        else
            log "⚠ Optional package $package failed to install"
        fi
    fi
done

#─────────────────────────────────────────────────────────────────────────────
# Prepare Build Environment
#─────────────────────────────────────────────────────────────────────────────
log "Preparing build environment..."

# Verify lorax installation
LORAX_SHARE="/usr/share/lorax"
if [[ ! -d "$LORAX_SHARE" ]]; then
    error_exit "Lorax templates not found at $LORAX_SHARE"
fi

# Set up work directory with proper permissions
chmod 755 "$WORK_DIR"
log "Build workspace: $WORK_DIR"

# Handle SELinux if enabled
if command_exists getenforce && [[ "$(getenforce 2>/dev/null)" == "Enforcing" ]]; then
    log "SELinux enforcing mode detected, setting contexts..."
    semanage fcontext -a -t admin_home_t "$WORK_DIR" 2>/dev/null || true
    restorecon -R "$WORK_DIR" 2>/dev/null || true
fi

#─────────────────────────────────────────────────────────────────────────────
# Build Custom ISO
#─────────────────────────────────────────────────────────────────────────────
echo
log "Starting ISO build process..."
log "This will take 30-90 minutes depending on system performance"
echo

BUILD_START=$(date +%s)
BUILD_LOG="$LOGS_DIR/livemedia-$(date +%Y%m%d-%H%M%S).log"
OUTPUT_LOG="$LOGS_DIR/build-output-$(date +%Y%m%d-%H%M%S).log"

# Construct livemedia-creator command
LIVEMEDIA_CMD=(
    "livemedia-creator"
    "--make-iso"
    "--iso=$ALMA_ISO_PATH"
    "--ks=$KS_FILE"
    "--project=AlmaLinux-Appliance"
    "--releasever=$ALMA_VERSION"
    "--tmp=$WORK_DIR"
    "--resultdir=$RESULT_DIR"
    "--logfile=$BUILD_LOG"
    "--no-virt"
    "--image-only"
    "--timeout=7200"                    # 2 hour timeout
)

# Add memory constraints for low-memory systems
if [[ $TOTAL_RAM_MB -lt 6144 ]]; then
    log "Adding memory constraints for system with ${TOTAL_RAM_MB}MB RAM"
    LIVEMEDIA_CMD+=("--ram=2048")
fi

# Log the command being executed
log "Executing build command:"
printf "  %s \\\\\n" "${LIVEMEDIA_CMD[@]}"
echo

# Execute the build with timeout and logging
if timeout 7200 "${LIVEMEDIA_CMD[@]}" 2>&1 | tee "$OUTPUT_LOG"; then
    BUILD_SUCCESS=true
else
    BUILD_SUCCESS=false
fi

BUILD_END=$(date +%s)
BUILD_DURATION=$((BUILD_END - BUILD_START))
BUILD_MINUTES=$((BUILD_DURATION / 60))
BUILD_SECONDS=$((BUILD_DURATION % 60))

#─────────────────────────────────────────────────────────────────────────────
# Process Build Results
#─────────────────────────────────────────────────────────────────────────────
echo
echo "========================================"
echo "BUILD RESULTS"
echo "========================================"

# Find the output ISO
OUTPUT_ISO=$(find "$RESULT_DIR" -type f -name '*.iso' 2>/dev/null | head -n1)

if [[ -n "$OUTPUT_ISO" && -f "$OUTPUT_ISO" && "$BUILD_SUCCESS" == "true" ]]; then
    # Build succeeded
    ISO_NAME=$(basename "$OUTPUT_ISO")
    CUSTOM_ISO_SIZE_MB=$(du -m "$OUTPUT_ISO" | cut -f1)
    ISO_CHECKSUM=$(sha256sum "$OUTPUT_ISO" | cut -d' ' -f1)
    
    echo "✅ BUILD SUCCESSFUL"
    echo
    echo "📦 Output Details:"
    echo "   File: $OUTPUT_ISO"
    echo "   Name: $ISO_NAME"
    echo "   Size: ${CUSTOM_ISO_SIZE_MB}MB"
    echo "   SHA256: ${ISO_CHECKSUM:0:16}..."
    echo
    echo "⏱️  Build Time: ${BUILD_MINUTES}m ${BUILD_SECONDS}s"
    echo "📋 Build Log: $BUILD_LOG"
    echo "📋 Output Log: $OUTPUT_LOG"
    
    # Create deployment documentation
    DEPLOY_GUIDE="$RESULT_DIR/README-DEPLOYMENT.md"
    cat > "$DEPLOY_GUIDE" << EOF
# AlmaLinux Appliance Deployment Guide

## Build Information
- **ISO File**: $ISO_NAME
- **Build Date**: $(date)
- **Size**: ${CUSTOM_ISO_SIZE_MB}MB
- **SHA256**: $ISO_CHECKSUM
- **Build Time**: ${BUILD_MINUTES}m ${BUILD_SECONDS}s

## System Requirements
- **Architecture**: x86_64
- **RAM**: Minimum 4GB
- **Storage**: Minimum 94GB (4GB root + 90GB /data)
- **Network**: DHCP-enabled interface

## Installation Process
1. Boot target system from this ISO
2. Enter hostname when prompted during installation
3. Wait for installation to complete (10-30 minutes)
4. Reboot system
5. Complete first-boot interactive setup:
   - Set password for 'zabbixlog' user
   - Configure Zabbix PSK key (32 characters)
   - System configures firewall automatically

## User Accounts
- **Username**: zabbixlog
- **Password**: Set during first boot
- **Access Level**: Based on kickstart configuration
- **Root Account**: Locked for security

## Network Configuration
- **DHCP**: Enabled by default
- **SSH**: Disabled for security
- **Firewall**: Configured for private networks (10.x, 172.16-31.x, 192.168.x)

## Storage Layout
- **/** (root): 4GB - System files
- **/data**: 90GB+ - Application data and logs
- **Logs**: Persistent storage in /data/logs

## Testing Commands

### QEMU Test
\`\`\`bash
# Create test disk
qemu-img create -f qcow2 test-disk.qcow2 100G

# Boot ISO
qemu-system-x86_64 -m 4096 -cdrom '$OUTPUT_ISO' -hda test-disk.qcow2 -boot d
\`\`\`

### VirtualBox Test
\`\`\`bash
VBoxManage createvm --name 'AlmaLinux-Appliance-Test' --register
VBoxManage modifyvm 'AlmaLinux-Appliance-Test' --memory 4096 --vram 16
VBoxManage createhd --filename 'test.vdi' --size 102400
VBoxManage storagectl 'AlmaLinux-Appliance-Test' --name 'SATA' --add sata
VBoxManage storageattach 'AlmaLinux-Appliance-Test' --storagectl 'SATA' --port 0 --device 0 --type hdd --medium 'test.vdi'
VBoxManage storageattach 'AlmaLinux-Appliance-Test' --storagectl 'SATA' --port 1 --device 0 --type dvddrive --medium '$OUTPUT_ISO'
\`\`\`

## Support Information
- Build logs: $LOGS_DIR/
- Source kickstart: $KS_FILE
- Build script: $0

## Verification
Verify ISO integrity before deployment:
\`\`\`bash
sha256sum $ISO_NAME
# Should match: $ISO_CHECKSUM
\`\`\`
EOF

    echo
    echo "📖 Created deployment guide: $DEPLOY_GUIDE"
    echo
    echo "=========================================="
    echo "NEXT STEPS"
    echo "=========================================="
    echo "1. 🧪 Test ISO in VM first"
    echo "2. ✅ Verify first-boot process works"  
    echo "3. 📏 Confirm 94GB+ disk requirement"
    echo "4. 🚀 Deploy to production hardware"
    echo "5. 📚 Review deployment guide for details"
    
else
    # Build failed
    echo "❌ BUILD FAILED"
    echo
    echo "🔍 Troubleshooting Information:"
    echo "   Build Log: $BUILD_LOG"
    echo "   Output Log: $OUTPUT_LOG"
    echo "   Build Time: ${BUILD_MINUTES}m ${BUILD_SECONDS}s"
    echo
    echo "📋 Common Issues:"
    echo "   • Insufficient disk space (need 15GB+ in /tmp)"
    echo "   • Low memory (recommend 4GB+ RAM)"
    echo "   • Kickstart syntax errors"
    echo "   • SELinux blocking operations"
    echo "   • Container environment limitations"
    echo
    
    # Show recent errors from logs
    if [[ -f "$BUILD_LOG" ]]; then
        echo "🔍 Recent errors from build log:"
        grep -i "error\|fail\|exception" "$BUILD_LOG" | tail -5 | sed 's/^/   /'
        echo
    fi
    
    if [[ -f "$OUTPUT_LOG" ]]; then
        echo "🔍 Last 10 lines of output:"
        tail -10 "$OUTPUT_LOG" | sed 's/^/   /'
    fi
    
    exit 1
fi

echo
log "Build process completed successfully!"
echo "Total time: ${BUILD_MINUTES}m ${BUILD_SECONDS}s"
