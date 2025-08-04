# Zabbix Proxy Installation Scripts

## Overview

This repository contains scripts for creating a bootable USB drive and automating the installation of Zabbix Proxy on AlmaLinux 9.

## Prerequisites

Before running the installation scripts, ensure you have:

- A USB drive with at least 8GB capacity for the bootable media
- A target system with at least 120GB storage (100GB for zabbix-data partition + OS)
- Network connectivity for downloading packages and ISO files
- Administrative access to the target system
- Required information for Zabbix and MariaDB configuration (see Configuration Requirements below)

## Configuration Requirements

### Required Information for Installation

The installation process will prompt for the following information:

#### 1. System Configuration
- **Hostname**: The hostname for the Zabbix proxy server
- **NTP Server**: Network Time Protocol server address (e.g., `pool.ntp.org` or your organization's NTP server)

#### 2. Zabbix Proxy Configuration
- **Zabbix Server IP**: The IP address of your main Zabbix server
- **Proxy Hostname**: The hostname that will be registered with the Zabbix server
- **PSK Identity**: Pre-Shared Key identity for secure communication (e.g., `zabbix-proxy-01`)
- **PSK Key**: 32-character hexadecimal string for PSK authentication (e.g., `a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6`)

#### 3. MariaDB Configuration
- **Database Name**: Name for the Zabbix database (default: `zabbix`)
- **Database User**: Username for database access (default: `zabbix`)
- **Database Password**: Strong password for the Zabbix database user
- **Root Password**: MariaDB root password for administrative access

#### 4. Network Configuration
- **Network Interface**: The primary network interface to configure
- **IP Configuration**: Whether to use DHCP or static IP addressing

### Security Considerations

- All passwords should be strong and unique
- PSK keys should be randomly generated 32-character hexadecimal strings
- Database passwords should meet your organization's security requirements
- Consider using a dedicated VLAN for Zabbix proxy communication

### **BIOS Security**
   - Disable USB Boot 
   - Optional disable USB
   - Set HD as first Boot 
   - Set Password to BIOS 

## Installation Process

### Step 1: Create Bootable USB
1. Run `./build.sh` to create the bootable USB drive
2. Select your target USB device when prompted
3. Wait for the download and creation process to complete

### Step 2: Install AlmaLinux
1. Boot the target system from the USB drive
2. Install AlmaLinux 9 minimal with the following partition scheme:
   - OS partition: At least 20GB
   - zabbix-data partition: At least 100GB
3. Complete the AlmaLinux installation

### Step 3: Run Zabbix Proxy Installation
1. After first login, navigate to `/zabbix-packages` directory
2. Run `./install.sh` as root
3. Provide all required configuration information when prompted
4. Wait for the installation to complete

## Post-Installation

### Verification Steps
1. Check that MariaDB service is running: `systemctl status mariadb`
2. Verify Zabbix proxy service: `systemctl status zabbix-proxy`
3. Test database connectivity
4. Verify network connectivity to Zabbix server
5. Check firewall configuration

### Troubleshooting
- Check `/var/log/zabbix/zabbix_proxy.log` for proxy issues
- Review `/var/log/mariadb/mariadb.log` for database problems
- Verify network connectivity and firewall rules
- Ensure PSK configuration matches on both proxy and server

## Security Notes

- The system is hardened for production use
- Root access is disabled for security
- Only essential services are enabled
- Network access is restricted to necessary ports
- OS partition is made read-only after installation

## Support

For issues or questions:
1. Check the logs in `/var/log/zabbix/` and `/var/log/mariadb/`
2. Verify network connectivity and firewall rules
3. Ensure all required information was provided correctly during installation
4. Contact your system administrator for additional support 
   
