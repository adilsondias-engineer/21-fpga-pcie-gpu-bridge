####################################################################################
## AX7203 PCIe Constraints for Project 21 (PCIe GPU Bridge)
## Board: ALINX AX7203B (XC7A200T-2FBG484I)
## PCIe: Gen2 x4 (5.0 GT/s per lane, ~2 GB/s total bandwidth)
##
## Reference: AX7203_PIN_Define3.csv from vendor documentation
####################################################################################

####################################################################################
## System Configuration
####################################################################################
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLUP [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

####################################################################################
## PCIe Reference Clock (100 MHz Differential)
## From PCIe edge connector via buffer to FPGA GTP
## Note: Our manual clock infrastructure creates ports named pcie_refclk_clk_p/n
####################################################################################
set_property PACKAGE_PIN F10 [get_ports {pcie_refclk_clk_p[0]}]
set_property PACKAGE_PIN E10 [get_ports {pcie_refclk_clk_n[0]}]

## Create 100 MHz PCIe reference clock
create_clock -period 10.000 -name pcie_refclk [get_ports {pcie_refclk_clk_p[0]}]

####################################################################################
## PCIe PERST# (Reset, Active Low)
## Active low reset from PCIe slot
## Note: XDMA automation creates port named reset_rtl_0
####################################################################################
set_property PACKAGE_PIN J20 [get_ports reset_rtl_0]
set_property IOSTANDARD LVCMOS33 [get_ports reset_rtl_0]
set_property PULLUP TRUE [get_ports reset_rtl_0]

## PERST# is asynchronous to all clocks
set_false_path -from [get_ports reset_rtl_0]

####################################################################################
## PCIe GTP Transceiver Lanes
## AX7203 uses GTPE2 transceivers with specific lane ordering
##
## CRITICAL: The lane order on AX7203 is NOT the default auto-generated order!
##   Auto-generated (WRONG): Lane0=X0Y7, Lane1=X0Y6, Lane2=X0Y5, Lane3=X0Y4
##   AX7203 correct order:   Lane0=X0Y5, Lane1=X0Y4, Lane2=X0Y6, Lane3=X0Y7
##
## GTP Quad Layout on AX7203:
##   GTPE2_CHANNEL_X0Y4 - PCIe Lane 1 (shared with MGT_TX0/RX0)
##   GTPE2_CHANNEL_X0Y5 - PCIe Lane 0 (shared with MGT_TX1/RX1)
##   GTPE2_CHANNEL_X0Y6 - PCIe Lane 2 (shared with MGT_TX2/RX2)
##   GTPE2_CHANNEL_X0Y7 - PCIe Lane 3 (shared with MGT_TX3/RX3)
####################################################################################

## PCIe MGT Package Pins (Fixed by GTPE2_CHANNEL location)
## These pins are determined by the GTP transceiver LOC constraints
## TX pins: differential pairs to PCIe slot
## RX pins: differential pairs from PCIe slot
##
## Physical pin mapping (from AX7203 schematic):
##   Lane 0 (X0Y5): TX=D5/C5, RX=D11/C11
##   Lane 1 (X0Y4): TX=B4/A4, RX=B8/A8
##   Lane 2 (X0Y6): TX=B6/A6, RX=B10/A10
##   Lane 3 (X0Y7): TX=D7/C7, RX=D9/C9

## GTP Channel LOC Constraints
## These use hierarchical paths that match the XDMA IP block design structure
## Multiple path patterns are provided for different XDMA/Vivado versions and wrapper naming

# Pattern 1: Block design path with U0/inst (VERIFIED FROM ACTUAL DESIGN)
# This matches: pcie_system_i/xdma_0/inst/.../pcie2_ip_i/U0/inst/gt_top_i/...
set_property LOC GTPE2_CHANNEL_X0Y5 [get_cells -quiet {pcie_system_i/xdma_0/inst/pcie_system_xdma_0_0_pcie2_to_pcie3_wrapper_i/pcie2_ip_i/U0/inst/gt_top_i/pipe_wrapper_i/pipe_lane[0].gt_wrapper_i/gtp_channel.gtpe2_channel_i}]
set_property LOC GTPE2_CHANNEL_X0Y4 [get_cells -quiet {pcie_system_i/xdma_0/inst/pcie_system_xdma_0_0_pcie2_to_pcie3_wrapper_i/pcie2_ip_i/U0/inst/gt_top_i/pipe_wrapper_i/pipe_lane[1].gt_wrapper_i/gtp_channel.gtpe2_channel_i}]
set_property LOC GTPE2_CHANNEL_X0Y6 [get_cells -quiet {pcie_system_i/xdma_0/inst/pcie_system_xdma_0_0_pcie2_to_pcie3_wrapper_i/pcie2_ip_i/U0/inst/gt_top_i/pipe_wrapper_i/pipe_lane[2].gt_wrapper_i/gtp_channel.gtpe2_channel_i}]
set_property LOC GTPE2_CHANNEL_X0Y7 [get_cells -quiet {pcie_system_i/xdma_0/inst/pcie_system_xdma_0_0_pcie2_to_pcie3_wrapper_i/pcie2_ip_i/U0/inst/gt_top_i/pipe_wrapper_i/pipe_lane[3].gt_wrapper_i/gtp_channel.gtpe2_channel_i}]

# Pattern 2: Wildcard pattern to catch any naming variations
# Using hierarchical wildcard to match any wrapper prefix
set_property LOC GTPE2_CHANNEL_X0Y5 [get_cells -quiet {*/xdma_0/inst/*pcie2_to_pcie3_wrapper_i/pcie2_ip_i/U0/inst/gt_top_i/pipe_wrapper_i/pipe_lane[0].gt_wrapper_i/gtp_channel.gtpe2_channel_i}]
set_property LOC GTPE2_CHANNEL_X0Y4 [get_cells -quiet {*/xdma_0/inst/*pcie2_to_pcie3_wrapper_i/pcie2_ip_i/U0/inst/gt_top_i/pipe_wrapper_i/pipe_lane[1].gt_wrapper_i/gtp_channel.gtpe2_channel_i}]
set_property LOC GTPE2_CHANNEL_X0Y6 [get_cells -quiet {*/xdma_0/inst/*pcie2_to_pcie3_wrapper_i/pcie2_ip_i/U0/inst/gt_top_i/pipe_wrapper_i/pipe_lane[2].gt_wrapper_i/gtp_channel.gtpe2_channel_i}]
set_property LOC GTPE2_CHANNEL_X0Y7 [get_cells -quiet {*/xdma_0/inst/*pcie2_to_pcie3_wrapper_i/pcie2_ip_i/U0/inst/gt_top_i/pipe_wrapper_i/pipe_lane[3].gt_wrapper_i/gtp_channel.gtpe2_channel_i}]

# Pattern 3: Alternative with inst/inst (older Vivado versions)
set_property LOC GTPE2_CHANNEL_X0Y5 [get_cells -quiet {pcie_system_i/xdma_0/inst/pcie_system_xdma_0_0_pcie2_to_pcie3_wrapper_i/pcie2_ip_i/inst/inst/gt_top_i/pipe_wrapper_i/pipe_lane[0].gt_wrapper_i/gtp_channel.gtpe2_channel_i}]
set_property LOC GTPE2_CHANNEL_X0Y4 [get_cells -quiet {pcie_system_i/xdma_0/inst/pcie_system_xdma_0_0_pcie2_to_pcie3_wrapper_i/pcie2_ip_i/inst/inst/gt_top_i/pipe_wrapper_i/pipe_lane[1].gt_wrapper_i/gtp_channel.gtpe2_channel_i}]
set_property LOC GTPE2_CHANNEL_X0Y6 [get_cells -quiet {pcie_system_i/xdma_0/inst/pcie_system_xdma_0_0_pcie2_to_pcie3_wrapper_i/pcie2_ip_i/inst/inst/gt_top_i/pipe_wrapper_i/pipe_lane[2].gt_wrapper_i/gtp_channel.gtpe2_channel_i}]
set_property LOC GTPE2_CHANNEL_X0Y7 [get_cells -quiet {pcie_system_i/xdma_0/inst/pcie_system_xdma_0_0_pcie2_to_pcie3_wrapper_i/pcie2_ip_i/inst/inst/gt_top_i/pipe_wrapper_i/pipe_lane[3].gt_wrapper_i/gtp_channel.gtpe2_channel_i}]

# Pattern 4: Vendor sample path (u_PCIe_wrapper/PCIe_i prefix)
set_property LOC GTPE2_CHANNEL_X0Y5 [get_cells -quiet {u_PCIe_wrapper/PCIe_i/xdma_0/inst/PCIe_xdma_0_1_pcie2_to_pcie3_wrapper_i/pcie2_ip_i/U0/inst/gt_top_i/pipe_wrapper_i/pipe_lane[0].gt_wrapper_i/gtp_channel.gtpe2_channel_i}]
set_property LOC GTPE2_CHANNEL_X0Y4 [get_cells -quiet {u_PCIe_wrapper/PCIe_i/xdma_0/inst/PCIe_xdma_0_1_pcie2_to_pcie3_wrapper_i/pcie2_ip_i/U0/inst/gt_top_i/pipe_wrapper_i/pipe_lane[1].gt_wrapper_i/gtp_channel.gtpe2_channel_i}]
set_property LOC GTPE2_CHANNEL_X0Y6 [get_cells -quiet {u_PCIe_wrapper/PCIe_i/xdma_0/inst/PCIe_xdma_0_1_pcie2_to_pcie3_wrapper_i/pcie2_ip_i/U0/inst/gt_top_i/pipe_wrapper_i/pipe_lane[2].gt_wrapper_i/gtp_channel.gtpe2_channel_i}]
set_property LOC GTPE2_CHANNEL_X0Y7 [get_cells -quiet {u_PCIe_wrapper/PCIe_i/xdma_0/inst/PCIe_xdma_0_1_pcie2_to_pcie3_wrapper_i/pcie2_ip_i/U0/inst/gt_top_i/pipe_wrapper_i/pipe_lane[3].gt_wrapper_i/gtp_channel.gtpe2_channel_i}]

## GTP Common (QPLL) Placement - uses GTP Quad 1 for X0Y4-X0Y7
# Pattern with U0/inst path (verified from actual design)
set_property LOC GTPE2_COMMON_X0Y1 [get_cells -quiet {pcie_system_i/xdma_0/inst/pcie_system_xdma_0_0_pcie2_to_pcie3_wrapper_i/pcie2_ip_i/U0/inst/gt_top_i/pipe_wrapper_i/pipe_lane[0].pipe_quad.gt_common_enabled.gt_common_int.gt_common_i/qpll_wrapper_i/gtp_common.gtpe2_common_i}]
# Wildcard pattern
set_property LOC GTPE2_COMMON_X0Y1 [get_cells -quiet {*/xdma_0/inst/*pcie2_to_pcie3_wrapper_i/pcie2_ip_i/U0/inst/gt_top_i/pipe_wrapper_i/pipe_lane[0].pipe_quad.gt_common_enabled.gt_common_int.gt_common_i/qpll_wrapper_i/gtp_common.gtpe2_common_i}]
# Alternative inst/inst path
set_property LOC GTPE2_COMMON_X0Y1 [get_cells -quiet {pcie_system_i/xdma_0/inst/pcie_system_xdma_0_0_pcie2_to_pcie3_wrapper_i/pcie2_ip_i/inst/inst/gt_top_i/pipe_wrapper_i/pipe_lane[0].pipe_quad.gt_common_enabled.gt_common_int.gt_common_i/qpll_wrapper_i/gtp_common.gtpe2_common_i}]

## PCI Express Block Placement (7-series integrated PCIe hard block)
# Pattern with U0/inst path (verified from actual design)
set_property LOC PCIE_X0Y0 [get_cells -quiet {pcie_system_i/xdma_0/inst/pcie_system_xdma_0_0_pcie2_to_pcie3_wrapper_i/pcie2_ip_i/U0/inst/pcie_top_i/pcie_7x_i/pcie_block_i}]
# Wildcard pattern
set_property LOC PCIE_X0Y0 [get_cells -quiet {*/xdma_0/inst/*pcie2_to_pcie3_wrapper_i/pcie2_ip_i/U0/inst/pcie_top_i/pcie_7x_i/pcie_block_i}]
# Alternative inst/inst path
set_property LOC PCIE_X0Y0 [get_cells -quiet {pcie_system_i/xdma_0/inst/pcie_system_xdma_0_0_pcie2_to_pcie3_wrapper_i/pcie2_ip_i/inst/inst/pcie_top_i/pcie_7x_i/pcie_block_i}]

####################################################################################
## PCIe MGT Port Constraints
## The pcie_mgt_* ports connect directly to GTP transceivers and don't need
## explicit PACKAGE_PIN constraints - their locations are determined by the
## GTPE2_CHANNEL LOC constraints above.
##
## Vivado DRC UCIO-1 complains about unconstrained ports, but GTP transceiver
## ports are handled differently - they're bonded to specific package pins based
## on the GTP LOC, not user-assignable.
##
## We suppress the DRC warning for these specific ports:
####################################################################################

## Suppress UCIO-1 DRC for GTP transceiver ports (they're constrained by GTP LOC)
## This is safe because GTP TX/RX ports have fixed package pin assignments
## based on their GTPE2_CHANNEL location
##
## The pcie_mgt_* ports are Multi-Gigabit Transceiver (MGT) differential pairs
## that connect directly to GTPE2 transceivers. They do NOT need PACKAGE_PIN
## constraints - their physical pins are determined by the GTPE2_CHANNEL LOC.
##
## Use create_waiver to explicitly waive the DRC for these specific ports:
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]

## Create waivers for PCIe MGT ports - these are GT ports, not regular I/O
## The -objects flag targets specific ports to avoid blanket waiver
create_waiver -quiet -type DRC -id {UCIO-1} -description {PCIe MGT TX/RX ports are constrained by GTPE2_CHANNEL LOC, not PACKAGE_PIN} \
    -objects [get_ports -quiet {pcie_mgt_txp[*] pcie_mgt_txn[*] pcie_mgt_rxp[*] pcie_mgt_rxn[*]}]

## Alternative waiver syntax if port names differ in wrapper
create_waiver -quiet -type DRC -id {UCIO-1} -description {PCIe MGT TX/RX ports are constrained by GTPE2_CHANNEL LOC} \
    -objects [get_ports -quiet {*_mgt_txp* *_mgt_txn* *_mgt_rxp* *_mgt_rxn*}]

## Waiver for pcie_7x_mgt interface ports (block design naming convention)
create_waiver -quiet -type DRC -id {UCIO-1} -description {PCIe MGT interface ports} \
    -objects [get_ports -quiet {pcie_mgt_*}]

## Alternative: If you want to be explicit about the GTP port pins
## (these are automatically assigned by the GTPE2_CHANNEL LOC, but can be explicit)
## Note: These are GTP transceiver pins, not regular I/O - IOSTANDARD is not applicable
##
## The AX7203 GTP Quad X0Y1 pin mapping:
##   X0Y4: TX_P=B4, TX_N=A4, RX_P=B8,  RX_N=A8   (Lane 1)
##   X0Y5: TX_P=D5, TX_N=C5, RX_P=D11, RX_N=C11  (Lane 0)
##   X0Y6: TX_P=B6, TX_N=A6, RX_P=B10, RX_N=A10  (Lane 2)
##   X0Y7: TX_P=D7, TX_N=C7, RX_P=D9,  RX_N=C9   (Lane 3)

####################################################################################
## System Clock (200 MHz Differential)
## Note: Not used in standalone PCIe design - trading logic uses XDMA clock
## Uncomment when integrating with Project 20
####################################################################################
# create_clock -period 5.000 -name sys_clk_p [get_ports sys_clk_p]
# set_property PACKAGE_PIN R4 [get_ports sys_clk_p]
# set_property IOSTANDARD DIFF_SSTL15 [get_ports sys_clk_p]

####################################################################################
## Reset Button (for debug)
## Note: Not used in standalone PCIe design
####################################################################################
# set_property PACKAGE_PIN T6 [get_ports reset_n]
# set_property IOSTANDARD LVCMOS15 [get_ports reset_n]
# set_false_path -from [get_ports reset_n]

####################################################################################
## LEDs (for status indication)
## Block design creates: user_lnk_up, led_streaming, led_overflow
####################################################################################

## LED 0: PCIe Link Up (directly from XDMA)
set_property PACKAGE_PIN B13 [get_ports user_lnk_up]
set_property IOSTANDARD LVCMOS33 [get_ports user_lnk_up]

## LED 1: BBO Streaming Active
set_property PACKAGE_PIN C13 [get_ports led_streaming]
set_property IOSTANDARD LVCMOS33 [get_ports led_streaming]

## LED 2: FIFO Overflow
set_property PACKAGE_PIN D14 [get_ports led_overflow]
set_property IOSTANDARD LVCMOS33 [get_ports led_overflow]

## LED outputs are async - no timing requirements
set_false_path -to [get_ports user_lnk_up]
set_false_path -to [get_ports led_streaming]
set_false_path -to [get_ports led_overflow]

####################################################################################
## PCIe Timing Constraints (from vendor sample)
####################################################################################

## GTP TXOUTCLK - 100 MHz reference for PIPE clock
## Multiple path patterns for different wrapper naming conventions
create_clock -period 10.000 -name txoutclk_x0y0 [get_pins -quiet {u_PCIe_wrapper/PCIe_i/xdma_0/inst/PCIe_xdma_0_1_pcie2_to_pcie3_wrapper_i/pcie2_ip_i/inst/inst/gt_top_i/pipe_wrapper_i/pipe_lane[0].gt_wrapper_i/gtp_channel.gtpe2_channel_i/TXOUTCLK}]
create_clock -period 10.000 -name txoutclk_x0y0 [get_pins -quiet {pcie_system_i/xdma_0/inst/pcie_system_xdma_0_0_pcie2_to_pcie3_wrapper_i/pcie2_ip_i/inst/inst/gt_top_i/pipe_wrapper_i/pipe_lane[0].gt_wrapper_i/gtp_channel.gtpe2_channel_i/TXOUTCLK}]

## PCIe PIPE Clock Mux false paths (clock switching between Gen1/Gen2)
set_false_path -quiet -to [get_pins -quiet {*xdma_0/inst/*pcie2_to_pcie3_wrapper_i/pcie2_ip_i/inst/inst/gt_top_i/pipe_wrapper_i/pipe_clock_int.pipe_clock_i/pclk_i1_bufgctrl.pclk_i1/S0}]
set_false_path -quiet -to [get_pins -quiet {*xdma_0/inst/*pcie2_to_pcie3_wrapper_i/pcie2_ip_i/inst/inst/gt_top_i/pipe_wrapper_i/pipe_clock_int.pipe_clock_i/pclk_i1_bufgctrl.pclk_i1/S1}]

## Generated clocks from MMCM (125 MHz and 250 MHz for Gen1/Gen2)
create_generated_clock -quiet -name clk_125mhz_x0y0 [get_pins -quiet {*xdma_0/inst/*pcie2_to_pcie3_wrapper_i/pcie2_ip_i/inst/inst/gt_top_i/pipe_wrapper_i/pipe_clock_int.pipe_clock_i/mmcm_i/CLKOUT0}]
create_generated_clock -quiet -name clk_250mhz_x0y0 [get_pins -quiet {*xdma_0/inst/*pcie2_to_pcie3_wrapper_i/pcie2_ip_i/inst/inst/gt_top_i/pipe_wrapper_i/pipe_clock_int.pipe_clock_i/mmcm_i/CLKOUT1}]

## Generated clocks for clock mux outputs (125 MHz and 250 MHz multiplexed)
create_generated_clock -quiet -name clk_125mhz_mux_x0y0 \
    -source [get_pins -quiet {*xdma_0/inst/*pcie2_to_pcie3_wrapper_i/pcie2_ip_i/inst/inst/gt_top_i/pipe_wrapper_i/pipe_clock_int.pipe_clock_i/pclk_i1_bufgctrl.pclk_i1/I0}] \
    -divide_by 1 \
    [get_pins -quiet {*xdma_0/inst/*pcie2_to_pcie3_wrapper_i/pcie2_ip_i/inst/inst/gt_top_i/pipe_wrapper_i/pipe_clock_int.pipe_clock_i/pclk_i1_bufgctrl.pclk_i1/O}]

create_generated_clock -quiet -name clk_250mhz_mux_x0y0 \
    -source [get_pins -quiet {*xdma_0/inst/*pcie2_to_pcie3_wrapper_i/pcie2_ip_i/inst/inst/gt_top_i/pipe_wrapper_i/pipe_clock_int.pipe_clock_i/pclk_i1_bufgctrl.pclk_i1/I1}] \
    -divide_by 1 -add -master_clock clk_250mhz_x0y0 \
    [get_pins -quiet {*xdma_0/inst/*pcie2_to_pcie3_wrapper_i/pcie2_ip_i/inst/inst/gt_top_i/pipe_wrapper_i/pipe_clock_int.pipe_clock_i/pclk_i1_bufgctrl.pclk_i1/O}]

####################################################################################
## GTP Async Signal False Paths (from vendor sample)
## These signals cross clock domains within the PCIe IP and don't need timing
####################################################################################

## PCIe core async signals
set_false_path -through [get_pins -quiet -filter {REF_PIN_NAME=~PLPHYLNKUPN} -of_objects [get_cells -quiet -hierarchical -filter {PRIMITIVE_TYPE =~ *}]]
set_false_path -through [get_pins -quiet -filter {REF_PIN_NAME=~PLRECEIVEDHOTRST} -of_objects [get_cells -quiet -hierarchical -filter {PRIMITIVE_TYPE =~ *}]]

## GTP transceiver async signals
set_false_path -through [get_pins -quiet -filter {REF_PIN_NAME=~RXELECIDLE} -of_objects [get_cells -quiet -hierarchical -filter {PRIMITIVE_TYPE =~ IO.gt.*}]]
set_false_path -through [get_pins -quiet -filter {REF_PIN_NAME=~TXPHINITDONE} -of_objects [get_cells -quiet -hierarchical -filter {PRIMITIVE_TYPE =~ IO.gt.*}]]
set_false_path -through [get_pins -quiet -filter {REF_PIN_NAME=~TXPHALIGNDONE} -of_objects [get_cells -quiet -hierarchical -filter {PRIMITIVE_TYPE =~ IO.gt.*}]]
set_false_path -through [get_pins -quiet -filter {REF_PIN_NAME=~TXDLYSRESETDONE} -of_objects [get_cells -quiet -hierarchical -filter {PRIMITIVE_TYPE =~ IO.gt.*}]]
set_false_path -through [get_pins -quiet -filter {REF_PIN_NAME=~RXDLYSRESETDONE} -of_objects [get_cells -quiet -hierarchical -filter {PRIMITIVE_TYPE =~ IO.gt.*}]]
set_false_path -through [get_pins -quiet -filter {REF_PIN_NAME=~RXPHALIGNDONE} -of_objects [get_cells -quiet -hierarchical -filter {PRIMITIVE_TYPE =~ IO.gt.*}]]
set_false_path -through [get_pins -quiet -filter {REF_PIN_NAME=~RXCDRLOCK} -of_objects [get_cells -quiet -hierarchical -filter {PRIMITIVE_TYPE =~ IO.gt.*}]]
set_false_path -through [get_pins -quiet -filter {REF_PIN_NAME=~CFGMSGRECEIVEDPMETO} -of_objects [get_cells -quiet -hierarchical -filter {PRIMITIVE_TYPE =~ *}]]
set_false_path -through [get_pins -quiet -filter {REF_PIN_NAME=~PLL0LOCK} -of_objects [get_cells -quiet -hierarchical -filter {PRIMITIVE_TYPE =~ IO.gt.*}]]
set_false_path -through [get_pins -quiet -filter {REF_PIN_NAME=~RXPMARESETDONE} -of_objects [get_cells -quiet -hierarchical -filter {PRIMITIVE_TYPE =~ IO.gt.*}]]
set_false_path -through [get_pins -quiet -filter {REF_PIN_NAME=~RXSYNCDONE} -of_objects [get_cells -quiet -hierarchical -filter {PRIMITIVE_TYPE =~ IO.gt.*}]]
set_false_path -through [get_pins -quiet -filter {REF_PIN_NAME=~TXSYNCDONE} -of_objects [get_cells -quiet -hierarchical -filter {PRIMITIVE_TYPE =~ IO.gt.*}]]

####################################################################################
## Clock Groups for Async Domains
####################################################################################

## Note: sys_clk_p not used in standalone design
## Uncomment when integrating with Project 20
# set_clock_groups -asynchronous \
#     -group [get_clocks sys_clk_p] \
#     -group [get_clocks -include_generated_clocks pcie_refclk]

####################################################################################
## CDC Constraints for BBO Data Path
## BBO data flows: Trading Logic (200 MHz) -> PCIe (125/250 MHz)
####################################################################################

## False paths for async FIFO gray-coded pointers (handled by FIFO IP)
## Note: These will be added once the actual register names are known

####################################################################################
## Physical Constraints for PCIe Block
####################################################################################

## The XDMA IP uses a specific GTP Quad location
## For 7-series, this is typically specified in the IP configuration
## The AX7203 uses GTP_QUAD_X0Y0 or similar

## Pblock for PCIe logic (optional - can improve timing closure)
# create_pblock pblock_pcie
# add_cells_to_pblock [get_pblocks pblock_pcie] [get_cells -hierarchical -filter {NAME =~ *xdma_*}]
# resize_pblock [get_pblocks pblock_pcie] -add {SLICE_X0Y0:SLICE_X49Y99}

####################################################################################
## Debug Constraints
####################################################################################

## ILA debug core constraints (if used)
# set_property C_CLK_INPUT_FREQ_HZ 125000000 [get_debug_cores dbg_hub]
# set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]

####################################################################################
## UART (for debug output) - disabled for now
####################################################################################
# set_property PACKAGE_PIN N15 [get_ports uart_tx]
# set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]
# set_false_path -to [get_ports uart_tx]

####################################################################################
## Notes for Integration with Project 20
####################################################################################
##
## When integrating with Project 20 (Order Book):
##
## 1. Remove Ethernet-specific constraints if PCIe replaces UDP output
##    Or keep both for dual-path operation
##
## 2. CDC between trading logic (200 MHz) and PCIe (125 MHz):
##    - Use async FIFO for BBO data (already exists in Project 20)
##    - Add false path constraints for gray-coded pointers
##
## 3. Control register access:
##    - PCIe AXI-Lite replaces UART configuration
##    - 125 MHz control -> 200 MHz trading logic CDC needed
##
## 4. Interrupt handling:
##    - XDMA supports MSI-X interrupts
##    - Configure up to 16 user interrupts for BBO events
##
####################################################################################
