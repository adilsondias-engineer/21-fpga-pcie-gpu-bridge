#include "xdma_wrapper.h"

#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <poll.h>
#include <dirent.h>
#include <cstring>
#include <cstdio>
#include <chrono>
#include <fstream>
#include <sstream>

namespace pcie {

/**
 * Implementation details (PIMPL pattern)
 */
struct XDMAWrapper::Impl {
    // File descriptors
    int fd_c2h = -1;         // Card-to-Host DMA channel
    int fd_h2c = -1;         // Host-to-Card DMA channel
    int fd_user = -1;        // User/control registers
    int fd_events = -1;      // Event/interrupt file

    // Memory-mapped control registers
    volatile uint32_t* ctrl_regs = nullptr;
    size_t ctrl_regs_size = 4096;  // 4KB page

    // Streaming state
    std::atomic<bool> streaming{false};
    std::thread stream_thread;
    BBOCallback stream_callback;

    // Statistics
    TransferStats stats;
    std::atomic<uint64_t> bbo_read_count{0};

    // Device info
    bool link_up = false;

    ~Impl() {
        // Ensure streaming is stopped
        streaming = false;
        if (stream_thread.joinable()) {
            stream_thread.join();
        }

        // Unmap control registers
        if (ctrl_regs != nullptr && ctrl_regs != MAP_FAILED) {
            munmap(const_cast<uint32_t*>(ctrl_regs), ctrl_regs_size);
        }

        // Close file descriptors
        if (fd_c2h >= 0) close(fd_c2h);
        if (fd_h2c >= 0) close(fd_h2c);
        if (fd_user >= 0) close(fd_user);
        if (fd_events >= 0) close(fd_events);
    }
};

XDMAWrapper::XDMAWrapper() : pImpl(std::make_unique<Impl>()) {}

XDMAWrapper::~XDMAWrapper() {
    close();
}

XDMAWrapper::XDMAWrapper(XDMAWrapper&&) noexcept = default;
XDMAWrapper& XDMAWrapper::operator=(XDMAWrapper&&) noexcept = default;

PCIeError XDMAWrapper::open() {
    // Check if driver is loaded
    if (!XDMADeviceDiscovery::is_driver_loaded()) {
        fprintf(stderr, "XDMA driver not loaded. Run: sudo modprobe xdma\n");
        return PCIeError::DEVICE_NOT_FOUND;
    }

    // Open C2H channel (for reading BBO data)
    pImpl->fd_c2h = ::open(XDMADevicePaths::C2H_0, O_RDONLY);
    if (pImpl->fd_c2h < 0) {
        fprintf(stderr, "Failed to open %s: %s\n",
                XDMADevicePaths::C2H_0, strerror(errno));
        return PCIeError::OPEN_FAILED;
    }

    // Open H2C channel (for writing commands)
    pImpl->fd_h2c = ::open(XDMADevicePaths::H2C_0, O_WRONLY);
    if (pImpl->fd_h2c < 0) {
        fprintf(stderr, "Failed to open %s: %s\n",
                XDMADevicePaths::H2C_0, strerror(errno));
        return PCIeError::OPEN_FAILED;
    }

    // Open user/control interface for mmap
    pImpl->fd_user = ::open(XDMADevicePaths::USER, O_RDWR | O_SYNC);
    if (pImpl->fd_user < 0) {
        fprintf(stderr, "Failed to open %s: %s\n",
                XDMADevicePaths::USER, strerror(errno));
        return PCIeError::OPEN_FAILED;
    }

    // Memory-map control registers
    pImpl->ctrl_regs = static_cast<volatile uint32_t*>(
        mmap(nullptr, pImpl->ctrl_regs_size,
             PROT_READ | PROT_WRITE, MAP_SHARED,
             pImpl->fd_user, 0));

    if (pImpl->ctrl_regs == MAP_FAILED) {
        fprintf(stderr, "Failed to mmap control registers: %s\n", strerror(errno));
        pImpl->ctrl_regs = nullptr;
        return PCIeError::MMAP_FAILED;
    }

    // Open events file (optional - for interrupt-driven mode)
    pImpl->fd_events = ::open(XDMADevicePaths::EVENTS_0, O_RDONLY);
    // Events file is optional, don't fail if not present

    // Check link status
    uint32_t status = get_status();
    pImpl->link_up = (status & ControlRegisters::STATUS_LINK_UP) != 0;

    if (!pImpl->link_up) {
        fprintf(stderr, "Warning: PCIe link is not up\n");
    }

    // Read and display version
    uint32_t version = get_version();
    printf("XDMA device opened. Version: 0x%08X, Link: %s\n",
           version, pImpl->link_up ? "UP" : "DOWN");

    return PCIeError::SUCCESS;
}

void XDMAWrapper::close() {
    stop_streaming();

    if (pImpl) {
        if (pImpl->ctrl_regs != nullptr && pImpl->ctrl_regs != MAP_FAILED) {
            munmap(const_cast<uint32_t*>(pImpl->ctrl_regs), pImpl->ctrl_regs_size);
            pImpl->ctrl_regs = nullptr;
        }

        if (pImpl->fd_c2h >= 0) { ::close(pImpl->fd_c2h); pImpl->fd_c2h = -1; }
        if (pImpl->fd_h2c >= 0) { ::close(pImpl->fd_h2c); pImpl->fd_h2c = -1; }
        if (pImpl->fd_user >= 0) { ::close(pImpl->fd_user); pImpl->fd_user = -1; }
        if (pImpl->fd_events >= 0) { ::close(pImpl->fd_events); pImpl->fd_events = -1; }
    }
}

bool XDMAWrapper::is_open() const {
    return pImpl && pImpl->fd_c2h >= 0 && pImpl->ctrl_regs != nullptr;
}

bool XDMAWrapper::is_link_up() const {
    return pImpl && pImpl->link_up;
}

PCIeError XDMAWrapper::read_bbo(BBOData& bbo, uint32_t timeout_ms) {
    if (!is_open()) {
        return PCIeError::DEVICE_NOT_FOUND;
    }

    // Use poll() for timeout handling
    if (timeout_ms > 0) {
        struct pollfd pfd;
        pfd.fd = pImpl->fd_c2h;
        pfd.events = POLLIN;

        int ret = poll(&pfd, 1, static_cast<int>(timeout_ms));
        if (ret < 0) {
            return PCIeError::READ_FAILED;
        }
        if (ret == 0) {
            return PCIeError::TIMEOUT;
        }
    }

    // Read BBO data
    ssize_t n = read(pImpl->fd_c2h, &bbo, sizeof(BBOData));
    if (n < 0) {
        return PCIeError::READ_FAILED;
    }
    if (n < static_cast<ssize_t>(sizeof(BBOData))) {
        return PCIeError::READ_FAILED;
    }

    // Update statistics
    pImpl->stats.bytes_transferred += sizeof(BBOData);
    pImpl->stats.transfers_completed++;
    pImpl->bbo_read_count++;

    // Calculate and record latency
    double latency = bbo.get_fpga_latency_us();
    pImpl->stats.update_latency(latency);

    return PCIeError::SUCCESS;
}

int XDMAWrapper::read_bbos(std::vector<BBOData>& bbos, size_t max_count, uint32_t timeout_ms) {
    if (!is_open()) {
        return -1;
    }

    bbos.clear();
    bbos.reserve(max_count);

    auto start = std::chrono::steady_clock::now();
    uint32_t remaining_ms = timeout_ms;

    while (bbos.size() < max_count && remaining_ms > 0) {
        BBOData bbo;
        PCIeError err = read_bbo(bbo, remaining_ms);

        if (err == PCIeError::SUCCESS) {
            bbos.push_back(bbo);
        } else if (err == PCIeError::TIMEOUT) {
            break;
        } else {
            return -1;
        }

        // Update remaining timeout
        auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - start).count();
        remaining_ms = (elapsed < timeout_ms) ? (timeout_ms - elapsed) : 0;
    }

    return static_cast<int>(bbos.size());
}

PCIeError XDMAWrapper::write_data(const void* data, size_t size, uint64_t offset) {
    if (!is_open() || pImpl->fd_h2c < 0) {
        return PCIeError::DEVICE_NOT_FOUND;
    }

    // Seek to offset
    if (lseek(pImpl->fd_h2c, static_cast<off_t>(offset), SEEK_SET) < 0) {
        return PCIeError::WRITE_FAILED;
    }

    // Write data
    ssize_t n = write(pImpl->fd_h2c, data, size);
    if (n < 0 || static_cast<size_t>(n) != size) {
        return PCIeError::WRITE_FAILED;
    }

    return PCIeError::SUCCESS;
}

// Control Register Access
PCIeError XDMAWrapper::set_enabled(bool enable) {
    if (!is_open()) {
        return PCIeError::DEVICE_NOT_FOUND;
    }

    uint32_t ctrl = read_register(ControlRegisters::CONTROL_OFFSET);
    if (enable) {
        ctrl |= ControlRegisters::CTRL_ENABLE;
    } else {
        ctrl &= ~ControlRegisters::CTRL_ENABLE;
    }
    write_register(ControlRegisters::CONTROL_OFFSET, ctrl);

    return PCIeError::SUCCESS;
}

PCIeError XDMAWrapper::reset() {
    if (!is_open()) {
        return PCIeError::DEVICE_NOT_FOUND;
    }

    // Assert reset
    uint32_t ctrl = read_register(ControlRegisters::CONTROL_OFFSET);
    write_register(ControlRegisters::CONTROL_OFFSET, ctrl | ControlRegisters::CTRL_RESET);

    // Wait briefly
    usleep(1000);  // 1ms

    // Deassert reset
    write_register(ControlRegisters::CONTROL_OFFSET, ctrl & ~ControlRegisters::CTRL_RESET);

    return PCIeError::SUCCESS;
}

bool XDMAWrapper::get_enabled() const {
    if (!is_open()) return false;
    return (read_register(ControlRegisters::CONTROL_OFFSET) & ControlRegisters::CTRL_ENABLE) != 0;
}

uint32_t XDMAWrapper::get_status() const {
    if (!is_open()) return 0;
    return read_register(ControlRegisters::STATUS_OFFSET);
}

uint32_t XDMAWrapper::get_bbo_count() const {
    if (!is_open()) return 0;
    return read_register(ControlRegisters::BBO_COUNT_OFFSET);
}

uint32_t XDMAWrapper::get_version() const {
    if (!is_open()) return 0;
    return read_register(ControlRegisters::VERSION_OFFSET);
}

PCIeError XDMAWrapper::set_symbol_filter(uint32_t index, const std::string& symbol) {
    if (!is_open()) {
        return PCIeError::DEVICE_NOT_FOUND;
    }
    if (index > 7) {
        return PCIeError::INVALID_PARAMETER;
    }

    // Prepare 8-byte symbol (space-padded)
    char sym_buf[8];
    memset(sym_buf, ' ', 8);
    size_t copy_len = std::min(symbol.length(), size_t(8));
    memcpy(sym_buf, symbol.c_str(), copy_len);

    // Write as two 32-bit words
    uint32_t offset = ControlRegisters::SYMBOL_FILTER_0_OFFSET + (index * 8);
    uint32_t word0, word1;
    memcpy(&word0, sym_buf, 4);
    memcpy(&word1, sym_buf + 4, 4);

    write_register(offset, word0);
    write_register(offset + 4, word1);

    return PCIeError::SUCCESS;
}

std::string XDMAWrapper::get_symbol_filter(uint32_t index) const {
    if (!is_open() || index > 7) {
        return "";
    }

    uint32_t offset = ControlRegisters::SYMBOL_FILTER_0_OFFSET + (index * 8);
    uint32_t word0 = read_register(offset);
    uint32_t word1 = read_register(offset + 4);

    char sym_buf[9];
    memcpy(sym_buf, &word0, 4);
    memcpy(sym_buf + 4, &word1, 4);
    sym_buf[8] = '\0';

    // Trim trailing spaces
    int len = 7;
    while (len >= 0 && sym_buf[len] == ' ') {
        sym_buf[len] = '\0';
        len--;
    }

    return std::string(sym_buf);
}

uint32_t XDMAWrapper::get_last_rx_timestamp() const {
    if (!is_open()) return 0;
    return read_register(ControlRegisters::RX_TIMESTAMP_OFFSET);
}

uint32_t XDMAWrapper::get_last_tx_timestamp() const {
    if (!is_open()) return 0;
    return read_register(ControlRegisters::TX_TIMESTAMP_OFFSET);
}

double XDMAWrapper::get_last_latency_us() const {
    if (!is_open()) return 0.0;
    // LATENCY_US register stores microseconds × 100 as integer
    uint32_t latency_x100 = read_register(ControlRegisters::LATENCY_US_OFFSET);
    return static_cast<double>(latency_x100) / 100.0;
}

PCIeError XDMAWrapper::start_streaming(BBOCallback callback) {
    if (!is_open()) {
        return PCIeError::DEVICE_NOT_FOUND;
    }

    if (pImpl->streaming) {
        return PCIeError::SUCCESS;  // Already streaming
    }

    pImpl->stream_callback = std::move(callback);
    pImpl->streaming = true;

    pImpl->stream_thread = std::thread([this]() {
        BBOData bbo;

        while (pImpl->streaming) {
            PCIeError err = read_bbo(bbo, 100);  // 100ms timeout

            if (err == PCIeError::SUCCESS && pImpl->stream_callback) {
                pImpl->stream_callback(bbo);
            } else if (err != PCIeError::TIMEOUT && err != PCIeError::SUCCESS) {
                fprintf(stderr, "Streaming error: %s\n", pcie_error_string(err));
                break;
            }
        }
    });

    return PCIeError::SUCCESS;
}

void XDMAWrapper::stop_streaming() {
    pImpl->streaming = false;
    if (pImpl->stream_thread.joinable()) {
        pImpl->stream_thread.join();
    }
}

bool XDMAWrapper::is_streaming() const {
    return pImpl->streaming;
}

TransferStats XDMAWrapper::get_stats() const {
    return pImpl->stats;
}

void XDMAWrapper::reset_stats() {
    pImpl->stats = TransferStats();
    pImpl->bbo_read_count = 0;
}

uint32_t XDMAWrapper::read_register(uint32_t offset) const {
    if (!pImpl || !pImpl->ctrl_regs) return 0;
    return pImpl->ctrl_regs[offset / 4];
}

void XDMAWrapper::write_register(uint32_t offset, uint32_t value) {
    if (!pImpl || !pImpl->ctrl_regs) return;
    pImpl->ctrl_regs[offset / 4] = value;
    __sync_synchronize();  // Memory barrier
}

// Device Discovery Implementation
std::vector<XDMADeviceDiscovery::DeviceInfo> XDMADeviceDiscovery::enumerate_devices() {
    std::vector<DeviceInfo> devices;

    // Check /dev for xdma devices
    DIR* dev = opendir("/dev");
    if (!dev) {
        return devices;
    }

    struct dirent* entry;
    while ((entry = readdir(dev)) != nullptr) {
        std::string name(entry->d_name);
        if (name.find("xdma") == 0 && name.find("_") != std::string::npos) {
            // Extract device number (e.g., "xdma0" from "xdma0_c2h_0")
            size_t underscore = name.find('_');
            std::string dev_name = name.substr(0, underscore);

            // Check if we already have this device
            bool found = false;
            for (const auto& d : devices) {
                if (d.device_path.find(dev_name) != std::string::npos) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                DeviceInfo info;
                info.device_path = "/dev/" + dev_name;

                // Try to read PCI info from sysfs
                // This is a simplified approach - real implementation would
                // search /sys/bus/pci/devices/ for matching devices
                info.vendor_id = 0x10EE;  // Xilinx
                info.device_id = 0x7024;  // Default XDMA
                info.link_up = true;  // Assume up if device exists
                info.link_width = 4;
                info.link_speed = 2;  // Gen2

                devices.push_back(info);
            }
        }
    }

    closedir(dev);
    return devices;
}

bool XDMADeviceDiscovery::is_driver_loaded() {
    std::ifstream modules("/proc/modules");
    std::string line;

    while (std::getline(modules, line)) {
        if (line.find("xdma") == 0) {
            return true;
        }
    }

    return false;
}

bool XDMADeviceDiscovery::load_driver() {
    // Requires root privileges
    int ret = system("modprobe xdma 2>/dev/null");
    return (ret == 0);
}

}  // namespace pcie
