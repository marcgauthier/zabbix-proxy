Below is an updated version of the build script that explicitly uses the **AlmaLinux minimal ISO** as your install source. Notice the change in the `livemedia-creator` invocation:

```bash
#!/usr/bin/env bash
set -euo pipefail

### CONFIGURATION ###
ALMA_VERSION="9.6"
MINIMAL_ISO="AlmaLinux-${ALMA_VERSION}-x86_64-minimal.iso"
BASE_ISO_URL="https://repo.almalinux.org/almalinux/${ALMA_VERSION}/isos/x86_64/${MINIMAL_ISO}"
WORK_DIR="/root/iso-build"
DOWNLOAD_DIR="${WORK_DIR}/downloads"
OVERLAY_DIR="${WORK_DIR}/overlay"
KS_FILE="${WORK_DIR}/zabbix-install.ks"
OUTPUT_ISO_NAME="AlmaLinux-${ALMA_VERSION}-zabbix-proxy.iso"
LOG_DIR="${WORK_DIR}/logs"

### PREPARE WORKSPACE ###
rm -rf "${WORK_DIR}"
mkdir -p "${DOWNLOAD_DIR}" "${OVERLAY_DIR}/root/files" "${LOG_DIR}"
cd "${WORK_DIR}"

### 1) Download AlmaLinux minimal ISO if missing ###
if [[ ! -f "${MINIMAL_ISO}" ]]; then
  echo "Downloading AlmaLinux ${ALMA_VERSION} minimal ISO..."
  curl -fsSL -o "${MINIMAL_ISO}" "${BASE_ISO_URL}"
fi

### 2) Pull in Zabbix & MySQL packages + your install.sh ###
dnf install -y dnf-plugins-core &>/dev/null
echo "Downloading Zabbix packages..."
dnf download --resolve --destdir="${DOWNLOAD_DIR}" \
    zabbix-proxy-mysql zabbix-agent2 mysql
echo "Downloading custom install.sh..."
curl -fsSL \
  -o "${DOWNLOAD_DIR}/install.sh" \
  "https://raw.githubusercontent.com/marcgauthier/.../install.sh"

### 3) Prepare overlay so /root/files/* ends up on target ###
cp -a "${DOWNLOAD_DIR}/." "${OVERLAY_DIR}/root/files/"

### 4) Write Kickstart ###
cat > "${KS_FILE}" << 'EOF'
# Kickstart for AlmaLinux + Zabbix Proxy Installer

lang en_US.UTF-8
keyboard us
timezone UTC --utc
interactive

install
cdrom

reboot

zerombr
clearpart --all --initlabel
part /       --size=4096  --fstype=ext4
part /data   --size=102400 --fstype=ext4 --grow

rootpw --plaintext zabbix-proxy

%post --interpreter=/usr/bin/bash
mkdir -p /root/files
cp -a /files/* /root/files/

cat >> /root/.bash_profile << 'EOS'
if [[ -f /root/files/install.sh && ! -f /root/.install_done ]]; then
  bash /root/files/install.sh
  touch /root/.install_done
fi
EOS
%end
EOF

### 5) Build with livemedia-creator ###
echo "Building custom installation ISO..."
livemedia-creator \
  --make-iso \
  --iso "${WORK_DIR}/${MINIMAL_ISO}" \            # use Alma minimal ISO as install source :contentReference[oaicite:0]{index=0}
  --ks "${KS_FILE}" \
  --copy-overlay "${OVERLAY_DIR}" \
  --project "ZabbixProxyInstaller" \
  --releasever "${ALMA_VERSION}" \
  --no-virt \
  --resultdir "${LOG_DIR}" \
  --iso-only \                                    # strip artifacts, keep only a bootable ISO :contentReference[oaicite:1]{index=1}
  --iso-name "${OUTPUT_ISO_NAME}"

echo "✅ Done. You’ll find your ISO here: ${LOG_DIR}/${OUTPUT_ISO_NAME}"
```

**Key changes to ensure “minimal ISO” is used**

* We download `AlmaLinux-<version>-x86_64-minimal.iso` explicitly.
* We pass that file to `livemedia-creator` with `--iso [path/to/minimal.iso]` ([Weldr][1]).
* We tell it to `--make-iso` and then use `--iso-only --iso-name` so the **only** output is your custom installer ISO named `AlmaLinux-<version>-zabbix-proxy.iso` ([Fedora Project][2]).

[1]: https://weldr.io/lorax/livemedia-creator.html?utm_source=chatgpt.com "livemedia-creator — Lorax 41.3 documentation - Weldr"
[2]: https://fedoraproject.org/wiki/Livemedia-creator-_How_to_create_and_use_a_Live_CD?utm_source=chatgpt.com "Livemedia-creator- How to create and use a Live CD - Fedora Linux"
Below is an updated version of the build script that explicitly uses the **AlmaLinux minimal ISO** as your install source. Notice the change in the `livemedia-creator` invocation:

```bash
#!/usr/bin/env bash
set -euo pipefail

### CONFIGURATION ###
ALMA_VERSION="9.6"
MINIMAL_ISO="AlmaLinux-${ALMA_VERSION}-x86_64-minimal.iso"
BASE_ISO_URL="https://repo.almalinux.org/almalinux/${ALMA_VERSION}/isos/x86_64/${MINIMAL_ISO}"
WORK_DIR="/root/iso-build"
DOWNLOAD_DIR="${WORK_DIR}/downloads"
OVERLAY_DIR="${WORK_DIR}/overlay"
KS_FILE="${WORK_DIR}/zabbix-install.ks"
OUTPUT_ISO_NAME="AlmaLinux-${ALMA_VERSION}-zabbix-proxy.iso"
LOG_DIR="${WORK_DIR}/logs"

### PREPARE WORKSPACE ###
rm -rf "${WORK_DIR}"
mkdir -p "${DOWNLOAD_DIR}" "${OVERLAY_DIR}/root/files" "${LOG_DIR}"
cd "${WORK_DIR}"

### 1) Download AlmaLinux minimal ISO if missing ###
if [[ ! -f "${MINIMAL_ISO}" ]]; then
  echo "Downloading AlmaLinux ${ALMA_VERSION} minimal ISO..."
  curl -fsSL -o "${MINIMAL_ISO}" "${BASE_ISO_URL}"
fi

### 2) Pull in Zabbix & MySQL packages + your install.sh ###
dnf install -y dnf-plugins-core &>/dev/null
echo "Downloading Zabbix packages..."
dnf download --resolve --destdir="${DOWNLOAD_DIR}" \
    zabbix-proxy-mysql zabbix-agent2 mysql
echo "Downloading custom install.sh..."
curl -fsSL \
  -o "${DOWNLOAD_DIR}/install.sh" \
  "https://raw.githubusercontent.com/marcgauthier/zabbix-proxy/refs/heads/main/install.sh"

### 3) Prepare overlay so /root/files/* ends up on target ###
cp -a "${DOWNLOAD_DIR}/." "${OVERLAY_DIR}/root/files/"

### 4) Write Kickstart ###
cat > "${KS_FILE}" << 'EOF'
# Kickstart for AlmaLinux + Zabbix Proxy Installer

lang en_US.UTF-8
keyboard us
timezone UTC --utc
interactive

install
cdrom

reboot

zerombr
clearpart --all --initlabel
part /       --size=4096  --fstype=ext4
part /data   --size=102400 --fstype=ext4 --grow

rootpw --plaintext zabbix-proxy

%post --interpreter=/usr/bin/bash
mkdir -p /root/files
cp -a /files/* /root/files/

cat >> /root/.bash_profile << 'EOS'
if [[ -f /root/files/install.sh && ! -f /root/.install_done ]]; then
  bash /root/files/install.sh
  touch /root/.install_done
fi
EOS
%end
EOF

### 5) Build with livemedia-creator ###
echo "Building custom installation ISO..."
livemedia-creator \
  --make-iso \
  --iso "${WORK_DIR}/${MINIMAL_ISO}" \            # use Alma minimal ISO as install source :contentReference[oaicite:0]{index=0}
  --ks "${KS_FILE}" \
  --copy-overlay "${OVERLAY_DIR}" \
  --project "ZabbixProxyInstaller" \
  --releasever "${ALMA_VERSION}" \
  --no-virt \
  --resultdir "${LOG_DIR}" \
  --iso-only \                                    # strip artifacts, keep only a bootable ISO :contentReference[oaicite:1]{index=1}
  --iso-name "${OUTPUT_ISO_NAME}"

echo "✅ Done. You’ll find your ISO here: ${LOG_DIR}/${OUTPUT_ISO_NAME}"
```

**Key changes to ensure “minimal ISO” is used**

* We download `AlmaLinux-<version>-x86_64-minimal.iso` explicitly.
* We pass that file to `livemedia-creator` with `--iso [path/to/minimal.iso]` ([Weldr][1]).
* We tell it to `--make-iso` and then use `--iso-only --iso-name` so the **only** output is your custom installer ISO named `AlmaLinux-<version>-zabbix-proxy.iso` ([Fedora Project][2]).

[1]: https://weldr.io/lorax/livemedia-creator.html?utm_source=chatgpt.com "livemedia-creator — Lorax 41.3 documentation - Weldr"
[2]: https://fedoraproject.org/wiki/Livemedia-creator-_How_to_create_and_use_a_Live_CD?utm_source=chatgpt.com "Livemedia-creator- How to create and use a Live CD - Fedora Linux"
s
