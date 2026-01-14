# Makefile for PCIe GPU Bridge Tests

CXX = g++
CXXFLAGS = -std=c++20 -Wall -Wextra -O2 -g
INCLUDES = -I../include -I../../common

# Source files
SRCS = pcie_loopback_test.cpp ../src/xdma_wrapper.cpp
OBJS = $(SRCS:.cpp=.o)

# Target
TARGET = pcie_loopback_test

.PHONY: all clean test

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CXX) $(CXXFLAGS) $(INCLUDES) -o $@ $^ -lpthread

%.o: %.cpp
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c -o $@ $<

clean:
	rm -f $(TARGET) $(OBJS)

test: $(TARGET)
	@echo "=== Running PCIe Tests ==="
	@echo ""
	@echo "Note: Requires FPGA programmed with PCIe bitstream and XDMA driver loaded"
	@echo ""
	@if lsmod | grep -q xdma; then \
		sudo ./$(TARGET) -r -n 10 -v; \
	else \
		echo "XDMA driver not loaded. Run: sudo modprobe xdma"; \
	fi

# Install test to system
install: $(TARGET)
	sudo cp $(TARGET) /usr/local/bin/

# Check prerequisites
check:
	@echo "Checking PCIe prerequisites..."
	@echo ""
	@echo "1. XDMA driver:"
	@if lsmod | grep -q xdma; then \
		echo "   [OK] xdma module loaded"; \
	else \
		echo "   [MISSING] xdma module not loaded"; \
		echo "   Run: sudo modprobe xdma"; \
	fi
	@echo ""
	@echo "2. Device files:"
	@if [ -c /dev/xdma0_c2h_0 ]; then \
		echo "   [OK] /dev/xdma0_c2h_0 exists"; \
	else \
		echo "   [MISSING] /dev/xdma0_c2h_0"; \
	fi
	@if [ -c /dev/xdma0_h2c_0 ]; then \
		echo "   [OK] /dev/xdma0_h2c_0 exists"; \
	else \
		echo "   [MISSING] /dev/xdma0_h2c_0"; \
	fi
	@if [ -c /dev/xdma0_user ]; then \
		echo "   [OK] /dev/xdma0_user exists"; \
	else \
		echo "   [MISSING] /dev/xdma0_user"; \
	fi
	@echo ""
	@echo "3. PCIe device:"
	@if lspci | grep -q "Xilinx"; then \
		lspci | grep "Xilinx"; \
	else \
		echo "   [MISSING] No Xilinx PCIe device found"; \
		echo "   Check FPGA is programmed with PCIe bitstream"; \
	fi

help:
	@echo "Available targets:"
	@echo "  all      - Build test executable"
	@echo "  clean    - Remove build artifacts"
	@echo "  test     - Run tests (requires FPGA)"
	@echo "  check    - Check prerequisites"
	@echo "  install  - Install to /usr/local/bin"
	@echo ""
	@echo "Test options:"
	@echo "  ./pcie_loopback_test -h    Show all options"
	@echo "  ./pcie_loopback_test -r    Read BBO stream"
	@echo "  ./pcie_loopback_test -s    Streaming mode"
	@echo "  ./pcie_loopback_test -v    Verbose output"
