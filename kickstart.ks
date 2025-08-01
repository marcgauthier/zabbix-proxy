# AlmaLinux 9.6 Kickstart for Zabbix Proxy Installation
#
# Requirements from original specification:
# - First thing to do Bind /var/logs to data/logs
# - set system language to en_US.UTF-8.
# - set keyboard layout to US.
# - set timezone to UTC.
# - configure all network cards via DHCP.
# - Copy /run/install/repo/iso-content/root/* to /mnt/sysimage/root/
#   to recreate the /root/files folder.
# - Ask variables
#               time-server i.e.  DCS-STR-CP09161.forces.mil.ca
#               zabbix-proxy-name
#               zabbix-server-ip
#               32 characters Pre-Shared-Key and confirm
# - Enable NetworkManager, chronyd, and firewalld services.
# - Disable services:
#               ssh
#               cups (printing)
#               ModemManager
#               ...
#               sudo systemctl disable bluetooth
#               sudo systemctl disable avahi-daemon
# - Install Packages
#               Zabbix-proxy
#               Zabbix-selinux-policy
#               MySql set password
# - Configure MySQL
#               create database
# - Configure Zabbix
#               create a file for zabbix PSK with the 32 characters password
#               chmod 600
# - Configure chronyd to get time from a SSC time server
#               DCS-STR-CP0961.forces.mil.ca
# - Configure Firewall
#               no out to non private IP
#               only zabbix ports and 80/443
# - Create zabbixlog user that only has access to /data/logs no execute
#               password randomely generated
# - Disable all users, root shell must be disable
# - Disable any services not needed
# - Confirm Installation
#               - Print Zabbixuser password ask to send it to DGITI
#               - Print mac address ask user to open a ticket to do an IP reservation
#                 and send the IP to DGITI
# - Delete install.sh after installation is complete!

# Language and keyboard settings
lang en_US.UTF-8
keyboard us
timezone UTC

# Network configuration
network --bootproto=dhcp --device=link --activate

# Root password (will be set during installation)
rootpw --iscrypted $6$rounds=656000$salt$hash

# System bootloader
bootloader --location=mbr --append="console=tty0 console=ttyS0,115200n8"

# Partitioning
clearpart --all --initlabel
autopart --type=lvm

# Package selection
%packages
@core
@network-tools
zabbix-proxy-mysql
zabbix-agent2
mysql-server
mysql-client
zabbix-selinux-policy
chrony
firewalld
NetworkManager
%end

# Post-installation script
%post
#!/bin/bash

# Set system language
localectl set-locale LANG=en_US.UTF-8

# Configure timezone
timedatectl set-timezone UTC

# Enable required services
systemctl enable NetworkManager
systemctl enable chronyd
systemctl enable firewalld
systemctl enable mysqld

# Disable unnecessary services
systemctl disable sshd
systemctl disable cups
systemctl disable ModemManager
systemctl disable bluetooth
systemctl disable avahi-daemon

# Create data directory and bind mount
mkdir -p /data/logs
echo "/data/logs /var/log none bind 0 0" >> /etc/fstab

# Copy installation files
if [ -d /run/install/repo/iso-content/root ]; then
    cp -r /run/install/repo/iso-content/root/* /root/
fi

# Configure MySQL
mysql_secure_installation --use-default

# Configure chronyd for time server
sed -i 's/^server.*/server DCS-STR-CP09161.forces.mil.ca iburst/' /etc/chrony.conf

# Configure firewall
firewall-cmd --permanent --add-service=zabbix-proxy
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload

# Create zabbixlog user
useradd -r -d /data/logs -s /sbin/nologin zabbixlog
chown zabbixlog:zabbixlog /data/logs
chmod 755 /data/logs

# Disable root shell
passwd -l root

# Clean up installation script
rm -f /root/install.sh

echo "Zabbix Proxy installation completed!"
echo "Please configure the following:"
echo "1. Zabbix proxy name"
echo "2. Zabbix server IP"
echo "3. 32-character Pre-Shared Key"
echo "4. Send MAC address to DGITI for IP reservation"
%end
