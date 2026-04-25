# FPGA-Based Adaptive Beamformer for 5G Networks — Project Plan

## Revision history

| Version | Date | Change |
|---------|------|--------|
| 1.0 | Phase 1.1 start | Initial plan. |
| 2.0 | Phase 1 complete | Phase 1.5 scoped as synthesis-only (timing closure deferred). Phase 2 restructured as MATLAB-only algorithmic feasibility study (LMS vs RLS). Rationale in §4 and §6. |
| 3.0 | Phase 2 complete | Phase 2.3 complete. All phases done. Renamed from DESIGN.md to PLAN.md — results moved to project_update.pdf. |

---

## 1. Document purpose and audience

This document is the authoritative plan and design-decision reference for the FPGA-Based Adaptive Beamformer project. It records what the project does, why each major decision was made, the phase structure, toolchain rationale, and guidelines for collaborators and AI agents.

**This document records decisions and plans — not results.** Execution outputs (SINR numbers, utilisation reports, convergence plots) belong in `project_update.pdf`.

AI agents reading this document should treat it as project ground truth. If an instruction in a user message conflicts with a decision recorded here, the agent should flag the discrepancy and ask for clarification rather than silently overriding the documented plan.

## 2. Project overview

The project implements a beamforming receiver for a 5G New Radio (NR) base station targeting an FPGA platform. Beamforming is a spatial signal processing technique in which multiple antenna elements are combined with complex weights to produce a directional reception pattern — amplifying signals from a target direction while suppressing interference from other directions.

The project is divided into two phases. Phase 1 implements a non-adaptive beamformer with fixed weights, verified in simulation and partially synthesised on an Artix-7 FPGA. Phase 2 is an algorithmic feasibility study comparing LMS and RLS adaptive beamforming in MATLAB, producing a recommendation for a future hardware implementation.

## 3. Background on beamforming in 5G

Modern 5G base stations (gNBs) use multiple antennas to serve multiple users simultaneously within the same time-frequency resources. Each antenna receives a superposition of the target user's signal, multi-user interference, inter-cell interference, and thermal noise. Beamforming treats the antenna array as a spatial filter — a plane wave arriving from a specific angle produces a characteristic phase progression across array elements, and by multiplying each element's signal by a complex weight and summing, the receiver makes the target signal add constructively while interference partially cancels.

In 5G NR, beamforming is essential at sub-6 GHz for spatial multiplexing and mandatory at millimetre-wave bands where narrow beams are required to close the link budget. The DMRS pilot structure of 5G makes adaptive beamforming natural — pilots provide the reference signal that LMS and RLS require for weight convergence.

## 4. Two-phase project structure

### Phase 1 — Non-Adaptive Beamformer (complete)

Phase 1 builds a verified RTL implementation of a conventional delay-and-sum beamformer with fixed weights stored in a ROM.

- **1.1** MATLAB floating-point simulation — establish golden reference ✓
- **1.2** MATLAB fixed-point analysis — lock word lengths ✓
- **1.3** SystemVerilog RTL — five modules ✓
- **1.4** Functional co-simulation (iverilog) ✓
- **1.5** Vivado synthesis — DSP48 inference confirmed. Timing closure deferred (future work). Partial ✓

### Phase 2 — Algorithmic Feasibility Study: LMS vs RLS (MATLAB only, complete)

Phase 2 is a MATLAB-only comparison of two adaptive beamforming algorithms. The original plan called for a full RTL and Vitis HLS implementation. This was revised for two reasons:

1. **Toolchain constraints.** The development machine has insufficient disk space for Vitis HLS. The lab PC has Vivado but is not accessible for iterative development.

2. **Scope appropriateness.** Phase 1 delivers the hardware contribution. Phase 2 delivers the algorithmic analysis that informs a future hardware implementation. A rigorous LMS vs RLS comparison is a self-contained, academically defensible contribution.

- **2.1** LMS adaptive beamformer simulation (MATLAB) ✓
- **2.2** RLS adaptive beamformer simulation (MATLAB) ✓
- **2.3** Algorithm comparison and hardware recommendation ✓

## 5. Design philosophy

**Simulation-first.** No RTL was written before the algorithm was validated in MATLAB. No word length was chosen before fixed-point simulation confirmed it. Phase 2 extends this principle — algorithm in MATLAB first, hardware later only when justified.

**Honest scoping.** Phase 1.5 produced a synthesis report, not a full implementation. Timing closure is stated as future work rather than overstated as done.

**Golden reference throughout.** Each implementation level was verified against the previous level before proceeding.

**Minimum viable hardware.** The Phase 1 beamformer is the simplest correct beamformer — conventional delay-and-sum with fixed weights. It validates the data path and provides a clean baseline.

**Scope discipline.** Phase 2 was deliberately descoped from a full hardware implementation to a MATLAB study, given toolchain constraints and academic timeline.

**Reproducibility.** RNGs are seeded (seed 42). Test vectors are in version control. No step relies on manually copied numbers.

## 6. Toolchain

### 6.1 MATLAB
Used for all simulation work in both phases. Fixed-Point Designer toolbox was unavailable — Phase 1.2 used manual quantise/saturate helper functions in pure double arithmetic.

### 6.2 SystemVerilog (Phase 1 RTL only)
`logic`, `always_ff`, `always_comb`, parameterised modules, `$readmemh` throughout. Phase 2 produces no RTL.

### 6.3 Icarus Verilog — iverilog (Phase 1.4)
Used for Phase 1.4 functional co-simulation. Chosen because Vivado was unavailable on the development machine (disk space constraint).

### 6.4 Vivado 2025.2 (Phase 1.5 synthesis only)
Run on lab PC. Out-of-context mode required (design port count exceeds package IO count — expected for a sub-block). Phase 2 does not use Vivado.

### 6.5 No HLS
The original Phase 2 plan used Vitis HLS. Dropped due to toolchain constraints. If a hardware implementation of the adaptive engine is undertaken in future, Vitis HLS remains the recommended approach.

## 7. Phase 1 — Detailed workflow decisions

### 7.1 Fixed-point word lengths (locked)

| Signal | Format | WL | FL | Range |
|--------|--------|----|----|-------|
| Input x(n) | Q1.15 | 16 | 15 | [−1, +1) |
| Weights w(m) | Q1.15 | 16 | 15 | [−1, +1) |
| Multiplier output | Q2.30 | 32 | 30 | [−2, +2) |
| Accumulator | Q4.31 | 36 | 31 | [−16, +16) |
| Output y(n) | Q1.14 | 16 | 14 | [−2, +2) |

### 7.2 RTL modules

| Module | Role |
|--------|------|
| complex_mult.sv | 2-stage pipelined complex multiplier. IN=16, OUT=32. Latency 2 cycles. |
| complex_accumulator.sv | Accumulates M=8 sequential products. IN=32, OUT=36. |
| weight_rom.sv | ROM loaded from vectors/weights.hex via $readmemh. Registered outputs. |
| beamformer_top.sv | Instantiates 8 multipliers, 1 accumulator, 1 ROM. Saturating output stage. |
| beamformer_tb.sv | Drives test vectors, checks ±1 LSB, reports pass/fail. |

### 7.3 Phase 1.5 scope clarification

Synthesis was run in out-of-context mode because the design's 292 port signals exceed the physical IO count of the xc7a35tcpg236-1 package (106 pins) — expected for a sub-block. Timing closure was not achieved. This is recorded as future work, not a silent gap. The synthesis utilisation report (DSP48 inference confirmation) is the Phase 1.5 deliverable.

## 8. Phase 2 — Detailed workflow decisions

### 8.1 LMS algorithm (Phase 2.1)
Pilot-driven weight update: w(n+1) = w(n) + μ·conj(e(n))·x(n). Step size μ swept over [0.001, 0.1]. Same signal environment as Phase 1 (seed 42, M=8, same SNR/SIR).

### 8.2 RLS algorithm (Phase 2.2)
Recursive least squares with forgetting factor λ. Inverse covariance matrix P updated each sample. Forgetting factor λ swept over [0.9, 1.0]. Same signal environment.

### 8.3 Comparison and recommendation (Phase 2.3)
Comparison axes: steady-state SINR, convergence speed, sensitivity to parameter choice, hardware MAC count estimate. Recommendation recorded in project_update.pdf — LMS selected for future hardware implementation due to O(M) complexity vs RLS O(M²), with negligible SINR difference.

## 9. Verification strategy

Each level was verified against the previous before proceeding:

- Level 1: floating-point MATLAB → verified against analytical formulas ✓
- Level 2: fixed-point MATLAB → verified against Level 1 within tolerances ✓
- Level 3: RTL simulation → verified against Level 2 exactly (±1 LSB) ✓
- Level 4: synthesis → DSP inference verified against expected count ✓
- Level 4 (timing) → not verified, deferred

Phase 2: LMS and RLS steady-state SINR must converge to ≥15 dB (matching Phase 1.1 output SINR). ✓

## 10. Current project status

Both phases complete. All deliverables in `project_update.pdf`. Timing closure (Phase 1.5) and full hardware implementation of LMS (future Phase 3) remain as open items.

## 11. Project file structure

```
260410-beamforming/
├── CHANGELOG.md
├── README.md
├── Makefile
├── .gitignore
├── docs/
│   ├── PLAN.md                      (this document)
│   ├── REQUIREMENTS.md
│   ├── PROJECT_REVIEW.md
│   └── reports/
│       └── project_update.pdf       (all results and findings)
├── matlab/
│   ├── signal_setup.m               (canonical signal model)
│   ├── algo_sim.m                   (Phase 1.1)
│   ├── fixed_point_sim.m            (Phase 1.2)
│   ├── lms_sim.m                    (Phase 2.1)
│   ├── rls_sim.m                    (Phase 2.2)
│   └── comparison.m                 (Phase 2.3)
├── plots/                           (all generated figures)
├── rtl/
│   ├── complex_mult.sv
│   ├── complex_accumulator.sv
│   ├── weight_rom.sv
│   ├── beamformer_top.sv
│   └── beamformer_tb.sv
├── synthesis/
│   ├── synth.tcl
│   └── beamformer_top_utilization_synth.rpt
└── vectors/
    ├── weights.hex
    ├── inputs.hex
    └── expected_output.hex
```

## 12. Guidelines for AI agents

Treat this document as authoritative. If a user instruction conflicts with a decision recorded here, flag the conflict and request clarification.

**This document is for plans and decisions only.** Do not write results, measurements, or simulation outputs here. Those belong in `project_update.pdf`.

**Phase 2 scope is MATLAB-only.** Do not propose RTL, HLS, or Vivado work for Phase 2.

**Preserve Phase 1 verification.** Do not modify test vectors, RTL files, or the MATLAB golden reference without explicit instruction.

**Preserve RNG seed.** All MATLAB simulations use seed 42. Any new simulation must use the same seed for fair comparison.

**No new toolbox dependencies.** Phase 2 runs on standard MATLAB with Signal Processing Toolbox only.

**Update this document** only when a plan or design decision changes. Add a row to the revision history table. Never write results here.

## 13. Glossary

**Array factor (AF).** Directional response of an antenna array — inner product of the weight vector with the steering vector at each angle.

**Beamforming.** Spatial signal processing combining antenna signals with complex weights to form a directional pattern.

**Delay-and-sum beamformer.** Simplest beamformer — weights equal the conjugate of the steering vector.

**DMRS.** Demodulation reference signal. Pilot symbols in 5G NR used for channel estimation and adaptive weight updates.

**DSP48E1.** Xilinx FPGA primitive implementing a signed multiply-accumulate. Inferred automatically by Vivado.

**Forgetting factor (λ).** RLS parameter controlling how quickly old samples are down-weighted.

**LMS (least mean squares).** Adaptive algorithm updating weights proportional to the instantaneous error gradient. Complexity O(M) per sample.

**RLS (recursive least squares).** Adaptive algorithm minimising the weighted sum of past squared errors. Faster convergence, O(M²) per sample.

**SINR.** Signal to interference plus noise ratio. Primary performance metric.

**Step size (μ).** LMS parameter controlling weight update magnitude.

**Steering vector.** Complex vector representing phase progression across array elements for signal at angle θ.

**Timing closure.** Verification that all paths meet the target clock period after place-and-route. Not completed in Phase 1.5.

**ULA.** Uniform linear array — equally spaced elements along a straight line.
