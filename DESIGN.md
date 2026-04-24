# FPGA-Based Adaptive Beamformer for 5G Networks — Design Documentation

## 1. Document purpose and audience

This document is the authoritative design reference for the FPGA-Based Adaptive Beamformer project. It is written to be consumed by both human collaborators and AI agents (such as Claude Code) that join the project at any stage. It captures not only what the project does, but the reasoning behind every major decision — the design philosophy, the tool choices, the phase structure, and the verification strategy. Anyone picking up this project later, whether a teammate or an automated agent, should be able to read this document and understand the full context without needing to reconstruct decisions from source code or chat history.

AI agents reading this document should treat it as project ground truth. If an instruction in a user message conflicts with a decision recorded here, the agent should flag the discrepancy and ask for clarification rather than silently overriding the documented design.

## 2. Project overview

The project implements a beamforming receiver for a 5G New Radio (NR) base station on a field-programmable gate array (FPGA). Beamforming is a spatial signal processing technique in which multiple antenna elements are combined with complex weights to produce a directional reception pattern. The goal is to amplify signals arriving from a target user direction while suppressing signals and noise arriving from other directions.

The project is divided into two phases. Phase 1 implements a non-adaptive beamformer in which the weights are fixed at synthesis time for a known target direction. Phase 2 extends this into an adaptive beamformer that uses the Least Mean Squares (LMS) algorithm to automatically update the weights in response to channel conditions, with no prior knowledge of the target direction required at runtime.

The project emphasises a top-down, simulation-first workflow. Every hardware decision is validated first in software (MATLAB) before being committed to RTL. Every RTL block is verified against a golden reference generated from the same MATLAB simulation. This methodology ensures that bugs are caught at the cheapest stage possible and that the hardware faithfully implements the mathematically validated algorithm.

## 3. Background on beamforming in 5G

Modern 5G base stations (gNBs) use multiple antennas — sometimes many tens or hundreds — to serve multiple users simultaneously within the same time-frequency resources. Each antenna receives a superposition of the target user's signal, signals from other users (multi-user interference), signals from adjacent cells (inter-cell interference), and thermal noise. Without spatial processing, it is impossible to separate these contributions.

Beamforming solves this problem by treating the antenna array as a spatial filter. A plane wave arriving from a specific angle produces a characteristic phase progression across the array elements — the signal reaches each antenna at a slightly different time, which translates to a fixed phase offset between adjacent elements. By multiplying each antenna's signal by a complex weight and summing the results, the receiver can make signals from a particular direction add constructively while signals from other directions partially cancel. The vector of complex weights is called the beamforming vector, and the angle at which constructive combining occurs is called the steering direction.

In 5G NR specifically, beamforming is essential at sub-6 GHz bands to improve spectral efficiency through spatial multiplexing, and it is absolutely required at millimetre-wave bands where propagation losses are severe and narrow beams are needed to close the link budget. 5G uses demodulation reference signals (DMRS) embedded in each slot to allow the base station to estimate the channel and compute or update beamforming weights. The pilot-and-data structure of 5G makes LMS-style adaptive beamforming a natural fit, because the pilot symbols provide the reference signal that LMS requires.

## 4. Two-phase project structure

The project is organised into two distinct phases, each with five sub-stages. This structure ensures that a working, verified design exists at the end of Phase 1 before any adaptive logic is introduced.

Phase 1 builds a non-adaptive beamformer where weights are precomputed in MATLAB for a target angle, converted to fixed-point, and stored in a read-only memory (ROM) inside the FPGA. The hardware reads the weights from the ROM, multiplies each antenna sample by the corresponding weight, and sums the results to produce the beamformer output. The five sub-stages are:

- 1.1 Algorithm simulation in MATLAB (floating-point) — establish the golden reference.
- 1.2 Fixed-point analysis in MATLAB — determine the minimum acceptable word lengths.
- 1.3 RTL implementation in SystemVerilog — complex multiplier, accumulator, weight ROM, top-level wrapper.
- 1.4 Co-simulation and verification — drive the RTL with test vectors from 1.1 and compare outputs.
- 1.5 Synthesis and timing closure in Vivado — verify resource usage and clock frequency targets.

Phase 2 extends the Phase 1 hardware with an LMS weight-update engine, a pilot-signal controller, and a writeable weight register bank that replaces the ROM. The five sub-stages parallel Phase 1:

- 2.1 LMS algorithm simulation in MATLAB — validate convergence behaviour.
- 2.2 Fixed-point LMS analysis — check for overflow and weight drift in finite precision.
- 2.3 HLS implementation of the LMS update in Vitis HLS.
- 2.4 Co-simulation — verify weight convergence against the MATLAB reference.
- 2.5 Integration and synthesis — integrate HLS-generated RTL with the Phase 1 data path, synthesize the full system, compare resources against Phase 1.

This structure deliberately minimises the surface area of change between phases. The Phase 1 data path — complex multiplier, accumulator, pipeline — is reused unchanged in Phase 2. Only the weight storage is modified (ROM becomes register bank), and new blocks are added around the data path (error computation, LMS update, pilot controller). This keeps the Phase 1 verification work valid and reduces the risk that Phase 2 changes break a previously working design.

## 5. Design philosophy

The single guiding principle of this project is to do the simplest correct thing in hardware and verify it exhaustively before adding complexity. Every design decision derives from this principle.

Simulation-first. No RTL is written before the algorithm is validated in MATLAB floating-point, and no RTL word length is chosen before fixed-point simulation confirms the chosen precision gives acceptable results. Bugs found in MATLAB take minutes to fix; bugs found in simulation waveforms take hours; bugs found after synthesis take days. Pushing validation as early as possible is not optional.

Golden reference throughout. Every level of the implementation is verified against the MATLAB golden reference. The fixed-point MATLAB output must match the floating-point output within acceptable quantisation error. The RTL simulation output must match the fixed-point MATLAB output exactly (within rounding). The synthesized hardware output, when driven with captured test vectors, must match the RTL simulation output. This chain of equivalence makes debugging tractable.

Minimum viable hardware. The Phase 1 beamformer is the simplest working beamformer — a conventional delay-and-sum design with fixed weights. It is not the most spectrally efficient beamformer, it does not provide optimal interference suppression, and it is not what a production 5G base station would use. It is, however, the design that validates the data path most clearly. Better algorithms come in Phase 2 and in future extensions, built on top of a verified foundation.

Clean extensibility. Every Phase 1 decision is made with Phase 2 in mind. The weight storage is separated from the data path so it can be upgraded from ROM to register bank without touching the multipliers. The pipeline depth is designed to accommodate the additional latency of the LMS update path. The test infrastructure is structured so the same testbench framework can drive Phase 2 with minimal changes.

Reproducibility. The entire workflow — from MATLAB scripts to RTL source to synthesis constraints — is designed to be reproducible by anyone with the same toolchain. Random number generators are seeded. Test vectors are checked into version control. No step relies on manually copied numbers between tools.

## 6. Toolchain selection and rationale

The toolchain was chosen layer by layer, with each choice justified by the question that layer must answer. The final selections are recorded below along with the reasoning.

### 6.1 Algorithm simulation: MATLAB

MATLAB was chosen over Python, C, or direct RTL simulation for the algorithm-development stage. MATLAB's matrix syntax maps one-to-one onto beamforming equations — the expression `w' * X` is literally the beamformer output. The Phased Array System Toolbox and Signal Processing Toolbox provide validated implementations of array geometries, steering vector generation, and radiation pattern computation, which would otherwise have to be written from scratch. MATLAB also has first-class support for fixed-point modelling via the Fixed-Point Designer toolbox, which is critical for Phase 1.2.

An important secondary benefit is that MATLAB can export test vectors and expected outputs as hexadecimal or binary files that can be read directly by a SystemVerilog testbench using `$readmemh` or `$readmemb`. This automates the golden-reference flow and removes an entire class of transcription errors.

### 6.2 Fixed-point modelling: MATLAB Fixed-Point Designer

The same MATLAB environment handles floating-point and fixed-point modelling through the Fixed-Point Designer toolbox. `fi` objects allow specifying signed-ness, word length, and fraction length per signal, with configurable rounding and overflow modes. Sweeping word lengths is as simple as wrapping the simulation in a loop and plotting radiation-pattern degradation as a function of bit width. Doing the same analysis in RTL would require repeated synthesis runs and is not tractable.

### 6.3 RTL language: SystemVerilog

SystemVerilog was selected over VHDL and classic Verilog. It is the modern industry standard, combining Verilog's conciseness with stronger typing, packed structures, interfaces, and improved verification constructs. For this project specifically, SystemVerilog's `logic` type, packed arrays, and parameterised module interfaces make the pipelined complex multiplier and accumulator cleaner to express than in either VHDL or classic Verilog.

The complex arithmetic operations in the beamformer benefit particularly from SystemVerilog's support for user-defined packed structs representing complex numbers, and from its explicit `always_ff` and `always_comb` blocks which communicate intent to the synthesizer more clearly than classic Verilog's `always @(posedge clk)` patterns.

### 6.4 Implementation approach: RTL for data path, HLS for LMS

The Phase 1 data path — complex multiplier, accumulator, weight ROM — is implemented in hand-written SystemVerilog RTL. This is because the data path is small, well-understood, and the exercise of writing it in RTL teaches the most about FPGA pipeline design, DSP48 inference, and timing closure. Hand-written RTL also gives precise control over latency and resource mapping, which is valuable for the throughput-critical data path.

The Phase 2 LMS update engine is implemented in C++ using Vitis HLS (Xilinx High-Level Synthesis). The LMS update involves a more complex control flow — iterating over all M antennas to update each weight, managing the feedback of the error signal, and sequencing between pilot and data modes. Writing this in C++ with HLS pragmas to control pipelining and resource binding is significantly faster than hand-writing the equivalent RTL, and because the LMS algorithm is well within HLS's comfort zone (loops with regular structure, fixed-point arithmetic, no complex memory patterns), the generated RTL is of good quality.

This hybrid approach — RTL where control matters, HLS where productivity matters — is representative of how real FPGA design teams work on mixed-criticality projects.

### 6.5 Synthesis and implementation: Vivado (Xilinx/AMD)

Vivado is the natural choice given that the RTL is hand-written for Xilinx FPGA targets and the HLS tool in use is Vitis HLS. Vivado has strong automatic DSP48 inference — if a multiply-accumulate is written correctly in SystemVerilog, the synthesizer will map it to a DSP48E1 or DSP48E2 slice without any explicit instantiation, which is essential for the beamformer core. Vivado also provides the WebPACK license free of charge for the device families typically used in academic projects (Artix-7, Zynq-7000), removing any licensing friction.

Target board is flexible but the design is written with an Artix-7 or Zynq-7000 in mind as the baseline. Porting to a Kintex or UltraScale device would require only constraint-file changes.

### 6.6 Simulation: Vivado Simulator

Vivado Simulator (xsim) is used for RTL simulation. It is tightly integrated with the Vivado flow, supports SystemVerilog fully, and handles mixed SV / VHDL simulation if any third-party IP is introduced. While ModelSim is also a valid option, staying within the Vivado ecosystem reduces tool-chain complexity for a single-developer academic project.

### 6.7 Verification: MATLAB golden reference driving SV testbench

The verification methodology is consistent across both phases. MATLAB generates a set of input samples (complex IQ data simulating the received signal at the antenna array) and the expected output samples (the beamformed output, or in Phase 2, the converged weights). These are written to text files in hexadecimal format with appropriate fixed-point representation. The SystemVerilog testbench reads these files using `$readmemh`, drives them into the DUT, and compares the DUT output against the expected output on every clock cycle.

Any mismatch immediately fails the test and reports the cycle, expected value, and actual value. This makes regressions trivial to catch and root-cause.

## 7. Phase 1 detailed workflow

### 7.1 Phase 1.1 — algorithm simulation (MATLAB floating-point)

File: `algo_sim.m` (or equivalent).

Status: complete.

Parameters: M = 8 antennas, half-wavelength spacing (d/lambda = 0.5), target signal at 30 degrees from broadside, interferer at minus 20 degrees, SNR 10 dB, SIR 0 dB, 512 time samples.

Algorithm: generate steering vectors for target and interferer, construct received signal matrix X = a(theta_sig) * s + sqrt(int_power) * a(theta_int) * i + sigma * n, compute weights w = a(theta_sig), normalise w to unit norm, apply beamformer y = w' * X, compute array factor by sweeping a trial angle phi over minus 90 to plus 90 degrees.

Outputs: radiation pattern in dB (rectangular), polar radiation pattern, weight values (real and imaginary), weight phases with unwrap, beamformer output in time domain compared against the desired signal. All plots have been verified as correct — main lobe at 30 degrees, weights exhibit linear phase progression of 90 degrees per element, beamformer output tracks the desired signal modulo noise and residual interference.

Key verification outputs from this stage: array gain toward signal 9 dB, array gain toward interferer minus 9.5 dB, input SINR minus 2.55 dB, output SINR plus 15.78 dB, SINR improvement 18.33 dB. These numbers constitute the golden reference that the fixed-point and RTL stages must reproduce within tolerance.

### 7.2 Phase 1.2 — fixed-point analysis (MATLAB Fixed-Point Designer)

File: `fixed_point_sim.m`. This script imports parameters and signals from `algo_sim.m` to avoid duplication of constants and random-seed configuration.

Purpose: determine the minimum word lengths for input samples, weights, multiplier outputs, and accumulator that produce acceptable radiation-pattern fidelity relative to the floating-point reference.

Starting assumptions, to be validated: input samples Q1.15 (16-bit signed, 15 fractional bits), weights Q1.15, multiplier output Q2.30 (product of two Q1.15 values), accumulator Q5.30 (M = 8 summations require log2(8) = 3 bits of integer headroom above the product format).

Methodology: convert the floating-point `w`, `X`, and `s` variables to `fi` objects with the starting word lengths. Re-run the beamformer and the array-factor sweep in fixed-point. Compare the radiation pattern against the floating-point reference and compute the maximum deviation in dB. Sweep each word length downward and plot the degradation curve. The smallest word length at which the main-lobe peak, 3 dB beamwidth, and sidelobe levels remain within defined tolerances is selected as the RTL target.

Output: a summary table of chosen word lengths per signal, saved to disk, and a set of quantised test vectors in hex format for use by the SystemVerilog testbench.

### 7.3 Phase 1.3 — RTL implementation (SystemVerilog)

Modules to implement:

- `complex_mult.sv` — a pipelined complex multiplier. Input: two complex operands in the chosen fixed-point format. Output: complex product. Internal structure: four real multipliers wired in the standard (a + jb)(c + jd) = (ac - bd) + j(ad + bc) pattern. Two pipeline stages (one after the partial products, one after the sum) to ensure DSP48 inference and meet timing at the target clock. Parameterise on input and output widths.

- `complex_accumulator.sv` — sums M complex products into a single complex output per sample clock. Pipelined adder tree to keep the critical path short. Parameterised on M and on input width. Output register holds the final sum.

- `weight_rom.sv` — stores the precomputed fixed-point weights. Synthesized as either distributed RAM or a block RAM (BRAM), depending on M and the weight width. Initialised from a hex file generated by `fixed_point_sim.m`. One read port delivering all M weights in parallel to the multiplier array.

- `beamformer_top.sv` — instantiates M complex multipliers in parallel, one accumulator, and the weight ROM. Handles pipeline-depth alignment between the data path and any valid-signal propagation.

- `beamformer_tb.sv` — testbench. Reads input samples and expected outputs from hex files, drives the DUT, compares outputs, counts mismatches, reports pass/fail.

Coding conventions: use `logic` throughout, not `reg` or `wire`. Use `always_ff` for sequential blocks, `always_comb` for combinational. Use packed structs for complex numbers. Parameterise all widths. Include `timeunit` and `timeprecision` declarations in the testbench. No latches.

### 7.4 Phase 1.4 — co-simulation and verification

Run the SystemVerilog testbench in Vivado Simulator. Drive the input samples from the fixed-point MATLAB reference, capture the output, compare against the expected output on every clock cycle. Both must match exactly within the rounding mode specified in the fixed-point analysis. Any mismatch indicates either an RTL bug, a fixed-point format mismatch, or a pipeline-alignment issue.

Additional directed tests to run: impulse response (all antennas receive a single unit impulse), known-angle test (synthesize a pure tone from a specific angle and confirm the output matches the expected beam gain), all-zero input (output must be zero), saturation test (drive maximum-magnitude input and verify no overflow in the accumulator).

Acceptance criterion for this stage: all directed tests pass and the full 512-sample vector matches the MATLAB reference to within one least-significant-bit rounding error.

### 7.5 Phase 1.5 — synthesis and timing closure

Run Vivado synthesis targeting the chosen device (Artix-7 baseline). Extract the resource utilisation report — number of DSP slices used (expect approximately M = 8 to M times 2 = 16 DSPs depending on pipeline choices), LUT count, flip-flop count, BRAM count. Verify that DSP48 inference has captured all the complex multipliers — if not, review the RTL to ensure the multiplication pattern is DSP-friendly.

Set the target clock frequency (suggested: 200 MHz baseline, 300 MHz stretch). Run place-and-route and review the timing report. Fix any failing paths by adjusting pipeline depth. Generate a bitstream if a board is available for hardware testing; otherwise, the synthesized design is the Phase 1 deliverable.

## 8. Phase 2 detailed workflow

### 8.1 Phase 2.1 — LMS algorithm simulation (MATLAB floating-point)

File: `lms_sim.m`, also importing from `algo_sim.m`.

Purpose: validate that the LMS weight-update loop converges to the correct beam direction from an arbitrary starting point, using only a pilot reference signal.

Algorithm: initialise weights to all-zero or small-random. For each pilot sample, compute output y(n) = w' * x(n), compute error e(n) = d(n) - y(n) where d(n) is the known pilot, update weights as w(n+1) = w(n) + mu * conj(e(n)) * x(n). Sweep step size mu over a range and observe convergence speed versus stability. Typical convergence in 100 to 500 samples for the chosen array geometry.

Outputs: weight convergence trajectories (real and imaginary parts of each weight over time), mean-squared error curve on a log scale, radiation pattern before and after convergence, final beam-direction estimate versus true target direction.

### 8.2 Phase 2.2 — fixed-point LMS analysis

File: `lms_fixed_sim.m`.

Purpose: verify that LMS converges correctly with finite-precision arithmetic and identify any overflow or underflow conditions in the weight update. LMS is notoriously sensitive to fixed-point issues because the weight accumulator must hold small updates over many iterations without losing precision.

Additional considerations over Phase 1.2: the weight update `mu * conj(e) * x` can be very small in magnitude, so the fraction length of the weight register must be long enough to represent these small updates. The step size mu is typically chosen as a power of two to allow implementation by right-shift rather than multiplication.

Output: locked-in word lengths for weight register (typically wider than the Phase 1 weight ROM), error signal, LMS product, and step size shift amount.

### 8.3 Phase 2.3 — HLS implementation of LMS update (Vitis HLS)

File: `lms_update.cpp`, `lms_update.h`.

Describe the LMS update as a C++ function with `ap_fixed` types matching the word lengths from Phase 2.2. Annotate with `#pragma HLS PIPELINE` for single-sample throughput, `#pragma HLS UNROLL` to parallelise the weight update across antennas, and `#pragma HLS ARRAY_PARTITION` on the weight register array to provide enough read/write ports.

Co-simulate in Vitis HLS against test vectors from `lms_fixed_sim.m`. Export as IP (packaged RTL) for integration into the Vivado block design.

### 8.4 Phase 2.4 — integration and verification

Replace the Phase 1 weight ROM with a writeable weight register bank. Instantiate the HLS-generated LMS update module. Add a pilot-sequencer FSM that switches between weight-update mode (during pilot symbols) and data-passthrough mode (during data symbols, weights frozen).

Write a new testbench that generates a pilot-then-data sequence and verifies that weights converge during the pilot phase and the beamformer output during the data phase shows the expected SINR improvement.

### 8.5 Phase 2.5 — synthesis and comparison

Synthesize the full Phase 2 design. Compare resource usage against Phase 1 — LMS adds DSP slices for the update multipliers and registers for the weight bank. Verify timing closure at the same target clock. Document the delta in resources and power consumption as the cost of adaptivity.

## 9. Data types and precision

The following fixed-point formats are the working assumptions for the project. Exact values are to be confirmed by Phase 1.2 and Phase 2.2 simulation.

Signal samples x(n) per antenna: 16-bit signed, Q1.15 format, one sign bit, 15 fractional bits. Real and imaginary parts stored separately, giving 32 bits per complex sample.

Weights w(m): 16-bit signed, Q1.15 format, matching the input sample format. Same rationale — magnitude bounded by unity given normalisation.

Complex multiplier output: 32-bit signed per component, Q2.30 format (product of two Q1.15 values). Real and imaginary parts computed as sums of real-multiplier products with appropriate sign handling.

Accumulator: 36-bit signed per component, Q5.31 or similar format. Extra integer bits provide headroom for M = 8 summations without saturation. Exact width to be confirmed during fixed-point analysis.

Final output y(n): truncated back to Q1.15 or Q2.14 for downstream processing, depending on post-beamformer requirements.

LMS-specific formats (Phase 2): error signal e(n) same as y(n) format. Step size mu a power of two, implemented as a right shift. Weight update accumulator may require wider fraction length than the Phase 1 weights — to be determined by Phase 2.2 analysis.

## 10. Verification strategy

The verification strategy follows an equivalence-chain model. Each implementation level is verified against the previous level, forming a chain of provable equivalences from algorithm to hardware.

Level 1: floating-point MATLAB simulation. Verified against analytical expectations — main lobe location, array gain formulas, input-output SINR predictions. This is the root of the verification tree.

Level 2: fixed-point MATLAB simulation. Verified against level 1 with a defined tolerance on pattern metrics (peak deviation less than 0.5 dB, null depth within 5 dB of reference).

Level 3: RTL simulation. Verified against level 2 exactly — every output sample must match the fixed-point MATLAB output to the least-significant bit, given the same input vectors.

Level 4: synthesised hardware. If hardware testing is performed, captured outputs from the FPGA are compared against level 3 simulation outputs for the same input vectors. Exact match expected.

Regression testing: the entire verification chain is re-run any time a change is made to the RTL, the fixed-point formats, or the MATLAB simulation. A passing run at every level is required before merging any change.

## 11. Current project status

As of the latest update, the project is at the end of Phase 1.1. The MATLAB floating-point simulation (`algo_sim.m`) is written, runs cleanly, and produces the expected plots: radiation pattern, polar pattern, weights, and beamformer output. Phase 1.2 — fixed-point analysis — is the next task to be undertaken.

Design decisions locked in: all toolchain selections, the two-phase structure, the parameter set (M = 8, target at 30 degrees, interferer at minus 20 degrees), the conventional delay-and-sum beamformer approach, the use of a ROM for weight storage in Phase 1, the use of LMS for Phase 2 adaptation.

Decisions pending: exact word lengths for fixed-point representation (to be determined in Phase 1.2), target FPGA device and board (Artix-7 is the baseline assumption), target clock frequency (200 MHz is the working target).

## 12. Project file structure

The recommended project folder structure:

```
beamformer_project/
├── DESIGN.md                    (this document)
├── README.md                    (quick-start and build instructions)
├── matlab/
│   ├── algo_sim.m               (Phase 1.1 — floating-point simulation)
│   ├── fixed_point_sim.m        (Phase 1.2 — fixed-point analysis)
│   ├── lms_sim.m                (Phase 2.1 — LMS simulation)
│   ├── lms_fixed_sim.m          (Phase 2.2 — fixed-point LMS)
│   ├── export_vectors.m         (writes test vectors for RTL testbench)
│   └── plots/                   (saved .png outputs)
├── rtl/
│   ├── complex_mult.sv
│   ├── complex_accumulator.sv
│   ├── weight_rom.sv
│   ├── beamformer_top.sv
│   └── beamformer_tb.sv
├── hls/
│   ├── lms_update.cpp
│   ├── lms_update.h
│   └── lms_testbench.cpp
├── vivado/
│   ├── project.xpr              (Vivado project)
│   ├── constraints.xdc
│   └── reports/                 (synthesis, timing, utilisation)
└── vectors/
    ├── inputs.hex
    ├── weights.hex
    └── expected_output.hex
```

## 13. Guidelines for AI agents

AI agents (Claude Code or equivalent) working on this project should follow these guidelines:

Treat this document as authoritative. If a user instruction conflicts with a decision recorded here, flag the conflict and request clarification. Do not silently override documented design decisions.

Preserve verification equivalence. Any change to the MATLAB simulation must be accompanied by regeneration of the test vectors. Any change to the RTL must be verified against the existing MATLAB golden reference before being considered complete. Do not modify test vectors to make failing tests pass.

Ask before introducing new dependencies. The toolchain is deliberately minimal. Do not introduce new MATLAB toolboxes, new HLS libraries, or new Vivado IP cores without explicit approval. If a new dependency seems warranted, propose it and explain why.

Maintain coding conventions. SystemVerilog code uses `logic`, `always_ff`, and `always_comb` consistently. Modules are parameterised. No latches. MATLAB code uses descriptive variable names, consistent comment style, and imports from `algo_sim.m` rather than duplicating parameters.

Preserve the phase boundary. Phase 1 and Phase 2 are separate deliverables. Do not mix Phase 2 features (LMS logic, writeable weights, pilot sequencer) into Phase 1 files. If extending a Phase 1 module to support Phase 2, either parameterise cleanly or create a new Phase 2 variant — do not silently modify Phase 1 behaviour.

Update this document. If a design decision changes during implementation, update the relevant section of this document and note the change in a revision history at the top. This document is the single source of truth; letting it drift out of sync with the code defeats its purpose.

Preserve randomness seeding. The MATLAB simulations seed their random number generators for reproducibility. Do not remove or modify these seeds. Any test-vector regeneration must use the same seeds so that previous verification results remain valid.

## 14. Glossary

Array factor (AF). The complex-valued directional response of an antenna array as a function of angle, computed as the inner product of the weight vector with the steering vector at each angle.

Beamforming. Spatial signal processing technique combining multiple antenna signals with complex weights to produce a directional reception or transmission pattern.

Broadside. The direction perpendicular to the antenna array axis. Angles in this project are measured relative to broadside, with positive angles typically on one side and negative on the other.

Delay-and-sum beamformer. The simplest beamformer, in which weights equal the conjugate of the steering vector toward the target. Also called the conventional beamformer.

DMRS (demodulation reference signal). Pilot symbols embedded in the 5G NR slot structure that the receiver uses for channel estimation and, in this project, as the reference signal for LMS adaptation.

DSP48. A Xilinx FPGA hardware primitive that implements a signed multiply-accumulate with pre-adder and accumulator registers. Inferred automatically by Vivado for compatible RTL patterns.

Fixed-point arithmetic. Integer arithmetic with an implicit radix point, parameterised by word length and fraction length. Used in FPGA designs because it is much cheaper than floating-point.

Fixed-Point Designer. A MATLAB toolbox providing the `fi` object type for simulating fixed-point arithmetic in MATLAB code.

Golden reference. The authoritative expected output for a computation, used as the comparison target in verification. In this project, the MATLAB simulation output is the golden reference for the RTL.

HLS (high-level synthesis). A design methodology in which hardware is described in a high-level language (typically C or C++) and an automated tool generates RTL. Vitis HLS is the Xilinx implementation.

LMS (least mean squares). An adaptive filtering algorithm that updates filter weights proportional to the instantaneous gradient of the squared error. Used in Phase 2 for adaptive weight computation.

RTL (register transfer level). A level of hardware abstraction at which signals, registers, and combinational logic are described explicitly, typically in SystemVerilog or VHDL.

SINR (signal to interference plus noise ratio). The ratio of signal power to the sum of interference power and noise power, in dB. Improving SINR is the main quantitative goal of beamforming.

Steering vector. A complex vector representing the phase progression of a signal arriving from a specific angle across the elements of an antenna array. For a uniform linear array with half-wavelength spacing, the m-th element of the steering vector for angle theta is exp(j pi m sin(theta)).

ULA (uniform linear array). An antenna array with equally spaced elements along a straight line. The simplest array geometry and the one used in this project.

Vitis HLS. The Xilinx high-level synthesis tool. Takes C++ with HLS pragmas and produces synthesizable RTL.

Vivado. The Xilinx FPGA design suite, including synthesis, place-and-route, timing analysis, and simulation.

Weight vector. The vector of complex coefficients applied to antenna signals by the beamformer. In Phase 1, fixed at synthesis. In Phase 2, updated adaptively by LMS.

---

Revision history

- Initial version — Phase 1.1 complete, Phase 1.2 next.
