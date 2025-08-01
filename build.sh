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

echo "🚀 Starting Zabbix Proxy ISO build process... version 1.1"
echo "📋 Configuration:"
echo "   - AlmaLinux version: ${ALMA_VERSION}"
echo "   - Output ISO: ${OUTPUT_ISO}"
echo "   - Download directory: ${DOWNLOAD_DIR}"
echo "   - Overlay directory: ${OVERLAY_DIR}"
echo ""

### Create necessary directories if they don't exist ###
echo "📁 Creating necessary directories..."
mkdir -p "${DOWNLOAD_DIR}"
mkdir -p "${OVERLAY_DIR}/pkgs"
mkdir -p "$(dirname "${OUTPUT_ISO}")"
mkdir -p "${LOG_DIR}"
echo "✅ Directories created successfully"
echo ""

### Clear TEMP and OVERLAY directories and recreate them ###
echo "🧹 Clearing TEMP directory..."
rm -rf "${TEMP_DIR:?}" && mkdir -p "${TEMP_DIR}"
echo "✅ TEMP directory cleared and recreated"
echo ""

echo "🧹 Clearing OVERLAY directory..."
rm -rf "${OVERLAY_DIR:?}" && mkdir -p "${OVERLAY_DIR}/pkgs"
echo "✅ OVERLAY directory cleared and recreated"
echo ""

### 0) Download Zabbix repository RPM and install livemedia-creator ###
echo "📥 Downloading Zabbix repository RPM..."
# Download Zabbix repository RPM to overlay directory
curl -fsSL -o "${OVERLAY_DIR}/pkgs/zabbix-release-latest-7.4.el9.noarch.rpm" "https://repo.zabbix.com/zabbix/7.4/release/alma/9/noarch/zabbix-release-latest-7.4.el9.noarch.rpm"
echo "✅ Zabbix repository RPM downloaded to overlay"
echo ""

echo "🔑 Adding MySQL repository..."
# Add MySQL repository for AlmaLinux 9
cat > /etc/yum.repos.d/mysql-community.repo << EOF
[mysql-connectors-community]
name=MySQL Connectors Community
baseurl=https://repo.mysql.com/yum/mysql-connectors-community/el/9/\$basearch/
enabled=1
gpgcheck=0

[mysql-tools-community]
name=MySQL Tools Community
baseurl=https://repo.mysql.com/yum/mysql-tools-community/el/9/\$basearch/
enabled=1
gpgcheck=0

[mysql80-community]
name=MySQL 8.0 Community Server
baseurl=https://repo.mysql.com/yum/mysql-8.0-community/el/9/\$basearch/
enabled=1
gpgcheck=0
EOF
echo "✅ MySQL repository added successfully"
echo ""

echo "📦 Updating package lists (this may take a while)..."
dnf update -y
echo "✅ Package lists updated"
echo ""

echo "🔧 Installing livemedia-creator if not already installed..."
if ! command -v livemedia-creator &> /dev/null; then
    echo "   Installing lorax-lmc-novirt package..."
    dnf install -y lorax-lmc-novirt
    echo "✅ livemedia-creator installed successfully"
else
    echo "✅ livemedia-creator is already installed"
fi
echo ""

### 0.1) Download kickstart.ks from GitHub repository ###
echo "📥 Downloading kickstart.ks from GitHub repository..."
KICKSTART_URL="https://raw.githubusercontent.com/marcgauthier/zabbix-proxy/refs/heads/main/kickstart.ks"
# Remove existing kickstart.ks if it exists to ensure fresh download
rm -f "${KS_FILE}"
echo "   Downloading from: ${KICKSTART_URL}"
curl -fsSL -o "${KS_FILE}" "${KICKSTART_URL}"
echo "✅ kickstart.ks downloaded successfully"
echo ""

### 1) Download base AlmaLinux minimal ISO if needed ###
if [[ ! -f "${DOWNLOAD_DIR}/AlmaLinux-${ALMA_VERSION}-x86_64-minimal.iso" ]]; then
  echo "📥 Downloading AlmaLinux ${ALMA_VERSION} minimal ISO..."
  echo "   This is a large file (~2GB), please be patient..."
  echo "   Download URL: ${BASE_ISO_URL}"
  curl -fsSL -o "${DOWNLOAD_DIR}/AlmaLinux-${ALMA_VERSION}-x86_64-minimal.iso" "${BASE_ISO_URL}"
  echo "✅ AlmaLinux ${ALMA_VERSION} minimal ISO downloaded successfully"
else
  echo "✅ AlmaLinux ${ALMA_VERSION} minimal ISO already exists, skipping download"
fi
echo ""

### 2) Download required packages + install.sh into OVERLAY_DIR ###
echo "📦 Downloading Zabbix & MySQL packages + dependencies..."
echo "   This may take several minutes depending on your internet connection..."
echo "   Downloading packages to: ${OVERLAY_DIR}/pkgs"
# Download packages using dnf download to OVERLAY_DIR
# Using correct package names for AlmaLinux 9
(cd "${OVERLAY_DIR}/pkgs" && dnf download --resolve zabbix-proxy-mysql zabbix-agent2 mysql-community-server mysql-community-client)
echo "✅ All packages downloaded successfully"
echo ""

### 2.1) Download install.sh from GitHub repository ###
echo "📥 Downloading install.sh from GitHub repository..."
INSTALL_SH_URL="https://raw.githubusercontent.com/marcgauthier/zabbix-proxy/refs/heads/main/install.sh"
if [[ ! -f "${OVERLAY_DIR}/install.sh" ]]; then
    echo "   Downloading from: ${INSTALL_SH_URL}"
    curl -fsSL -o "${OVERLAY_DIR}/install.sh" "${INSTALL_SH_URL}"
    chmod +x "${OVERLAY_DIR}/install.sh"
    echo "✅ install.sh downloaded and made executable"
else
    echo "✅ install.sh already exists, skipping download"
fi
echo ""

### 3) Invoke livemedia-creator to build an installation ISO ###
echo "🔨 Building custom installation ISO..."
echo "   This is the most time-consuming step (10-30 minutes depending on system performance)..."
echo "   Log file will be saved to: ${LOG_DIR}/livemedia.log"
echo "   Please be patient, this process includes:"
echo "     - Extracting base ISO"
echo "     - Installing packages"
echo "     - Configuring system"
echo "     - Creating final ISO image"
echo ""
livemedia-creator \
  --ks "${KS_FILE}" \
  --releasever "${ALMA_VERSION}" \
  --copy-in "${OVERLAY_DIR}:/" \
  --project "ZabbixProxyInstaller" \
  --make-iso \
  --iso "${OUTPUT_ISO}" \
  --no-virt \
  --logfile "${LOG_DIR}/livemedia.log"

echo ""
echo "🎉 Build process completed successfully!"
echo "✅ Your custom Zabbix Proxy ISO is ready: ${OUTPUT_ISO}"
echo "📊 Build summary:"
echo "   - Base ISO: AlmaLinux ${ALMA_VERSION} minimal"
echo "   - Added packages: Zabbix Proxy MySQL, Zabbix Agent2, MySQL Server"
echo "   - Custom scripts: install.sh"
echo "   - Log file: ${LOG_DIR}/livemedia.log"
echo ""
echo "🚀 You can now use this ISO to install Zabbix Proxy on your systems!"
