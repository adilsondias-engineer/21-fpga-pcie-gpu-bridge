#pragma once

#include <cstdint>
#include <cstring>
#include <string>

namespace pcie {

/**
 * BBO Data Structure (36 bytes)
 * Matches FPGA output format from Project 20
 * All multi-byte fields are big-endian (network byte order)
 */
#pragma pack(push, 1)
struct BBOData {
    char symbol[8];           // Stock ticker (ASCII, space-padded)
    uint32_t bid_price;       // Fixed-point, 4 decimal places (big-endian)
    uint32_t bid_size;        // Number of shares (big-endian)
    uint32_t ask_price;       // Fixed-point, 4 decimal places (big-endian)
    uint32_t ask_size;        // Number of shares (big-endian)
    uint32_t spread;          // Ask - Bid, 4 decimal places (big-endian)
    uint32_t rx_timestamp;    // FPGA cycle count when ITCH received (big-endian)
    uint32_t tx_timestamp;    // FPGA cycle count when packet sent (big-endian)

    // Convert from network byte order to host
    double get_bid_price() const {
        return static_cast<double>(__builtin_bswap32(bid_price)) / 10000.0;
    }

    double get_ask_price() const {
        return static_cast<double>(__builtin_bswap32(ask_price)) / 10000.0;
    }

    double get_spread() const {
        return static_cast<double>(__builtin_bswap32(spread)) / 10000.0;
    }

    uint32_t get_bid_size() const {
        return __builtin_bswap32(bid_size);
    }

    uint32_t get_ask_size() const {
        return __builtin_bswap32(ask_size);
    }

    uint32_t get_rx_timestamp() const {
        return __builtin_bswap32(rx_timestamp);
    }

    uint32_t get_tx_timestamp() const {
        return __builtin_bswap32(tx_timestamp);
    }

    // Calculate FPGA processing latency in microseconds
    // Both timestamps are cycle counts at 125 MHz (8 ns per cycle)
    double get_fpga_latency_us() const {
        uint32_t rx = get_rx_timestamp();
        uint32_t tx = get_tx_timestamp();

        uint32_t cycles;
        if (tx >= rx) {
            cycles = tx - rx;
        } else {
            // Handle wraparound (32-bit counter wraps every ~34 seconds at 125 MHz)
            cycles = (0xFFFFFFFF - rx) + tx + 1;
        }

        return static_cast<double>(cycles) * 0.008;  // 8 ns per cycle = 0.008 μs
    }

    // Get symbol as std::string (trimmed)
    std::string get_symbol() const {
        char sym[9];
        std::memcpy(sym, symbol, 8);
        sym[8] = '\0';

        // Trim trailing spaces
        int len = 7;
        while (len >= 0 && sym[len] == ' ') {
            sym[len] = '\0';
            len--;
        }

        return std::string(sym);
    }
};
#pragma pack(pop)

static_assert(sizeof(BBOData) == 36, "BBOData must be 36 bytes");

/**
 * Control Register Structure
 * Mapped via /dev/xdma0_user mmap
 */
struct ControlRegisters {
    static constexpr uint32_t VERSION_OFFSET = 0x00;
    static constexpr uint32_t CONTROL_OFFSET = 0x04;
    static constexpr uint32_t STATUS_OFFSET = 0x08;
    static constexpr uint32_t BBO_COUNT_OFFSET = 0x0C;
    static constexpr uint32_t SYMBOL_FILTER_0_OFFSET = 0x10;
    static constexpr uint32_t RX_TIMESTAMP_OFFSET = 0x40;
    static constexpr uint32_t TX_TIMESTAMP_OFFSET = 0x44;
    static constexpr uint32_t LATENCY_US_OFFSET = 0x48;

    // Control register bits
    static constexpr uint32_t CTRL_ENABLE = 0x01;
    static constexpr uint32_t CTRL_RESET = 0x02;

    // Status register bits
    static constexpr uint32_t STATUS_RUNNING = 0x01;
    static constexpr uint32_t STATUS_FIFO_FULL = 0x02;
    static constexpr uint32_t STATUS_LINK_UP = 0x04;
};

/**
 * XDMA Device File Paths
 */
struct XDMADevicePaths {
    static constexpr const char* C2H_0 = "/dev/xdma0_c2h_0";
    static constexpr const char* H2C_0 = "/dev/xdma0_h2c_0";
    static constexpr const char* USER = "/dev/xdma0_user";
    static constexpr const char* CONTROL = "/dev/xdma0_control";
    static constexpr const char* EVENTS_0 = "/dev/xdma0_events_0";
};

/**
 * PCIe Transfer Statistics
 */
struct TransferStats {
    uint64_t bytes_transferred;
    uint64_t transfers_completed;
    uint64_t transfers_failed;
    double avg_latency_us;
    double min_latency_us;
    double max_latency_us;

    TransferStats()
        : bytes_transferred(0), transfers_completed(0), transfers_failed(0),
          avg_latency_us(0.0), min_latency_us(1e9), max_latency_us(0.0) {}

    void update_latency(double latency_us) {
        if (latency_us < min_latency_us) min_latency_us = latency_us;
        if (latency_us > max_latency_us) max_latency_us = latency_us;

        // Running average
        avg_latency_us = (avg_latency_us * transfers_completed + latency_us) /
                         (transfers_completed + 1);
    }
};

/**
 * PCIe Error Codes
 */
enum class PCIeError {
    SUCCESS = 0,
    DEVICE_NOT_FOUND,
    OPEN_FAILED,
    MMAP_FAILED,
    READ_FAILED,
    WRITE_FAILED,
    TIMEOUT,
    LINK_DOWN,
    BUFFER_OVERFLOW,
    INVALID_PARAMETER
};

inline const char* pcie_error_string(PCIeError err) {
    switch (err) {
        case PCIeError::SUCCESS: return "Success";
        case PCIeError::DEVICE_NOT_FOUND: return "Device not found";
        case PCIeError::OPEN_FAILED: return "Failed to open device";
        case PCIeError::MMAP_FAILED: return "Memory mapping failed";
        case PCIeError::READ_FAILED: return "Read operation failed";
        case PCIeError::WRITE_FAILED: return "Write operation failed";
        case PCIeError::TIMEOUT: return "Operation timed out";
        case PCIeError::LINK_DOWN: return "PCIe link is down";
        case PCIeError::BUFFER_OVERFLOW: return "Buffer overflow";
        case PCIeError::INVALID_PARAMETER: return "Invalid parameter";
        default: return "Unknown error";
    }
}

}  // namespace pcie
