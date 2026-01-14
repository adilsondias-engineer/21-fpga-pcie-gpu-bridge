/*
 * Test Pattern Verification Tool
 * Reads from XDMA C2H channel and verifies incrementing counter pattern
 *
 * Expected pattern: 64-bit little-endian incrementing counter
 *   Bytes: 00 00 00 00 00 00 00 00  (counter = 0)
 *          01 00 00 00 00 00 00 00  (counter = 1)
 *          02 00 00 00 00 00 00 00  (counter = 2)
 *          ...
 *
 * Usage: ./test_pattern_verify [device] [count]
 *   device: XDMA device path (default: /dev/xdma0_c2h_0)
 *   count: Number of 64-bit words to read and verify (default: 1024)
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
#define DEFAULT_COUNT 1024

int main(int argc, char **argv) {
    const char *device = DEFAULT_DEVICE;
    uint64_t count = DEFAULT_COUNT;

    if (argc > 1) device = argv[1];
    if (argc > 2) count = strtoull(argv[2], NULL, 10);

    printf("Test Pattern Verification\n");
    printf("==========================\n");
    printf("Device: %s\n", device);
    printf("Words to read: %lu (%.2f KB)\n", count, count * 8.0 / 1024.0);
    printf("\n");

    // Open device
    int fd = open(device, O_RDONLY);
    if (fd < 0) {
        perror("Failed to open device");
        return 1;
    }

    // Allocate buffer (aligned for DMA)
    uint64_t *buf = aligned_alloc(4096, count * sizeof(uint64_t));
    if (!buf) {
        perror("Failed to allocate buffer");
        close(fd);
        return 1;
    }

    // Read data
    printf("Reading data from FPGA...\n");
    struct timeval start, end;
    gettimeofday(&start, NULL);

    ssize_t bytes_read = read(fd, buf, count * sizeof(uint64_t));

    gettimeofday(&end, NULL);

    if (bytes_read < 0) {
        perror("Read failed");
        free(buf);
        close(fd);
        return 1;
    }

    double elapsed = (end.tv_sec - start.tv_sec) +
                     (end.tv_usec - start.tv_usec) / 1000000.0;
    double throughput = (bytes_read / 1024.0 / 1024.0) / elapsed;

    printf("Read %zd bytes in %.3f seconds (%.2f MB/s)\n\n",
           bytes_read, elapsed, throughput);

    // Verify pattern
    uint64_t words_read = bytes_read / sizeof(uint64_t);
    uint64_t errors = 0;
    uint64_t first_error_idx = 0;
    uint64_t first_error_expected = 0;
    uint64_t first_error_got = 0;

    printf("Verifying incrementing counter pattern...\n");

    for (uint64_t i = 0; i < words_read; i++) {
        if (buf[i] != i) {
            if (errors == 0) {
                first_error_idx = i;
                first_error_expected = i;
                first_error_got = buf[i];
            }
            errors++;

            // Print first 10 errors
            if (errors <= 10) {
                printf("  Error at word %lu: expected 0x%016lx, got 0x%016lx\n",
                       i, i, buf[i]);
            }
        }
    }

    printf("\n");
    printf("Results:\n");
    printf("========\n");
    printf("Words verified: %lu\n", words_read);
    printf("Errors: %lu\n", errors);

    if (errors == 0) {
        printf("Status: PASS ✓ - Pattern is correct!\n");
        printf("\nFirst 16 values:\n");
        for (int i = 0; i < 16 && i < words_read; i++) {
            printf("  [%2d] = %lu (0x%016lx)\n", i, buf[i], buf[i]);
        }
        free(buf);
        close(fd);
        return 0;
    } else {
        printf("Status: FAIL ✗ - Pattern errors detected\n");
        printf("First error at word %lu: expected 0x%016lx, got 0x%016lx\n",
               first_error_idx, first_error_expected, first_error_got);
        free(buf);
        close(fd);
        return 1;
    }
}
