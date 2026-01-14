#!/bin/bash
#
# XDMA Driver Installation Script for Linux
# Installs Xilinx XDMA driver from github.com/Xilinx/dma_ip_drivers
#
# Usage: sudo ./install_xdma_driver.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVER_DIR="${HOME}/xdma_driver"
REPO_URL="https://github.com/Xilinx/dma_ip_drivers"

echo "=== XDMA Driver Installation Script ==="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (sudo)"
    exit 1
fi

# Check for required tools
echo "Checking prerequisites..."
for tool in git make gcc; do
    if ! command -v $tool &> /dev/null; then
        echo "ERROR: $tool is not installed"
        exit 1
    fi
    echo "  [OK] $tool"
done

# Check for kernel headers
KERNEL_VERSION=$(uname -r)
HEADERS_DIR="/lib/modules/${KERNEL_VERSION}/build"
if [ ! -d "$HEADERS_DIR" ]; then
    echo ""
    echo "ERROR: Kernel headers not found for ${KERNEL_VERSION}"
    echo "Install with:"
    echo "  Ubuntu/Debian: sudo apt install linux-headers-${KERNEL_VERSION}"
    echo "  RHEL/CentOS:   sudo yum install kernel-devel-${KERNEL_VERSION}"
    exit 1
fi
echo "  [OK] Kernel headers for ${KERNEL_VERSION}"

echo ""
echo "Step 1: Clone XDMA driver repository..."
if [ -d "$DRIVER_DIR" ]; then
    echo "  Directory exists, updating..."
    cd "$DRIVER_DIR"
    git pull
else
    git clone "$REPO_URL" "$DRIVER_DIR"
    cd "$DRIVER_DIR"
fi

echo ""
echo "Step 2: Build XDMA kernel module..."
cd XDMA/linux-kernel/xdma
make clean || true
make

echo ""
echo "Step 3: Install kernel module..."
make install

echo ""
echo "Step 4: Create udev rules for device permissions..."
cat > /etc/udev/rules.d/60-xdma.rules << 'EOF'
# XDMA device permissions
# Allow users in 'xdma' group to access XDMA devices without root

# Main XDMA devices
KERNEL=="xdma[0-9]*_c2h_[0-9]*", MODE="0666", GROUP="xdma"
KERNEL=="xdma[0-9]*_h2c_[0-9]*", MODE="0666", GROUP="xdma"
KERNEL=="xdma[0-9]*_user", MODE="0666", GROUP="xdma"
KERNEL=="xdma[0-9]*_control", MODE="0666", GROUP="xdma"
KERNEL=="xdma[0-9]*_bypass*", MODE="0666", GROUP="xdma"
KERNEL=="xdma[0-9]*_events_[0-9]*", MODE="0666", GROUP="xdma"
EOF

# Create xdma group if it doesn't exist
if ! getent group xdma > /dev/null 2>&1; then
    groupadd xdma
    echo "  Created 'xdma' group"
fi

# Reload udev rules
udevadm control --reload-rules
udevadm trigger

echo ""
echo "Step 5: Configure kernel module to load at boot..."
echo "xdma" > /etc/modules-load.d/xdma.conf

echo ""
echo "Step 6: Load XDMA driver..."
modprobe -r xdma 2>/dev/null || true
modprobe xdma

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Driver status:"
if lsmod | grep -q xdma; then
    echo "  [OK] xdma module loaded"
else
    echo "  [ERROR] xdma module not loaded"
fi

echo ""
echo "To use XDMA without root, add your user to the 'xdma' group:"
echo "  sudo usermod -aG xdma \$USER"
echo "  (logout and login for changes to take effect)"
echo ""

# Check for PCIe device
echo "PCIe device status:"
if lspci | grep -qi "xilinx\|7024"; then
    lspci | grep -i "xilinx\|7024"
    echo "  [OK] Xilinx PCIe device found"
else
    echo "  [WARNING] No Xilinx PCIe device detected"
    echo "  Make sure FPGA is programmed with PCIe bitstream"
fi

echo ""
echo "Device files:"
ls -la /dev/xdma* 2>/dev/null || echo "  [WARNING] No /dev/xdma* devices found (PCIe not connected)"

echo ""
echo "Next steps:"
echo "  1. Program FPGA with PCIe bitstream"
echo "  2. Reboot or rescan PCIe: echo 1 > /sys/bus/pci/rescan"
echo "  3. Verify: lspci | grep Xilinx"
echo "  4. Test: cd ${SCRIPT_DIR}/../test && make && ./pcie_loopback_test -r"
