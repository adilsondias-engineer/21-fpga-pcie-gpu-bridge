# Project 21: PCIe GPU Bridge

## Part of FPGA Trading Systems Portfolio

This project is part of a complete end-to-end trading system:
- **Main Repository:** [fpga-trading-systems](https://github.com/adilsondias-engineer/fpga-trading-systems)
- **Project Number:** 21 of 30
- **Category:** FPGA Core
- **Dependencies:** None (PCIe infrastructure project)

---

## Overview

PCIe Gen2 x4 interface for FPGA ↔ CPU ↔ GPU communication, enabling:
- BBO stream transfer from FPGA to CPU (C2H DMA)
- Control commands from CPU to FPGA (H2C DMA + AXI-Lite)
- Zero-copy data path to GPU (CUDA pinned memory)

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Host PC (Linux)                                  │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │                     User Space Application                          ││
│  │  ┌─────────────┐  ┌─────────────┐  ┌────────────────────────────┐  ││
│  │  │ BBO Reader  │  │  Control    │  │   CUDA Pinned Memory       │  ││
│  │  │ (C2H DMA)   │  │  Writer     │  │   (GPU Zero-Copy)          │  ││
│  │  └──────┬──────┘  └──────┬──────┘  └─────────────┬──────────────┘  ││
│  └─────────┼────────────────┼───────────────────────┼──────────────────┘│
│            │                │                       │                    │
│  ┌─────────┼────────────────┼───────────────────────┼──────────────────┐│
│  │         │      XDMA Linux Kernel Driver          │                  ││
│  │         ▼                ▼                       ▼                  ││
│  │  /dev/xdma0_c2h_0  /dev/xdma0_h2c_0  /dev/xdma0_user              ││
│  └─────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────┘
                              │ PCIe Gen2 x4 (~2 GB/s)
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         FPGA (AX7203 - Kintex-7)                        │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │                        XDMA IP Core                                 ││
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  ││
│  │  │ C2H Channel  │  │ H2C Channel  │  │  AXI-Lite Master         │  ││
│  │  │ (BBO Stream) │  │ (Commands)   │  │  (Control Registers)     │  ││
│  │  └──────┬───────┘  └──────┬───────┘  └───────────┬──────────────┘  ││
│  └─────────┼─────────────────┼──────────────────────┼──────────────────┘│
│            │                 │                      │                    │
│  ┌─────────┼─────────────────┼──────────────────────┼──────────────────┐│
│  │         ▼                 ▼                      ▼                  ││
│  │  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────────┐││
│  │  │ BBO Stream   │  │ Command      │  │  Control Registers         │││
│  │  │ Buffer       │  │ FIFO         │  │  (AXI-Lite Slave)          │││
│  │  │ (AXI-Stream) │  │ (AXI-Stream) │  │  - Enable/Status           │││
│  │  └──────┬───────┘  └──────┬───────┘  │  - Symbol Filter           │││
│  │         │                 │          │  - Statistics              │││
│  │         │                 │          └────────────────────────────┘││
│  └─────────┼─────────────────┼─────────────────────────────────────────┘│
│            │                 │                                           │
│  ┌─────────┼─────────────────┼─────────────────────────────────────────┐│
│  │         ▼                 ▼              Trading Logic (200 MHz)    ││
│  │  ┌──────────────────────────────────────────────────────────────┐  ││
│  │  │              Existing Order Book / BBO Detection              │  ││
│  │  │              (from Project 20)                                │  ││
│  │  └───────────────────────────────────────────────────────────────┘  ││
│  └─────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────┘
```

## Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| PCIe Bandwidth | ~2 GB/s | Gen2 x4 theoretical max |
| DMA Latency | <2 μs | Single 4KB transfer |
| BBO Update Rate | 100K updates/sec | 36 bytes per BBO |
| Control Register Access | <1 μs | AXI-Lite single word |

## XDMA Configuration

```
PCIe Link:
  - Max Link Speed: 5.0 GT/s (Gen2)
  - Max Link Width: X4
  - Device ID: 0x7024
  - Vendor ID: 0x10EE (Xilinx)

AXI Interface:
  - Data Width: 128-bit
  - Clock Frequency: 125 MHz
  - DMA Channels: 1 H2C + 1 C2H (expandable to 4 each)

Address Map:
  - 0x00000000-0x0FFFFFFF: C2H DMA Buffer (256 MB)
  - 0x10000000-0x1FFFFFFF: H2C DMA Buffer (256 MB)
  - 0x20000000-0x2000FFFF: Control Registers (64 KB)
```

## BBO Stream Format (36 bytes)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0-7 | 8 | Symbol | Stock ticker (ASCII, space-padded) |
| 8-11 | 4 | Bid Price | Fixed-point (4 decimal places) |
| 12-15 | 4 | Bid Size | Number of shares |
| 16-19 | 4 | Ask Price | Fixed-point (4 decimal places) |
| 20-23 | 4 | Ask Size | Number of shares |
| 24-27 | 4 | Spread | Ask - Bid (4 decimal places) |
| 28-31 | 4 | RX Timestamp | FPGA cycle count when ITCH received |
| 32-35 | 4 | TX Timestamp | FPGA cycle count when packet sent |

## Control Register Map (AXI-Lite)

| Address | Name | R/W | Description |
|---------|------|-----|-------------|
| 0x00 | VERSION | R | IP version (0x21000001) |
| 0x04 | CONTROL | RW | Bit 0: Enable, Bit 1: Reset |
| 0x08 | STATUS | R | Bit 0: Running, Bit 1: FIFO Full |
| 0x0C | BBO_COUNT | R | Total BBOs transmitted |
| 0x10-0x17 | SYMBOL_FILTER_0 | RW | First symbol filter (8 chars) |
| 0x18-0x1F | SYMBOL_FILTER_1 | RW | Second symbol filter |
| ... | ... | ... | Up to 8 symbol filters |
| 0x40 | RX_TIMESTAMP | R | Last RX timestamp |
| 0x44 | TX_TIMESTAMP | R | Last TX timestamp |
| 0x48 | LATENCY_US | R | Last FPGA latency (microseconds × 100) |

## Linux Driver Setup (CRITICAL)

### Driver Selection

**IMPORTANT**: Linux has TWO different `xdma` drivers. You MUST use the correct one:

| Driver | Type | Purpose | Device Nodes |
|--------|------|---------|--------------|
| **Kernel built-in** `xdma.ko` | Platform driver | DMA engines in SoCs (Zynq, etc.) | None for PCIe |
| **Xilinx dma_ip_drivers** `xdma.ko` | PCIe driver | PCIe endpoint DMA (what we need!) | `/dev/xdma*` |

### Check Current Driver

```bash
# Check if wrong driver is loaded
lsmod | grep xdma
modinfo xdma 2>/dev/null | grep -E "filename|description"

# If you see "platform" or no PCIe mentions, it's the WRONG driver
```

### Install Correct XDMA Driver

```bash
# 1. Clone Xilinx dma_ip_drivers (if not already done)
cd /work/projects
git clone https://github.com/Xilinx/dma_ip_drivers

# 2. Build the PCIe XDMA driver
cd dma_ip_drivers/XDMA/linux-kernel/xdma
make clean
make

# 3. Unload wrong driver (if loaded)
sudo rmmod xdma 2>/dev/null

# 4. Load correct driver
sudo insmod /work/projects/dma_ip_drivers/XDMA/linux-kernel/xdma/xdma.ko

# 5. Verify device nodes created
ls -la /dev/xdma*
```

### Verification Checklist

```bash
# 1. Check PCIe device is detected
lspci -d 10ee:
# Expected: XX:00.0 Memory controller: Xilinx Corporation Device 7024

# 2. Check driver is bound
lspci -d 10ee: -k
# Expected: Kernel driver in use: xdma

# 3. Check device nodes exist
ls /dev/xdma0_* | head -5
# Expected: /dev/xdma0_c2h_0, /dev/xdma0_h2c_0, /dev/xdma0_control, etc.

# 4. Test register access (read XDMA identifier)
/work/projects/dma_ip_drivers/XDMA/linux-kernel/tools/reg_rw /dev/xdma0_control 0x0 w
# Expected: 0x1fc00006 (XDMA block identifier)

# 5. Test DMA read (should return data if FPGA is streaming)
dd if=/dev/xdma0_c2h_0 of=/tmp/test.bin bs=64 count=1
xxd /tmp/test.bin
```

### Build XDMA Test Tools

```bash
cd /work/projects/dma_ip_drivers/XDMA/linux-kernel/tools
make

# Available tools:
# - reg_rw        : Read/write XDMA registers
# - dma_to_device : H2C DMA test (host → FPGA)
# - dma_from_device: C2H DMA test (FPGA → host)
# - performance   : DMA bandwidth test
```

### Troubleshooting

| Symptom | Cause | Solution |
|---------|-------|----------|
| `lspci -d 10ee:` returns nothing | No power or bitstream not loaded | Connect 12V power, program FPGA |
| `/dev/xdma*` not created | Wrong driver loaded | Unload kernel driver, load dma_ip_drivers version |
| `reg_rw` returns all 0xFF | PCIe link not trained | Check power, rescan PCIe bus |
| DMA read hangs | FPGA not streaming data | Check FPGA design has data source |
| Permission denied | Need root or udev rules | `sudo` or add udev rule (see below) |

### Udev Rules (Optional)

Create `/etc/udev/rules.d/99-xdma.rules` for non-root access:

```
# Xilinx XDMA PCIe devices
SUBSYSTEM=="xdma", MODE="0666", GROUP="xdma"
```

Then: `sudo udevadm control --reload-rules && sudo udevadm trigger`

### Device Files

```bash
# DMA channels
/dev/xdma0_c2h_0    # Card-to-Host (BBO stream)
/dev/xdma0_h2c_0    # Host-to-Card (commands)
/dev/xdma0_user     # Control registers (mmap)

# Events/Interrupts
/dev/xdma0_events_0 # BBO available interrupt
```

### Example Usage (C++)

```cpp
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

// Open DMA channel for BBO stream
int fd_c2h = open("/dev/xdma0_c2h_0", O_RDONLY);

// Read BBO update (36 bytes)
BBOData bbo;
ssize_t n = read(fd_c2h, &bbo, sizeof(BBOData));

// Memory-mapped control registers
int fd_user = open("/dev/xdma0_user", O_RDWR);
uint32_t* ctrl = (uint32_t*)mmap(NULL, 4096,
    PROT_READ | PROT_WRITE, MAP_SHARED, fd_user, 0);

// Enable BBO streaming
ctrl[1] = 0x01;  // CONTROL register, bit 0 = enable

// Read status
uint32_t status = ctrl[2];  // STATUS register
```

## Build Instructions

### FPGA Bitstream

```bash
cd 21-pcie-gpu-bridge

# Step 1: Create block design with XDMA IP
vivado -mode batch -source scripts/create_block_design.tcl

# Step 2: Add custom BBO stream logic
vivado -mode batch -source scripts/add_custom_logic.tcl

# Step 3: Run implementation and generate bitstream (from Vivado GUI or TCL)
vivado vivado_project/pcie_gpu_bridge.xpr
# In Vivado: Run Synthesis → Run Implementation → Generate Bitstream
```

### Linux Driver

```bash
# Clone Xilinx XDMA driver
git clone https://github.com/Xilinx/dma_ip_drivers
cd dma_ip_drivers/XDMA/linux-kernel/xdma

# Build and install
make
sudo make install
sudo modprobe xdma
```

### Test Application

```bash
cd test
make
./pcie_loopback_test
```

## Files

```
21-pcie-gpu-bridge/
├── src/
│   ├── pcie_bbo_top.vhd          # Top-level PCIe BBO wrapper (integrates all modules)
│   ├── bbo_axi_stream.vhd        # BBO to 128-bit AXI-Stream converter
│   ├── bbo_cdc_fifo.vhd          # Clock domain crossing FIFO (200 MHz → XDMA)
│   ├── control_registers.vhd     # AXI-Lite slave (config & status)
│   ├── latency_calculator.vhd    # 4-point latency measurement (min/max/last)
│   └── xdma_wrapper.cpp          # C++ XDMA wrapper class
├── include/
│   ├── pcie_types.h              # C++ type definitions
│   └── xdma_wrapper.h            # XDMA C++ wrapper class
├── constraints/
│   └── ax7203_pcie.xdc           # PCIe pin constraints
├── scripts/
│   ├── create_block_design.tcl   # Block design generation (XDMA + AXI infrastructure)
│   ├── add_custom_logic.tcl      # Add custom BBO logic to block design
│   └── install_xdma_driver.sh    # Linux driver installation script
├── driver/
│   └── xdma_patches/             # Any Linux-specific patches
├── test/
│   ├── tb_bbo_axi_stream.vhd     # Testbench: AXI-Stream converter
│   ├── tb_bbo_cdc_fifo.vhd       # Testbench: CDC FIFO
│   ├── pcie_loopback_test.cpp    # Basic loopback test
│   └── Makefile
└── docs/
    └── pcie_integration_notes.md # Detailed integration notes
```

## Custom Logic Architecture

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                           pcie_bbo_top                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │                                                                         │  │
│  │  ┌─────────────┐    ┌─────────────────┐    ┌───────────────────────┐  │  │
│  │  │ bbo_cdc_fifo│───▶│ bbo_axi_stream  │───▶│  AXI-Stream to C2H   │  │  │
│  │  │ (CDC 200→   │    │ (128-bit beats) │    │  (Block Design FIFO) │  │  │
│  │  │  XDMA clk)  │    │                 │    │                      │  │  │
│  │  └──────▲──────┘    └─────────────────┘    └───────────────────────┘  │  │
│  │         │                    │                                         │  │
│  │         │           ┌────────▼────────┐                               │  │
│  │  From   │           │latency_calculator│                               │  │
│  │  Order  │           │ (min/max/last)  │                               │  │
│  │  Book   │           └────────┬────────┘                               │  │
│  │         │                    │                                         │  │
│  │         │           ┌────────▼────────┐    ┌───────────────────────┐  │  │
│  │         │           │control_registers│◀───│  AXI-Lite from Host   │  │  │
│  │         │           │ (AXI-Lite slave)│    │  (via XDMA M_AXI_LITE)│  │  │
│  │         │           └─────────────────┘    └───────────────────────┘  │  │
│  │         │                                                              │  │
│  └─────────┼──────────────────────────────────────────────────────────────┘  │
│            │                                                                  │
│  Trading   │  clk_trading (200 MHz)                                          │
│  Logic ────┴──────────────────────────────────────────────────────────────── │
└───────────────────────────────────────────────────────────────────────────────┘
```

## Integration with Project 20

This project extends Project 20 (Order Book) by adding PCIe output alongside the existing UDP output:

1. **BBO FIFO Output**: Connects to both UDP TX (existing) and PCIe C2H (new)
2. **Control Interface**: Replaces/augments UART configuration with PCIe
3. **Shared Trading Logic**: Order book and BBO detection unchanged

## Hardware Setup (CRITICAL)

### Power Requirements

**IMPORTANT**: The AX7203 requires external 12V power for PCIe operation!

The GTP transceivers used for PCIe draw ~1-1.5W additional power compared to
non-GTP designs (like Project 20 Ethernet). Without external power:
- LEDs appear "half-bright"
- PCIe device not detected (`lspci -d 10ee:` returns nothing)
- XDMA driver won't load

**Power options (diode-OR on board):**
1. **CN1**: External 12V DC barrel jack
2. **J14**: ATX PSU 4-pin Molex connector
3. **PCIe slot**: 12V from PCIe edge connector

For reliable operation, connect CN1 or J14 in addition to PCIe slot power.

### GTP Lane Constraints (CRITICAL)

The XDMA IP auto-generates GTP lane constraints with the **WRONG order** for AX7203.
This is handled automatically by the TCL script, but for manual builds:

**Auto-generated (WRONG for AX7203):**
```
Lane 0 → X0Y7
Lane 1 → X0Y6
Lane 2 → X0Y5
Lane 3 → X0Y4
```

**AX7203 correct order:**
```
Lane 0 → X0Y5
Lane 1 → X0Y4
Lane 2 → X0Y6
Lane 3 → X0Y7
```

**Solution:**
1. After `generate_target`, disable the auto-generated constraint file:
   ```tcl
   set_property IS_ENABLED false [get_files *pcie2_ip-PCIE_X0Y0.xdc]
   ```
2. Use `constraints/ax7203_pcie.xdc` which has the correct lane order

### JTAG vs Flash Boot

- For **JTAG programming**: Keep JTAG cable connected
- For **Flash boot** (cold boot from SPI flash): **Disconnect JTAG cable**
  - JTAG cable prevents FPGA from booting from flash
  - Program flash → Power off → Disconnect JTAG → Power on

## Current Status

**PCIe Link: WORKING** ✓

```
$ lspci -d 10ee:
11:00.0 Memory controller: Xilinx Corporation Device 7024

$ cat /sys/bus/pci/devices/0000:11:00.0/current_link_*
2.5 GT/s PCIe   (Gen1, negotiated down via TB4)
4               (x4 lanes)

$ ls /dev/xdma0_*
/dev/xdma0_c2h_0      # Card-to-Host DMA (BBO stream)
/dev/xdma0_c2h_1
/dev/xdma0_control
/dev/xdma0_events_*   # Interrupt events
/dev/xdma0_h2c_0      # Host-to-Card DMA (commands)
/dev/xdma0_h2c_1
```

**Board capability:** PCIe Gen2 x4 (5.0 GT/s, ~2 GB/s)

**Tested configurations:**
- **Native PCIe slot**: Gen2 x4 (5.0 GT/s) - full speed with external 12V power
- **Thunderbolt 4 dock**: Gen1 x4 (2.5 GT/s) - link trains down due to TB4 tunnel limitations

### DMA Bandwidth Test Results

Tested with vendor HDMI example bitstream (continuous streaming):

```bash
# Quick bandwidth test
dd if=/dev/xdma0_c2h_0 of=/dev/null bs=1M count=100
```

| Transfer Size | Throughput | Notes |
|---------------|------------|-------|
| 1 MB          | ~1.0 GB/s  | Single transfer |
| 10 MB         | ~953 MB/s  | Sustained |
| 100 MB        | ~953 MB/s  | Sustained |

**~950 MB/s** sustained throughput = **7.6 Gbps** (via TB4 dock)

With 44-byte BBO packets, this supports **~21.6 million updates/sec** - far exceeding any exchange's actual rate.

## Dependencies

- Vivado 2019.1+ (for XDMA IP v4.1)
- Linux kernel 5.x+ with kernel headers
- Xilinx `dma_ip_drivers` (for PCIe XDMA driver)
- CUDA Toolkit 12.0+ (for GPU integration, optional)
- C++20 compiler (GCC 14+)
