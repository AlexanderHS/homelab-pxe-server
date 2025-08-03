# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Commands

### Setup and Configuration
```bash
# Initial setup - validates environment and generates configs
./scripts/setup.sh

# Download required boot files (iPXE, wimboot, memtest86+, Debian netboot)
./scripts/download-bootfiles.sh

# Start PXE services
docker-compose up -d

# Stop services
docker-compose down

# Restart services after configuration changes
docker-compose restart
```

### Development and Debugging
```bash
# View all service logs
docker-compose logs -f

# View specific service logs
docker-compose logs -f dnsmasq
docker-compose logs -f nginx
docker-compose logs -f netbootxyz

# Check service health status
docker-compose ps

# Monitor DHCP/PXE network traffic
sudo tcpdump -i any port 67 or port 68
sudo tcpdump -i any port 69

# Validate configuration after .env changes
./scripts/setup.sh && docker-compose restart
```

### File Management
```bash
# Backup configuration
tar -czf pxe-backup-$(date +%Y%m%d).tar.gz .env config/ tftpboot/ scripts/

# Set proper file permissions (run after manual file changes)
chmod 644 config/*
chmod -R 755 tftpboot/
chmod +x scripts/*.sh
```

## Architecture Overview

This is a Docker-based PXE proxy server that provides unattended OS deployment without replacing existing DHCP infrastructure. The system uses a three-service architecture:

### Core Services
- **dnsmasq**: Proxy DHCP server (responds to PXE requests) + TFTP server (serves boot files)
- **nginx**: HTTP file server (serves ISOs, templates, and boot files over HTTP)
- **netboot.xyz**: Web-based boot menu interface (optional convenience tool)

### Template-Based Configuration System
The project uses environment variable substitution (`envsubst`) to generate all configuration files from templates:

- `.env` → Configuration templates → Generated configs
- All `.template` files in `config/` are processed by `setup.sh`
- Generated files are gitignored to prevent credential exposure

### Key Data Flow
1. PXE client broadcasts DHCP request
2. Existing DHCP server assigns IP address
3. dnsmasq proxy responds with PXE boot information (TFTP server location)
4. Client downloads iPXE bootloader via TFTP
5. iPXE loads menu from HTTP server and boots selected OS
6. Unattended installation uses preseed/unattend files with domain join scripts

## Configuration Architecture

### Environment Variables (.env)
All configuration is driven by environment variables to avoid hardcoded values:
- Network settings (IP ranges, DNS servers, PXE server IP)
- Domain credentials (AD domain name, join account)
- Service ports and timeouts
- OS installation parameters

### Template Processing
Templates support full `envsubst` variable substitution:
- `config/*.template` → `config/` (dnsmasq, iPXE menu)
- `config/templates/*.template` → `config/templates/` (OS installation files)

### Security Model
- `.env` file contains credentials (gitignored)
- Generated configs contain substituted credentials (gitignored) 
- Template files are safe to commit (no actual credentials)
- Domain join uses minimal-privilege service account

## File Structure Logic

### Generated vs Static Files
- **Templates**: `*.template` files are version controlled and safe
- **Generated**: Created by `setup.sh` from templates, contain credentials (gitignored)
- **Downloaded**: Boot files downloaded by `download-bootfiles.sh` (gitignored)
- **ISO Content**: User-provided Windows/Linux installation files (gitignored)

### Critical Paths
- `tftpboot/`: TFTP root, must be readable by dnsmasq container
- `isos/`: HTTP-served installation files, mounted read-only in nginx
- `config/templates/`: HTTP-served unattend/preseed files for automated installs

## Network Requirements

### Host Network Mode
dnsmasq runs in host network mode because:
- DHCP proxy requires raw socket access to UDP/67
- TFTP server needs UDP/69 access
- Container networking doesn't support DHCP proxy functionality

### Firewall Considerations
Required ports: 67/udp (DHCP), 69/udp (TFTP), 80/tcp (HTTP), 3000/tcp (Web UI)

## Domain Integration

### Windows Domain Join
- Uses `Microsoft-Windows-UnattendedJoin` in unattend.xml
- PowerShell post-install script handles complex scenarios
- Requires domain join service account with "Add workstations to domain" permission

### Linux Domain Join  
- Debian preseed triggers post-install script
- Uses realmd/SSSD for AD integration
- Automatic home directory creation via pam_mkhomedir

## Troubleshooting Context

### Common Failure Points
1. **Network connectivity**: PXE server must be reachable on required ports
2. **Template processing**: Missing .env variables cause setup.sh failures
3. **File permissions**: TFTP requires specific permissions on boot files
4. **Domain join**: Time sync and DNS resolution critical for AD operations
5. **ISO extraction**: Windows requires proper file structure in isos/windows11/

### Service Dependencies
- nginx must start before dnsmasq (docker-compose dependency)
- Configuration generation must complete before service start
- Boot files must be downloaded before first PXE boot attempt