# Requirements — FPGA-Based Adaptive Beamformer for 5G Networks

## Document scope

This document defines the functional and performance requirements for the project. Each requirement carries a unique ID, a verification method, and a status reflecting the project's completed state.

**Requirement status values:**

| Status | Meaning |
|--------|---------|
| Verified | Requirement met and confirmed by cited evidence |
| Deferred | Requirement scoped out with documented rationale |

---

## 1. System-level requirements

| ID | Requirement | Verification method | Status |
|----|-------------|-------------------|--------|
| REQ-SYS-001 | The system shall implement a beamforming receiver for a uniform linear array (ULA) with M = 8 half-wavelength-spaced antenna elements. | Inspection of `algo_sim.m`, `lms_sim.m`, `rls_sim.m`, and `beamformer_top.sv` parameters. | Verified |
| REQ-SYS-002 | The system shall operate on complex baseband (I/Q) signals representative of a 5G NR downlink channel. | Inspection of signal generation model in MATLAB scripts and RTL data path. | Verified |
| REQ-SYS-003 | All simulations shall use a fixed random seed (seed = 42) to ensure fully reproducible results. | `rng(42)` present at the start of every MATLAB simulation script. | Verified |
| REQ-SYS-004 | The signal environment shall model one target user at +30° and one interferer at −20° with SNR = 10 dB and SIR = 0 dB. | Parameter block in `signal_setup.m` and all simulation scripts. | Verified |

---

## 2. Phase 1 — Non-adaptive beamformer requirements

### 2.1 Algorithm (Phase 1.1)

| ID | Requirement | Verification method | Status |
|----|-------------|-------------------|--------|
| REQ-P1-001 | The floating-point beamformer shall implement conventional delay-and-sum with weights equal to the conjugate normalised steering vector: **w** = **a**(θ_s) / ‖**a**(θ_s)‖. | Inspection of `algo_sim.m` weight definition. | Verified |
| REQ-P1-002 | The floating-point beamformer shall achieve an output SINR of ≥ 15 dB under the REQ-SYS-004 signal environment. | SINR computed in `algo_sim.m` confirmed ≥ 15 dB. Results in `project_update.pdf` §3.1. | Verified |
| REQ-P1-003 | The radiation pattern shall exhibit a main lobe aligned with +30° and a null in the direction of the interferer (−20°). | Array factor plot in `project_update.pdf` §3.1. | Verified |

### 2.2 Fixed-point analysis (Phase 1.2)

| ID | Requirement | Verification method | Status |
|----|-------------|-------------------|--------|
| REQ-P1-004 | All fixed-point word lengths shall be determined by simulation, not by assumption. | Word-length sweep in `fixed_point_sim.m`; Q-format table in `PLAN.md` §7.1. | Verified |
| REQ-P1-005 | Input samples and weights shall use Q1.15 (16-bit) format; accumulator shall use Q4.31 (36-bit) format. | `PLAN.md` §7.1 word-length table; `fixed_point_sim.m`. | Verified |
| REQ-P1-006 | Fixed-point SINR shall be within 1 dB of the floating-point reference. | SINR comparison in `fixed_point_sim.m` and `project_update.pdf` §3.2. | Verified |

### 2.3 RTL implementation (Phase 1.3)

| ID | Requirement | Verification method | Status |
|----|-------------|-------------------|--------|
| REQ-P1-007 | The RTL shall consist of five SystemVerilog modules: `complex_mult`, `complex_accumulator`, `weight_rom`, `beamformer_top`, and `beamformer_tb`. | Inspection of `rtl/` directory. | Verified |
| REQ-P1-008 | `complex_mult` shall implement a 2-cycle pipelined complex multiplier with 16-bit inputs and 32-bit outputs. | Inspection of `rtl/complex_mult.sv`; pipeline latency confirmed in `PLAN.md` §7.2. | Verified |
| REQ-P1-009 | `weight_rom` shall load weights from `vectors/weights.hex` via `$readmemh`. | Inspection of `rtl/weight_rom.sv`. | Verified |
| REQ-P1-010 | The beamformer output shall include a saturating stage to prevent overflow on the Q1.14 output word. | Inspection of `rtl/beamformer_top.sv` output stage. | Verified |

### 2.4 Co-simulation (Phase 1.4)

| ID | Requirement | Verification method | Status |
|----|-------------|-------------------|--------|
| REQ-P1-011 | The RTL testbench shall achieve a 512/512 sample match against fixed-point MATLAB reference vectors within ±1 LSB tolerance. | `beamformer_tb.sv` PASS/FAIL output; 512/512 confirmed in `project_update.pdf` §3.4. | Verified |
| REQ-P1-012 | Co-simulation shall be run using Icarus Verilog (iverilog) on the development machine. | `project_update.pdf` §3.4; `PLAN.md` §6.3. | Verified |

### 2.5 Synthesis (Phase 1.5)

| ID | Requirement | Verification method | Status |
|----|-------------|-------------------|--------|
| REQ-P1-013 | Vivado synthesis shall confirm DSP48E1 inference for the complex multiplier instances. | `synthesis/beamformer_top_utilization_synth.rpt`; 16 DSPs reported. | Verified |
| REQ-P1-014 | Synthesis shall target the Artix-7 xc7a35tcpg236-1 device. | `synthesis/beamformer_top_utilization_synth.rpt` device field. | Verified |
| REQ-P1-015 | Timing closure at 200 MHz shall be verified post place-and-route. | Timing closure not achieved — IO overutilisation required out-of-context synthesis. Deferred as documented in `PLAN.md` §7.3. | Deferred |

---

## 3. Phase 2 — Algorithmic feasibility study requirements

### 3.1 Scope constraint

Phase 2 is a MATLAB-only study. Full RTL and HLS implementation were descoped due to toolchain constraints (Vitis HLS unavailable on the development machine). Rationale in `PLAN.md` §4.

### 3.2 LMS simulation (Phase 2.1)

| ID | Requirement | Verification method | Status |
|----|-------------|-------------------|--------|
| REQ-P2-001 | The LMS simulation shall use the pilot-driven update rule: **w**(n+1) = **w**(n) + μ · conj(e(n)) · **x**(n). | Inspection of `matlab/lms_sim.m` weight update loop. | Verified |
| REQ-P2-002 | The step-size sweep shall cover μ ∈ {0.001, 0.005, 0.01, 0.05, 0.1}. | `matlab/lms_sim.m` `mu_vals` parameter. | Verified |
| REQ-P2-003 | The converged LMS SINR shall reach ≥ 15 dB (matching the Phase 1 fixed-weight baseline). | LMS SINR = 18.93 dB confirmed in `project_update.pdf` §4.1. | Verified |

### 3.3 RLS simulation (Phase 2.2)

| ID | Requirement | Verification method | Status |
|----|-------------|-------------------|--------|
| REQ-P2-004 | The RLS simulation shall implement the standard Kalman-gain update with forgetting factor λ and initialisation P = (1/δ)·**I**. | Inspection of `matlab/rls_sim.m` update loop. | Verified |
| REQ-P2-005 | The forgetting factor sweep shall cover λ ∈ {0.9, 0.95, 0.99, 0.999, 1.0}. | `matlab/rls_sim.m` `lambda_vals` parameter. | Verified |
| REQ-P2-006 | The converged RLS SINR shall reach ≥ 15 dB. | RLS SINR = 18.90 dB confirmed in `project_update.pdf` §4.2. | Verified |

### 3.4 Algorithm comparison (Phase 2.3)

| ID | Requirement | Verification method | Status |
|----|-------------|-------------------|--------|
| REQ-P2-007 | The comparison shall quantify steady-state SINR, convergence speed, parameter sensitivity, and hardware MAC count for both algorithms. | `matlab/comparison.m`; comparison table in `project_update.pdf` §4.3. | Verified |
| REQ-P2-008 | The MAC count estimate shall distinguish O(M) complexity for LMS and O(M²) complexity for RLS. | MAC count computation in `matlab/comparison.m`; LMS = 32, RLS = 288 for M = 8. | Verified |
| REQ-P2-009 | The study shall produce a hardware implementation recommendation with stated justification. | Recommendation in `project_update.pdf` §4.3: LMS selected — 8× lower MAC count, < 0.03 dB SINR penalty. | Verified |

---

## 4. Traceability summary

| Phase | REQs | Verified | Deferred |
|-------|------|----------|---------|
| Phase 1.1 (Algorithm) | REQ-P1-001 to 003 | 3 | 0 |
| Phase 1.2 (Fixed-point) | REQ-P1-004 to 006 | 3 | 0 |
| Phase 1.3 (RTL) | REQ-P1-007 to 010 | 4 | 0 |
| Phase 1.4 (Co-simulation) | REQ-P1-011 to 012 | 2 | 0 |
| Phase 1.5 (Synthesis) | REQ-P1-013 to 015 | 2 | 1 |
| Phase 2.1 (LMS) | REQ-P2-001 to 003 | 3 | 0 |
| Phase 2.2 (RLS) | REQ-P2-004 to 006 | 3 | 0 |
| Phase 2.3 (Comparison) | REQ-P2-007 to 009 | 3 | 0 |
| **Total** | **23** | **22** | **1** |

The single deferred requirement (REQ-P1-015, timing closure) is documented with rationale in `PLAN.md` §7.3 and recorded as future work.
