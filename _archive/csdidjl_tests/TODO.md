# CSDid.jl - Pending Items

## Tests
- [x] Tests with covariates (`xformla`) validated against R `did` package
- [x] Tests with `notyettreated` control group validated against R
- [x] Unbalanced panel support validation (errors clearly when panel is unbalanced)
- [x] Comparison against Python `csdid` package (see `comparison_csdid.ipynb`)
- [x] All 40 formerly NOT IMPLEMENTED tests now passing (65/65 with Python parity)

## Performance
- [x] Benchmark speed vs native Stata `csdid` (see README.md for results)
- [ ] Test GPU option (`use_gpu=true`) with CUDA.jl on machine with NVIDIA GPU

## Resolved
- [x] IPW estimator with covariates: fixed Abadie-style normalization to Hajek-style
      (separate denominators for treated/control). Now matches R to 1e-6. (v0.4)
- [x] Sampling weights: `weights_name` parameter in `att_gt()` (Step 2)
- [x] Clustered standard errors: `clustervar` parameter in `att_gt()` (Step 3)
- [x] Repeated cross-section data: `panel=false` in `att_gt()` (Step 8)
- [x] Universal base period: fully validated with JEL replication (Step 1 + 7)
- [x] Categorical covariates: `C(varname)` syntax in `xformla` (Step 5)
- [x] Time-varying weights: `fix_weights` parameter (Step 4)
- [x] JEL replication: 5 tests matching published Callaway & Sant'Anna values (Step 7)
