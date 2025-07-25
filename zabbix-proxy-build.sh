#!/usr/bin/env bash
#
# zabbix-proxy-build.sh
#
# This script automates the creation of a custom AlmaLinux ISO
# preloaded with Zabbix Proxy and its dependencies.
#
# Prerequisites:
#   - Run on an AlmaLinux minimal VM (or equivalent RHEL-9/Alma-9).
#   - Network access to the Internet to download packages and scripts.
#   - Sufficient disk space under /root for downloads and result ISO.
#   - Root privileges for package installation and ISO creation.
#
# Usage:
#
#   curl -fsSL -o zabbix-kickstart.cfg https://raw.githubusercontent.com/marcgauthier/zabbix-proxy/refs/heads/main/zabbix-kickstart.cfg
#   curl -fsSL -o zabbix-proxy-build.sh https://raw.githubusercontent.com/marcgauthier/zabbix-proxy/refs/heads/main/zabbix-proxy-build.sh
#   chmod +x zabbix-proxy-build.sh
#   ./zabbix-proxy-build.sh
#
# Exit codes:
#   0 - Success
#   1 - General error
#   2 - Missing prerequisites
#   3 - Insufficient disk space
#   4 - Download failure
#   5 - Validation failure
#
set -euo pipefail
IFS=$'\n\t'

#------------------------------------------------------------------------------
# GLOBAL CONFIGURATION VARIABLES
#------------------------------------------------------------------------------
# URL of the AlmaLinux minimal ISO to download if missing.
# Adjust the URL to point to the desired AlmaLinux 9 minimal ISO.
ALMA_ISO_URL="https://repo.almalinux.org/almalinux/9.6/isos/x86_64/AlmaLinux-9.6-x86_64-minimal.iso"

# Path to the AlmaLinux minimal ISO you have downloaded.
ALMA_ISO_PATH="/root/downloads/AlmaLinux-9-x86_64-minimal.iso"

# URL of the Zabbix RPM repository package to install.
# Adjust version (7.4) and AlmaLinux major (9) as needed.
ZABBIX_REPO_RPM="https://repo.zabbix.com/zabbix/7.4/release/alma/9/noarch/zabbix-release-latest-7.4.el9.noarch.rpm"

# Directory under which to stash downloaded Zabbix RPMs
PKG_DIR="/root/zabbix-pkgs"

# Kickstart file location
KS_FILE="/root/zabbix-kickstart.cfg"

# Directories for ISO build
RESULT_DIR="/root/custom-iso"
TMP_DIR=""  # Will be set by mktemp

# Minimum required disk space in GB
MIN_DISK_SPACE_GB=15

# Script version for logging
SCRIPT_VERSION="2.0"

#------------------------------------------------------------------------------
# LOGGING AND UTILITY FUNCTIONS
#------------------------------------------------------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

log_info() {
    log "INFO: $*"
}

log_warn() {
    log "WARN: $*"
}

log_error() {
    log "ERROR: $*"
}

log_success() {
    log "SUCCESS: $*"
}

# Progress indicator for long-running operations
show_progress() {
    local pid=$1
    local message=$2
    local spin='/-\|'
    local i=0
    
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r%s %c" "$message" "${spin:$i:1}"
        sleep 0.2
    done
    printf "\r%s ... done\n" "$message"
}

# Cleanup function
cleanup() {
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed with exit code $exit_code"
    fi
    
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        log_info "Cleaning up temporary directory: $TMP_DIR"
        rm -rf "$TMP_DIR"
    fi
    
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "Script completed successfully"
    fi
    
    exit $exit_code
}

# Set up signal handlers
trap cleanup EXIT
trap 'exit 130' INT  # Ctrl+C
trap 'exit 143' TERM # Termination

#------------------------------------------------------------------------------
# VALIDATION FUNCTIONS
#------------------------------------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 2
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    local required_tools=(
        "curl"
        "dnf" 
        "rpm"
        "file"
        "df"
        "mktemp"
    )
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install the missing tools and try again"
        exit 2
    fi
    
    # Check if we're on a compatible system
    if [[ -f /etc/os-release ]]; then
        local os_id
        os_id=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
        case "$os_id" in
            almalinux|rhel|rocky|centos)
                log_info "Running on compatible OS: $os_id"
                ;;
            *)
                log_warn "Running on potentially incompatible OS: $os_id"
                log_warn "This script is designed for RHEL-based distributions"
                ;;
        esac
    fi
    
    log_success "Prerequisites check passed"
}

check_disk_space() {
    log_info "Checking available disk space..."
    
    local available_gb
    available_gb=$(df /root --output=avail -BG 2>/dev/null | tail -1 | tr -d 'G' | tr -d ' ')
    
    if [[ ! "$available_gb" =~ ^[0-9]+$ ]]; then
        log_error "Could not determine available disk space"
        exit 3
    fi
    
    if [[ $available_gb -lt $MIN_DISK_SPACE_GB ]]; then
        log_error "Insufficient disk space in /root"
        log_error "Required: ${MIN_DISK_SPACE_GB}GB, Available: ${available_gb}GB"
        exit 3
    fi
    
    log_success "Disk space check passed (${available_gb}GB available)"
}

validate_kickstart_file() {
    log_info "Validating kickstart file..."
    
    if [[ ! -f "$KS_FILE" ]]; then
        log_error "Kickstart file not found at $KS_FILE"
        log_error "Please ensure you've downloaded the kickstart configuration:"
        log_error "curl -fsSL -o zabbix-kickstart.cfg https://raw.githubusercontent.com/marcgauthier/zabbix-proxy/refs/heads/main/zabbix-kickstart.cfg"
        exit 5
    fi
    
    if [[ ! -s "$KS_FILE" ]]; then
        log_error "Kickstart file is empty: $KS_FILE"
        exit 5
    fi
    
    # Basic syntax validation
    if command -v ksvalidator >/dev/null 2>&1; then
        if ! ksvalidator "$KS_FILE" 2>/dev/null; then
            log_warn "Kickstart file may have syntax issues (ksvalidator failed)"
            log_warn "Proceeding anyway, but build may fail"
        else
            log_success "Kickstart file validation passed"
        fi
    else
        log_info "ksvalidator not available, skipping syntax validation"
    fi
    
    log_success "Kickstart file validated"
}

validate_iso_file() {
    local iso_path="$1"
    
    log_info "Validating ISO file: $iso_path"
    
    if [[ ! -f "$iso_path" ]]; then
        log_error "ISO file not found: $iso_path"
        return 1
    fi
    
    if [[ ! -s "$iso_path" ]]; then
        log_error "ISO file is empty: $iso_path"
        return 1
    fi
    
    # Check if it's actually an ISO file
    local file_type
    file_type=$(file "$iso_path" 2>/dev/null)
    
    if [[ ! "$file_type" =~ "ISO 9660" ]]; then
        log_warn "File may not be a valid ISO: $file_type"
        log_warn "Proceeding anyway, but build may fail"
        return 0
    fi
    
    # Check file size (ISO should be at least 500MB)
    local file_size_mb
    file_size_mb=$(du -m "$iso_path" | cut -f1)
    
    if [[ $file_size_mb -lt 500 ]]; then
        log_warn "ISO file seems too small (${file_size_mb}MB), may be incomplete"
        return 0
    fi
    
    log_success "ISO file validation passed (${file_size_mb}MB)"
    return 0
}

#------------------------------------------------------------------------------
# DOWNLOAD FUNCTIONS
#------------------------------------------------------------------------------
download_with_progress() {
    local url="$1"
    local output_path="$2"
    local description="$3"
    
    log_info "Downloading $description..."
    log_info "URL: $url"
    log_info "Destination: $output_path"
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$output_path")"
    
    # Download with progress bar and error handling
    if ! curl -fsSL \
        --connect-timeout 30 \
        --max-time 3600 \
        --retry 3 \
        --retry-delay 5 \
        --show-error \
        --progress-bar \
        -o "$output_path" \
        "$url"; then
        log_error "Failed to download $description from $url"
        return 4
    fi
    
    log_success "Downloaded $description successfully"
    return 0
}

ensure_iso_available() {
    log_info "Ensuring AlmaLinux ISO is available..."
    
    if [[ -f "$ALMA_ISO_PATH" ]]; then
        log_info "Found existing ISO at $ALMA_ISO_PATH"
        if validate_iso_file "$ALMA_ISO_PATH"; then
            log_success "Using existing ISO file"
            return 0
        else
            log_warn "Existing ISO file is invalid, re-downloading..."
            rm -f "$ALMA_ISO_PATH"
        fi
    fi
    
    log_info "Downloading AlmaLinux ISO..."
    if ! download_with_progress "$ALMA_ISO_URL" "$ALMA_ISO_PATH" "AlmaLinux ISO"; then
        exit 4
    fi
    
    if ! validate_iso_file "$ALMA_ISO_PATH"; then
        log_error "Downloaded ISO file is invalid"
        exit 4
    fi
    
    log_success "AlmaLinux ISO is ready"
}

#------------------------------------------------------------------------------
# PACKAGE MANAGEMENT FUNCTIONS
#------------------------------------------------------------------------------
install_base_packages() {
    log_info "Installing base packages and repositories..."
    
    # Install EPEL repository
    log_info "Installing EPEL repository..."
    if ! dnf install -y epel-release; then
        log_error "Failed to install EPEL repository"
        exit 1
    fi
    
    # Update system metadata
    log_info "Updating package metadata..."
    if ! dnf clean all && dnf makecache; then
        log_error "Failed to update package metadata"
        exit 1
    fi
    
    log_success "Base packages installed successfully"
}

setup_zabbix_repository() {
    log_info "Setting up Zabbix repository..."
    
    log_info "Installing Zabbix repository package from: $ZABBIX_REPO_RPM"
    if ! rpm -Uvh --quiet "$ZABBIX_REPO_RPM"; then
        log_error "Failed to install Zabbix repository package"
        exit 1
    fi
    
    # Refresh metadata after adding new repository
    log_info "Refreshing package metadata..."
    if ! dnf clean all && dnf makecache; then
        log_error "Failed to refresh package metadata"
        exit 1
    fi
    
    log_success "Zabbix repository configured successfully"
}

download_zabbix_packages() {
    log_info "Downloading Zabbix packages..."
    
    # Create package directory
    mkdir -p "$PKG_DIR"
    
    # List of packages to download (including dependencies)
    local packages=(
        "zabbix-proxy-mysql"
        "zabbix-agent2"
    )
    
    log_info "Downloading packages with dependencies to: $PKG_DIR"
    for package in "${packages[@]}"; do
        log_info "Downloading package: $package"
    done
    
    # Download packages with all dependencies
    if ! dnf install --downloadonly \
        --downloaddir="$PKG_DIR" \
        --resolve \
        "${packages[@]}"; then
        log_error "Failed to download Zabbix packages"
        exit 1
    fi
    
    # Verify packages were downloaded
    local pkg_count
    pkg_count=$(find "$PKG_DIR" -name "*.rpm" | wc -l)
    
    if [[ $pkg_count -eq 0 ]]; then
        log_error "No RPM packages found in $PKG_DIR"
        exit 1
    fi
    
    log_success "Downloaded $pkg_count RPM packages to $PKG_DIR"
}

create_local_repository() {
    log_info "Creating local repository from downloaded packages..."
    
    # Install createrepo_c if not present
    if ! command -v createrepo_c >/dev/null 2>&1; then
        log_info "Installing createrepo_c..."
        if ! dnf install -y createrepo_c; then
            log_error "Failed to install createrepo_c"
            exit 1
        fi
    fi
    
    # Create repository metadata
    log_info "Creating repository metadata in $PKG_DIR"
    if ! createrepo_c "$PKG_DIR"; then
        log_error "Failed to create repository metadata"
        exit 1
    fi
    
    # Verify repository was created
    if [[ ! -d "$PKG_DIR/repodata" ]]; then
        log_error "Repository metadata not found in $PKG_DIR/repodata"
        exit 1
    fi
    
    log_success "Local repository created successfully"
}

create_repository_file() {
    log_info "Creating repository configuration file..."
    
    local repo_file="$PKG_DIR/zabbix-local.repo"
    
    cat > "$repo_file" << EOF
[zabbix-local]
name=Local Zabbix Repository
baseurl=file://$PKG_DIR
enabled=1
gpgcheck=0
EOF
    
    if [[ ! -f "$repo_file" ]]; then
        log_error "Failed to create repository file: $repo_file"
        exit 1
    fi
    
    log_success "Repository configuration created: $repo_file"
}

install_build_tools() {
    log_info "Installing ISO build tools..."
    
    # Install development tools
    log_info "Installing Development Tools group..."
    if ! dnf groupinstall -y "Development Tools"; then
        log_error "Failed to install Development Tools group"
        exit 1
    fi
    
    # Install specific tools for ISO creation
    local build_tools=(
        "lorax"
        "anaconda-tui"
        "python3-kickstart"
        "createrepo_c"
    )
    
    log_info "Installing ISO creation tools: ${build_tools[*]}"
    if ! dnf install -y "${build_tools[@]}"; then
        log_error "Failed to install ISO build tools"
        exit 1
    fi
    
    # Verify livemedia-creator is available
    if ! command -v livemedia-creator >/dev/null 2>&1; then
        log_error "livemedia-creator not found after installation"
        exit 1
    fi
    
    # Verify createrepo_c is available
    if ! command -v createrepo_c >/dev/null 2>&1; then
        log_error "createrepo_c not found after installation"
        exit 1
    fi
    
    log_success "Build tools installed successfully"
}

#------------------------------------------------------------------------------
# ISO BUILD FUNCTIONS
#------------------------------------------------------------------------------
create_custom_iso() {
    log_info "Creating custom AlmaLinux ISO with Zabbix Proxy..."
    
    # Create temporary directory securely
    TMP_DIR=$(mktemp -d -t zabbix-iso-build.XXXXXX)
    log_info "Using temporary directory: $TMP_DIR"
    
    # Prepare result directory
    mkdir -p "$RESULT_DIR"
    log_info "Results will be saved to: $RESULT_DIR"
    
    # Verify all prerequisites before starting build
    if [[ ! -f "$ALMA_ISO_PATH" ]]; then
        log_error "AlmaLinux ISO not found at $ALMA_ISO_PATH"
        exit 5
    fi
    
    if [[ ! -f "$KS_FILE" ]]; then
        log_error "Kickstart file not found at $KS_FILE"
        exit 5
    fi
    
    if [[ ! -d "$PKG_DIR" ]] || [[ $(find "$PKG_DIR" -name "*.rpm" | wc -l) -eq 0 ]]; then
        log_error "No RPM packages found in $PKG_DIR"
        exit 5
    fi
    
    if [[ ! -d "$PKG_DIR/repodata" ]]; then
        log_error "Repository metadata not found in $PKG_DIR/repodata"
        exit 5
    fi
    
    # Create a modified kickstart file that includes our local repository
    local modified_ks="$TMP_DIR/modified-kickstart.cfg"
    log_info "Creating modified kickstart file: $modified_ks"
    
    # Copy original kickstart and add our repository
    cp "$KS_FILE" "$modified_ks"
    
    # Add local repository configuration to kickstart
    cat >> "$modified_ks" << EOF

# Local Zabbix repository added by build script
repo --name="zabbix-local" --baseurl="file://$PKG_DIR"
EOF
    
    # Start the ISO build process
    log_info "Starting livemedia-creator..."
    log_info "This process may take 30-60 minutes depending on your system"
    log_info "ISO Source: $ALMA_ISO_PATH"
    log_info "Kickstart: $modified_ks"
    log_info "Local repository: $PKG_DIR"
    
    # Run livemedia-creator with the corrected approach
    local lmc_cmd=(
        "livemedia-creator"
        "--make-iso"
        "--iso=$ALMA_ISO_PATH"
        "--ks=$modified_ks"
        "--title=Alma-Zabbix-Proxy"
        "--project=AlmaLinux-Zabbix"
        "--releasever=9"
        "--tmp=$TMP_DIR"
        "--resultdir=$RESULT_DIR"
        "--logfile=$RESULT_DIR/build.log"
        "--no-virt"
    )
    
    log_info "Executing: ${lmc_cmd[*]}"
    
    if ! "${lmc_cmd[@]}"; then
        log_error "livemedia-creator failed"
        log_error "Check the build log at: $RESULT_DIR/build.log"
        
        # Show last few lines of the log for immediate debugging
        if [[ -f "$RESULT_DIR/build.log" ]]; then
            log_info "Last 20 lines of build log:"
            tail -n 20 "$RESULT_DIR/build.log" || true
        fi
        
        exit 1
    fi
    
    # Verify the output ISO was created
    local output_iso
    output_iso=$(find "$RESULT_DIR" -name "*.iso" -type f | head -n1)
    
    if [[ -z "$output_iso" ]] || [[ ! -f "$output_iso" ]]; then
        log_error "No output ISO found in $RESULT_DIR"
        
        # List what files were actually created
        log_info "Files in result directory:"
        ls -la "$RESULT_DIR" || true
        
        exit 1
    fi
    
    # Validate the created ISO
    if ! validate_iso_file "$output_iso"; then
        log_error "Created ISO appears to be invalid"
        exit 1
    fi
    
    local iso_size_mb
    iso_size_mb=$(du -m "$output_iso" | cut -f1)
    
    log_success "Custom ISO created successfully!"
    log_success "Output ISO: $output_iso"
    log_success "Size: ${iso_size_mb}MB"
    log_success "Build log: $RESULT_DIR/build.log"
}

#------------------------------------------------------------------------------
# MAIN SCRIPT EXECUTION
#------------------------------------------------------------------------------
main() {
    log_info "Starting Zabbix Proxy ISO Builder v$SCRIPT_VERSION"
    log_info "Timestamp: $(date)"
    log_info "Working directory: $(pwd)"
    
    # Display configuration
    echo
    log_info "Configuration:"
    log_info "  ALMA_ISO_URL    = $ALMA_ISO_URL"
    log_info "  ALMA_ISO_PATH   = $ALMA_ISO_PATH"
    log_info "  ZABBIX_REPO_RPM = $ZABBIX_REPO_RPM"
    log_info "  PKG_DIR         = $PKG_DIR"
    log_info "  KS_FILE         = $KS_FILE"
    log_info "  RESULT_DIR      = $RESULT_DIR"
    echo
    
    # Step 0: Prerequisites and validation
    log_info "==> Step 1: System validation"
    check_root
    check_prerequisites
    check_disk_space
    validate_kickstart_file
    
    # Step 1: Ensure ISO is available
    log_info "==> Step 2: Ensure AlmaLinux ISO"
    ensure_iso_available
    
    # Step 2: Prepare base system
    log_info "==> Step 3: Prepare base system"
    install_base_packages
    setup_zabbix_repository
    
    # Step 3: Download packages and create repository
    log_info "==> Step 4: Download Zabbix packages and create local repository"
    download_zabbix_packages
    create_local_repository
    create_repository_file
    
    # Step 4: Install build tools
    log_info "==> Step 5: Install build tools"
    install_build_tools
    
    # Step 5: Create custom ISO
    log_info "==> Step 6: Create custom ISO"
    create_custom_iso
    
    # Final success message
    echo
    log_success "=== BUILD COMPLETED SUCCESSFULLY ==="
    log_success "Your custom AlmaLinux ISO with Zabbix Proxy is ready!"
    log_success "Location: $RESULT_DIR"
    echo
    log_info "Next steps:"
    log_info "1. Test the ISO in a virtual machine"
    log_info "2. Deploy to target systems"
    log_info "3. Configure Zabbix Proxy settings as needed"
    echo
}

# Execute main function
main "$@"
