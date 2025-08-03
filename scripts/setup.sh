#!/bin/bash
# PXE Server Setup Script
# Validates environment and generates configuration files

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate IP address format
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Validate network subnet format
validate_subnet() {
    local subnet=$1
    if [[ $subnet =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        local ip=$(echo "$subnet" | cut -d'/' -f1)
        local cidr=$(echo "$subnet" | cut -d'/' -f2)
        if validate_ip "$ip" && [[ $cidr -ge 8 && $cidr -le 30 ]]; then
            return 0
        fi
    fi
    return 1
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_deps=()
    
    # Check for Docker
    if ! command_exists docker; then
        missing_deps+=("docker")
    else
        log_success "Docker found"
    fi
    
    # Check for Docker Compose
    if ! command_exists docker-compose && ! docker compose version >/dev/null 2>&1; then
        missing_deps+=("docker-compose")
    else
        log_success "Docker Compose found"
    fi
    
    # Check for envsubst
    if ! command_exists envsubst; then
        missing_deps+=("gettext (for envsubst)")
    else
        log_success "envsubst found"
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_error "Please install the missing dependencies and run this script again."
        exit 1
    fi
    
    log_success "All prerequisites satisfied"
}

# Check port availability
check_ports() {
    log_info "Checking port availability..."
    
    local ports=("67:udp" "69:udp" "${HTTP_PORT:-80}:tcp" "${WEB_INTERFACE_PORT:-3000}:tcp")
    local busy_ports=()
    
    for port_proto in "${ports[@]}"; do
        local port=$(echo "$port_proto" | cut -d':' -f1)
        local proto=$(echo "$port_proto" | cut -d':' -f2)
        
        if [[ $proto == "tcp" ]]; then
            if netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
                busy_ports+=("$port/tcp")
            fi
        elif [[ $proto == "udp" ]]; then
            if netstat -ulnp 2>/dev/null | grep -q ":${port} "; then
                busy_ports+=("$port/udp")
            fi
        fi
    done
    
    if [[ ${#busy_ports[@]} -gt 0 ]]; then
        log_warning "The following ports are already in use: ${busy_ports[*]}"
        log_warning "This may cause conflicts. Consider stopping services using these ports."
    else
        log_success "All required ports are available"
    fi
}

# Validate .env file
validate_env() {
    log_info "Validating environment configuration..."
    
    if [[ ! -f .env ]]; then
        log_error ".env file not found. Please copy .env.example to .env and configure it."
        exit 1
    fi
    
    # Source .env file
    set -a
    source .env
    set +a
    
    # Required variables
    local required_vars=(
        "NETWORK_SUBNET"
        "GATEWAY_IP"
        "DNS_SERVERS"
        "PXE_SERVER_IP"
        "DOMAIN_NAME"
        "DOMAIN_JOIN_USER"
        "DOMAIN_JOIN_PASS"
        "LOCAL_ADMIN_USER"
        "LOCAL_ADMIN_PASS"
    )
    
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        exit 1
    fi
    
    # Validate network configuration
    if ! validate_subnet "$NETWORK_SUBNET"; then
        log_error "Invalid NETWORK_SUBNET format: $NETWORK_SUBNET"
        exit 1
    fi
    
    if ! validate_ip "$GATEWAY_IP"; then
        log_error "Invalid GATEWAY_IP format: $GATEWAY_IP"
        exit 1
    fi
    
    if ! validate_ip "$PXE_SERVER_IP"; then
        log_error "Invalid PXE_SERVER_IP format: $PXE_SERVER_IP"
        exit 1
    fi
    
    # Validate DNS servers
    IFS=',' read -ra DNS_ARRAY <<< "$DNS_SERVERS"
    for dns in "${DNS_ARRAY[@]}"; do
        if ! validate_ip "$dns"; then
            log_error "Invalid DNS server IP: $dns"
            exit 1
        fi
    done
    
    log_success "Environment configuration is valid"
}

# Generate configuration files
generate_configs() {
    log_info "Generating configuration files..."
    
    # Generate dnsmasq.conf with proper DNS server formatting
    log_info "Processing DNS servers: $DNS_SERVERS"
    
    # Create DNS server lines
    dns_server_lines=""
    IFS=',' read -ra DNS_ARRAY <<< "$DNS_SERVERS"
    for dns in "${DNS_ARRAY[@]}"; do
        dns_server_lines="${dns_server_lines}server=${dns}\\n"
    done
    
    # Generate config with environment substitution
    envsubst < config/dnsmasq.conf.template > config/dnsmasq.conf.tmp
    
    # Replace DNS servers placeholder with proper server lines
    sed -i "s/__DNS_SERVERS_PLACEHOLDER__/${dns_server_lines}/" config/dnsmasq.conf.tmp
    
    # Ensure file ends with newline
    echo "" >> config/dnsmasq.conf.tmp
    
    mv config/dnsmasq.conf.tmp config/dnsmasq.conf
    log_success "Generated config/dnsmasq.conf"
    
    # Generate iPXE menu
    envsubst < config/menu.ipxe.template > tftpboot/menu.ipxe
    log_success "Generated tftpboot/menu.ipxe"
    
    # Generate Windows unattend.xml
    envsubst < config/templates/windows11-unattend.xml.template > config/templates/windows11-unattend.xml
    log_success "Generated config/templates/windows11-unattend.xml"
    
    # Generate Debian preseed
    envsubst < config/templates/debian-preseed.cfg.template > config/templates/debian-preseed.cfg
    log_success "Generated config/templates/debian-preseed.cfg"
    
    # Generate Debian post-install script
    envsubst < config/templates/debian-post-install.sh.template > config/templates/debian-post-install.sh
    chmod +x config/templates/debian-post-install.sh
    log_success "Generated config/templates/debian-post-install.sh"
    
    # Generate PowerShell domain join script
    envsubst < config/templates/domain-join.ps1.template > config/templates/domain-join.ps1
    log_success "Generated config/templates/domain-join.ps1"
    
    log_success "All configuration files generated successfully"
}

# Create directories
create_directories() {
    log_info "Creating required directories..."
    
    local dirs=(
        "tftpboot"
        "isos/windows11"
        "isos/debian12"
        "config/templates"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        log_success "Created directory: $dir"
    done
}

# Set permissions
set_permissions() {
    log_info "Setting file permissions..."
    
    # Make scripts executable
    find scripts/ -name "*.sh" -exec chmod +x {} \;
    
    # Set appropriate permissions for TFTP files
    chmod -R 755 tftpboot/
    
    # Set read permissions for config files
    chmod -R 644 config/
    
    log_success "File permissions set"
}

# Display next steps
display_next_steps() {
    log_success "Setup completed successfully!"
    echo
    log_info "Next steps:"
    echo "1. Download boot files: ./scripts/download-bootfiles.sh"
    echo "2. Place your ISO files in the isos/ directory:"
    echo "   - Windows 11 ISO extracted to isos/windows11/"
    echo "   - Debian 12 netinst ISO contents to isos/debian12/"
    echo "3. Start the PXE server: docker-compose up -d"
    echo "4. Monitor logs: docker-compose logs -f"
    echo
    log_info "Web interfaces will be available at:"
    echo "- Nginx HTTP server: http://${PXE_SERVER_IP}:${HTTP_PORT:-80}"
    echo "- NetBoot.xyz interface: http://${PXE_SERVER_IP}:${WEB_INTERFACE_PORT:-3000}"
    echo
    log_warning "Remember to configure your firewall to allow traffic on the required ports!"
}

# Main execution
main() {
    echo "========================================"
    echo "    PXE Server Setup Script"
    echo "========================================"
    echo
    
    # Change to script directory
    cd "$(dirname "${BASH_SOURCE[0]}")/.."
    
    check_prerequisites
    validate_env
    check_ports
    create_directories
    generate_configs
    set_permissions
    display_next_steps
}

# Run main function
main "$@"