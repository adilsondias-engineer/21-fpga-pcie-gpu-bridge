####################################################################################
## Generate MCS file for SPI Flash Programming
## Target: AX7203 (XC7A200T-2FBG484I) with 128 Mbit SPI Flash
##
## Usage: vivado -mode batch -source scripts/generate_mcs.tcl
##
## After generating, program the flash in Vivado Hardware Manager:
##   1. Open Hardware Manager
##   2. Right-click on the FPGA device
##   3. Select "Add Configuration Memory Device"
##   4. Choose: mt25ql128-spi-x1_x2_x4 (or similar 128 Mbit SPI)
##   5. Program the .mcs file
##   6. Power cycle the PC (cold boot required for PCIe enumeration)
####################################################################################

# Open project
set project_dir "./vivado_project"
set project_name "21-pcie_gpu_bridge"

open_project $project_dir/$project_name.xpr

# Path to bitstream
set bitstream_file "$project_dir/$project_name.runs/impl_1/pcie_system_wrapper.bit"
set mcs_file "$project_dir/$project_name.runs/impl_1/pcie_system_wrapper.mcs"

# Verify bitstream exists
if {![file exists $bitstream_file]} {
    puts "ERROR: Bitstream not found at $bitstream_file"
    puts "       Run implementation first: launch_runs impl_1 -to_step write_bitstream"
    exit 1
}

# Generate MCS file for 128 Mbit SPI flash (SPIx4 mode)
# The AX7203 uses a 128 Mbit (16 MB) SPI flash
write_cfgmem -format mcs -size 16 -interface SPIx4 \
    -loadbit "up 0x0 $bitstream_file" \
    -file $mcs_file -force

puts ""
puts "=============================================="
puts "MCS file generated successfully!"
puts "=============================================="
puts ""
puts "Output file: $mcs_file"
puts ""
puts "To program the SPI flash:"
puts "  1. Open Vivado Hardware Manager"
puts "  2. Connect to the FPGA via JTAG"
puts "  3. Right-click on xc7a200t device"
puts "  4. Select 'Add Configuration Memory Device...'"
puts "  5. Search for: mt25ql128 (or your flash type)"
puts "  6. Click OK, then 'Program Configuration Memory Device'"
puts "  7. Select the .mcs file: $mcs_file"
puts "  8. Enable 'Verify' checkbox"
puts "  9. Click OK to program"
puts ""
puts "After programming:"
puts "  1. Power OFF the PC completely"
puts "  2. Wait 10 seconds"
puts "  3. Power ON the PC"
puts "  4. Check: lspci -d 10ee:"
puts "  5. Load driver: sudo modprobe xdma"
puts ""

close_project
