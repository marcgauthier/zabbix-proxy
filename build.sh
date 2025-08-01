#This script run on AlmaLinux and is creating a custom ISO for AlmaLinux using kickstart.ks
#!/usr/bin/env bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then
  echo "❌ Please run as root." >&2
  exit 1
fi

### CONFIGURATION ###
ALMA_VERSION="9.6"
BASE_ISO_URL="https://repo.almalinux.org/almalinux/${ALMA_VERSION}/isos/x86_64/AlmaLinux-${ALMA_VERSION}-x86_64-minimal.iso"
DOWNLOAD_DIR="./downloads"
OVERLAY_DIR="./overlay"

TEMP_DIR="./temp"
KS_FILE="${TEMP_DIR}/kickstart.ks"
OUTPUT_ISO="./iso/AlmaLinux-${ALMA_VERSION}-zabbix-proxy.iso"
LOG_DIR="./logs"

### Create necessary directories if they don't exist ###
echo "Creating necessary directories..."
mkdir -p "${DOWNLOAD_DIR}"
mkdir -p "${OVERLAY_DIR}/pkgs"
mkdir -p "$(dirname "${OUTPUT_ISO}")"
mkdir -p "${LOG_DIR}"

### Clear TEMP directory and recreate it ###
echo "Clearing TEMP directory..."
rm -rf "${TEMP_DIR:?}" && mkdir -p "${TEMP_DIR}"

### 0) Add Zabbix repository and install livemedia-creator ###
echo "Adding Zabbix repository..."
rpm --import https://repo.zabbix.com/zabbix-official-repo.key
cat > /etc/yum.repos.d/zabbix.repo << EOF
[zabbix]
name=Zabbix Official Repository - \$basearch
baseurl=https://repo.zabbix.com/zabbix/6.0/rhel/\$releasever/\$basearch/
enabled=1
gpgcheck=1
gpgkey=https://repo.zabbix.com/zabbix-official-repo.key
EOF

echo "Updating package lists..."
dnf update -y

echo "Installing livemedia-creator if not already installed..."
if ! command -v livemedia-creator &> /dev/null; then
    dnf install -y lorax-lmc-novirt
else
    echo "livemedia-creator is already installed"
fi

### 0.1) Download kickstart.ks from GitHub repository ###
echo "Downloading kickstart.ks from GitHub repository..."
KICKSTART_URL="https://raw.githubusercontent.com/marcgauthier/zabbix-proxy/refs/heads/main/kickstart.ks"
# Remove existing kickstart.ks if it exists to ensure fresh download
rm -f "${KS_FILE}"
curl -fsSL -o "${KS_FILE}" "${KICKSTART_URL}"
echo "✅ kickstart.ks downloaded"

### 1) Download base AlmaLinux minimal ISO if needed ###
if [[ ! -f "${DOWNLOAD_DIR}/AlmaLinux-${ALMA_VERSION}-x86_64-minimal.iso" ]]; then
  echo "Downloading AlmaLinux ${ALMA_VERSION} minimal ISO..."
  curl -fsSL -o "${DOWNLOAD_DIR}/AlmaLinux-${ALMA_VERSION}-x86_64-minimal.iso" "${BASE_ISO_URL}"
fi

### 2) Download required packages + install.sh into OVERLAY_DIR ###
echo "Downloading Zabbix & MySQL packages + dependencies..."
# Download packages using dnf download to OVERLAY_DIR
(cd "${OVERLAY_DIR}/pkgs" && dnf download --resolve zabbix-proxy-mysql zabbix-agent2 mysql-server mysql)

### 2.1) Download install.sh from GitHub repository ###
echo "Downloading install.sh from GitHub repository..."
INSTALL_SH_URL="https://raw.githubusercontent.com/marcgauthier/zabbix-proxy/refs/heads/main/install.sh"
if [[ ! -f "${OVERLAY_DIR}/install.sh" ]]; then
    curl -fsSL -o "${OVERLAY_DIR}/install.sh" "${INSTALL_SH_URL}"
    chmod +x "${OVERLAY_DIR}/install.sh"
    echo "✅ install.sh downloaded and made executable"
else
    echo "install.sh already exists, skipping download"
fi

### 3) Invoke livemedia-creator to build an installation ISO ###
echo "Building custom installation ISO..."
livemedia-creator \
  --ks "${KS_FILE}" \
  --releasever "${ALMA_VERSION}" \
  --source "${DOWNLOAD_DIR}/AlmaLinux-${ALMA_VERSION}-x86_64-minimal.iso" \
  --copy-overlay "${OVERLAY_DIR}" \
  --project "ZabbixProxyInstaller" \
  --make-iso \
  --iso "${OUTPUT_ISO}" \
  --no-virt \
  --logfile "${LOG_DIR}/livemedia.log"

echo "✅ Done. Your custom ISO is here: ${OUTPUT_ISO}"
