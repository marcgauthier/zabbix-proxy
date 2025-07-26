#!/usr/bin/env bash
#
# Simple Zabbix Proxy ISO Builder (no temp KS)
# Creates a custom AlmaLinux ISO with Zabbix Proxy preinstalled
#
# Usage: ./zabbix-proxy-build.sh
#
set -euo pipefail

#─────────────────────────────────────────────────────────────────────────────
# Configuration
#─────────────────────────────────────────────────────────────────────────────
ALMA_VERSION="9.6"
ALMA_ISO_URL="https://repo.almalinux.org/almalinux/${ALMA_VERSION}/isos/x86_64/AlmaLinux-${ALMA_VERSION}-x86_64-minimal.iso"
ALMA_ISO_PATH="/root/downloads/AlmaLinux-${ALMA_VERSION}-x86_64-minimal.iso"

ZABBIX_REPO_RPM="https://repo.zabbix.com/zabbix/7.4/release/alma/9/noarch/zabbix-release-latest-7.4.el9.noarch.rpm"

PKG_DIR="/root/zabbix-pkgs"
KS_FILE="/root/zabbix-kickstart.cfg"
RESULT_DIR="/root/custom-iso"
LOGS_DIR="/root/logs"

echo "=== Starting Zabbix Proxy ISO Builder ==="

#─────────────────────────────────────────────────────────────────────────────
# Prerequisites & Environment Checks
#─────────────────────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || { echo "ERROR: Must run as root"; exit 1; }
mkdir -p "$LOGS_DIR" "$PKG_DIR" "$(dirname "$ALMA_ISO_PATH")" "$RESULT_DIR"

#─────────────────────────────────────────────────────────────────────────────
# 1) Download/Kickstart Verification
#─────────────────────────────────────────────────────────────────────────────
echo "[1/9] Fetching kickstart file..."
curl -fsSL -o "$KS_FILE" \
  https://raw.githubusercontent.com/marcgauthier/zabbix-proxy/refs/heads/main/zabbix-kickstart.cfg

echo "    → Verifying that KS file has no external URLs..."
if grep -E '^(url|repo).*(http|https)' "$KS_FILE"; then
  echo "ERROR: Kickstart still references an external URL. Please remove any 'url --url=…' or 'repo …http…' lines." >&2
  exit 1
fi

#─────────────────────────────────────────────────────────────────────────────
# 2) Download AlmaLinux ISO
#─────────────────────────────────────────────────────────────────────────────
echo "[2/9] Ensuring AlmaLinux ISO is present..."
if [[ ! -f "$ALMA_ISO_PATH" ]]; then
  curl -fsSL -o "$ALMA_ISO_PATH" "$ALMA_ISO_URL"
else
  echo "    → ISO already exists, skipping download."
fi

#─────────────────────────────────────────────────────────────────────────────
# 3) Install EPEL & DNF Plugins
#─────────────────────────────────────────────────────────────────────────────
echo "[3/9] Installing EPEL & dnf-plugins-core..."
dnf install -y epel-release dnf-plugins-core || echo "    → already installed"
dnf clean all && dnf makecache

#─────────────────────────────────────────────────────────────────────────────
# 4) Configure Zabbix Repo
#─────────────────────────────────────────────────────────────────────────────
echo "[4/9] Installing Zabbix repo RPM..."
rpm -qa | grep -q '^zabbix-release' || rpm -Uvh "$ZABBIX_REPO_RPM" 2>/dev/null || echo "    → already installed"
dnf clean all && dnf makecache

#─────────────────────────────────────────────────────────────────────────────
# 5) Download Zabbix & Dependencies
#─────────────────────────────────────────────────────────────────────────────
echo "[5/9] Downloading Zabbix packages + deps..."
dnf install -y --downloadonly --downloaddir="$PKG_DIR" \
    zabbix-proxy-mysql zabbix-agent2 || echo "    → some already present"

echo "[6/9] Downloading additional packages..."
dnf install -y --downloadonly --downloaddir="$PKG_DIR" \
    mariadb-server acl bind-utils wget curl tar gzip || echo "    → some already present"

echo "    → RPM count in $PKG_DIR: $(find "$PKG_DIR" -type f -name '*.rpm' | wc -l)"

#─────────────────────────────────────────────────────────────────────────────
# 7) Install Build Tools
#─────────────────────────────────────────────────────────────────────────────
echo "[7/9] Installing lorax, anaconda, kickstart..."
dnf install -y lorax anaconda python3-kickstart createrepo_c || echo "    → some already present"

#─────────────────────────────────────────────────────────────────────────────
# 8) Create Local Repo
#─────────────────────────────────────────────────────────────────────────────
echo "[8/9] Creating local YUM repo..."
createrepo_c "$PKG_DIR" || echo "    → createrepo_c failed, continuing"
cat > "$PKG_DIR/zabbix-local.repo" << EOF
[zabbix-local]
name=Local Zabbix Repository
baseurl=file://$PKG_DIR
enabled=1
gpgcheck=0
EOF

#─────────────────────────────────────────────────────────────────────────────
# 9) Build the ISO
#─────────────────────────────────────────────────────────────────────────────
echo "[9/9] Running livemedia-creator (this may take up to an hour)..."
livemedia-creator \
  --make-iso \
  --iso="$ALMA_ISO_PATH" \
  --ks="$KS_FILE" \
  --project=AlmaLinux-Zabbix \
  --releasever=9 \
  --tmp=/tmp/lmc-$$ \
  --resultdir="$RESULT_DIR" \
  --logfile="$LOGS_DIR/build.log" \
  --no-virt

#─────────────────────────────────────────────────────────────────────────────
# Final Reporting
#─────────────────────────────────────────────────────────────────────────────
OUTPUT_ISO=$(find "$RESULT_DIR" -type f -name '*.iso' | head -n1)
if [[ -z "$OUTPUT_ISO" ]]; then
  echo "ERROR: No ISO found. Check $LOGS_DIR/build.log" >&2
  exit 1
fi

echo -e "\n=== BUILD SUCCESS ==="
echo "ISO:  $OUTPUT_ISO"
echo "Size: $(du -m "$OUTPUT_ISO" | cut -f1) MB"
echo "Log:  $LOGS_DIR/build.log"
echo "Next: Test in VM, then deploy!"
