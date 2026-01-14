###################################################################################
## Vivado Block Design TCL Script for PCIe GPU Bridge
## Target: AX7203 (XC7A200T-2FBG484I)
## PCIe: Gen2 x4 with XDMA IP
##
## Usage: vivado -mode batch -source scripts/create_block_design.tcl
###################################################################################

# Project settings
set project_name "21-pcie_gpu_bridge"
set project_dir "./vivado_project"
set part_name "xc7a200tfbg484-2"
set board_part ""

# Create project
create_project $project_name $project_dir -part $part_name -force

# Set project properties
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]

###################################################################################
## Create Block Design
###################################################################################
create_bd_design "pcie_system"

# Add XDMA IP (DMA/Bridge Subsystem for PCIe)
create_bd_cell -type ip -vlnv xilinx.com:ip:xdma:4.2 xdma_0

# Configure XDMA IP for Gen2 x4 with AXI-Stream mode (matching vendor demo)
# This provides S_AXIS_C2H_0 (input) and M_AXIS_H2C_0 (output) interfaces
#
# CRITICAL: select_quad must be GTH_Quad_128 for AX7203 board
# Lane locations from vendor demo:
#   Lane 0 -> GTPE2_CHANNEL_X0Y5
#   Lane 1 -> GTPE2_CHANNEL_X0Y4
#   Lane 2 -> GTPE2_CHANNEL_X0Y6
#   Lane 3 -> GTPE2_CHANNEL_X0Y7
#   Common -> GTPE2_COMMON_X0Y1
set_property -dict [list \
    CONFIG.pcie_blk_locn {X0Y0} \
    CONFIG.select_quad {GTH_Quad_128} \
    CONFIG.pl_link_cap_max_link_width {X4} \
    CONFIG.pl_link_cap_max_link_speed {5.0_GT/s} \
    CONFIG.axi_data_width {64_bit} \
    CONFIG.axisten_freq {250} \
    CONFIG.pf0_device_id {7024} \
    CONFIG.pf0_subsystem_id {0007} \
    CONFIG.pf0_subsystem_vendor_id {10EE} \
    CONFIG.pf0_class_code_base {05} \
    CONFIG.pf0_class_code_sub {80} \
    CONFIG.pf0_class_code_interface {00} \
    CONFIG.xdma_num_usr_irq {4} \
    CONFIG.pf0_msi_enabled {true} \
    CONFIG.pf0_msix_enabled {false} \
    CONFIG.cfg_mgmt_if {false} \
    CONFIG.plltype {QPLL1} \
    CONFIG.dma_reset_source_sel {User_Reset} \
    CONFIG.en_gt_selection {true} \
    CONFIG.mode_selection {Advanced} \
    CONFIG.pcie_extended_tag {true} \
    CONFIG.c_s_axi_supports_narrow_burst {false} \
    CONFIG.xdma_axi_intf_mm {AXI_Stream} \
    CONFIG.xdma_rnum_chnl {1} \
    CONFIG.xdma_wnum_chnl {1} \
    CONFIG.axilite_master_en {false} \
    CONFIG.axisten_if_enable_client_tag {false} \
    CONFIG.xdma_sts_ports {false} \
] [get_bd_cells xdma_0]

# Configure BAR0 for XDMA control registers (128 KB minimum for XDMA IP)
set_property -dict [list \
    CONFIG.pf0_bar0_enabled {true} \
    CONFIG.pf0_bar0_type {Memory} \
    CONFIG.pf0_bar0_64bit {false} \
    CONFIG.pf0_bar0_prefetchable {false} \
    CONFIG.pf0_bar0_scale {Kilobytes} \
    CONFIG.pf0_bar0_size {128} \
] [get_bd_cells xdma_0]

###################################################################################
## Create External Ports
###################################################################################

# PCIe interface
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:pcie_7x_mgt_rtl:1.0 pcie_mgt
connect_bd_intf_net [get_bd_intf_pins xdma_0/pcie_mgt] [get_bd_intf_ports pcie_mgt]

# Manual PCIe clock infrastructure (instead of automation)
# Create external ports first
create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 pcie_refclk
create_bd_port -dir I -type rst reset_rtl_0
set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports reset_rtl_0]

# Create utility differential buffer for PCIe reference clock (100 MHz)
# Using IBUFDS_GTE2 primitive for GTP reference clock
create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.2 util_ds_buf_0
set_property CONFIG.C_BUF_TYPE {IBUFDSGTE} [get_bd_cells util_ds_buf_0]

# Connect differential clock to buffer
connect_bd_intf_net [get_bd_intf_ports pcie_refclk] [get_bd_intf_pins util_ds_buf_0/CLK_IN_D]

# Connect single-ended output to XDMA
connect_bd_net [get_bd_pins util_ds_buf_0/IBUF_OUT] [get_bd_pins xdma_0/sys_clk]

# Connect reset
connect_bd_net [get_bd_ports reset_rtl_0] [get_bd_pins xdma_0/sys_rst_n]

# Print XDMA interface information for debugging
puts ""
puts "=== XDMA Interface Debug ==="
puts "M_AXI interface pins:"
foreach pin [get_bd_intf_pins -quiet -of_objects [get_bd_cells xdma_0] -filter {VLNV =~ "*axi*"}] {
    puts "  $pin"
}
puts ""
puts "XDMA configuration:"
foreach prop {axi_data_width xdma_axi_intf_mm} {
    puts "  $prop = [get_property CONFIG.$prop [get_bd_cells xdma_0]]"
}
puts "============================="
puts ""

# Rename the auto-created differential clock port for clarity
# The automation creates: diff_clock_rtl_0 -> util_ds_buf -> xdma_0/sys_clk
# Also creates: pcie_perstn port -> xdma_0/sys_rst_n

# Get reference to auto-created ports for documentation
# diff_clock_rtl_0: PCIe reference clock (100 MHz differential)
# pcie_perstn: PCIe reset (directly connected by automation)

###################################################################################
## Tie Off Unused AXI Stream Interfaces
## For initial testing, S_AXIS_C2H is tied off to prevent hanging
###################################################################################

# List available interfaces for debugging
puts "Available XDMA interfaces (AXI Stream mode):"
foreach intf [get_bd_intf_pins -of_objects [get_bd_cells xdma_0]] {
    puts "  $intf"
}
puts ""

###################################################################################
## Test Pattern Generator for S_AXIS_C2H
## Using Xilinx binary counter IP to avoid VHDL hierarchy issues
###################################################################################

# Create 64-bit counter for TDATA (with CE pin enabled)
create_bd_cell -type ip -vlnv xilinx.com:ip:c_counter_binary:12.0 counter_tdata
set_property -dict [list \
    CONFIG.Output_Width {64} \
    CONFIG.Increment_Value {1} \
    CONFIG.CE {true} \
] [get_bd_cells counter_tdata]

# Create constant for TVALID (always 1)
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_one_1
set_property -dict [list \
    CONFIG.CONST_WIDTH {1} \
    CONFIG.CONST_VAL {1} \
] [get_bd_cells const_one_1]

# Create constant for TKEEP (all 1s = all bytes valid)
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_tkeep
set_property -dict [list \
    CONFIG.CONST_WIDTH {8} \
    CONFIG.CONST_VAL {0xFF} \
] [get_bd_cells const_tkeep]

# Create constant for TLAST (0 = continuous stream, no packet boundaries)
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_tlast
set_property -dict [list \
    CONFIG.CONST_WIDTH {1} \
    CONFIG.CONST_VAL {0} \
] [get_bd_cells const_tlast]

# Connect test pattern to S_AXIS_C2H_0
puts "Connecting test pattern generator to S_AXIS_C2H_0"

# Connect counter clock and enable
connect_bd_net [get_bd_pins xdma_0/axi_aclk] [get_bd_pins counter_tdata/CLK]
# Counter enable = TREADY (only count when XDMA accepts data)
connect_bd_net [get_bd_pins xdma_0/s_axis_c2h_tready_0] [get_bd_pins counter_tdata/CE]

# Connect counter output to TDATA
connect_bd_net [get_bd_pins counter_tdata/Q] [get_bd_pins xdma_0/s_axis_c2h_tdata_0]

# Connect constants to control signals
connect_bd_net [get_bd_pins const_one_1/dout] [get_bd_pins xdma_0/s_axis_c2h_tvalid_0]
connect_bd_net [get_bd_pins const_tkeep/dout] [get_bd_pins xdma_0/s_axis_c2h_tkeep_0]
connect_bd_net [get_bd_pins const_tlast/dout] [get_bd_pins xdma_0/s_axis_c2h_tlast_0]

puts "Test pattern generator connected (using Xilinx IP):"
puts "  TDATA: 64-bit incrementing counter (0, 1, 2, 3, ...)"
puts "  TVALID: Always 1 (continuous streaming)"
puts "  TKEEP: 0xFF (all bytes valid)"
puts "  TLAST: Always 0 (no packet boundaries)"

###################################################################################
## Tie Off M_AXIS_H2C (Host-to-Card) Interface
## CRITICAL: Without this, H2C transfers hang and cause PC stuttering!
## The design accepts and discards any data sent from host to card
###################################################################################

# Create constant 1 for TREADY (always ready to accept H2C data)
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_h2c_tready
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] [get_bd_cells const_h2c_tready]

# Connect TREADY high - accept and discard all H2C data
connect_bd_net [get_bd_pins const_h2c_tready/dout] [get_bd_pins xdma_0/m_axis_h2c_tready_0]

puts "M_AXIS_H2C_0 tied off (TREADY=1, data discarded)"

###################################################################################
## Clock and Reset Infrastructure
###################################################################################

# Processor System Reset for XDMA clock domain
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_xdma
connect_bd_net [get_bd_pins xdma_0/axi_aclk] [get_bd_pins rst_xdma/slowest_sync_clk]
connect_bd_net [get_bd_pins xdma_0/axi_aresetn] [get_bd_pins rst_xdma/ext_reset_in]

# Tie dcm_locked high - no external PLL to monitor
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_one
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] [get_bd_cells const_one]
connect_bd_net [get_bd_pins const_one/dout] [get_bd_pins rst_xdma/dcm_locked]

# No BRAM in AXI Stream mode - all clocks managed by XDMA IP

###################################################################################
## External Ports for User Logic
###################################################################################

# Tie off user interrupts (not used in basic design)
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_zero_4
set_property -dict [list CONFIG.CONST_WIDTH {4} CONFIG.CONST_VAL {0}] [get_bd_cells const_zero_4]
connect_bd_net [get_bd_pins const_zero_4/dout] [get_bd_pins xdma_0/usr_irq_req]

# LED output for link status (directly from XDMA, active high)
create_bd_port -dir O user_lnk_up
connect_bd_net [get_bd_pins xdma_0/user_lnk_up] [get_bd_ports user_lnk_up]

# UART debug removed for now - focus on core PCIe streaming first

###################################################################################
## Address Map Configuration
###################################################################################
# AXI Stream mode has no memory-mapped address space (no M_AXI interface)
# Streaming data flows through S_AXIS_C2H_0 and M_AXIS_H2C_0
assign_bd_address

puts ""
puts "=== AXI Stream Configuration ==="
puts "XDMA configured for pure streaming mode (no M_AXI)"
puts "Available AXI-Stream interfaces:"
foreach intf [get_bd_intf_pins -quiet -of_objects [get_bd_cells xdma_0] -filter {MODE == Slave && VLNV =~ "*axis*"}] {
    puts "  Input: $intf"
}
foreach intf [get_bd_intf_pins -quiet -of_objects [get_bd_cells xdma_0] -filter {MODE == Master && VLNV =~ "*axis*"}] {
    puts "  Output: $intf"
}
puts "================================"
puts ""

###################################################################################
## Validate and Save Block Design
###################################################################################

# Regenerate layout
regenerate_bd_layout

# Validate design
validate_bd_design

# Save block design
save_bd_design

# Generate HDL wrapper
make_wrapper -files [get_files $project_dir/$project_name.srcs/sources_1/bd/pcie_system/pcie_system.bd] -top
add_files -norecurse $project_dir/$project_name.gen/sources_1/bd/pcie_system/hdl/pcie_system_wrapper.vhd

###################################################################################
## Add Constraints
###################################################################################

# Add constraints file
add_files -fileset constrs_1 -norecurse constraints/ax7203_pcie.xdc

###################################################################################
## Generate Output Products
###################################################################################

# Generate block design output products
generate_target all [get_files $project_dir/$project_name.srcs/sources_1/bd/pcie_system/pcie_system.bd]

###################################################################################
## Disable Auto-Generated GTP Constraints (CRITICAL for AX7203)
###################################################################################
# The XDMA IP auto-generates a constraint file with WRONG GTP lane order:
#   Auto-generated: Lane0=X0Y7, Lane1=X0Y6, Lane2=X0Y5, Lane3=X0Y4
#   AX7203 correct: Lane0=X0Y5, Lane1=X0Y4, Lane2=X0Y6, Lane3=X0Y7
#
# The auto-generated file must be disabled; ax7203_pcie.xdc is used instead.

# Find and disable the auto-generated PCIE_X0Y0.xdc constraint file
set auto_gen_xdc [get_files -quiet *pcie2_ip-PCIE_X0Y0.xdc]
if {[llength $auto_gen_xdc] > 0} {
    puts "Disabling auto-generated GTP constraint file: $auto_gen_xdc"
    set_property IS_ENABLED false [get_files $auto_gen_xdc]
    # Also set USED_IN to none to prevent it from being processed
    set_property USED_IN {} [get_files $auto_gen_xdc]
} else {
    puts "WARNING: Auto-generated PCIE_X0Y0.xdc not found - may need manual disable"
}

# Disable any xdma IP-level constraint files that have wrong LOC constraints
set xdma_xdc_files [get_files -quiet -of_objects [get_ips -quiet *xdma*] *.xdc]
foreach xdc_file $xdma_xdc_files {
    # Get the file name/path - the object itself can be used as a string
    set file_name [get_property NAME $xdc_file]
    if {[string match "*PCIE_X0Y0*" $file_name] || [string match "*pcie2_ip*" $file_name]} {
        puts "Disabling XDMA IP constraint file: $xdc_file"
        set_property IS_ENABLED false $xdc_file
        set_property USED_IN {} $xdc_file
    }
}

# Also check for any other auto-generated transceiver constraints
set auto_gen_gt_xdc [get_files -quiet *_gt.xdc]
if {[llength $auto_gen_gt_xdc] > 0} {
    foreach xdc_file $auto_gen_gt_xdc {
        puts "Found auto-generated GT constraint file: $xdc_file"
        # Only disable if it conflicts with the project constraints
        # set_property IS_ENABLED false [get_files $xdc_file]
    }
}

# Ensure custom constraints have higher priority
set_property PROCESSING_ORDER LATE [get_files constraints/ax7203_pcie.xdc]

###################################################################################
## Configure Implementation Strategy for Timing Closure
###################################################################################

# Set aggressive implementation directives for timing closure
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraTimingOpt [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]


# Run synthesis
# puts "Starting synthesis..."
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# Check synthesis status
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed!"
    return
}
puts "Synthesis completed successfully."

# Run implementation through bitstream
puts "Starting implementation..."
launch_runs impl_1 -jobs 8
wait_on_run impl_1

# Check implementation status
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed!"
    return
}
puts "Implementation completed successfully."

# Generate bitstream
puts "Generating bitstream..."
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

puts ""
puts "=============================================="
puts "Build completed successfully!"
puts "=============================================="
puts ""
puts "Bitstream location:"
puts "  vivado_project/21-pcie_gpu_bridge.runs/impl_1/pcie_system_wrapper.bit"
puts ""
puts "To program FPGA:"
puts "  open_hw_manager"
puts "  connect_hw_server"
puts "  open_hw_target"
puts "  set_property PROGRAM.FILE {vivado_project/21-pcie_gpu_bridge.runs/impl_1/pcie_system_wrapper.bit} [current_hw_device]"
puts "  program_hw_devices"
puts ""
