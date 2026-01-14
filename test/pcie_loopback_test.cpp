/**
 * PCIe Loopback Test
 * Tests basic XDMA communication with FPGA
 *
 * Usage: ./pcie_loopback_test [options]
 *   -r          Read-only mode (BBO stream)
 *   -w          Write-only mode (loopback)
 *   -b          Bidirectional test
 *   -n <count>  Number of iterations (default: 100)
 *   -t <ms>     Timeout in milliseconds (default: 1000)
 *   -v          Verbose output
 */

#include "xdma_wrapper.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <chrono>
#include <getopt.h>
#include <signal.h>

using namespace pcie;

// Global flag for graceful shutdown
static volatile bool running = true;

void signal_handler(int sig) {
    (void)sig;
    running = false;
    printf("\nInterrupt received, stopping...\n");
}

void print_usage(const char* prog) {
    printf("Usage: %s [options]\n", prog);
    printf("Options:\n");
    printf("  -r          Read-only mode (BBO stream)\n");
    printf("  -w          Write-only mode (loopback)\n");
    printf("  -b          Bidirectional test\n");
    printf("  -n <count>  Number of iterations (default: 100)\n");
    printf("  -t <ms>     Timeout in milliseconds (default: 1000)\n");
    printf("  -s          Streaming mode (continuous read)\n");
    printf("  -v          Verbose output\n");
    printf("  -h          Show this help\n");
}

void print_bbo(const BBOData& bbo, bool verbose) {
    printf("BBO: %s | Bid: $%.4f (%u) | Ask: $%.4f (%u) | Spread: $%.4f | Latency: %.3f μs\n",
           bbo.get_symbol().c_str(),
           bbo.get_bid_price(), bbo.get_bid_size(),
           bbo.get_ask_price(), bbo.get_ask_size(),
           bbo.get_spread(),
           bbo.get_fpga_latency_us());

    if (verbose) {
        printf("  RX Timestamp: %u | TX Timestamp: %u\n",
               bbo.get_rx_timestamp(), bbo.get_tx_timestamp());
    }
}

int test_read_bbo(XDMAWrapper& xdma, int count, int timeout_ms, bool verbose) {
    printf("\n=== BBO Read Test ===\n");
    printf("Reading %d BBO updates with %dms timeout...\n\n", count, timeout_ms);

    int success = 0;
    int timeout = 0;
    int failed = 0;

    auto start = std::chrono::high_resolution_clock::now();

    for (int i = 0; i < count && running; i++) {
        BBOData bbo;
        PCIeError err = xdma.read_bbo(bbo, timeout_ms);

        switch (err) {
            case PCIeError::SUCCESS:
                success++;
                if (verbose || success <= 5 || success == count) {
                    printf("[%d] ", success);
                    print_bbo(bbo, verbose);
                }
                break;

            case PCIeError::TIMEOUT:
                timeout++;
                if (verbose) {
                    printf("[%d] Timeout\n", i + 1);
                }
                break;

            default:
                failed++;
                printf("[%d] Error: %s\n", i + 1, pcie_error_string(err));
                break;
        }
    }

    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();

    printf("\n=== Results ===\n");
    printf("Success: %d | Timeout: %d | Failed: %d\n", success, timeout, failed);
    printf("Duration: %ld ms\n", duration);

    if (success > 0) {
        auto stats = xdma.get_stats();
        printf("Latency: avg=%.3f μs, min=%.3f μs, max=%.3f μs\n",
               stats.avg_latency_us, stats.min_latency_us, stats.max_latency_us);
        printf("Throughput: %.2f KB/s\n",
               static_cast<double>(stats.bytes_transferred) / duration);
    }

    return (failed == 0) ? 0 : 1;
}

int test_write_loopback(XDMAWrapper& xdma, int count, bool verbose) {
    printf("\n=== Write Loopback Test ===\n");
    printf("Writing %d test patterns...\n\n", count);

    int success = 0;
    int failed = 0;

    // Test pattern
    uint32_t pattern[256];
    for (int i = 0; i < 256; i++) {
        pattern[i] = 0xDEADBEEF + i;
    }

    auto start = std::chrono::high_resolution_clock::now();

    for (int i = 0; i < count && running; i++) {
        // Write pattern
        pattern[0] = 0xDEADBEEF + i;  // Unique per iteration

        PCIeError err = xdma.write_data(pattern, sizeof(pattern), 0);

        if (err == PCIeError::SUCCESS) {
            success++;
            if (verbose) {
                printf("[%d] Write OK, pattern[0]=0x%08X\n", i + 1, pattern[0]);
            }
        } else {
            failed++;
            printf("[%d] Write FAILED: %s\n", i + 1, pcie_error_string(err));
        }
    }

    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();

    printf("\n=== Results ===\n");
    printf("Success: %d | Failed: %d\n", success, failed);
    printf("Duration: %ld ms\n", duration);
    printf("Throughput: %.2f MB/s\n",
           static_cast<double>(success * sizeof(pattern)) / 1024.0 / duration);

    return (failed == 0) ? 0 : 1;
}

int test_streaming(XDMAWrapper& xdma, bool verbose) {
    printf("\n=== Streaming Mode Test ===\n");
    printf("Press Ctrl+C to stop...\n\n");

    uint64_t count = 0;
    auto start = std::chrono::high_resolution_clock::now();

    // Start streaming with callback
    xdma.start_streaming([&count, verbose](const BBOData& bbo) {
        count++;
        if (verbose || count <= 10 || count % 1000 == 0) {
            printf("[%lu] ", count);
            print_bbo(bbo, false);
        }
    });

    // Wait for interrupt
    while (running && xdma.is_streaming()) {
        usleep(100000);  // 100ms
    }

    xdma.stop_streaming();

    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::seconds>(end - start).count();

    printf("\n=== Results ===\n");
    printf("Total BBOs received: %lu\n", count);
    printf("Duration: %ld seconds\n", duration);
    if (duration > 0) {
        printf("Average rate: %.2f BBOs/sec\n",
               static_cast<double>(count) / duration);
    }

    auto stats = xdma.get_stats();
    printf("Latency: avg=%.3f μs, min=%.3f μs, max=%.3f μs\n",
           stats.avg_latency_us, stats.min_latency_us, stats.max_latency_us);

    return 0;
}

int test_registers(XDMAWrapper& xdma, bool verbose) {
    printf("\n=== Register Test ===\n");

    // Read version
    uint32_t version = xdma.get_version();
    printf("Version: 0x%08X\n", version);

    // Read status
    uint32_t status = xdma.get_status();
    printf("Status: 0x%08X\n", status);
    printf("  Running: %s\n", (status & ControlRegisters::STATUS_RUNNING) ? "Yes" : "No");
    printf("  FIFO Full: %s\n", (status & ControlRegisters::STATUS_FIFO_FULL) ? "Yes" : "No");
    printf("  Link Up: %s\n", (status & ControlRegisters::STATUS_LINK_UP) ? "Yes" : "No");

    // Read BBO count
    printf("BBO Count: %u\n", xdma.get_bbo_count());

    // Test enable/disable
    printf("\nTesting enable/disable...\n");
    xdma.set_enabled(true);
    printf("  Enabled: %s\n", xdma.get_enabled() ? "Yes" : "No");

    xdma.set_enabled(false);
    printf("  Disabled: %s\n", !xdma.get_enabled() ? "Yes" : "No");

    // Test symbol filter
    printf("\nTesting symbol filter...\n");
    xdma.set_symbol_filter(0, "AAPL");
    std::string filter = xdma.get_symbol_filter(0);
    printf("  Filter 0: '%s' (expected 'AAPL')\n", filter.c_str());

    // Test latency registers
    printf("\nLatency registers:\n");
    printf("  RX Timestamp: %u\n", xdma.get_last_rx_timestamp());
    printf("  TX Timestamp: %u\n", xdma.get_last_tx_timestamp());
    printf("  Last Latency: %.3f μs\n", xdma.get_last_latency_us());

    return 0;
}

int main(int argc, char* argv[]) {
    bool read_mode = false;
    bool write_mode = false;
    bool bidirectional = false;
    bool streaming = false;
    bool verbose = false;
    int count = 100;
    int timeout_ms = 1000;

    // Parse options
    int opt;
    while ((opt = getopt(argc, argv, "rwbsn:t:vh")) != -1) {
        switch (opt) {
            case 'r': read_mode = true; break;
            case 'w': write_mode = true; break;
            case 'b': bidirectional = true; break;
            case 's': streaming = true; break;
            case 'n': count = atoi(optarg); break;
            case 't': timeout_ms = atoi(optarg); break;
            case 'v': verbose = true; break;
            case 'h':
            default:
                print_usage(argv[0]);
                return (opt == 'h') ? 0 : 1;
        }
    }

    // Default to read mode if nothing specified
    if (!read_mode && !write_mode && !bidirectional && !streaming) {
        read_mode = true;
    }

    // Set up signal handler
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    printf("=== PCIe Loopback Test ===\n");
    printf("Mode: %s%s%s%s\n",
           read_mode ? "Read " : "",
           write_mode ? "Write " : "",
           bidirectional ? "Bidirectional " : "",
           streaming ? "Streaming " : "");

    // Check if driver is loaded
    if (!XDMADeviceDiscovery::is_driver_loaded()) {
        printf("ERROR: XDMA driver not loaded!\n");
        printf("Run: sudo modprobe xdma\n");
        return 1;
    }

    // Enumerate devices
    auto devices = XDMADeviceDiscovery::enumerate_devices();
    if (devices.empty()) {
        printf("ERROR: No XDMA devices found!\n");
        printf("Check:\n");
        printf("  1. FPGA is programmed with PCIe bitstream\n");
        printf("  2. PCIe link is up (lspci | grep Xilinx)\n");
        printf("  3. Driver is loaded (lsmod | grep xdma)\n");
        return 1;
    }

    printf("\nFound %zu XDMA device(s):\n", devices.size());
    for (const auto& dev : devices) {
        printf("  %s (VID:0x%04X DID:0x%04X)\n",
               dev.device_path.c_str(), dev.vendor_id, dev.device_id);
    }

    // Open XDMA device
    XDMAWrapper xdma;
    PCIeError err = xdma.open();
    if (err != PCIeError::SUCCESS) {
        printf("ERROR: Failed to open XDMA device: %s\n", pcie_error_string(err));
        return 1;
    }

    // Run register test first
    int result = test_registers(xdma, verbose);

    // Run selected tests
    if (running && read_mode) {
        result |= test_read_bbo(xdma, count, timeout_ms, verbose);
    }

    if (running && write_mode) {
        result |= test_write_loopback(xdma, count, verbose);
    }

    if (running && bidirectional) {
        result |= test_write_loopback(xdma, count / 2, verbose);
        result |= test_read_bbo(xdma, count / 2, timeout_ms, verbose);
    }

    if (running && streaming) {
        result |= test_streaming(xdma, verbose);
    }

    xdma.close();

    printf("\n=== Test %s ===\n", (result == 0) ? "PASSED" : "FAILED");
    return result;
}
