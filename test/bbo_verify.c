/*
 * BBO Packet Verification Tool
 * Reads from XDMA C2H channel and verifies BBO packet format
 *
 * BBO Packet Format (48 bytes = 6 x 64-bit beats):
 *   Beat 1 (bytes 0-7):   Symbol (8 ASCII chars, e.g., "TESTAAPL")
 *   Beat 2 (bytes 8-15):  BidPrice[31:0] | BidSize[63:32]
 *   Beat 3 (bytes 16-23): AskPrice[31:0] | AskSize[63:32]
 *   Beat 4 (bytes 24-31): Spread[31:0]   | T1[63:32]
 *   Beat 5 (bytes 32-39): T2[31:0]       | T3[63:32]
 *   Beat 6 (bytes 40-47): T4[31:0]       | Padding[63:32] (0xDEADBEEF)
 *
 * Usage: ./bbo_verify [device] [count] [-v] [-raw]
 *   device: XDMA device path (default: /dev/xdma0_c2h_0)
 *   count: Number of BBO packets to read (default: 10)
 *   -v: Verbose mode (show raw beats)
 *   -raw: Just dump raw data without parsing
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <sys/time.h>
#include <errno.h>

#define DEFAULT_DEVICE "/dev/xdma0_c2h_0"
#define DEFAULT_COUNT 10
#define BBO_PACKET_SIZE 48  /* 6 beats x 8 bytes */
#define PADDING_MARKER 0xDEADBEEF

/* BBO Packet structure (packed, 48 bytes) */
typedef struct __attribute__((packed)) {
    char     symbol[8];      /* Bytes 0-7: ASCII symbol */
    uint32_t bid_price;      /* Bytes 8-11: Bid price (fixed-point, /10000 for dollars) */
    uint32_t bid_size;       /* Bytes 12-15: Bid size (shares) */
    uint32_t ask_price;      /* Bytes 16-19: Ask price */
    uint32_t ask_size;       /* Bytes 20-23: Ask size */
    uint32_t spread;         /* Bytes 24-27: Spread (ask - bid) */
    uint32_t ts_t1;          /* Bytes 28-31: T1 timestamp (ITCH parse) */
    uint32_t ts_t2;          /* Bytes 32-35: T2 timestamp (CDC FIFO write) */
    uint32_t ts_t3;          /* Bytes 36-39: T3 timestamp (BBO FIFO read) */
    uint32_t ts_t4;          /* Bytes 40-43: T4 timestamp (TX start) */
    uint32_t padding;        /* Bytes 44-47: Padding marker (0xDEADBEEF) */
} BboPacket;

void print_bbo(const BboPacket *pkt, int index) {
    char symbol[9];
    memcpy(symbol, pkt->symbol, 8);
    symbol[8] = '\0';

    /* Calculate latency in nanoseconds (assuming 250 MHz clock = 4 ns per cycle for Gen2) */
    uint32_t latency_cycles = pkt->ts_t4 - pkt->ts_t1;
    uint32_t latency_ns = latency_cycles * 4;

    printf("BBO #%d:\n", index);
    printf("  Symbol:    '%s'\n", symbol);
    printf("  Bid:       $%.4f x %u shares\n",
           pkt->bid_price / 10000.0, pkt->bid_size);
    printf("  Ask:       $%.4f x %u shares\n",
           pkt->ask_price / 10000.0, pkt->ask_size);
    printf("  Spread:    $%.4f\n", pkt->spread / 10000.0);
    printf("  Timestamps: T1=%u T2=%u T3=%u T4=%u\n",
           pkt->ts_t1, pkt->ts_t2, pkt->ts_t3, pkt->ts_t4);
    printf("  Latency:   %u cycles (%u ns)\n", latency_cycles, latency_ns);
    printf("  Padding:   0x%08X %s\n", pkt->padding,
           pkt->padding == PADDING_MARKER ? "✓" : "✗ INVALID!");
    printf("\n");
}

void print_raw_beats(const uint64_t *beats, int num_beats) {
    printf("  Raw beats:\n");
    for (int i = 0; i < num_beats; i++) {
        printf("    Beat %d: 0x%016lx\n", i + 1, beats[i]);
    }
}

void print_raw_dump(const uint8_t *buf, size_t len) {
    printf("Raw data dump (%zu bytes):\n", len);
    for (size_t i = 0; i < len; i++) {
        if (i % 16 == 0) {
            printf("  %04zx: ", i);
        }
        printf("%02x ", buf[i]);
        if (i % 16 == 7) printf(" ");
        if (i % 16 == 15 || i == len - 1) {
            /* Print ASCII representation */
            int padding = 15 - (i % 16);
            for (int j = 0; j < padding; j++) printf("   ");
            if (padding > 7) printf(" ");
            printf(" |");
            size_t line_start = i - (i % 16);
            for (size_t j = line_start; j <= i; j++) {
                char c = buf[j];
                printf("%c", (c >= 0x20 && c <= 0x7e) ? c : '.');
            }
            printf("|\n");
        }
    }
    printf("\n");
}

int verify_bbo(const BboPacket *pkt, int *errors) {
    int local_errors = 0;

    /* Check padding marker */
    if (pkt->padding != PADDING_MARKER) {
        printf("  ERROR: Invalid padding (expected 0x%08X, got 0x%08X)\n",
               PADDING_MARKER, pkt->padding);
        local_errors++;
    }

    /* Check for reasonable price values (non-zero, less than $1M) */
    if (pkt->bid_price == 0 || pkt->bid_price > 10000000000UL) {
        printf("  WARNING: Unusual bid price: %u\n", pkt->bid_price);
    }
    if (pkt->ask_price == 0 || pkt->ask_price > 10000000000UL) {
        printf("  WARNING: Unusual ask price: %u\n", pkt->ask_price);
    }

    /* Check spread = ask - bid (handle crossed markets) */
    uint32_t expected_spread;
    if (pkt->ask_price > pkt->bid_price) {
        /* Normal market: spread = ask - bid */
        expected_spread = pkt->ask_price - pkt->bid_price;
    } else {
        /* Crossed market (bid >= ask): spread = 0 */
        expected_spread = 0;
    }
    if (pkt->spread != expected_spread) {
        printf("  WARNING: Spread mismatch (expected %u, got %u)\n",
               expected_spread, pkt->spread);
    }

    *errors += local_errors;
    return local_errors == 0;
}

int main(int argc, char **argv) {
    const char *device = DEFAULT_DEVICE;
    int count = DEFAULT_COUNT;
    int verbose = 0;
    int raw_dump = 0;

    /* Parse arguments */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-v") == 0 || strcmp(argv[i], "--verbose") == 0) {
            verbose = 1;
        } else if (strcmp(argv[i], "-raw") == 0) {
            raw_dump = 1;
        } else if (argv[i][0] == '/') {
            device = argv[i];
        } else {
            count = atoi(argv[i]);
            if (count <= 0) count = DEFAULT_COUNT;
        }
    }

    printf("BBO Packet Verification\n");
    printf("========================\n");
    printf("Device: %s\n", device);
    printf("Packet size: %d bytes (48-byte standard format)\n", BBO_PACKET_SIZE);
    printf("Packets to read: %d (%d bytes)\n", count, count * BBO_PACKET_SIZE);
    printf("Verbose: %s\n", verbose ? "yes" : "no");
    printf("\n");

    /* Open device */
    int fd = open(device, O_RDONLY);
    if (fd < 0) {
        perror("Failed to open device");
        return 1;
    }

    /* Allocate buffer (aligned for DMA) */
    size_t buf_size = count * BBO_PACKET_SIZE + 64;  /* Extra for partial packet detection */
    uint8_t *buf = aligned_alloc(4096, buf_size);
    if (!buf) {
        perror("Failed to allocate buffer");
        close(fd);
        return 1;
    }
    memset(buf, 0, buf_size);

    /* Read data */
    printf("Reading BBO packets from FPGA...\n");
    struct timeval start, end;
    gettimeofday(&start, NULL);

    ssize_t bytes_read = read(fd, buf, buf_size);

    gettimeofday(&end, NULL);

    if (bytes_read < 0) {
        perror("Read failed");
        free(buf);
        close(fd);
        return 1;
    }

    double elapsed = (end.tv_sec - start.tv_sec) +
                     (end.tv_usec - start.tv_usec) / 1000000.0;
    double throughput = elapsed > 0 ? (bytes_read / 1024.0 / 1024.0) / elapsed : 0;

    printf("Read %zd bytes in %.3f seconds (%.2f MB/s)\n\n",
           bytes_read, elapsed, throughput);

    /* Raw dump mode */
    if (raw_dump) {
        print_raw_dump(buf, bytes_read);
        free(buf);
        close(fd);
        return 0;
    }

    /* Verify packets */
    int packets_read = bytes_read / BBO_PACKET_SIZE;
    int errors = 0;
    int valid_packets = 0;

    printf("Parsing %d BBO packets:\n", packets_read);
    printf("========================\n\n");

    for (int i = 0; i < packets_read; i++) {
        BboPacket *pkt = (BboPacket *)(buf + i * BBO_PACKET_SIZE);

        print_bbo(pkt, i + 1);

        if (verbose) {
            print_raw_beats((uint64_t *)(buf + i * BBO_PACKET_SIZE), 6);
            printf("\n");
        }

        if (verify_bbo(pkt, &errors)) {
            valid_packets++;
        }
    }

    /* Summary */
    printf("\n");
    printf("Results:\n");
    printf("========\n");
    printf("Bytes read:     %zd\n", bytes_read);
    printf("Packets parsed: %d\n", packets_read);
    printf("Valid packets:  %d\n", valid_packets);
    printf("Errors:         %d\n", errors);

    if (errors == 0 && packets_read > 0) {
        printf("Status: PASS ✓ - All BBO packets valid!\n");
    } else if (packets_read == 0) {
        printf("Status: NO DATA - No packets received\n");
    } else {
        printf("Status: FAIL ✗ - %d errors detected\n", errors);
    }

    /* Check for partial packet */
    int remaining = bytes_read % BBO_PACKET_SIZE;
    if (remaining > 0) {
        printf("\nWARNING: %d bytes remaining (partial packet)\n", remaining);
        printf("Raw remaining bytes:\n");
        print_raw_dump(buf + packets_read * BBO_PACKET_SIZE, remaining);
    }

    free(buf);
    close(fd);
    return (errors == 0 && packets_read > 0) ? 0 : 1;
}
