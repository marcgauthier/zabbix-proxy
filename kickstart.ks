# install AlmaLinux into two partitions one of 4GB the second with remaining free space
# copy Zabbix installation files from the ISO to the 4GB partition into /root/files
# this will include install.sh
# install.sh will run on first boot and configure and secure the appliance
#
zerombr
clearpart --all --initlabel
part /     --size=4096 --fstype=ext4
part /data --grow --fstype=ext4

%post --nochroot
# Create the target directory inside the installed system
mkdir -p /mnt/sysimage/root/files

# Copy files from the ISO environment (where you placed them manually)
cp -r /root/files/* /mnt/sysimage/root/files/

# Make install.sh executable
chmod +x /mnt/sysimage/root/files/install.sh

# Optional: set it to run on first login and clean itself up
echo "/root/files/install.sh && rm -f /root/.bash_profile" >> /mnt/sysimage/root/.bash_profile
%end
