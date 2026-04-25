# Project Review — FPGA-Based Adaptive Beamformer for 5G Networks

Review date: 2026-04-25. Project state at review: all phases complete.

---

## 1. Executive summary

The project successfully delivered a verified non-adaptive beamformer through the full waterfall (algorithm → fixed-point → RTL → co-simulation → synthesis) and a rigorous algorithmic feasibility study comparing LMS and RLS for future hardware implementation. The engineering work is technically sound and honestly scoped. The principal weaknesses are not in *what* was built but in *how the project was orchestrated* — manual rather than automated workflows, prose-heavy rather than artifact-driven documentation, and a single moving report rather than separated design / verification / results documents.

### Grades by category

| Category | Grade | Rationale |
|---|---|---|
| Technical correctness | A | Waterfall verification, ±1 LSB RTL match, honest scope flagging |
| Reproducibility | B+ | Seeded RNG, vectors in version control, but manual tool steps |
| Documentation formality | B− | PLAN/REQUIREMENTS/CHANGELOG in place; ICDs, test plans, coding standards still missing |
| Build and orchestration | C | GUI-driven Vivado, no Makefile during development, hand-copied numbers between scripts |
| Project management | B | Phased structure works; no risk register, no issue tracker, no traceability until late |

---

## 2. Project structure review

### 2.1 What works

- Phased decomposition (1.1–1.5, 2.1–2.3) maps cleanly to deliverables and provides natural commit milestones.
- Verification-against-previous-level chain is textbook and was actually followed.
- Repository layout (`matlab/`, `rtl/`, `vectors/`, `plots/`, `synthesis/`) keeps concerns separate.
- Honest scope discipline — Phase 1.5 documented as synthesis-only, Phase 2 descoped to MATLAB-only with rationale rather than overstated.

### 2.2 What is missing

- No `docs/` separation during development — design rationale, verification specs, and results all lived in one moving document. Should be three documents: design, verification, results.
- `vectors/` has no provenance manifest — three `.hex` files with no record of which commit of `fixed_point_sim.m` produced them.
- `plots/` mixes Phase 1.1 informally-named figures with later structured `P2.x_*` names. The old four should be renamed to `P1.1_*` for consistency.
- No `synthesis/` Tcl script during development — the entire Vivado GUI incident would have been avoided with a batch script from the start.

### 2.3 Recommended target structure (now partially implemented)

```
260410-beamforming/
├── PLAN.md, REQUIREMENTS.md, CHANGELOG.md, README.md
├── Makefile
├── docs/
│   ├── PROJECT_REVIEW.md           (this file)
│   ├── design_document.md          (future)
│   ├── verification_report.md      (future)
│   └── coding_style.md             (future)
├── matlab/
│   ├── signal_setup.m              (single source of truth)
│   └── *.m
├── rtl/, vectors/, synthesis/, plots/
└── adr/                            (future — architecture decision records)
```

---

## 3. Implementation review

### 3.1 RTL implementation

**Strengths.** Five-module decomposition is clean. Pipelined `complex_mult` (2 cycles) correctly infers DSP48E1. Saturating output stage is correct hardware practice.

**Weaknesses.**
- No formal port headers in `.sv` files (name/dir/width/clock-domain/reset-behaviour per port).
- Reset polarity, clock naming, and active-low conventions are implicit — need a `coding_style.md`.
- No SystemVerilog assertions. At minimum: accumulator overflow, saturation-boundary coverage.
- `M=8` baked into multiple modules — a package parameter would enable sweeping at synth time.

### 3.2 MATLAB implementation

**Strengths.** Section-banner comments make each script readable. Auto-selection of best parameters by SINR-on-tail is robust. `signal_setup.m` now provides a single source of truth for the signal model.

**Weaknesses.**
- No unit tests for `steeringVector` or `compute_sinr`. A `tests/runtests.m` would catch silent regressions.
- Plots saved with no embedded metadata (no git hash, no parameter list). Provenance is implicit.
- No assertion of expected results in each script — a regression in SINR would print silently.

### 3.3 Fixed-point methodology

**Strengths.** Manual quantise/saturate is the right call when the toolbox is unavailable. Word-length sweep before locking is correct methodology.

**Weaknesses.**
- No edge-case test vectors: ±1.0 saturation boundary, all-zeros, all-ones.
- No standalone bit-true MATLAB model of the RTL pipeline (saturation + truncation per stage).

---

## 4. Development workflow review

### 4.1 What worked

- One commit per phase milestone — appropriate granularity.
- `.gitignore` discipline — build artefacts kept out of version control.
- Headless MATLAB execution via `-nodisplay -nosplash -batch`.
- GitHub as dev-machine ↔ lab-PC transfer mechanism — practical given the constraints.

### 4.2 What did not

- Vivado GUI workflow caused the IO-overutilisation incident. `synth.tcl` (now committed) would have eliminated it.
- No CI — every test run is manual. A pre-push hook running `make rtl` and checking for PASS would catch RTL regressions.
- `command_line_output.txt` tracked in git — a generated artifact that should be gitignored (now fixed).
- `signal_setup.m` added late rather than at project start.

---

## 5. Logs and trackers review

### 5.1 What exists

- `synthesis/beamformer_top_utilization_synth.rpt` — Vivado utilisation report.
- `CHANGELOG.md` — milestone log.
- Git commit history.

### 5.2 What is missing

- Per-script run logs with timestamps. The old `command_line_output.txt` was a single file overwritten on every run. A `logs/` directory with dated per-script files would retain history.
- No issue tracker. The Phase 1.5 timing deferral and toolchain disk constraint are undocumented risks.
- No ADR (Architecture Decision Record) folder. The "Phase 2 descoped from HLS" and "LMS selected over RLS" decisions are buried in prose rather than dated immutable records.

### 5.3 Recommended additions

```
adr/
├── 0001-fixed-point-via-manual-quantise.md
├── 0002-iverilog-instead-of-vivado-locally.md
├── 0003-out-of-context-synthesis-mode.md
├── 0004-phase-2-descoped-from-hls.md
└── 0005-lms-selected-over-rls.md

RISKS.md   (timing closure deferred, toolchain disk constraint)
```

---

## 6. Documentation review

### 6.1 Documents present at review

| Document | Quality |
|---|---|
| `PLAN.md` | Good — restricted to decisions only |
| `REQUIREMENTS.md` | Good — 23 numbered requirements, 22 verified, 1 deferred |
| `CHANGELOG.md` | Good — full milestone history |
| `README.md` | Good — entry point with quickstart and file map |
| `Makefile` | Good — one-command builds for sim / rtl / report / synth |
| `project_update.pdf` | Adequate — mixes design, verification, and results in one document |

### 6.2 Documents still missing

| Document | Purpose |
|---|---|
| `docs/design_document.md` | Locked design rationale — supersedes design portion of report |
| `docs/verification_report.md` | Test plan + executed test results per requirement |
| `docs/coding_style.md` | RTL naming, reset polarity, Q-format conventions |
| `vectors/MANIFEST.md` | Which script/commit generated each `.hex` file |

---

## 7. Report structure recommendation

If the report is rewritten for final submission:

```
1. Executive summary (1 page)
2. Background and requirements (1-2 pages)   — cite REQUIREMENTS.md
3. Design (3-4 pages)                         — algorithm, fixed-point, RTL
4. Verification (2-3 pages)                   — test plan, results per requirement
5. Phase 2 algorithmic study (2-3 pages)
6. Synthesis results (1 page)
7. Conclusions and future work (1 page)
8. References                                 — Widrow 1960, Frost 1972, Haykin
9. Appendices: requirements table, results tables, reproduction instructions
```

Content gaps to fill: literature citations, acknowledgement of perfect-pilot assumption (`d = s`), SNR/SIR robustness sweep, statement of static-channel limitation.

---

## 8. Priority list

1. `Makefile` + `synth.tcl` — eliminates manual orchestration (done)
2. `README.md` — repo entry point (done)
3. `signal_setup.m` adoption — single source of truth (done)
4. `REQUIREMENTS.md` with traceability (done)
5. `REPRODUCE.md` — step-by-step rebuild with tool versions (open)
6. `RISKS.md` + ADR folder (open)
7. Report restructure into design / verification / results split (open)

---

## 9. Closing assessment

The technical depth is appropriate for a final-year / capstone engineering project. The ±1 LSB co-simulation match is real engineering rigor. Honest scoping of Phase 1.5 and Phase 2 is more mature than most student projects.

**The pattern across every avoidable pain point: manual orchestration where a script would have done the job.** GUI synthesis, hand-copied numbers, overwriting log files, recompiled LaTeX. The highest-value takeaway: anything done more than twice in a project lifecycle is a target for a script.
