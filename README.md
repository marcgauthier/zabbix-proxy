# Zabbix Proxy Installation Scripts

## Overview

This repository contains scripts for creating a bootable USB drive and automating the installation of Zabbix Proxy on AlmaLinux 9.

## Scripts

### build.sh
Creates a bootable USB drive that can be used to install AlmaLinux and Zabbix Proxy.

**Features:**
- Auto-detects and lists available USB drives
- Downloads latest AlmaLinux 9 minimal ISO
- Creates bootable USB with the downloaded ISO
- Downloads Zabbix packages (proxy-mysql, agent, get, sender) without installing them
- Copies Zabbix packages and install.sh to `/zabbix-packages` directory on the USB drive
- Allows user to select target USB device with confirmation

### install.sh
Automated first-login installer for Zabbix Proxy deployment.

**What the script does:**

#### ✅ Implemented Features:

0. **Partition check**
   - Make sure two partitions exists and one will hold the OS and 
   - The second will be named zabbix-data and be at least 100GB

1. **Partition Management**
   - Binds `/var/log` to `/zabbix-data/logs` partition
   - Adds mount entry to `/etc/fstab` for persistence

2. **System Configuration**
   - Sets locale to en_US.UTF-8
   - Configures keyboard layout to US
   - Sets timezone to UTC
   - Configures time synchronization with specified server, ask for NTP server information.
   - Ask and set hostname 

3. **Network Configuration**
   - Enables DHCP on all network interfaces via NetworkManager
   - Restarts NetworkManager service

4. **Package Installation**
   - Installs Zabbix proxy, SELinux policy, and MariaDB server
   - Enables and starts MariaDB service

5. **MariaDB Configuration**
   - Create Zabbix database 
   - Use password ... 

5. **Zabbix Configuration**
   - Configures Zabbix proxy with PSK authentication
   - Sets up TLS/PSK security settings
   - Configures proxy identity and server connections
   - Ask for Server IP 
   - Ask for proxy hostname 
   
6. **Security Hardening**
   - Configures firewall to allow only HTTP/HTTPS and Zabbix port 10051
   - Blocks all outbound traffic except to private networks (RFC1918)
   - Disables unwanted services (SSH, CUPS, ModemManager, Bluetooth, Avahi)
   - Creates zabbixlog user with default password, only has access to zabbix-data partition and only /zabbix-data/logs
   - Locks root account and disables root shell
   - All users except zabbixlog should not have shell access. 
     
7. **User Management**
   - Prompts for required variables (time server, proxy hostname, Zabbix server IP, PSK)
   
8. **Final Reporting**
   - Displays MAC address of all interfaces
   - Prompts user to open ticket for IP reservation for macd 
   - Self-removes the installation script

9. **OS Partition Read-Only**
   - Make the OS partition read-only for security

10. **USB Disable**
   - Disable USB functionality on the OS for security

11. **BIOS Security**
   - Disable USB Boot 
   - Set HD as first Boot 
   - Set Password to BIOS 
   
