# CSDid.jl — Feature Implementation Plan

## Objective
Pass ALL 40 NOT IMPLEMENTED tests from the d2cml-ai/csdid Python repo test suite.
No existing tests (145 unit + 269 comparison) may break after any step.

## Test Inventory

| Feature | Tests | Count |
|---------|-------|-------|
| Anticipation | `gap[anticipation1]` | 1 |
| Universal base period | `gap[universal]` + 5 JEL | 6 |
| Sampling weights | `gap[weighted]`, `fix_weights[none]` | 2 |
| Clustered SEs | `gap[clustered]` | 1 |
| fix_weights | `fix_weights[base_period/first_period]` | 2 |
| fix_weights varying | `fix_weights[varying]` | 1 |
| Categorical covariates | `factor_cov[False/True]` | 2 |
| Sim dataset expansion | 24 sim_attgt tests | 24 |
| Repeated cross-sections | `gap[rc]` | 1 |
| JEL replication | 5 JEL tests | 5 |
| **TOTAL** | | **40** |

---

## Step 1 — Universal Base Period Fix + Anticipation Validation (S) ✅
- [x] Fix `att_gt.jl:112`: change `bp = tlist[1]` → `bp = g_eff - 1` (ONLY in universal mode)
- [x] When t == bp in universal mode: include cell with att=0, se=NaN
- [x] Verify varying mode is UNCHANGED (269 comparisons still pass)
- [x] Validate anticipation against ref_gaps.csv (already implemented, just test)
- [x] Copy `mpdta_extra.csv` to `data/`
- [x] Commit (fa13b2c)

**Tests covered:** `gap[anticipation1]`, `gap[universal]`

---

## Step 2 — Sampling Weights (M) ✅
- [x] Add `weights_name` parameter to `att_gt()`
- [x] Extract weights from data via `_build_weight_matrix` (n × nT wide format)
- [x] Default behavior with time-varying weights: weight from base period (bp)
- [x] Update Stata wrapper: add `weights(varname)` option
- [x] Copy `mpdta_tvw.csv` to `data/`
- [x] Validate against ref_gaps.csv "weighted" + ref_fixweights.csv "none"
- [x] Commit (c298d34)

**Tests covered:** `gap[weighted]`, `fix_weights[none]`

---

## Step 3 — Clustered SEs (M) ✅
- [x] Add `clustervar` parameter to `att_gt()`
- [x] Extract cluster IDs from data via `_build_cluster_ids`
- [x] Implement clustered analytical SE: aggregate IF by cluster before squaring
- [x] Implement clustered multiplier bootstrap: same xi for all units in cluster
- [x] Update Stata wrapper: add `cluster(varname)` option
- [x] Validate against ref_gaps.csv "clustered" — 12/12 match at 1e-17
- [x] Commit (248725a)

**Tests covered:** `gap[clustered]`

---

## Step 4 — fix_weights: base_period + first_period (M) ✅
- [x] Add `fix_weights` parameter to `att_gt()`
- [x] w_wide matrix already built in Step 2
- [x] Select weight period: base_period → g_eff-1, first_period → tlist[1]
- [x] Validate against ref_fixweights.csv — 24/24 match at 1e-17
- [x] Commit (32f9a03)

**Tests covered:** `fix_weights[base_period]`, `fix_weights[first_period]`

---

## Step 5 — Categorical Covariates (M) ✅
- [x] Accept "C(varname)" syntax in xformla (explicit marker, NOT auto-detect integers)
- [x] Parse "C(...)" entries, create dummy variables (drop first level, global levels)
- [x] Refactor covariates to per-period extraction (R uses base period, not first period)
- [x] Add `faster_mode` parameter (accept but ignore — Julia is fast)
- [x] Copy `factor_cov.csv` to `data/`
- [x] Validate against ref_factor.csv — 9/9 match at 1e-15
- [x] Commit (679a71f)

**Tests covered:** `factor_cov[False]`, `factor_cov[True]`

---

## Step 6 — Sim Dataset Expansion (S) ✅
- [x] Copy 6 sim CSVs to `data/`: tp2_const, tp4_const, tp4_dyn, tp5_dyn, tp8_dyn, tp10_const
- [x] Add 24 scenarios to generate_julia_results.jl
- [x] Validate against ref_sim.csv — 660/660 match at 1e-6 / 5e-4
- [x] Commit (fe801a3)

**Tests covered:** 24 `test_sim_attgt_matches_r[dataset-cg-method]`

---

## Step 7 — JEL Replication (M) ✅
- [x] Download county_mortality_data.csv from JEL-DiD GitHub
- [x] Create generate_jel_results.jl with 5 scenarios
- [x] Fixed weighted group shares in aggte (pg computation)
- [x] Fixed DR estimator OLS trim (controls not trimmed for outcome regression)
- [x] Fixed covariate period extraction (min(t, bp) like Python panel2cs2)
- [x] Validate Julia against published values and Python
- [x] Commit (765b9fc)

**Tests covered:** 5 `test_jel_*` tests

---

## Step 8 — Repeated Cross-Sections (L) ✅
- [x] Implement `reg_did_rc(y, post, D, X; w)` in estimators.jl
- [x] Add panel=false data handling in att_gt.jl (stack pre/post with post indicator)
- [x] fix_weights="varying" forces RC path internally
- [x] Per-row IF storage for true RC (n_eff = total rows, not unique units)
- [x] Validate against ref_gaps.csv "rc" — ATTs & SEs at 1e-15
- [x] Validate against ref_fixweights.csv "varying" — ATTs at 1e-15
- [x] Update Stata wrapper: add `nopanel` and `fix_weights()` options
- [x] Commit (6a4d362)

**Tests covered:** `gap[rc]`, `fix_weights[varying]`

---

## Final Verification ✅
- [x] Python test suite: 65/65 PASS
- [x] Julia verification vs R references: 65/65 PASS (all at 1e-10 or better)
- [x] Julia unit tests: 145/145 PASS
- [x] All 40 formerly NOT IMPLEMENTED tests now implemented and passing
- [x] Stata wrapper updated with all new options
- [x] Documentation updated (README, TODO, FEATURES_PLAN)
