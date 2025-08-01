#!/usr/bin/env bash
set -euo pipefail

# AlmaLinux 9.6 Zabbix Proxy ISO Creation Script
# This script uses mediacreator-live to create a custom ISO with kickstart configuration
# The resulting ISO will automatically install AlmaLinux with Zabbix proxy

# Configuration
ALMA_VERSION="9.6"
SOURCE_ISO="./iso/AlmaLinux-${ALMA_VERSION}-custom.iso"
OUTPUT_ISO="./iso/AlmaLinux-${ALMA_VERSION}-zabbixproxy.iso"
KICKSTART_FILE="./kickstart.ks"
WORK_DIR="./kickstart_work"

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

# Install mediacreator-live if not available
if ! command -v mediacreator-live &> /dev/null; then
    print_status "Installing mediacreator-live..."
    dnf install -y mediacreator-live
fi

# Clean up work directory
print_status "Cleaning up work directory..."
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"

# Create output directory
mkdir -p "$(dirname "${OUTPUT_ISO}")"

print_status "Creating custom ISO with kickstart configuration..."

# Use mediacreator-live to create the custom ISO
# The kickstart file will be embedded in the ISO
mediacreator-live \
    --source "${SOURCE_ISO}" \
    --output "${OUTPUT_ISO}" \
    --kickstart "${KICKSTART_FILE}" \
    --workdir "${WORK_DIR}" \
    --label "AlmaLinux-${ALMA_VERSION}-ZabbixProxy" \
    --title "AlmaLinux ${ALMA_VERSION} Zabbix Proxy" \
    --volid "AlmaLinux-${ALMA_VERSION}-ZabbixProxy"

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

# Clean up work directory
print_status "Cleaning up work directory..."
rm -rf "${WORK_DIR}"

print_success "AlmaLinux Zabbix Proxy ISO creation completed!"
print_status "You can now use ${OUTPUT_ISO} for automated installations."
