#!/bin/bash
# Download iPXE boot files and other required components

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

# Download function with retry
download_file() {
    local url=$1
    local output=$2
    local description=$3
    local max_retries=3
    local retry=0
    
    log_info "Downloading $description..."
    
    while [[ $retry -lt $max_retries ]]; do
        if curl -L --progress-bar -o "$output" "$url"; then
            log_success "Downloaded $description"
            return 0
        else
            retry=$((retry + 1))
            if [[ $retry -lt $max_retries ]]; then
                log_warning "Download failed, retrying ($retry/$max_retries)..."
                sleep 2
            else
                log_error "Failed to download $description after $max_retries attempts"
                return 1
            fi
        fi
    done
}

# Verify file integrity
verify_file() {
    local file=$1
    local expected_hash=$2
    local description=$3
    
    if [[ -n "$expected_hash" ]]; then
        log_info "Verifying $description..."
        local actual_hash=$(sha256sum "$file" | cut -d' ' -f1)
        if [[ "$actual_hash" == "$expected_hash" ]]; then
            log_success "File integrity verified for $description"
        else
            log_error "Hash mismatch for $description"
            log_error "Expected: $expected_hash"
            log_error "Actual:   $actual_hash"
            return 1
        fi
    fi
}

# Download iPXE boot files
download_ipxe() {
    log_info "Downloading iPXE boot files..."
    
    # iPXE URLs (using official builds)
    local ipxe_base_url="https://boot.ipxe.org"
    
    # Create tftpboot directory if it doesn't exist
    mkdir -p tftpboot
    
    # Download iPXE EFI file for UEFI systems
    if ! download_file "${ipxe_base_url}/ipxe.efi" "tftpboot/ipxe.efi" "iPXE EFI boot file"; then
        log_error "Failed to download iPXE EFI file"
        return 1
    fi
    
    # Download iPXE for legacy BIOS (optional)
    if ! download_file "${ipxe_base_url}/undionly.kpxe" "tftpboot/undionly.kpxe" "iPXE BIOS boot file"; then
        log_warning "Failed to download iPXE BIOS file (optional)"
    fi
    
    # Download wimboot for Windows PE
    log_info "Downloading wimboot for Windows PE..."
    if ! download_file "https://github.com/ipxe/wimboot/releases/latest/download/wimboot" "tftpboot/wimboot" "wimboot"; then
        log_error "Failed to download wimboot"
        return 1
    fi
    
    # Make wimboot executable
    chmod +x tftpboot/wimboot
    
    log_success "iPXE boot files downloaded successfully"
}

# Download memtest86+
download_memtest() {
    log_info "Downloading memtest86+..."
    
    local memtest_url="https://www.memtest.org/download/v6.20/mt86plus_6.20.bin.zip"
    local temp_dir=$(mktemp -d)
    
    if download_file "$memtest_url" "$temp_dir/memtest.zip" "memtest86+"; then
        if command_exists unzip; then
            cd "$temp_dir"
            unzip -q memtest.zip
            # Find the .bin file and copy it
            local bin_file=$(find . -name "*.bin" | head -n1)
            if [[ -n "$bin_file" ]]; then
                cp "$bin_file" ../tftpboot/memtest86+
                log_success "memtest86+ installed"
            else
                log_warning "Could not find memtest86+ binary in downloaded archive"
            fi
            cd - >/dev/null
        else
            log_warning "unzip not found, skipping memtest86+ extraction"
        fi
    else
        log_warning "Failed to download memtest86+ (optional)"
    fi
    
    # Clean up
    rm -rf "$temp_dir"
}

# Create sample files structure
create_sample_structure() {
    log_info "Creating sample directory structure..."
    
    # Create ISO directories
    mkdir -p isos/{windows11,debian12}
    
    # Create placeholder files with instructions
    cat > isos/windows11/README.txt << 'EOF'
Windows 11 ISO Instructions
==========================

1. Download Windows 11 ISO from Microsoft
2. Mount or extract the ISO
3. Copy all contents to this directory (isos/windows11/)

Required files:
- bootmgr
- Boot/BCD
- Boot/boot.sdi
- sources/boot.wim
- sources/install.wim (or install.esd)

The directory structure should look like:
isos/windows11/
├── bootmgr
├── Boot/
│   ├── BCD
│   ├── boot.sdi
│   └── ...
├── sources/
│   ├── boot.wim
│   ├── install.wim
│   └── ...
└── ...
EOF

    cat > isos/debian12/README.txt << 'EOF'
Debian 12 Netboot Instructions
==============================

1. Download Debian 12 netboot files or extract from netinst ISO
2. Copy the kernel and initrd to this directory

Required files:
- linux (kernel)
- initrd.gz (initial ramdisk)

You can get these from:
- Debian netboot: http://ftp.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/
- Or extract from debian-12.x.x-amd64-netinst.iso

Download commands:
wget http://ftp.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux
wget http://ftp.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz
EOF

    log_success "Sample directory structure created"
}

# Download Debian netboot files
download_debian_netboot() {
    log_info "Downloading Debian 12 netboot files..."
    
    local debian_base="http://ftp.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64"
    
    mkdir -p isos/debian12
    
    if download_file "${debian_base}/linux" "isos/debian12/linux" "Debian 12 kernel"; then
        if download_file "${debian_base}/initrd.gz" "isos/debian12/initrd.gz" "Debian 12 initrd"; then
            log_success "Debian 12 netboot files downloaded"
        else
            log_error "Failed to download Debian initrd"
            return 1
        fi
    else
        log_error "Failed to download Debian kernel"
        return 1
    fi
}

# Set file permissions
set_permissions() {
    log_info "Setting file permissions..."
    
    # Set proper permissions for TFTP files
    find tftpboot/ -type f -exec chmod 644 {} \;
    find tftpboot/ -name "wimboot" -exec chmod 755 {} \;
    
    # Set permissions for ISO directories
    find isos/ -type d -exec chmod 755 {} \;
    find isos/ -type f -exec chmod 644 {} \;
    
    log_success "File permissions set"
}

# Display information
display_info() {
    log_success "Boot files download completed!"
    echo
    log_info "Downloaded files:"
    echo "- iPXE EFI boot file: tftpboot/ipxe.efi"
    echo "- iPXE BIOS boot file: tftpboot/undionly.kpxe"
    echo "- wimboot for Windows PE: tftpboot/wimboot"
    echo "- memtest86+: tftpboot/memtest86+"
    echo "- Debian 12 kernel: isos/debian12/linux"
    echo "- Debian 12 initrd: isos/debian12/initrd.gz"
    echo
    log_warning "Still needed:"
    echo "- Windows 11 ISO contents in isos/windows11/"
    echo "  (See isos/windows11/README.txt for instructions)"
    echo
    log_info "After adding Windows 11 files, run: ./scripts/setup.sh"
}

# Main execution
main() {
    echo "========================================"
    echo "    PXE Boot Files Download Script"
    echo "========================================"
    echo
    
    # Change to script directory
    cd "$(dirname "${BASH_SOURCE[0]}")/.."
    
    # Check prerequisites
    if ! command_exists curl; then
        log_error "curl is required but not installed"
        exit 1
    fi
    
    # Download files
    if ! download_ipxe; then
        log_error "Failed to download iPXE files"
        exit 1
    fi
    
    download_memtest
    create_sample_structure
    
    if ! download_debian_netboot; then
        log_error "Failed to download Debian netboot files"
        exit 1
    fi
    
    set_permissions
    display_info
}

# Run main function
main "$@"