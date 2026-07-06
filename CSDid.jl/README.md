# CSDid.jl

Julia implementation of the **Callaway & Sant'Anna (2021)** difference-in-differences
estimator with multiple time periods and staggered treatment adoption, plus a **Stata
wrapper** (`csdid_jl`) so Stata users can call the fast Julia engine without leaving
Stata.

- **10× faster** than Stata's native `csdid` on typical panels (see benchmarks below)
- Validated against R `did` and Python `csdid` at machine precision (65 test scenarios)
- Supports every feature of R `did::att_gt`: DR / IPW / Reg estimators, event-study /
  group / calendar / simple aggregations, covariates, sampling weights, clustered SEs,
  universal or varying base period, anticipation, unbalanced panels
- Optional GPU acceleration via CUDA.jl
- Optional plots that mirror R's `ggdid()`

---

## Requirements

| Software | Minimum | Purpose |
|----------|---------|---------|
| [**Julia**](https://julialang.org/downloads/) | 1.10 | Core computation engine (**required for both Julia and Stata usage**) |
| **Stata** | 17 (MP or SE) | Only if you want to call `csdid_jl` from Stata |
| [`jl` (julia.ado)](https://github.com/droodman/julia.ado) | latest | Stata↔Julia bridge, one line to install |
| NVIDIA GPU + CUDA toolkit | optional | Only if you want GPU acceleration |

**Julia install (all platforms):** we strongly recommend
[**juliaup**](https://github.com/JuliaLang/juliaup) — it manages Julia versions cleanly
and doesn't require admin rights:

```bash
# macOS / Linux
curl -fsSL https://install.julialang.org | sh

# Windows (PowerShell)
winget install julia -s msstore
```

Verify:

```bash
julia --version    # should print 1.10 or newer
```

---

## Install (Julia users)

### Option A — from the General Registry (when published)

```julia
julia> ]                       # enters Pkg mode
(@v1.10) pkg> add CSDid
```

### Option B — direct from GitHub (works today)

```julia
julia> ]
(@v1.10) pkg> add https://github.com/<YOUR-USERNAME>/CSDid.jl
```

Replace `<YOUR-USERNAME>` with the account that owns the repo.

### Option C — for local development / testing

```bash
git clone https://github.com/<YOUR-USERNAME>/CSDid.jl.git
cd CSDid.jl
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
```

**First install downloads and precompiles ~30 dependencies. Budget 5–15 minutes on
the first run.** Subsequent loads are seconds.

### Smoke test (Julia)

```julia
using CSDid
df = mpdta()                                    # bundled example dataset
r  = att_gt(yname="lemp", tname="year",
            idname="countyreal", gname="first_treat",
            data=df)
println(summary_attgt(r))

# Event study
es = aggte(r, type="dynamic")
println(summary_aggte(es))
```

If you see a table of ATT(g,t) estimates, you're done.

---

## Install (Stata users)

This section is for people who want to call `csdid_jl` from Stata. You still need
Julia 1.10+ installed first.

### Step 1 — install Julia (see Requirements above)

Verify from a **terminal** (Terminal.app on macOS, PowerShell on Windows):

```bash
julia --version
julia -e 'println(dirname(Sys.BINDIR))'    # remember this path!
```

The second command prints Julia's install root. You may need it in Step 4.

### Step 2 — install the `jl` Stata package

In Stata:

```stata
ssc install julia, replace
```

### Step 3 — get CSDid.jl on your machine

Clone or download this repository:

```bash
git clone https://github.com/<YOUR-USERNAME>/CSDid.jl.git ~/CSDid.jl
```

Or [download the ZIP from GitHub](https://github.com/<YOUR-USERNAME>/CSDid.jl/archive/refs/heads/main.zip)
and unzip somewhere permanent (e.g. `~/CSDid.jl` on macOS/Linux, `C:\CSDid.jl` on Windows).

### Step 4 — one-time precompile (recommended)

Run this once in a **terminal** so you see the progress bar (5–15 min):

```bash
julia --project=/absolute/path/to/CSDid.jl \
      -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
```

You can skip this — the wrapper will precompile on first Stata call — but doing it up
front makes the first Stata run look responsive instead of seemingly hung.

### Step 5 — point Stata at CSDid.jl

Add these to your Stata `profile.do` so every session picks them up automatically:

**macOS / Linux (juliaup users):**

```stata
global csdid_jl_julia_lib "/absolute/path/from/step-1/lib"
adopath + "/absolute/path/to/CSDid.jl"
```

Example on Apple Silicon with juliaup:

```stata
global csdid_jl_julia_lib "/Users/you/.julia/juliaup/julia-1.12.1+0.aarch64.apple.darwin14/lib"
adopath + "/Users/you/CSDid.jl"
```

**Windows:**

```stata
adopath + "C:/CSDid.jl"
```

The Windows path is auto-detected — no `csdid_jl_julia_lib` needed if Julia is in the
default `AppData\Local\Programs\Julia-*` location.

### Step 6 — smoke test (Stata)

```stata
import delimited "/absolute/path/to/CSDid.jl/data/mpdta.csv", clear
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal)
```

Expected output:

```
Callaway & Sant'Anna (2021) Estimator
Outcome variable: lemp                       Number of units =       500
Estimator:        dr                         Control group   = nevertreated

     Group  Time |     ATT(g,t)   Std. Err.     [95.0% Conf. Band]
      2004  2004 |      -0.0215      0.0214     -0.0634      0.0203
      2004  2005 |      -0.0807      0.0274     -0.1345     -0.0269   *
      ...
```

You're done. Type `help csdid_jl` for the full option list.

---

## Quick start

### Stata

```stata
* Basic DR estimation
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal)

* With covariates
csdid_jl lemp lpop, tname(year) gname(firsttreat) idname(countyreal)

* IPW + not-yet-treated control group
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) est_method(ipw) notyet

* Event-study aggregation with plot
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) agg(event) graph

* All aggregations + all plots
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) agg(all) graph

* Sampling weights + clustered SEs
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) weights(pop) cluster(state)

* Universal base period + anticipation
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) base_period(universal) anticipation(1)

* Unbalanced panel
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) unbalanced

* Repeated cross-sections
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) nopanel
```

### Julia

```julia
using CSDid

df = mpdta()   # bundled example dataset

# Group-time ATTs
r = att_gt(
    yname="lemp", tname="year",
    idname="countyreal", gname="first_treat",
    data=df,
    est_method="dr",
    control_group="nevertreated",
)

# Aggregations
dyn = aggte(r, type="dynamic")   # event study
grp = aggte(r, type="group")     # by treatment cohort
cal = aggte(r, type="calendar")  # by calendar year
s   = aggte(r, type="simple")    # single overall ATT
```

---

## Troubleshooting

### `Cannot find libjulia.dll / libjulia.dylib / libjulia.so`

The wrapper couldn't locate your Julia install. Find the correct path with:

```bash
julia -e 'println(dirname(Sys.BINDIR))'
```

Then in Stata (or `profile.do`), append `/lib` (macOS/Linux) or use `\bin` (Windows):

```stata
global csdid_jl_julia_lib "/that/path/lib"
```

### `Failed to precompile stataplugininterface` — `sys.dylib` not found

Symptom: an error mentioning a path to `sys.dylib` in a Julia directory that no longer
exists. This means your Julia precompile cache is stale — built against an older Julia
install that's since been removed or moved.

**Fix**:

```bash
# Wipe the compile cache
rm -rf ~/.julia/compiled

# Check for stale env vars pointing at ghost Julia paths
env | grep -i julia
# If you see any, remove them from ~/.zshrc or ~/.bash_profile and start a fresh shell.

# Reprecompile
julia --project=/path/to/CSDid.jl \
      -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
```

### First Stata call takes 5–15 minutes and looks hung

This is Julia precompiling ~30 dependencies. It's a one-time cost per Julia version.
Subsequent calls start in seconds. If you kill it partway, delete
`~/.julia/compiled/v1.x/` and start over.

### `gpu option specified but CUDA is not available`

`gpu` requires an NVIDIA GPU + CUDA.jl:

```julia
julia> ]
(@v1.10) pkg> add CUDA
```

Only supported on Linux and Windows (macOS has no CUDA).

---

## Features

- Three estimators: **DR** (doubly robust), **IPW** (inverse propensity), **Reg** (outcome regression)
- Aggregations: `dynamic` (event study), `group`, `calendar`, `simple`, `all`
- Control groups: `nevertreated`, `notyettreated`
- Base period: `varying` (default) or `universal`
- Anticipation periods
- Covariates (formula or column list; `C(varname)` for categorical)
- Sampling weights (`weights_name`)
- Time-varying weight handling (`fix_weights`)
- Clustered standard errors
- Balanced and unbalanced panels (`allow_unbalanced_panel`)
- Repeated cross-sections (`panel=false`)
- Multiplier bootstrap for simultaneous (uniform) confidence bands
- Pointwise CIs (`cband=false`)
- Analytical SEs option (`bstrap=false`)
- GPU acceleration via CUDA.jl weak dependency
- Stata wrapper with plots matching R `ggdid()`

## Validation

Validated against the R `did` package (v2.5.0+) and Python `csdid` across **65 test
scenarios**:

| Test Group | Tests | Status | Precision |
|-----------|-------|--------|-----------|
| ATT(g,t) parity | 5 | PASS | 1e-16 |
| Aggregation overall | 5 | PASS | 1e-16 |
| Aggregation egt (× 3 types) | 15 | PASS | 1e-11 |
| Gap scenarios (RC, universal, anticipation, weighted, clustered) | 5 | PASS | 1e-15 |
| `fix_weights` (none, base_period, first_period, varying) | 4 | PASS | 1e-15 |
| Categorical covariates | 2 | PASS | 1e-15 |
| Sim datasets (6 × 2 control-groups × 2 methods) | 24 | PASS | 1e-10 |
| JEL replication | 5 | PASS | 1e-2 |
| **TOTAL** | **65** | **ALL PASS** | |

## Benchmarks

DR estimator, not-yet-treated control group, no bootstrap. Median of 1 warmup + 5
timed runs.

### mpdta (500 units × 5 periods, 2 500 obs)

| Implementation | Median (s) | Speedup |
|---|---|---|
| Stata native `csdid` | 0.920 | 1× |
| **CSDid.jl** | **0.066** | **13.9×** |

### Synthetic panel (100 000 units × 8 periods, 800 000 obs)

| Implementation | Median (s) | Speedup |
|---|---|---|
| Stata native `csdid` | 276.9 | 1× |
| **CSDid.jl** | **20.4** | **13.6×** |

*Stata: StataMP-64 v17.0. Julia: v1.12.*

---

## Repository layout

```
CSDid.jl/
├── Project.toml                 Julia package manifest (Pkg reads this)
├── Manifest.toml                Locked dependency versions (for reproducibility)
├── LICENSE                      MIT
├── README.md                    This file
├── src/                         Julia source
│   ├── CSDid.jl                 Module entry point
│   ├── att_gt.jl                Group-time ATT estimator
│   ├── aggte.jl                 Aggregations
│   ├── estimators.jl            DR / IPW / Reg
│   ├── types.jl                 Result structs
│   ├── mpdta.jl                 Example dataset loader
│   └── gpu_stubs.jl             GPU stubs (real code in ext/)
├── ext/
│   └── CSDidCUDAExt.jl          Weak-dep CUDA extension
├── test/
│   ├── runtests.jl              145-test suite
│   └── gpu_tests.jl             GPU tests
├── data/
│   └── mpdta.csv                Callaway–Sant'Anna example data
├── csdid_jl.ado                 Main Stata command
├── csdid_jl_load.ado            Julia environment loader
├── _csdid_jl_start_julia.ado    Julia startup helper (cross-platform)
└── csdid_jl.sthlp               Stata help file
```

---

## References

- Callaway, B. and Sant'Anna, P.H.C. (2021). "Difference-in-Differences with
  Multiple Time Periods." *Journal of Econometrics* 225(2): 200–230.
- Sant'Anna, P.H.C. and Zhao, J. (2020). "Doubly Robust Difference-in-Differences
  Estimators." *Journal of Econometrics* 219(1): 101–122.
- Roodman, D. `julia.ado`: Stata–Julia bridge. https://github.com/droodman/julia.ado

## License

MIT — see [LICENSE](LICENSE).
