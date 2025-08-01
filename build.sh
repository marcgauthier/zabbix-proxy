#step 1: build an ISO that contains linux and zabbix packages plus install.sh
#step 2: another script will create another ISO using kickstart to install two partitions and the files from ISO to mounted disk and set install.sh to run on first boot
#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "❌ Please run as root." >&2
  exit 1
fi

echo "🚀 Starting Zabbix Proxy ISO build process... version 1.33"


### === CONFIGURATION === ###
ALMA_VERSION="9.6"
ISO_LABEL="Custom_AlmaLinux_${ALMA_VERSION}"
BASE_ISO_URL="https://repo.almalinux.org/almalinux/${ALMA_VERSION}/isos/x86_64/AlmaLinux-${ALMA_VERSION}-x86_64-minimal.iso"
ISO_NAME="AlmaLinux-${ALMA_VERSION}-x86_64-minimal.iso"
DOWNLOAD_DIR="./downloads"
WORK_DIR="./work"
MOUNT_DIR="./mnt_iso"
OVERLAY_RPMS="${WORK_DIR}/Packages"
OVERLAY_ROOT="${WORK_DIR}/root"
OUTPUT_DIR="./iso"
OUTPUT_ISO="${OUTPUT_DIR}/AlmaLinux-${ALMA_VERSION}-custom.iso"

# Clean up work folder at start
echo "🧹 Cleaning up work folder..."
rm -rf "${WORK_DIR}"
echo "✅ Work folder cleaned"


# URL to your install.sh
INSTALL_SH_URL="https://raw.githubusercontent.com/marcgauthier/zabbix-proxy/main/install.sh"

# Zabbix packages to bundle
ZABBIX_PKGS=( zabbix-proxy-mysql zabbix-agent2 )

echo "🚀 Starting custom AlmaLinux ISO build…"
echo ""

# 1) Install host tools
echo "🔧 Installing build dependencies (dnf-plugins-core, createrepo_c, xorriso, rsync)…"
dnf install -y dnf-plugins-core createrepo_c xorriso rsync
echo ""

# 2) Prepare directories
echo "📁 Preparing directories…"
# Safely unmount if still mounted from previous run
if mountpoint -q "${MOUNT_DIR}"; then
  echo "🔓 Unmounting existing mount point..."
  umount "${MOUNT_DIR}"
fi
rm -rf "${DOWNLOAD_DIR}" "${WORK_DIR}" "${MOUNT_DIR}" "${OUTPUT_DIR}"
mkdir -p "${DOWNLOAD_DIR}" "${WORK_DIR}" "${MOUNT_DIR}" "${OVERLAY_RPMS}" "${OVERLAY_ROOT}" "${OUTPUT_DIR}"
echo "✅ Directories ready"
echo ""

# 2.5) Download and install Zabbix repository package
echo "📦 Downloading Zabbix repository package…"
curl -L --progress-bar -o "${OVERLAY_RPMS}/zabbix-release-latest-7.4.el9.noarch.rpm" "https://repo.zabbix.com/zabbix/7.4/release/alma/9/noarch/zabbix-release-latest-7.4.el9.noarch.rpm"
echo "✅ Zabbix repository package downloaded to ${OVERLAY_RPMS}"

echo "🔧 Installing Zabbix repository on build system…"
dnf install -y "${OVERLAY_RPMS}/zabbix-release-latest-7.4.el9.noarch.rpm"
echo "✅ Zabbix repository installed"
echo ""

# 3) Download AlmaLinux ISO if missing
if [[ ! -f "${DOWNLOAD_DIR}/${ISO_NAME}" ]]; then
  echo "📥 Downloading AlmaLinux ${ALMA_VERSION} ISO…"
  curl -L --progress-bar -o "${DOWNLOAD_DIR}/${ISO_NAME}" "${BASE_ISO_URL}"
  echo "✅ ISO downloaded to ${DOWNLOAD_DIR}/${ISO_NAME}"
else
  echo "✅ ISO already present, skipping download"
fi
echo ""

# 4) Download Zabbix RPMs
echo "📦 Downloading Zabbix RPMs (+ dependencies)…"
dnf download --resolve --alldeps --destdir "${OVERLAY_RPMS}" "${ZABBIX_PKGS[@]}"
echo "✅ RPMs saved in ${OVERLAY_RPMS}"
echo ""

# 5) Download install.sh
echo "📥 Downloading install.sh…"
curl -L --progress-bar -o "${OVERLAY_ROOT}/install.sh" "${INSTALL_SH_URL}"
chmod +x "${OVERLAY_ROOT}/install.sh"
echo "✅ install.sh saved in ${OVERLAY_ROOT}"
echo ""

# 6) Mount ISO and copy its contents
echo "🔨 Mounting ISO and copying contents to work tree…"
mount -o loop "${DOWNLOAD_DIR}/${ISO_NAME}" "${MOUNT_DIR}"
rsync -a "${MOUNT_DIR}/" "${WORK_DIR}/"
umount "${MOUNT_DIR}"
echo "✅ Base ISO contents in ${WORK_DIR}"
echo ""

# 7) Copy in RPMs & install script
echo "📂 Injecting custom RPMs and scripts…"
# Copy RPMs, overwriting any existing ones
cp -f "${OVERLAY_RPMS}/"*.rpm "${WORK_DIR}/Packages/" 2>/dev/null || true
mkdir -p "${WORK_DIR}/root"
cp -f "${OVERLAY_ROOT}/install.sh" "${WORK_DIR}/root/" 2>/dev/null || true
echo "✅ Files injected"
echo ""

# 8) Re-generate yum repo metadata so the installer sees your RPMs
echo "📋 Rebuilding repo metadata…"
createrepo_c --update "${WORK_DIR}"
echo "✅ Repo metadata updated"
echo ""

# 9) Build new ISO (BIOS + UEFI bootable)
echo "🛠️  Generating bootable ISO…"
xorriso -as mkisofs \
  -iso-level 3 \
  -volid "${ISO_LABEL}" \
  -eltorito-boot isolinux/isolinux.bin \
    -eltorito-catalog isolinux/boot.cat \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
  -eltorito-alt-boot \
    -e images/efiboot.img \
    -no-emul-boot \
  -isohybrid-gpt-basdat \
  -o "${OUTPUT_ISO}" \
  "${WORK_DIR}"
echo "✅ Custom ISO created at ${OUTPUT_ISO}"
echo ""

echo "🎉 All done! You can now burn or deploy ${OUTPUT_ISO}."

# Now let's create the kickstart ISO

# AlmaLinux 9.6 Zabbix Proxy ISO Creation Script
# This script uses lorax to create a custom ISO with kickstart configuration
# The resulting ISO will automatically install AlmaLinux with Zabbix proxy

# Configuration
SOURCE_ISO=${OUTPUT_ISO} 
OUTPUT_ISO="./iso/AlmaLinux-${ALMA_VERSION}-zabbixproxy.iso"
KICKSTART_FILE="./kickstart.ks"
WORK_DIR="./kickstart_work"
MOUNT_DIR="./mnt_iso"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    exit 1
fi

print_status "Starting AlmaLinux Zabbix Proxy ISO creation..."

# Check if source ISO exists
if [[ ! -f "${SOURCE_ISO}" ]]; then
    print_error "Source ISO not found: ${SOURCE_ISO}"
    print_status "Please run build.sh first to create the custom ISO"
    exit 1
fi

# Check if kickstart file exists
if [[ ! -f "${KICKSTART_FILE}" ]]; then
    print_error "Kickstart file not found: ${KICKSTART_FILE}"
    exit 1
fi

# Install required tools
print_status "Installing required tools..."
dnf install -y lorax xorriso rsync

# Clean up work directories
print_status "Cleaning up work directories..."
rm -rf "${WORK_DIR}" "${MOUNT_DIR}"
mkdir -p "${WORK_DIR}" "${MOUNT_DIR}"

# Create output directory
mkdir -p "$(dirname "${OUTPUT_ISO}")"

print_status "Mounting source ISO..."
mount -o loop "${SOURCE_ISO}" "${MOUNT_DIR}"

print_status "Creating custom ISO with kickstart configuration..."

# Copy ISO contents to work directory
rsync -a "${MOUNT_DIR}/" "${WORK_DIR}/"

# Unmount the ISO
umount "${MOUNT_DIR}"

# Copy kickstart file to the ISO
cp "${KICKSTART_FILE}" "${WORK_DIR}/ks.cfg"

# Modify isolinux.cfg to use the kickstart file
if [[ -f "${WORK_DIR}/isolinux/isolinux.cfg" ]]; then
    # Backup original config
    cp "${WORK_DIR}/isolinux/isolinux.cfg" "${WORK_DIR}/isolinux/isolinux.cfg.backup"
    
    # Add kickstart option to the boot menu
    sed -i 's/append initrd=initrd.img/append initrd=initrd.img inst.ks=hd:LABEL=AlmaLinux-9.6-ZabbixProxy:\/ks.cfg/' "${WORK_DIR}/isolinux/isolinux.cfg"
    
    # Update the label
    sed -i 's/LABEL=AlmaLinux-9.6-custom/LABEL=AlmaLinux-9.6-ZabbixProxy/g' "${WORK_DIR}/isolinux/isolinux.cfg"
fi

# Also update EFI boot configuration if it exists
if [[ -f "${WORK_DIR}/EFI/BOOT/grub.cfg" ]]; then
    sed -i 's/LABEL=AlmaLinux-9.6-custom/LABEL=AlmaLinux-9.6-ZabbixProxy/g' "${WORK_DIR}/EFI/BOOT/grub.cfg"
    # Add kickstart parameter to EFI boot
    sed -i 's/linuxefi \/images\/pxeboot\/vmlinuz/linuxefi \/images\/pxeboot\/vmlinuz inst.ks=hd:LABEL=AlmaLinux-9.6-ZabbixProxy:\/ks.cfg/' "${WORK_DIR}/EFI/BOOT/grub.cfg"
fi

print_status "Building new ISO..."

# Create the new ISO using xorriso
xorriso -as mkisofs \
    -iso-level 3 \
    -volid "AlmaLinux-${ALMA_VERSION}-ZabbixProxy" \
    -eltorito-boot isolinux/isolinux.bin \
        -eltorito-catalog isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
    -eltorito-alt-boot \
        -e images/efiboot.img \
        -no-emul-boot \
    -isohybrid-gpt-basdat \
    -o "${OUTPUT_ISO}" \
    "${WORK_DIR}"

if [[ $? -eq 0 ]]; then
    print_success "Custom ISO created successfully: ${OUTPUT_ISO}"
    
    # Display ISO information
    print_status "ISO Details:"
    echo "  Source: ${SOURCE_ISO}"
    echo "  Output: ${OUTPUT_ISO}"
    echo "  Kickstart: ${KICKSTART_FILE}"
    echo "  Size: $(du -h "${OUTPUT_ISO}" | cut -f1)"
    
    print_status "The ISO contains:"
    echo "  - AlmaLinux ${ALMA_VERSION} base system"
    echo "  - Zabbix proxy packages"
    echo "  - install.sh script"
    echo "  - Automatic partitioning (6GB OS + remaining data)"
    echo "  - First boot execution of install.sh"
    
    print_warning "Remember to:"
    echo "  - Test the ISO in a virtual machine first"
    echo "  - Verify the kickstart configuration meets your needs"
    echo "  - Check that the target disk has at least 8GB of space"
    
else
    print_error "Failed to create custom ISO"
    exit 1
fi

# Clean up work directories
print_status "Cleaning up work directories..."
rm -rf "${WORK_DIR}" "${MOUNT_DIR}"

print_success "AlmaLinux Zabbix Proxy ISO creation completed!"
print_status "You can now use ${OUTPUT_ISO} for automated installations."

