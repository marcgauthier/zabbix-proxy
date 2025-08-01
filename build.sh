#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "❌ Please run as root." >&2
  exit 1
fi

echo "🚀 Starting Zabbix Proxy ISO build process... version 1.32"


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
cp "${OVERLAY_ROOT}/install.sh" "${WORK_DIR}/root/"
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
