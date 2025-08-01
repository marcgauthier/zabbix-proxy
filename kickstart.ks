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
zerombr
clearpart --all --initlabel
part /     --size=4096 --fstype=ext4
part /data --grow --fstype=ext4
