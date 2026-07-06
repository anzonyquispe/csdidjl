# CSDid.jl — Installation Guide

## Requirements

| Software | Version | Purpose | Required? |
|----------|---------|---------|-----------|
| [Julia](https://julialang.org/downloads/) | 1.12+ | Core computation engine | **Yes** |
| Stata | 17+ (MP or SE) | Stata wrapper interface | **Yes** |
| [`jl` (julia.ado)](https://github.com/droodman/julia.ado) | latest | Stata–Julia bridge | **Yes** |
| [R](https://cran.r-project.org/) | 4.5+ | Regenerating R reference CSVs only | Optional |
| [Python](https://www.python.org/downloads/) | 3.10+ | Re-executing the validation notebook only | Optional |

## Installation

### Step 1: Install Julia

Download and install Julia 1.12+ from <https://julialang.org/downloads/>.
Use the default installation path (the Stata wrapper auto-detects standard
Julia locations on Windows).

### Step 2: Install the `jl` Stata package

```stata
ssc install julia
```

### Step 3: Unzip and add to Stata's ado path

Unzip the delivery package to a permanent location, e.g. `C:\CSDid.jl`.
Then in Stata:

```stata
adopath + "C:\CSDid.jl"
```

To make this permanent, add the line to your `profile.do`.

### Step 4: First run (one-time precompilation)

The very first time you call `csdid_jl`, Julia will precompile the package
and all its dependencies. **This takes approximately 5–15 minutes** depending
on your machine. You will see Julia compilation messages in the Stata output
window — this is normal. Subsequent calls start in a few seconds.

To trigger precompilation explicitly:

```stata
adopath + "C:\CSDid.jl"
import delimited "C:\CSDid.jl\data\mpdta.csv", clear
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal)
```

Note: `import delimited` converts `first.treat` in the CSV to `firsttreat`
(dots are removed). Use `firsttreat` in all Stata commands.

## Smoke Test

After installation, run this to verify everything works:

```stata
adopath + "C:\CSDid.jl"
import delimited "C:\CSDid.jl\data\mpdta.csv", clear
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal)
```

Expected output (after precompilation completes):

```
ATT(g,t) Results
─────────────────────────────────────────────────────────
      Group │   Time │       ATT │        SE │ [95% CI]
────────────┼────────┼───────────┼───────────┼─────────
       2004 │   2004 │  -0.02155 │   0.02139 │ ...
       2004 │   2005 │  -0.08069 │   0.02739 │ ...
       2004 │   2006 │  -0.13727 │   0.03303 │ ...
       2004 │   2007 │  -0.10597 │   0.03211 │ ...
       ...  │   ...  │    ...    │    ...    │ ...
─────────────────────────────────────────────────────────
```

You should see 9 ATT(g,t) estimates with standard errors and confidence
intervals. The table is stored in `e(b)` and `e(V)` as usual.

## Full Command Syntax

```
csdid_jl depvar [indepvars] [if] [in] , tname(varname) gname(varname) idname(varname) [options]
```

### Required options

| Option | Description |
|--------|-------------|
| `tname(varname)` | Time-period variable |
| `gname(varname)` | First-treatment-period variable (0 = never treated) |
| `idname(varname)` | Unit identifier variable |

### Estimation options

| Option | Description | Default |
|--------|-------------|---------|
| `est_method(string)` | `dr` (doubly robust), `ipw`, or `reg` | `dr` |
| `control_group(string)` | `nevertreated` or `notyettreated` | `nevertreated` |
| `notyet` | Shorthand for `control_group(notyettreated)` | |
| `base_period(string)` | `varying` or `universal` | `varying` |
| `anticipation(#)` | Number of anticipation periods | 0 |
| `nopanel` | Treat data as repeated cross-sections | panel mode |

### Weights and clustering

| Option | Description |
|--------|-------------|
| `weights(varname)` | Sampling weights variable |
| `fix_weights(string)` | Time-varying weight adjustment: `base_period`, `first_period`, or `varying` |
| `cluster(varname)` | Cluster variable for standard errors |

### Inference options

| Option | Description | Default |
|--------|-------------|---------|
| `alpha(#)` | Significance level for confidence bands | 0.05 |
| `biters(#)` | Multiplier-bootstrap iterations | 1000 |
| `seed(#)` | Random seed for bootstrap | 12345 |
| `level(#)` | Confidence level for display | `c(level)` |

### Aggregation options

| Option | Description |
|--------|-------------|
| `aggregate(string)` | `att` (no aggregation), `event`/`dynamic`, `group`, `calendar`, `simple`, `all` |
| `balance_e(#)` | Balance event time for dynamic aggregation |
| `min_e(#)` | Minimum event time to display |
| `max_e(#)` | Maximum event time to display |

### Performance options

| Option | Description |
|--------|-------------|
| `gpu` | Use GPU acceleration (requires CUDA.jl and a compatible NVIDIA GPU) |

### Examples

```stata
* Basic DR estimation
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal)

* With covariates
csdid_jl lemp lpop, tname(year) gname(firsttreat) idname(countyreal)

* IPW with not-yet-treated control group
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) est_method(ipw) notyet

* Event-study aggregation
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) aggregate(event)

* All aggregations
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) aggregate(all)

* Sampling weights
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) weights(pop)

* Clustered standard errors
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) cluster(state)

* Repeated cross-sections
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) nopanel

* Universal base period with anticipation
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) base_period(universal) anticipation(1)

* Time-varying weights
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) weights(wt) fix_weights(base_period)
```

## Troubleshooting

### Precompilation is slow (5–15 minutes on first run)

This is expected. Julia compiles the entire dependency tree on first use.
After the first run, subsequent calls start in a few seconds. Do not interrupt
the process — if you do, delete the Julia compiled cache and retry:

```
# Delete Julia compiled cache (if precompilation was interrupted)
# The cache is at: %USERPROFILE%\.julia\compiled\v1.12\
```

### `jl` cannot find Julia

If Stata reports that `jl` cannot find Julia, set the path manually:

```stata
global jl_julia_lib "C:\path\to\julia\bin"
```

Or ensure Julia's `bin` directory is in your system `PATH`.

### GPU errors

GPU acceleration requires:
- An NVIDIA GPU with CUDA support
- Julia's `CUDA.jl` package installed
- Environment variable: `JULIA_CUDA_USE_BINARYBUILDER=false`

If GPU is not available, omit the `gpu` option — the CPU path is the default.

## Package Contents

```
csdidjl/
  src/                    Julia package source code
  ext/                    CUDA extension (optional GPU support)
  test/                   Julia test suite
  data/mpdta.csv          Example dataset (smoke test)
  Project.toml            Julia package dependencies
  Manifest.toml           Locked dependency versions
  csdid_jl.ado            Main Stata command
  csdid_jl_load.ado       Julia environment loader
  _csdid_jl_start_julia.ado  Julia startup helper
  csdid_jl.sthlp          Stata help file (help csdid_jl)
  README.md               Project overview and benchmarks
  INSTALL.md              This file
```

The cross-implementation validation (notebook, scripts, full datasets, result
CSVs) is delivered separately in `csdidjl_tests.zip`.

## References

- Callaway, B. and Sant'Anna, P.H.C. (2021). "Difference-in-Differences with
  Multiple Time Periods." *Journal of Econometrics*, 225(2), 200-230.
- Sant'Anna, P.H.C. and Zhao, J. (2020). "Doubly Robust Difference-in-Differences
  Estimators." *Journal of Econometrics*, 219(1), 101-122.
