# Changelog — FPGA-Based Adaptive Beamformer for 5G Networks

All notable changes to this project are recorded here. Entries are ordered most-recent first, grouped by commit milestone.

---

## [v3.2] — 2026-04-25 — Cleanup and formal documentation

### Added
- `REQUIREMENTS.md` — 23 numbered requirements (REQ-SYS, REQ-P1, REQ-P2) with verification method, status (22 Verified / 1 Deferred), and traceability summary table.
- `matlab/signal_setup.m` — canonical signal model function; single source of truth for array geometry, channel parameters, and RNG draw order (seed 42). Eliminates repeated setup blocks across scripts.
- `synthesis/` subdirectory — synthesis report relocated from project root.

### Changed
- `.gitignore` extended to cover `synthesis/*.log` and `synthesis/*.jou`.

### Removed
- `beamformer_sim` binary (iverilog build artifact, gitignored).
- LaTeX build artefacts from working directory (`*.aux`, `*.log`, `*.out`).

---

## [v3.1] — 2026-04-25 — PLAN.md rename and report footer update

### Changed
- `DESIGN.md` renamed to `PLAN.md`. Plan document now restricted to design decisions only — all result numbers removed.
- Revision history updated to v3.0; §1 clarifies document scope; §12 AI agent guidelines updated.
- `project_update.tex`/`.pdf` footer references updated from `DESIGN.md v2.0` to `PLAN.md v3.0`.

### Removed
- `DESIGN.md` (replaced by `PLAN.md`).

---

## [v3.0] — 2026-04-25 — Phase 2.3 complete: algorithm comparison and recommendation

### Added
- `matlab/comparison.m` — standalone Phase 2.3 script. Runs fixed-weight, LMS, and RLS beamformers on the same signal environment. Produces sensitivity sweeps (μ and λ), MAC count analysis, and a hardware recommendation.
- Six comparison plots in `plots/` with `P2.3_` prefix: `SINR_All_Algorithms`, `Early_Convergence`, `LMS_Sensitivity`, `RLS_Sensitivity`, `Final_Pattern_All`, `MSE_Comparison`.
- `project_update.pdf` updated with Phase 2.3 results and final recommendation section.

### Key result
LMS recommended for future hardware: 18.93 dB vs 18.90 dB SINR (< 0.03 dB delta), 8× lower MAC count (32 vs 288 for M = 8), convergence in 15 samples (within 5G NR DMRS pilot length).

---

## [v2.1] — 2026-04-25 — Phase 2.2 complete: RLS adaptive beamformer

### Added
- `matlab/rls_sim.m` — standalone Phase 2.2 script. Implements pilot-driven RLS with Kalman-gain update. Forgetting factor sweep λ ∈ {0.9, 0.95, 0.99, 0.999, 1.0}; δ = 0.01 initialisation.
- Five RLS plots in `plots/` with `P2.2_` prefix.

### Key result
Best λ = 1.000; converged SINR = 18.90 dB; convergence in 2 samples vs 15 for LMS.

---

## [v2.0] — 2026-04-24 — Phase 2.1 complete: LMS adaptive beamformer; DESIGN.md v2.0

### Added
- `matlab/lms_sim.m` — standalone Phase 2.1 script. Step-size sweep μ ∈ {0.001, 0.005, 0.01, 0.05, 0.1}. Auto-selects best μ by SINR in final 50 samples.
- Five LMS plots in `plots/` with `P2.1_` prefix.
- `DESIGN.md` v2.0 — Phase 2 restructured as MATLAB-only LMS vs RLS study (Vitis HLS descoped due to toolchain constraints).
- `project_update.pdf` updated with Phase 2 direction, Phase 2.1 results.

### Key result
Best μ = 0.001; converged SINR = 18.93 dB (+3.15 dB over fixed baseline); convergence in 15 samples.

---

## [v1.5] — 2026-04-23 — Phase 1.5 partial: Vivado synthesis

### Added
- `beamformer_top_utilization_synth.rpt` (now at `synthesis/`) — Vivado v2025.2 synthesis report for xc7a35tcpg236-1. DSPs = 16 (17.78 %), LUTs = 812, Registers = 930.

### Notes
- Synthesis run in out-of-context mode (design has 292 ports; package has 106 pins — expected for a sub-block).
- Timing closure not achieved; deferred as future work (REQ-P1-015).

---

## [v1.4] — 2026-04-22 — Phase 1.4 complete: RTL co-simulation

### Added
- `matlab/command_line_output.txt` — diary output from `fixed_point_sim.m`.

### Verified
- 512 / 512 sample match between RTL output and fixed-point MATLAB reference (±1 LSB). `beamformer_tb.sv` reports PASS.

---

## [v1.3] — 2026-04-21 — Phase 1.3 complete: SystemVerilog RTL

### Added
- `rtl/complex_mult.sv` — 2-cycle pipelined complex multiplier, 16-bit in / 32-bit out.
- `rtl/complex_accumulator.sv` — accumulates M = 8 products, 32-bit in / 36-bit out.
- `rtl/weight_rom.sv` — ROM loaded from `vectors/weights.hex` via `$readmemh`.
- `rtl/beamformer_top.sv` — top-level; instantiates 8 multipliers, 1 accumulator, 1 ROM; saturating output stage.
- `rtl/beamformer_tb.sv` — drives test vectors, checks ±1 LSB, reports PASS/FAIL.

---

## [v1.2] — 2026-04-20 — Phase 1.2 complete: fixed-point analysis

### Added
- `matlab/fixed_point_sim.m` — manual quantise/saturate fixed-point simulation (no Fixed-Point Designer toolbox). Word-length sweep confirms Q1.15 input/weight, Q4.31 accumulator.
- `vectors/weights.hex`, `vectors/inputs.hex`, `vectors/expected_output.hex` — test vectors generated from fixed-point simulation.
- Five fixed-point plots in `plots/` with `FP1.2_` prefix.

### Key result
SINR degradation vs floating-point: 0.00 dB. Output SQNR: 33.51 dB.

---

## [v1.1] — 2026-04-19 — Phase 1.1 complete: floating-point simulation and initial commit

### Added
- `matlab/algo_sim.m` — floating-point delay-and-sum beamformer, Phase 1.1 golden reference.
- `plots/Radiation Pattern.png`, `Polar Pattern.png`, `Beamforming Weights.png`, `Beamformer Output.png` — Phase 1.1 figures.
- `project_update.pdf` / `project_update.tex` — initial project report.
- `DESIGN.md` v1.0 — initial plan document.
- `.gitignore` — excludes MATLAB temporaries, Vivado artefacts, LaTeX intermediates, iverilog binary.

### Key result
Output SINR = 15.78 dB; SINR improvement = 18.33 dB over a single antenna element.
