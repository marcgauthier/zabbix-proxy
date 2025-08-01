# AlmaLinux 9.6 Zabbix Proxy Kickstart Configuration
# This kickstart file installs AlmaLinux with Zabbix proxy on a two-partition system
# - 6GB partition for OS (/)
# - Remaining space for data (/data)
# - Copies Zabbix files from ISO to /root/files
# - Executes install.sh on first boot then removes it

# Basic system configuration
lang en_US.UTF-8
keyboard us
network --bootproto=dhcp
rootpw --iscrypted $6$rounds=656000$salt$hash
firewall --disabled
selinux --permissive
timezone UTC
bootloader --location=mbr
text
skipx
reboot

# Package selection
%packages
@core
@network-tools
%end

# Partitioning configuration
# Clear all partitions and create new ones
zerombr
clearpart --all --initlabel
# 6GB partition for OS
part / --size=6144 --fstype=ext4 --asprimary
# Remaining space for data
part /data --grow --fstype=ext4

# Post-installation script to copy files and setup first boot execution
%post --nochroot
# Create target directory for Zabbix files
mkdir -p /mnt/sysimage/root/files

# Copy files from the ISO to the installed system
# The files are located in /root/files on the ISO
if [ -d /root/files ]; then
    echo "Copying Zabbix files from ISO to installed system..."
    cp -r /root/files/* /mnt/sysimage/root/files/ 2>/dev/null || true
    
    # Make install.sh executable
    if [ -f /mnt/sysimage/root/files/install.sh ]; then
        chmod +x /mnt/sysimage/root/files/install.sh
        echo "Made install.sh executable"
    fi
else
    echo "Warning: /root/files directory not found on ISO"
fi

# Create a systemd service to run install.sh on first boot
cat > /mnt/sysimage/etc/systemd/system/zabbix-firstboot.service << 'EOF'
[Unit]
Description=Zabbix First Boot Setup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/root/files/install.sh
ExecStartPost=/bin/rm -f /etc/systemd/system/zabbix-firstboot.service
ExecStartPost=/bin/systemctl disable zabbix-firstboot.service
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable the first boot service
ln -sf /etc/systemd/system/zabbix-firstboot.service /mnt/sysimage/etc/systemd/system/multi-user.target.wants/

echo "First boot service configured to run install.sh"
%end

# Additional post-installation tasks
%post
# Create data directory mount point
mkdir -p /data

# Set proper permissions for the files directory
chmod 755 /root/files
chown root:root /root/files

# Create a simple script to check if install.sh exists and is executable
cat > /usr/local/bin/check-zabbix-setup << 'EOF'
#!/bin/bash
if [ -f /root/files/install.sh ] && [ -x /root/files/install.sh ]; then
    echo "Zabbix setup files are ready"
    ls -la /root/files/
else
    echo "Warning: Zabbix setup files not found or not executable"
fi
EOF

chmod +x /usr/local/bin/check-zabbix-setup

echo "Zabbix kickstart installation completed"
%end
