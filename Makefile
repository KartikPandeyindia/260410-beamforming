# =============================================================================
# FPGA-Based Adaptive Beamformer — top-level build
#
# Targets:
#   make sim          Run all five MATLAB simulations
#   make rtl          Build and run iverilog co-simulation
#   make report       Recompile project_update.pdf (two pdflatex passes)
#   make synth        (Lab PC only) Run Vivado synthesis via synth.tcl
#   make all          sim + rtl + report
#   make clean        Remove build artefacts (binaries, LaTeX intermediates)
#
# Notes:
#   - MATLAB scripts call signal_setup() and cd to matlab/ internally.
#   - The RTL testbench reads vectors/*.hex relative to the working directory
#     (run from repo root).
#   - Vivado is not available on the dev machine; `make synth` is intended
#     to be run on the lab PC.
# =============================================================================

MATLAB    ?= matlab
IVERILOG  ?= iverilog
VVP       ?= vvp
PDFLATEX  ?= pdflatex
VIVADO    ?= vivado

MATLAB_FLAGS = -nodisplay -nosplash -batch
RTL_SOURCES  = rtl/complex_mult.sv rtl/complex_accumulator.sv \
               rtl/weight_rom.sv   rtl/beamformer_top.sv \
               rtl/beamformer_tb.sv

.PHONY: all sim rtl report synth clean

all: sim rtl report

# -----------------------------------------------------------------------------
# MATLAB simulations (run from matlab/ so scripts find signal_setup.m)
# -----------------------------------------------------------------------------
sim:
	cd matlab && $(MATLAB) $(MATLAB_FLAGS) "algo_sim"
	cd matlab && $(MATLAB) $(MATLAB_FLAGS) "fixed_point_sim"
	cd matlab && $(MATLAB) $(MATLAB_FLAGS) "lms_sim"
	cd matlab && $(MATLAB) $(MATLAB_FLAGS) "rls_sim"
	cd matlab && $(MATLAB) $(MATLAB_FLAGS) "comparison"

# -----------------------------------------------------------------------------
# RTL co-simulation (run from repo root so vectors/ path resolves)
# -----------------------------------------------------------------------------
rtl: beamformer_sim
	$(VVP) beamformer_sim

beamformer_sim: $(RTL_SOURCES)
	$(IVERILOG) -g2012 -o $@ $(RTL_SOURCES)

# -----------------------------------------------------------------------------
# LaTeX report (compiled from docs/reports/; graphicspath points to ../../plots/)
# -----------------------------------------------------------------------------
report: docs/reports/project_update.pdf

docs/reports/project_update.pdf: docs/reports/project_update.tex
	cd docs/reports && $(PDFLATEX) -interaction=nonstopmode project_update.tex; true
	cd docs/reports && $(PDFLATEX) -interaction=nonstopmode project_update.tex; true

# -----------------------------------------------------------------------------
# Vivado synthesis (lab PC only)
# -----------------------------------------------------------------------------
synth:
	cd synthesis && $(VIVADO) -mode batch -source synth.tcl -nojournal -nolog

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------
clean:
	rm -f beamformer_sim
	rm -f docs/reports/project_update.aux docs/reports/project_update.log \
	      docs/reports/project_update.out
