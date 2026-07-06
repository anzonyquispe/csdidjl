# CSDid.jl — Validation Package

This archive contains the full cross-implementation validation suite for
CSDid.jl, comparing results across **R** (`did` v2.5.0), **Python** (`csdid`),
**Julia** (CSDid.jl), and **Stata** (`csdid_jl`).

## Contents

| Path | Description |
|------|-------------|
| `comparison_csdid.ipynb` | Pre-executed validation notebook (65 tests, all PASS) |
| `build_notebook.py` | Script that generates the notebook from result CSVs |
| `data/` | All datasets (mpdta, sim, factor_cov, county_mortality, etc.) |
| `run_all_tests.do` | Stata script — generates `stata_results.csv` and `stata_aggte_results_full.csv` |
| `run_all_tests.R` | R script — generates `r_*.csv` files |
| `generate_julia_results.jl` | Julia script — generates `julia_results.csv` and `julia_aggte_results_full.csv` |
| `generate_jel_results.jl` | Julia script — generates JEL replication CSVs |
| `run_julia_tests.jl` | Runs Julia unit tests |
| `verify_vs_r.jl` | Quick Julia-vs-R comparison script |
| `r_*.csv` | R reference results |
| `julia_*.csv` | Julia results |
| `stata_*.csv` | Stata results |
| `*_all_tests.log` | Execution logs for each implementation |
| `FEATURES_PLAN.md` | Feature roadmap |
| `TODO.md` | Development notes |
| `README_TESTS.md` | This file |

## The Notebook (comparison_csdid.ipynb)

The notebook is shipped **pre-executed** — all 65 test outputs are visible
without re-running. Open it in VS Code, Jupyter, or any `.ipynb` viewer.

### Re-executing the notebook

To re-run the notebook you need:

1. **Python 3.10+** with `numpy` and `pandas`
2. A clone of the Python `csdid` package (provides the Python estimator and R reference CSVs):

```bash
git clone https://github.com/d2cml-ai/csdid  C:\csdid_python
```

3. Open the notebook, verify `CSDID_ROOT` in the Setup cell points to your
   clone, and run all cells.

If you get `TypeError: ATTgt.__init__() got an unexpected keyword argument
'fix_weights'`, your kernel is importing a stale `csdid` install. Restart the
kernel and ensure `CSDID_ROOT` is correct.

## Regenerating Results

### Stata

```stata
cd C:\path\to\csdidjl_tests
do run_all_tests.do
```

Requires: Stata 17+, the `jl` package (`ssc install julia`), and `csdidjl`
installed (from the main package ZIP).

### Julia

```bash
julia --project=<path_to_csdidjl_package> generate_julia_results.jl
julia --project=<path_to_csdidjl_package> generate_jel_results.jl
```

### R

```bash
Rscript run_all_tests.R
```

Requires: R 4.5+ with the `did` package (v2.5.0).

## Test Structure

| Section | Tests | Description |
|---------|-------|-------------|
| A. test_attgt_matches_r | 5 | ATT(g,t) point estimates and SEs |
| B. test_aggte_overall | 5 | Aggregation overall (simple/dynamic/group/calendar) |
| C. test_aggte_egt | 15 | Per-event/group/calendar aggregation |
| D. test_fix_weights | 4 | Time-varying weight scenarios |
| E. test_factor_covariate | 2 | Categorical covariate handling |
| F. test_gap_scenarios | 5 | RC, universal, anticipation, weighted, clustered |
| G. test_sim_attgt | 24 | 6 simulated datasets × 2 controls × 2 estimators |
| H. test_jel_replication | 5 | Replication of published results |
| **Total** | **65** | |

Tolerances: ATT < 1e-6, SE < 1e-4.
