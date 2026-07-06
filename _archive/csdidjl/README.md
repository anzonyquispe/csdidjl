# CSDid.jl

Julia implementation of the Callaway & Sant'Anna (2021) difference-in-differences
estimator with multiple time periods and staggered treatment adoption.

## Features

- Three estimators: **DR** (doubly robust), **IPW** (inverse probability weighting),
  **Reg** (outcome regression)
- Four aggregation types: dynamic (event-study), group, calendar, simple
- Control groups: never-treated, not-yet-treated
- Base period: varying (default) or universal
- Anticipation periods
- Covariates via `xformla` (formula or vector of column symbols)
- Categorical covariates via `C(varname)` syntax
- Sampling weights via `weights_name`
- Clustered standard errors via `clustervar`
- Time-varying weight handling via `fix_weights`
- Panel and repeated cross-section data (`panel=true/false`)
- Multiplier bootstrap for simultaneous confidence bands
- GPU acceleration via CUDA.jl extension (optional)
- Stata wrapper (`csdid_jl`) following the `reghdfejl` pattern

## Quick Start

```julia
include("src/CSDid.jl")
using .CSDid

df = mpdta()  # load example dataset

# Estimate group-time ATTs
result = att_gt(
    yname = "lemp", tname = "year",
    idname = "countyreal", gname = "first_treat",
    data = df, est_method = "dr",
    control_group = "nevertreated",
)

# Aggregate
dyn = aggte(result, type="dynamic")   # event-study
grp = aggte(result, type="group")     # by treatment cohort
s   = aggte(result, type="simple")    # overall
```

### Sampling Weights

```julia
result = att_gt(
    yname="lemp", tname="year", idname="countyreal",
    gname="first_treat", data=df,
    weights_name="population",   # column with sampling weights
)
```

### Clustered Standard Errors

```julia
result = att_gt(
    yname="lemp", tname="year", idname="countyreal",
    gname="first_treat", data=df,
    clustervar="state",          # cluster variable for SEs
)
```

### Repeated Cross-Sections

```julia
result = att_gt(
    yname="lemp", tname="year", idname="countyreal",
    gname="first_treat", data=df,
    panel=false,                 # use RC estimators
)
```

### Universal Base Period + Anticipation

```julia
result = att_gt(
    yname="lemp", tname="year", idname="countyreal",
    gname="first_treat", data=df,
    base_period="universal",     # use g-1 as base for all t
    anticipation=1,              # allow 1 period of anticipation
)
```

### Categorical Covariates

```julia
result = att_gt(
    yname="Y", tname="period", idname="id",
    gname="G", data=df,
    xformla=["C(cat)"],          # dummy encoding (drop first level)
)
```

### Time-Varying Weights

```julia
result = att_gt(
    yname="lemp", tname="year", idname="countyreal",
    gname="first_treat", data=df,
    weights_name="wt",
    fix_weights="base_period",   # or "first_period" or "varying"
)
```

## Validation

Validated against the R `did` package (v2.5.0+) and Python `csdid` package across
65 test scenarios:

| Test Group | Tests | Status |
|-----------|-------|--------|
| ATT(g,t) parity (5 scenarios) | 5 | PASS (1e-16) |
| Aggregation overall (5 scenarios) | 5 | PASS (1e-16) |
| Aggregation egt (5 × 3 types) | 15 | PASS (1e-11) |
| Gap scenarios (rc, universal, anticipation, weighted, clustered) | 5 | PASS (1e-15) |
| fix_weights (none, base_period, first_period, varying) | 4 | PASS (1e-15) |
| Categorical covariates | 2 | PASS (1e-15) |
| Sim datasets (6 datasets × 2 CG × 2 methods) | 24 | PASS (1e-10) |
| JEL replication | 5 | PASS (0.01) |
| **TOTAL** | **65** | **ALL PASS** |

### Cross-Implementation Comparison

Full comparison against the [Python csdid](https://github.com/d2cml-ai/csdid)
package, R `did` package, and Stata `csdid_jl` wrapper in `comparison_csdid.ipynb`.

## Benchmark: CSDid.jl vs Stata native `csdid`

Configuration: DR estimator, not-yet-treated control group, no bootstrap.
Methodology: 1 warmup + 5 timed runs, report median.

### mpdta (500 units x 5 periods, 2500 obs)

| Implementation | Median (s) | Speedup |
|---------------|-----------|---------|
| Stata native `csdid` | 0.920 | 1x |
| **CSDid.jl** (standalone) | **0.066** | **13.9x** |

### Synthetic panel (100,000 units x 8 periods, 800k obs)

| Implementation | Median (s) | Speedup |
|---------------|-----------|---------|
| Stata native `csdid` | 276.9 | 1x |
| **CSDid.jl** (standalone) | **20.4** | **13.6x** |

*Stata: StataMP-64 v17.0 (64-core license). Julia: v1.12.6.*
*Machine: Windows, details in benchmark scripts.*

## Stata Wrapper

```stata
* Install julia.ado first: ssc install julia
* Then use csdid_jl like native csdid:

* Basic usage
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal)
csdid_jl lemp lpop, tname(year) gname(firsttreat) idname(countyreal) aggregate(event)

* With sampling weights
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) weights(pop)

* With clustered SEs
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) cluster(state)

* Universal base period
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) base_period(universal)

* Repeated cross-sections
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) nopanel

* Time-varying weights
csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) weights(wt) fix_weights(base_period)
```

## Test Suite

```bash
julia test/runtests.jl
```

145 tests covering: data loading, ATT(g,t) estimation (DR/IPW/Reg),
aggregation (dynamic/group/simple/calendar), covariates, not-yet-treated
control group, sampling weights, clustered SEs, repeated cross-sections,
universal base period, categorical covariates, and unbalanced panel detection.

## References

- Callaway, B. and Sant'Anna, P.H.C. (2021). "Difference-in-Differences with
  Multiple Time Periods." *Journal of Econometrics*, 225(2), 200-230.
- Sant'Anna, P.H.C. and Zhao, J. (2020). "Doubly Robust Difference-in-Differences
  Estimators." *Journal of Econometrics*, 219(1), 101-122.
