# =============================================================================
# Vivado synthesis script — beamformer_top
#
# Target device : Artix-7 xc7a35tcpg236-1
# Mode          : Out-of-context (design has 292 ports; package has 106 pins)
# Top module    : beamformer_top
#
# Usage (from project root):
#   make synth
#   # or directly:
#   cd synthesis && vivado -mode batch -source synth.tcl
#
# Outputs (written into synthesis/):
#   beamformer_top.dcp                      - synthesis checkpoint
#   beamformer_top_utilization_synth.rpt    - utilisation report
#   beamformer_top_timing_synth.rpt         - timing summary
#
# Note: authored against Vivado 2025.2 docs. Verify on lab PC before
#       relying on output paths.
# =============================================================================

set proj_root [file normalize [file dirname [info script]]/..]
set rtl_dir   $proj_root/rtl
set vec_dir   $proj_root/vectors
set out_dir   [file dirname [info script]]

# -----------------------------------------------------------------------------
# Read SystemVerilog sources (testbench excluded from synthesis)
# -----------------------------------------------------------------------------
read_verilog -sv [list \
    $rtl_dir/complex_mult.sv \
    $rtl_dir/complex_accumulator.sv \
    $rtl_dir/weight_rom.sv \
    $rtl_dir/beamformer_top.sv \
]

# weights.hex is loaded by weight_rom.sv via $readmemh at elaboration time.
add_files -norecurse $vec_dir/weights.hex

# -----------------------------------------------------------------------------
# Synthesise in out-of-context mode (no IO buffers, no package pin check)
# -----------------------------------------------------------------------------
synth_design \
    -top beamformer_top \
    -part xc7a35tcpg236-1 \
    -mode out_of_context

# -----------------------------------------------------------------------------
# Write reports and checkpoint
# -----------------------------------------------------------------------------
write_checkpoint   -force $out_dir/beamformer_top.dcp
report_utilization -file  $out_dir/beamformer_top_utilization_synth.rpt
report_timing_summary -file $out_dir/beamformer_top_timing_synth.rpt

puts "================================================================"
puts "Synthesis complete. Reports written to: $out_dir"
puts "================================================================"
