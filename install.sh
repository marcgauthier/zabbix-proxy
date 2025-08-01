#!/usr/bin/env bash
set -euo pipefail

# ============================================
# install.sh – first-login installer for Zabbix Proxy
# ============================================

# 1) Bind /var/log to /data/logs
mkdir -p /data/logs
mount --bind /data/logs /var/log
if ! grep -q ' /var/log ' /etc/fstab; then
  echo "/data/logs /var/log none bind 0 0" >> /etc/fstab
fi

# 2) Locales, keyboard, timezone
localectl set-locale LANG=en_US.UTF-8
localectl set-keymap us
timedatectl set-timezone UTC

# 3) Configure all NICs for DHCP via NetworkManager
echo "Configuring network interfaces for DHCP..."
for dev in $(ls /sys/class/net | grep -vE '^(lo|bond|team)'); do
  nmcli dev set "$dev" managed yes
  nmcli connection add \
    type ethernet ifname "$dev" con-name "dhcp-$dev" ipv4.method auto \
    || nmcli connection modify "dhcp-$dev" ipv4.method auto
done
systemctl restart NetworkManager

# 4) (If running from installer) copy files into /root/files
SRC="/run/install/repo/iso-content/root"
if [[ -d "$SRC" ]]; then
  echo "Repopulating /root/files from installer media..."
  mkdir -p /root/files
  cp -a "$SRC"/* /root/files/
fi

# 5) Prompt for required variables
read -rp "Time server (e.g. DCS-STR-CP09161.forces.mil.ca): " TIME_SERVER
read -rp "Zabbix proxy hostname: " ZABBIX_PROXY_NAME
read -rp "Zabbix server IP: " ZABBIX_SERVER_IP

while true; do
  read -rp "32-char PSK: " PSK1
  read -rp "Confirm PSK: " PSK2
  [[ "$PSK1" == "$PSK2" ]] || { echo "PSKs do not match; retry."; continue; }
  [[ ${#PSK1} -eq 32 ]]     || { echo "PSK must be exactly 32 characters; retry."; continue; }
  PSK="$PSK1"
  break
done

# 6) Enable core services
systemctl enable --now NetworkManager chronyd firewalld

# 7) Disable unwanted services
for svc in sshd cups ModemManager bluetooth avahi-daemon; do
  systemctl disable --now "$svc" || true
done

# 8) Install required packages
dnf install -y zabbix-proxy zabbix-selinux-policy mysql-server

# 9) Configure MySQL
systemctl enable --now mysqld
mysql --execute "CREATE DATABASE IF NOT EXISTS zabbix_proxy CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;"

# 10) Configure Zabbix Proxy PSK & conf
mkdir -p /etc/zabbix
echo "$PSK" > /etc/zabbix/zabbix_proxy.psk
chmod 600 /etc/zabbix/zabbix_proxy.psk

ZCONF=/etc/zabbix/zabbix_proxy.conf
# set server and proxy identity
sed -i "s/^Server=.*/Server=$ZABBIX_SERVER_IP/"   $ZCONF
sed -i "s/^ServerActive=.*/ServerActive=$ZABBIX_SERVER_IP/"   $ZCONF
sed -i "s/^Hostname=.*/Hostname=$ZABBIX_PROXY_NAME/"         $ZCONF

# append TLS/PSK settings
cat >> $ZCONF <<EOF

TLSPSKFile=/etc/zabbix/zabbix_proxy.psk
TLSPSKIdentity=${ZABBIX_PROXY_NAME}.proxy
TLSConnect=psk
TLSAccept=psk
EOF

# 11) Configure chronyd
grep -q "$TIME_SERVER" /etc/chrony.conf \
  || echo "server $TIME_SERVER iburst" >> /etc/chrony.conf
systemctl restart chronyd

# 12) Configure firewall: only HTTP/HTTPS and Zabbix ports, block non-private egress
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --permanent --add-port=10051/tcp

# block all outbound except to RFC1918 (10/8,172.16/12,192.168/16)
for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
  firewall-cmd --permanent --direct --add-rule ipv4 filter OUTPUT 0 -d $net -j ACCEPT
done
firewall-cmd --permanent --direct --add-rule ipv4 filter OUTPUT 0 -j DROP

firewall-cmd --reload

# 13) Create zabbixlog user with no shell, home at /data/logs
LOGPASS=$(openssl rand -base64 16)
useradd -M -d /data/logs -s /sbin/nologin zabbixlog
echo "zabbixlog:$LOGPASS" | chpasswd

# 14) Lock out root shell
passwd -l root
usermod -s /sbin/nologin root

# 15) Final report
echo
echo "===== PROXY INSTALLATION COMPLETE ====="
echo "zabbixlog user password: $LOGPASS"
echo "  → Please forward this to DGITI"
MAC=$(ip -o link show | awk '/link\/ether/ {print $2; exit}')
IP=$(hostname -I | awk '{print $1}')
echo "MAC address: $MAC"
echo "IP address: $IP"
echo "  → Open a ticket for IP reservation and send to DGITI"
echo "======================================="

# 16) Self-remove
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
rm -f "$SCRIPT_PATH"
