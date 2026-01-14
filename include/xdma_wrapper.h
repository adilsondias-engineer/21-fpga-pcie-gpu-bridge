#pragma once

#include "pcie_types.h"
#include <string>
#include <memory>
#include <functional>
#include <atomic>
#include <thread>
#include <vector>

namespace pcie {

/**
 * XDMA Wrapper Class
 * Provides C++ interface to Xilinx XDMA Linux driver
 *
 * Usage:
 *   XDMAWrapper xdma;
 *   if (xdma.open() != PCIeError::SUCCESS) {
 *       // Handle error
 *   }
 *
 *   // Read BBO data
 *   BBOData bbo;
 *   if (xdma.read_bbo(bbo) == PCIeError::SUCCESS) {
 *       printf("Symbol: %s, Bid: %.4f\n", bbo.get_symbol().c_str(), bbo.get_bid_price());
 *   }
 *
 *   // Enable streaming
 *   xdma.set_enabled(true);
 *
 *   // With callback
 *   xdma.start_streaming([](const BBOData& bbo) {
 *       printf("BBO: %s %.4f/%.4f\n", bbo.get_symbol().c_str(),
 *              bbo.get_bid_price(), bbo.get_ask_price());
 *   });
 */
class XDMAWrapper {
public:
    using BBOCallback = std::function<void(const BBOData&)>;

    XDMAWrapper();
    ~XDMAWrapper();

    // Non-copyable
    XDMAWrapper(const XDMAWrapper&) = delete;
    XDMAWrapper& operator=(const XDMAWrapper&) = delete;

    // Movable
    XDMAWrapper(XDMAWrapper&&) noexcept;
    XDMAWrapper& operator=(XDMAWrapper&&) noexcept;

    /**
     * Open XDMA device files
     * @return PCIeError::SUCCESS on success
     */
    PCIeError open();

    /**
     * Close all device files
     */
    void close();

    /**
     * Check if device is open and link is up
     */
    bool is_open() const;
    bool is_link_up() const;

    /**
     * Read a single BBO update from C2H channel
     * @param bbo Output BBO data structure
     * @param timeout_ms Timeout in milliseconds (0 = non-blocking)
     * @return PCIeError::SUCCESS on success
     */
    PCIeError read_bbo(BBOData& bbo, uint32_t timeout_ms = 1000);

    /**
     * Read multiple BBO updates
     * @param bbos Output vector of BBO data
     * @param max_count Maximum number of BBOs to read
     * @param timeout_ms Timeout in milliseconds
     * @return Number of BBOs read, -1 on error
     */
    int read_bbos(std::vector<BBOData>& bbos, size_t max_count, uint32_t timeout_ms = 1000);

    /**
     * Write data to H2C channel
     * @param data Pointer to data buffer
     * @param size Size in bytes
     * @param offset Offset in FPGA memory space
     * @return PCIeError::SUCCESS on success
     */
    PCIeError write_data(const void* data, size_t size, uint64_t offset = 0);

    /**
     * Control Register Access
     */
    PCIeError set_enabled(bool enable);
    PCIeError reset();
    bool get_enabled() const;
    uint32_t get_status() const;
    uint32_t get_bbo_count() const;
    uint32_t get_version() const;

    /**
     * Symbol Filter Configuration
     * @param index Filter slot (0-7)
     * @param symbol 8-character symbol (space-padded)
     */
    PCIeError set_symbol_filter(uint32_t index, const std::string& symbol);
    std::string get_symbol_filter(uint32_t index) const;

    /**
     * Latency Measurement
     */
    uint32_t get_last_rx_timestamp() const;
    uint32_t get_last_tx_timestamp() const;
    double get_last_latency_us() const;

    /**
     * Streaming Mode
     * Starts background thread that calls callback for each BBO
     */
    PCIeError start_streaming(BBOCallback callback);
    void stop_streaming();
    bool is_streaming() const;

    /**
     * Statistics
     */
    TransferStats get_stats() const;
    void reset_stats();

    /**
     * Raw register access (for debugging)
     */
    uint32_t read_register(uint32_t offset) const;
    void write_register(uint32_t offset, uint32_t value);

private:
    struct Impl;
    std::unique_ptr<Impl> pImpl;
};

/**
 * XDMA Device Discovery
 * Find available XDMA devices in the system
 */
class XDMADeviceDiscovery {
public:
    struct DeviceInfo {
        std::string device_path;    // e.g., "/dev/xdma0"
        uint16_t vendor_id;
        uint16_t device_id;
        std::string pci_slot;       // e.g., "0000:01:00.0"
        bool link_up;
        uint8_t link_width;         // x1, x4, x8, x16
        uint8_t link_speed;         // 1=Gen1, 2=Gen2, 3=Gen3
    };

    /**
     * Enumerate all XDMA devices
     * @return Vector of discovered devices
     */
    static std::vector<DeviceInfo> enumerate_devices();

    /**
     * Check if XDMA driver is loaded
     */
    static bool is_driver_loaded();

    /**
     * Load XDMA driver module
     * Requires root privileges
     */
    static bool load_driver();
};

}  // namespace pcie
