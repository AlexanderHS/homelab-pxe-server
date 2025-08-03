# Homelab PXE Server

A Docker-based PXE proxy server for unattended OS deployment in home labs and enterprise environments. This solution works alongside existing DHCP/DNS infrastructure without requiring changes to your network configuration.

## Features

- **Proxy DHCP**: Works with existing DHCP servers (routers/firewalls)
- **UEFI PXE Boot**: Full support for modern UEFI systems
- **iPXE Menu System**: Interactive boot menu with multiple options
- **Unattended Installation**: Automated Windows 11 and Debian 12 deployment
- **Domain Join**: Automatic domain joining for both Windows and Linux
- **Docker Compose**: Easy deployment and management
- **Environment-based Configuration**: No hardcoded values

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   PXE Client    │    │   PXE Server    │    │ Existing DHCP   │
│   (UEFI Boot)   │    │  (This Setup)   │    │     Server      │
├─────────────────┤    ├─────────────────┤    ├─────────────────┤
│ 1. DHCP Request │───▶│                 │    │                 │
│ 2. Gets IP from │    │ dnsmasq (proxy) │◄──▶│   Router/FW     │
│    existing DHCP│    │ nginx (HTTP)    │    │                 │
│ 3. Gets PXE     │◄───│ netboot.xyz     │    │                 │
│    info from    │    │                 │    │                 │
│    proxy server │    │                 │    │                 │
│ 4. Downloads    │    │                 │    │                 │
│    boot files   │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Quick Start

### Prerequisites

- Docker and Docker Compose
- Linux host with network access
- Existing DHCP server on the network
- Domain environment (Active Directory)

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd homelab-pxe-server
   ```

2. **Configure environment**
   ```bash
   cp .env.example .env
   # Edit .env with your network settings
   nano .env
   ```

3. **Run setup script**
   ```bash
   ./scripts/setup.sh
   ```

4. **Download boot files**
   ```bash
   ./scripts/download-bootfiles.sh
   ```

5. **Add Windows 11 ISO**
   - Extract Windows 11 ISO to `isos/windows11/`
   - See `isos/windows11/README.txt` for details

6. **Start the services**
   ```bash
   docker-compose up -d
   ```

7. **Test PXE boot**
   - Boot a UEFI client via network
   - Select boot option from iPXE menu

## Configuration

### Network Settings (.env)

```bash
# Network Configuration
NETWORK_SUBNET=10.0.0.0/24          # Your network subnet
GATEWAY_IP=10.0.0.1                 # Network gateway
DNS_SERVERS=10.0.0.11,10.0.0.12     # Existing DNS servers
PXE_SERVER_IP=10.0.0.100            # This server's IP

# Domain Configuration
DOMAIN_NAME=homelab.local            # Active Directory domain
DOMAIN_JOIN_USER=pxe-joiner          # Domain join account
DOMAIN_JOIN_PASS=SecurePassword123!  # Domain join password
```

### Service Ports

- **67/UDP**: DHCP proxy (requires host network mode)
- **69/UDP**: TFTP server
- **80/TCP**: HTTP file server (configurable)
- **3000/TCP**: NetBoot.xyz web interface (configurable)

### Firewall Configuration

Allow the following ports on your PXE server:

```bash
# UFW example
sudo ufw allow 67/udp
sudo ufw allow 69/udp
sudo ufw allow 80/tcp
sudo ufw allow 3000/tcp

# iptables example
iptables -A INPUT -p udp --dport 67 -j ACCEPT
iptables -A INPUT -p udp --dport 69 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 3000 -j ACCEPT
```

## Boot Menu Options

The iPXE menu provides the following options:

1. **Windows 11 Unattended Install**
   - Fully automated Windows 11 deployment
   - Automatic domain join
   - Local administrator account creation
   - PowerShell post-install script

2. **Debian 12 Unattended Install**
   - Automated Debian 12 installation
   - Automatic domain join with realmd/SSSD
   - SSH server configuration
   - Package updates

3. **Boot from local disk**
   - Continue to local OS

4. **Network diagnostics**
   - Display network configuration
   - Useful for troubleshooting

5. **Memory test (memtest86+)**
   - Hardware memory testing

6. **Reboot**
   - Restart the system

## Directory Structure

```
homelab-pxe-server/
├── docker-compose.yml              # Docker services definition
├── .env.example                    # Environment variables template
├── config/                         # Configuration files
│   ├── dnsmasq.conf.template       # dnsmasq proxy DHCP config
│   ├── menu.ipxe.template          # iPXE boot menu
│   ├── nginx.conf                  # Nginx HTTP server config
│   └── templates/                  # Installation templates
│       ├── windows11-unattend.xml.template
│       ├── debian-preseed.cfg.template
│       ├── debian-post-install.sh.template
│       └── domain-join.ps1.template
├── tftpboot/                       # TFTP boot files
│   ├── ipxe.efi                   # iPXE UEFI boot file
│   ├── menu.ipxe                  # Generated iPXE menu
│   └── wimboot                    # Windows PE boot loader
├── isos/                           # ISO files and extracted content
│   ├── windows11/                 # Windows 11 ISO contents
│   └── debian12/                  # Debian netboot files
└── scripts/                       # Setup and utility scripts
    ├── setup.sh                   # Main setup script
    └── download-bootfiles.sh       # Download boot files
```

## Domain Configuration

### Active Directory Requirements

1. **Domain Join Account**
   - Create a service account with domain join permissions
   - Recommended: `pxe-joiner` with minimal privileges
   - Grant "Add workstations to domain" right

2. **DNS Configuration**
   - Ensure your DNS servers can resolve the domain
   - PXE clients need to reach domain controllers

3. **Time Synchronization**
   - Configure NTP/time sync on PXE server
   - Essential for domain operations

### Security Best Practices

1. **Credential Management**
   - Use strong passwords for all accounts
   - Consider external credential files
   - Rotate domain join password regularly

2. **Network Security**
   - Restrict PXE server access via firewall
   - Use VLANs to isolate PXE traffic
   - Monitor for unauthorized PXE requests

3. **File Permissions**
   - Secure .env file (chmod 600)
   - Limit access to configuration files
   - Regular security updates

## Troubleshooting

### Common Issues

**PXE client doesn't get boot menu**
- Check DHCP proxy is running: `docker-compose logs dnsmasq`
- Verify network connectivity to PXE server
- Ensure firewall allows UDP/67 and UDP/69

**Boot files not found**
- Run `./scripts/download-bootfiles.sh`
- Check TFTP service: `docker-compose logs dnsmasq`
- Verify file permissions in `tftpboot/`

**Windows installation fails**
- Check Windows ISO is properly extracted to `isos/windows11/`
- Verify unattend.xml template variables
- Review installation logs in Windows PE

**Domain join fails**
- Verify domain credentials in .env
- Check DNS resolution to domain controllers
- Review domain join script logs

**Debian installation issues**
- Ensure netboot files are downloaded
- Check preseed configuration
- Verify mirror accessibility

### Logs and Monitoring

**View all service logs**
```bash
docker-compose logs -f
```

**View specific service logs**
```bash
docker-compose logs -f dnsmasq
docker-compose logs -f nginx
docker-compose logs -f netbootxyz
```

**Monitor network traffic**
```bash
# Monitor DHCP traffic
sudo tcpdump -i any port 67 or port 68

# Monitor TFTP traffic
sudo tcpdump -i any port 69
```

### Service Status

**Check service health**
```bash
docker-compose ps
```

**Restart services**
```bash
docker-compose restart
```

**Update configuration**
```bash
# After changing .env
./scripts/setup.sh
docker-compose restart
```

## Advanced Configuration

### Custom Boot Options

Add custom menu items by editing `config/menu.ipxe.template`:

```ipxe
:custom
echo Loading custom image...
kernel http://${PXE_SERVER_IP}/custom/vmlinuz
initrd http://${PXE_SERVER_IP}/custom/initrd.img
boot
```

### Multiple OS Versions

Extend the structure for additional OS versions:

```
isos/
├── windows10/
├── windows11/
├── debian11/
├── debian12/
├── ubuntu2204/
└── centos8/
```

### External Storage

Mount external storage for ISOs:

```yaml
# In docker-compose.yml
volumes:
  - /mnt/storage/isos:/usr/share/nginx/html/isos:ro
```

## Migration and Backup

### Backup Configuration

```bash
# Backup script
tar -czf pxe-backup-$(date +%Y%m%d).tar.gz \
  .env config/ tftpboot/ scripts/
```

### Migration to New Server

1. Copy configuration and files
2. Update IP addresses in .env
3. Run setup script on new server
4. Update DHCP reservations if needed

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:
- Create an issue in the repository
- Check the troubleshooting section
- Review Docker and dnsmasq documentation

## Acknowledgments

- [iPXE Project](https://ipxe.org/) for network boot capabilities
- [dnsmasq](http://www.thekelleys.org.uk/dnsmasq/doc.html) for DHCP proxy and TFTP
- [NetBoot.xyz](https://netboot.xyz/) for additional boot options
- Community contributors and testers