# FPGA-Based Adaptive Beamformer for 5G Networks — Design Documentation v2.0

## Revision history

| Version | Date | Change |
|---------|------|--------|
| 1.0 | Phase 1.1 complete | Initial version. |
| 2.0 | Phase 1 complete | Phase 1 all sub-stages complete. Phase 1.5 accurately scoped as synthesis-only (timing closure deferred). Phase 2 restructured as MATLAB-only algorithmic feasibility study (LMS vs RLS). Rationale in §4 and §6. |

---

## 1. Document purpose and audience

This document is the authoritative design reference for the FPGA-Based Adaptive Beamformer project. It is written to be consumed by both human collaborators and AI agents (such as Claude Code) that join the project at any stage. It captures not only what the project does, but the reasoning behind every major decision — the design philosophy, the tool choices, the phase structure, and the verification strategy. Anyone picking up this project later, whether a teammate or an automated agent, should be able to read this document and understand the full context without needing to reconstruct decisions from source code or chat history.

AI agents reading this document should treat it as project ground truth. If an instruction in a user message conflicts with a decision recorded here, the agent should flag the discrepancy and ask for clarification rather than silently overriding the documented design.

## 2. Project overview

The project implements a beamforming receiver for a 5G New Radio (NR) base station targeting an FPGA platform. Beamforming is a spatial signal processing technique in which multiple antenna elements are combined with complex weights to produce a directional reception pattern — amplifying signals from a target direction while suppressing interference from other directions.

The project is divided into two phases. Phase 1 implements a non-adaptive beamformer with fixed weights, verified in simulation and partially synthesised on an Artix-7 FPGA. Phase 2 is an algorithmic feasibility study comparing the LMS and RLS adaptive beamforming algorithms in MATLAB, producing a recommendation for which algorithm is best suited for a future full hardware implementation.

## 3. Background on beamforming in 5G

Modern 5G base stations (gNBs) use multiple antennas to serve multiple users simultaneously within the same time-frequency resources. Each antenna receives a superposition of the target user's signal, multi-user interference, inter-cell interference, and thermal noise. Beamforming treats the antenna array as a spatial filter — a plane wave arriving from a specific angle produces a characteristic phase progression across array elements, and by multiplying each element's signal by a complex weight and summing, the receiver can make the target signal add constructively while interference partially cancels.

In 5G NR, beamforming is essential at sub-6 GHz for spatial multiplexing and mandatory at millimetre-wave bands where narrow beams are required to close the link budget. The DMRS pilot structure of 5G makes adaptive beamforming natural — pilots provide the reference signal that LMS and RLS algorithms require for weight convergence.

## 4. Two-phase project structure

### Phase 1 — Non-Adaptive Beamformer (complete)

Phase 1 builds a verified RTL implementation of a conventional delay-and-sum beamformer with fixed weights stored in a ROM. The five sub-stages and their actual outcomes:

- **1.1** MATLAB floating-point simulation — golden reference established. SINR improvement 18.33 dB. ✓
- **1.2** MATLAB fixed-point analysis — word lengths locked. SQNR 33.51 dB, zero pattern degradation. ✓
- **1.3** SystemVerilog RTL — five modules written and reviewed. ✓
- **1.4** Functional co-simulation (iverilog) — 512/512 samples matched within ±1 LSB. ✓
- **1.5** Vivado synthesis — DSP48 inference confirmed (16 DSP48E1, 3.90% LUT). Timing closure not completed (see §7.5). Partial ✓

Phase 1 deliverable: a functionally verified RTL design with confirmed synthesis resource mapping. Timing closure and bitstream generation are deferred — they are identified as future work, not silent gaps.

### Phase 2 — Algorithmic Feasibility Study: LMS vs RLS (MATLAB only)

Phase 2 is a MATLAB-only comparison of two adaptive beamforming algorithms. The original plan called for a full RTL and Vitis HLS implementation of the LMS engine. This was revised for the following reasons:

1. **Toolchain constraints.** The development machine has insufficient disk space for Vitis HLS (~5 GB free, tool requires ~10 GB minimum). The lab PC has Vivado but is not accessible for iterative development work.

2. **Project title interpretation.** The title "FPGA-Based Adaptive Beamformer for 5G NR" describes the design space, not a commitment to implement every algorithm in hardware. Phase 1 delivers the FPGA hardware contribution. Phase 2 delivers the adaptive algorithm analysis that would inform a future hardware implementation.

3. **Academic value.** A rigorous LMS vs RLS comparison — convergence speed, steady-state SINR, sensitivity analysis, hardware complexity implications — is a self-contained and academically defensible contribution. It answers the question "which algorithm should go on the FPGA, and why?" which is the natural next question after Phase 1.

Phase 2 sub-stages:

- **2.1** LMS adaptive beamformer simulation (MATLAB)
- **2.2** RLS adaptive beamformer simulation (MATLAB)
- **2.3** Algorithm comparison: LMS vs RLS vs Phase 1 fixed-weight baseline

## 5. Design philosophy

**Simulation-first.** No RTL was written before the algorithm was validated in MATLAB. No word length was chosen before fixed-point simulation confirmed it. Phase 2 extends this principle — algorithm in MATLAB first, hardware later only when justified.

**Honest scoping.** Phase 1.5 produced a synthesis report, not a full implementation. This is stated clearly rather than overstated. The contribution is what it is: verified RTL and confirmed DSP mapping. Timing closure is future work.

**Golden reference throughout.** Fixed-point MATLAB was verified against floating-point MATLAB. RTL simulation was verified against fixed-point MATLAB exactly. Synthesis was verified against expected DSP count. Each level was checked before proceeding.

**Minimum viable hardware.** The Phase 1 beamformer is the simplest correct beamformer — conventional delay-and-sum with fixed weights. It validates the data path clearly and provides a clean baseline for the Phase 2 comparison.

**Reproducibility.** The entire workflow is reproducible — RNGs are seeded (seed 42), test vectors are in version control, no step relies on manually copied numbers.

## 6. Toolchain

### 6.1 MATLAB

Used for all simulation work in both phases. Matrix syntax maps directly onto beamforming equations. Signal Processing Toolbox used for steering vectors and spectral analysis. Fixed-Point Designer toolbox was unavailable — Phase 1.2 implemented fixed-point arithmetic manually in pure double arithmetic using quantise/saturate helper functions.

### 6.2 SystemVerilog (Phase 1 RTL)

Used for all Phase 1 RTL. `logic`, `always_ff`, `always_comb`, parameterised modules, `$readmemh` throughout. Phase 2 produces no RTL.

### 6.3 Icarus Verilog — iverilog (Phase 1.4)

Used for Phase 1.4 functional co-simulation. Chosen because Vivado was unavailable on the development machine (disk space constraint — Vivado requires ~60 GB, machine had ~5 GB free). iverilog installs in under 100 MB and is fully sufficient for functional verification against test vectors.

### 6.4 Vivado 2025.2 (Phase 1.5 synthesis only)

Synthesis was run on a lab PC. Out-of-context mode was required because the design's 292 port signals exceed the physical IO count of the Artix-7 xc7a35tcpg236-1 package (106 pins) — expected for a sub-block. Synthesis confirmed correct DSP48 inference. Implementation (place-and-route) was not completed; timing closure is deferred. Phase 2 does not use Vivado.

### 6.5 No HLS

The original Phase 2 plan used Vitis HLS for the LMS update kernel. Dropped due to toolchain constraints (see §4). If a hardware implementation of the adaptive engine is undertaken in future, Vitis HLS remains the recommended approach — the Phase 2 MATLAB results will serve as the C-simulation reference.

## 7. Phase 1 detailed results

### 7.1 Phase 1.1 — floating-point simulation

Parameters: M = 8, d/λ = 0.5, target 30°, interferer −20°, SNR 10 dB, SIR 0 dB, 512 samples, seed 42.

| Metric | Value |
|--------|-------|
| Array gain (signal) | +9.03 dB |
| Array gain (interferer) | −9.53 dB |
| Input SINR | −2.55 dB |
| Output SINR | +15.78 dB |
| SINR improvement | 18.33 dB |

### 7.2 Phase 1.2 — fixed-point analysis

| Signal | Format | WL | FL | Range |
|--------|--------|----|----|-------|
| Input x(n) | Q1.15 | 16 | 15 | [−1, +1) |
| Weights w(m) | Q1.15 | 16 | 15 | [−1, +1) |
| Multiplier output | Q2.30 | 32 | 30 | [−2, +2) |
| Accumulator | Q4.31 | 36 | 31 | [−16, +16) |
| Output y(n) | Q1.14 | 16 | 14 | [−2, +2) |

SQNR 33.51 dB, pattern deviation 0.0000 dB, SINR degradation 0.00 dB. All pass.

### 7.3 Phase 1.3 — RTL modules

| Module | Description |
|--------|-------------|
| complex_mult.sv | 2-stage pipelined complex multiplier. IN=16, OUT=32. Latency 2 cycles. |
| complex_accumulator.sv | Accumulates M=8 sequential products. IN=32, OUT=36. |
| weight_rom.sv | ROM loaded from vectors/weights.hex via $readmemh. Registered outputs. |
| beamformer_top.sv | Instantiates 8 multipliers, 1 accumulator, 1 ROM. Serialises products. Saturating output: right-shift 17, clip to Q1.14. |
| beamformer_tb.sv | Drives 512 samples, checks ±1 LSB, reports pass/fail. |

### 7.4 Phase 1.4 — co-simulation

Tool: Icarus Verilog. Result: 512/512 samples matched, 0 mismatches, directed zero-input test passed.

### 7.5 Phase 1.5 — synthesis

Device: xc7a35tcpg236-1. Tool: Vivado 2025.2, out-of-context mode.

| Resource | Used | Available | Util% |
|----------|------|-----------|-------|
| Slice LUTs | 812 | 20,800 | 3.90% |
| Slice Registers | 930 | 41,600 | 2.24% |
| DSP48E1 | **16** | 90 | 17.78% |
| Block RAM | 0 | 50 | 0.00% |
| BUFG | 1 | 32 | 3.13% |

DSP count of 16 is exact: 8 complex multipliers × 2 real multiplies each. Vivado inferred all DSPs correctly from parameterised RTL without manual instantiation.

**Timing closure: not completed.** The timing summary report was unavailable after synthesis (greyed out — requires full place-and-route). Full implementation was not completed due to IO placement constraints in the target package. Timing closure at 200 MHz is identified as future work. The synthesis utilisation report is the Phase 1.5 deliverable.

## 8. Phase 2 detailed workflow

### 8.1 Phase 2.1 — LMS simulation (MATLAB)

File: `matlab/lms_sim.m`. Imports signal parameters from `algo_sim.m` (same seed, same array geometry, same SNR/SIR conditions) to ensure a fair comparison against the Phase 1 baseline.

Algorithm: initialise w = zeros(M,1). For each pilot sample n:
- y(n) = w' · x(n)
- e(n) = d(n) − y(n)  (d(n) is the known pilot)
- w = w + μ · conj(e(n)) · x(n)

Sweep step size μ over a range (e.g. 0.001 to 0.1). Observe convergence speed versus stability.

Outputs:
- Weight convergence trajectories (real and imaginary parts vs iteration)
- Mean squared error (learning curve) on log scale
- Radiation pattern at 0, 50%, and steady-state iterations
- SINR vs iteration number
- Converged beam direction vs true target (30°)

### 8.2 Phase 2.2 — RLS simulation (MATLAB)

File: `matlab/rls_sim.m`. Same signal conditions as Phase 2.1.

Algorithm: initialise w = zeros(M,1), P = δ⁻¹·I. For each pilot sample n:
- k(n) = P·x(n) / (λ + x(n)'·P·x(n))
- e(n) = d(n) − w'·x(n)
- w = w + k(n)·conj(e(n))
- P = λ⁻¹·P − λ⁻¹·k(n)·x(n)'·P

Sweep forgetting factor λ (e.g. 0.95 to 0.9999).

Outputs: same set as Phase 2.1.

### 8.3 Phase 2.3 — comparison (MATLAB)

File: `matlab/comparison.m`.

Comparison axes:

| Axis | Description |
|------|-------------|
| Convergence speed | Samples to reach within 1 dB of steady-state SINR |
| Steady-state SINR | vs Phase 1 fixed-weight result (15.78 dB) |
| Sensitivity | SINR degradation for ±50% variation in μ or λ |
| Complexity | MAC operations per sample: LMS = O(M), RLS = O(M²) |
| Hardware cost estimate | Approximate DSP count for RTL implementation of each |

Primary output: recommendation for which algorithm to implement in hardware in a future Phase 3, with justification based on the comparison results and the 5G DMRS pilot length constraint (typically 100–200 pilot samples per slot).

## 9. Verification strategy

Phase 1 followed an equivalence-chain model. Each level verified against the previous:

- Level 1: floating-point MATLAB → verified against analytical formulas ✓
- Level 2: fixed-point MATLAB → verified against Level 1 within tolerances ✓
- Level 3: RTL simulation → verified against Level 2 exactly (±1 LSB) ✓
- Level 4: synthesis → DSP inference verified against expected count ✓
- Level 4 (timing) → not verified, deferred

Phase 2: LMS and RLS steady-state SINR must converge to ≥15 dB (matching Phase 1.1 output SINR of 15.78 dB) to confirm the algorithms are solving the same problem. This is the pass criterion for Phase 2.1 and 2.2.

## 10. Current project status

Phase 1 is complete. Functional verification passed. Synthesis confirms correct resource mapping. Timing closure is a known open item.

Phase 2 is next, starting with `lms_sim.m`.

Locked-in decisions for Phase 2: MATLAB-only, floating-point, no RTL, no HLS, no Vivado. LMS (2.1) and RLS (2.2) both implemented. Comparison against Phase 1 fixed-weight baseline is the deliverable. Same signal parameters and RNG seed as Phase 1 throughout.

## 11. Project file structure

```
260410-beamforming/
├── DESIGN.md                        (this document)
├── project_update.pdf               (Phase 1 complete report)
├── project_update.tex               (LaTeX source)
├── .gitignore
├── matlab/
│   ├── algo_sim.m                   (Phase 1.1 — floating-point)
│   ├── fixed_point_sim.m            (Phase 1.2 — fixed-point analysis)
│   ├── lms_sim.m                    (Phase 2.1 — LMS simulation)
│   ├── rls_sim.m                    (Phase 2.2 — RLS simulation)
│   ├── comparison.m                 (Phase 2.3 — algorithm comparison)
│   └── command_line_output.txt      (diary output from latest run)
├── plots/
│   ├── Radiation Pattern.png
│   ├── Polar Pattern.png
│   ├── Beamforming Weights.png
│   ├── Beamformer Output.png
│   ├── FP1.2_Radiation_Pattern_Comparison.png
│   ├── FP1.2_Pattern_Deviation.png
│   ├── FP1.2_Word-Length_Sweep.png
│   ├── FP1.2_Output_Comparison.png
│   └── FP1.2_Quantisation_Error.png
├── rtl/
│   ├── complex_mult.sv
│   ├── complex_accumulator.sv
│   ├── weight_rom.sv
│   ├── beamformer_top.sv
│   └── beamformer_tb.sv
└── vectors/
    ├── weights.hex
    ├── inputs.hex
    └── expected_output.hex
```

## 12. Guidelines for AI agents

Treat this document as authoritative. If a user instruction conflicts with a decision recorded here, flag the conflict and request clarification.

**Phase 1.5 is synthesis-only.** Do not describe Phase 1.5 as a full implementation. Timing closure was not achieved and is honestly recorded as future work.

**Phase 2 scope is MATLAB-only.** Do not propose RTL, HLS, or Vivado work for Phase 2. If the user asks to extend Phase 2 into hardware, update this document first and record the rationale.

**Preserve Phase 1 verification.** Do not modify test vectors, RTL files, or the MATLAB golden reference without explicit instruction. Phase 1 is complete.

**Preserve RNG seed.** All MATLAB simulations use seed 42. Phase 2 scripts must use the same seed so the signal environment is identical and comparisons are fair.

**No new toolbox dependencies for Phase 2.** Phase 2 must run on standard MATLAB with Signal Processing Toolbox only. No Fixed-Point Designer, no Phased Array Toolbox.

**Update this document** if any design decision changes. Add a row to the revision history table.

## 13. Glossary

**Array factor (AF).** The directional response of an antenna array — inner product of the weight vector with the steering vector at each angle.

**Beamforming.** Spatial signal processing combining antenna signals with complex weights to form a directional pattern.

**Broadside.** Direction perpendicular to the array axis.

**Delay-and-sum beamformer.** Simplest beamformer — weights equal the conjugate of the steering vector. Also called the conventional beamformer.

**DMRS.** Demodulation reference signal. Pilot symbols in 5G NR slots used for channel estimation and adaptive weight updates.

**DSP48E1.** Xilinx FPGA primitive implementing a signed multiply-accumulate. Inferred automatically by Vivado for compatible RTL patterns.

**Forgetting factor (λ).** RLS parameter in (0, 1]. Controls how quickly old samples are down-weighted. λ close to 1 gives slow forgetting (stable, slow tracking). λ further from 1 gives fast forgetting (fast tracking, noisier).

**Golden reference.** The authoritative expected output. In this project, the Phase 1.1 MATLAB output is the golden reference for all subsequent levels.

**LMS (least mean squares).** Adaptive algorithm updating weights proportional to the instantaneous error gradient. Complexity O(M) per sample. Controlled by step size μ.

**RLS (recursive least squares).** Adaptive algorithm minimising the weighted sum of all past squared errors. Faster convergence than LMS but O(M²) per sample. Controlled by forgetting factor λ.

**SINR.** Signal to interference plus noise ratio. Primary performance metric.

**Steering vector.** Complex vector representing phase progression across array elements for a signal at angle θ. Element m: exp(jπm sin θ) for half-wavelength ULA.

**Step size (μ).** LMS parameter controlling weight update magnitude. Too large: unstable. Too small: slow convergence.

**Timing closure.** The process of verifying that all signal paths in the synthesised design meet the target clock period after place-and-route. Not completed in Phase 1.5.

**ULA.** Uniform linear array — equally spaced elements along a straight line.

**Vivado.** Xilinx FPGA design suite. Used in Phase 1.5 synthesis only.

**Weight vector.** Vector of complex coefficients applied to antenna signals. Fixed in Phase 1. Converged adaptively in Phase 2 simulation.
