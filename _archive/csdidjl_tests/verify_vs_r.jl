# ═══════════════════════════════════════════════════════════════
#  Verify CSDid.jl against R reference CSVs (same as Python tests)
#  This is the Julia equivalent of the Python test suite
# ═══════════════════════════════════════════════════════════════

using DataFrames, CSV, Printf

# Paths
JULIA_RESULTS = joinpath(@__DIR__, "julia_results.csv")
JULIA_AGGTE   = joinpath(@__DIR__, "julia_aggte_results_full.csv")
JULIA_JEL     = joinpath(@__DIR__, "julia_jel_results.csv")
JULIA_JEL_AGG = joinpath(@__DIR__, "julia_jel_aggte.csv")

R_REF_DIR = raw"C:\Users\Usuario\csdid_python\csdid\test_csdid\r_ref"
R_ATTGT   = joinpath(R_REF_DIR, "ref_attgt.csv")
R_AGGTE   = joinpath(R_REF_DIR, "ref_aggte.csv")
R_GAPS    = joinpath(R_REF_DIR, "sim", "ref_gaps.csv")
R_FIX_WT  = joinpath(R_REF_DIR, "ref_fixweights.csv")
R_FACTOR  = joinpath(R_REF_DIR, "sim", "ref_factor.csv")
R_SIM     = joinpath(R_REF_DIR, "sim", "ref_sim.csv")

# Load Julia results
jl_attgt = CSV.read(JULIA_RESULTS, DataFrame)
jl_aggte = CSV.read(JULIA_AGGTE, DataFrame)
jl_jel   = CSV.read(JULIA_JEL, DataFrame)
jl_jel_agg = CSV.read(JULIA_JEL_AGG, DataFrame)

# Load R references
r_attgt  = CSV.read(R_ATTGT, DataFrame; missingstring=["NA","NaN",""])
r_aggte  = CSV.read(R_AGGTE, DataFrame; missingstring=["NA","NaN",""])
r_gaps   = CSV.read(R_GAPS, DataFrame; missingstring=["NA","NaN",""])
r_fixwt  = CSV.read(R_FIX_WT, DataFrame; missingstring=["NA","NaN",""])
r_factor = CSV.read(R_FACTOR, DataFrame; missingstring=["NA","NaN",""])
r_sim    = CSV.read(R_SIM, DataFrame; missingstring=["NA","NaN",""])

pass_count = 0
fail_count = 0
test_details = String[]

function check_test(name::String, pass::Bool, detail::String="")
    global pass_count, fail_count
    if pass
        pass_count += 1
        push!(test_details, "  PASS  $name" * (detail == "" ? "" : "  ($detail)"))
    else
        fail_count += 1
        push!(test_details, "  FAIL  $name" * (detail == "" ? "" : "  ($detail)"))
    end
end

# ── Scenario name mapping: Julia → R reference ──────────────
REPO_SCENARIOS = Dict(
    "mpdta_nev_dr"      => "mpdta_nev_dr",
    "mpdta_nyt_dr"      => "mpdta_nyt_dr",
    "mpdta_nev_reg_cov" => "mpdta_nev_reg_cov",
    "mpdta_nev_ipw"     => "mpdta_nev_ipw",
    "sim_nev_dr"        => "sim_nev_dr",
)

AGG_TYPES = ["group", "dynamic", "calendar"]

# ═══════════════════════════════════════════════════════════════
# TEST GROUP 1: test_attgt_matches_r (5 tests)
# ═══════════════════════════════════════════════════════════════
println("=" ^ 70)
println("TEST GROUP 1: test_attgt_matches_r (5 tests)")
println("=" ^ 70)

for (jl_name, r_name) in sort(collect(REPO_SCENARIOS))
    jl_sub = filter(row -> row.scenario == jl_name, jl_attgt)
    r_sub  = filter(row -> row.scenario == r_name, r_attgt)

    matched = true
    max_diff = 0.0
    for r_row in eachrow(r_sub)
        jl_row = filter(row -> row.group == r_row.group && row.t == r_row.t, jl_sub)
        if nrow(jl_row) == 0
            matched = false
            break
        end
        d = abs(jl_row.att[1] - r_row.att)
        max_diff = max(max_diff, d)
        if d > 1e-6
            matched = false
        end
    end
    check_test("test_attgt[$jl_name]", matched, @sprintf("max_diff=%.2e, %d cells", max_diff, nrow(r_sub)))
end

# ═══════════════════════════════════════════════════════════════
# TEST GROUP 2: test_aggte_overall_matches_r (5 tests)
# ═══════════════════════════════════════════════════════════════
println("\n" * "=" ^ 70)
println("TEST GROUP 2: test_aggte_overall_matches_r (5 tests)")
println("=" ^ 70)

for (jl_name, r_name) in sort(collect(REPO_SCENARIOS))
    r_sub = filter(row -> row.scenario == r_name, r_aggte)
    jl_sub = filter(row -> row.scenario == jl_name && ismissing(row.egt), jl_aggte)

    all_pass = true
    details = String[]
    for atype in ["simple", "dynamic", "group", "calendar"]
        r_row = filter(row -> row.type == atype, r_sub)
        jl_row = filter(row -> row.agg_type == atype, jl_sub)
        if nrow(r_row) > 0 && nrow(jl_row) > 0
            d = abs(jl_row.overall_att[1] - r_row.overall_att[1])
            if d > 1e-6
                all_pass = false
                push!(details, "$atype: diff=$(@sprintf("%.2e", d))")
            end
        end
    end
    check_test("test_aggte_overall[$jl_name]", all_pass, join(details, ", "))
end

# ═══════════════════════════════════════════════════════════════
# TEST GROUP 3: test_aggte_egt_matches_r (15 tests)
# ═══════════════════════════════════════════════════════════════
println("\n" * "=" ^ 70)
println("TEST GROUP 3: test_aggte_egt_matches_r (15 tests = 5 scenarios × 3 agg types)")
println("=" ^ 70)

for atype in AGG_TYPES
    for (jl_name, r_name) in sort(collect(REPO_SCENARIOS))
        r_sub = filter(row -> row.scenario == r_name && row.type == atype && !ismissing(row.egt), r_aggte)
        jl_sub = filter(row -> row.scenario == jl_name && row.agg_type == atype && !ismissing(row.egt), jl_aggte)

        all_pass = true
        max_diff = 0.0
        for r_row in eachrow(r_sub)
            jl_row = filter(row -> !ismissing(row.egt) && abs(Float64(row.egt) - Float64(r_row.egt)) < 0.5, jl_sub)
            if nrow(jl_row) > 0
                d = abs(jl_row.att_egt[1] - r_row.att_egt)
                max_diff = max(max_diff, d)
                if d > 1e-5
                    all_pass = false
                end
            else
                all_pass = false
            end
        end
        check_test("test_aggte_egt[$atype-$jl_name]", all_pass, @sprintf("max_diff=%.2e", max_diff))
    end
end

# ═══════════════════════════════════════════════════════════════
# TEST GROUP 4: test_gap_scenarios_match_r (5 tests)
# ═══════════════════════════════════════════════════════════════
println("\n" * "=" ^ 70)
println("TEST GROUP 4: test_gap_scenarios_match_r (5 tests)")
println("=" ^ 70)

GAP_SCENARIOS = ["rc", "universal", "anticipation1", "weighted", "clustered"]

for scn in GAP_SCENARIOS
    r_sub = filter(row -> row.scenario == scn, r_gaps)
    jl_sub = filter(row -> row.scenario == scn, jl_attgt)

    all_pass = true
    max_att_diff = 0.0
    max_se_diff = 0.0
    n_cells = 0

    for r_row in eachrow(r_sub)
        jl_row = filter(row -> row.group == r_row.group && row.t == r_row.t, jl_sub)
        if nrow(jl_row) == 0
            all_pass = false
            continue
        end
        n_cells += 1

        d_att = abs(jl_row.att[1] - r_row.att)
        max_att_diff = max(max_att_diff, d_att)
        if d_att > 1e-6
            all_pass = false
        end

        if !ismissing(r_row.se) && !isnan(r_row.se)
            d_se = abs(jl_row.se[1] - r_row.se)
            max_se_diff = max(max_se_diff, d_se)
            if d_se > 1e-4
                all_pass = false
            end
        end
    end
    check_test("test_gap[$scn]", all_pass,
        @sprintf("ATT max_diff=%.2e, SE max_diff=%.2e, %d/%d cells",
                 max_att_diff, max_se_diff, n_cells, nrow(r_sub)))
end

# ═══════════════════════════════════════════════════════════════
# TEST GROUP 5: test_fix_weights_matches_r (4 tests)
# ═══════════════════════════════════════════════════════════════
println("\n" * "=" ^ 70)
println("TEST GROUP 5: test_fix_weights_matches_r (4 tests)")
println("=" ^ 70)

FW_MAP = Dict(
    "none"         => "fix_weights_none",
    "base_period"  => "fix_weights_base",
    "first_period" => "fix_weights_first",
    "varying"      => "fix_weights_varying",
)

for tag in ["none", "base_period", "first_period", "varying"]
    r_sub = filter(row -> row.fix_weights == tag, r_fixwt)
    jl_name = FW_MAP[tag]
    jl_sub = filter(row -> row.scenario == jl_name, jl_attgt)

    all_pass = true
    max_att_diff = 0.0
    max_se_diff = 0.0
    n_cells = 0

    for r_row in eachrow(r_sub)
        jl_row = filter(row -> row.group == r_row.group && row.t == r_row.t, jl_sub)
        if nrow(jl_row) == 0
            all_pass = false
            continue
        end
        n_cells += 1

        d_att = abs(jl_row.att[1] - r_row.att)
        max_att_diff = max(max_att_diff, d_att)
        if d_att > 1e-6
            all_pass = false
        end

        d_se = abs(jl_row.se[1] - r_row.se)
        max_se_diff = max(max_se_diff, d_se)
        if d_se > 1e-4
            all_pass = false
        end
    end
    check_test("test_fix_weights[$tag]", all_pass,
        @sprintf("ATT max_diff=%.2e, SE max_diff=%.2e, %d/%d cells",
                 max_att_diff, max_se_diff, n_cells, nrow(r_sub)))
end

# ═══════════════════════════════════════════════════════════════
# TEST GROUP 6: test_factor_covariate_matches_r (2 tests)
# ═══════════════════════════════════════════════════════════════
println("\n" * "=" ^ 70)
println("TEST GROUP 6: test_factor_covariate_matches_r (2 tests)")
println("=" ^ 70)

# Julia scenario "factor_cov" should match ref_factor.csv
# Python tests both faster_mode=False and faster_mode=True — same R reference
jl_fac = filter(row -> row.scenario == "factor_cov", jl_attgt)

for faster_mode in [false, true]
    all_pass = true
    max_att_diff = 0.0
    max_se_diff = 0.0

    for r_row in eachrow(r_factor)
        jl_row = filter(row -> row.group == r_row.group && row.t == r_row.t, jl_fac)
        if nrow(jl_row) == 0
            all_pass = false
            continue
        end
        d_att = abs(jl_row.att[1] - r_row.att)
        max_att_diff = max(max_att_diff, d_att)
        if d_att > 1e-5
            all_pass = false
        end
        d_se = abs(jl_row.se[1] - r_row.se)
        max_se_diff = max(max_se_diff, d_se)
        if d_se > 5e-4
            all_pass = false
        end
    end
    check_test("test_factor_cov[$faster_mode]", all_pass,
        @sprintf("ATT max_diff=%.2e, SE max_diff=%.2e", max_att_diff, max_se_diff))
end

# ═══════════════════════════════════════════════════════════════
# TEST GROUP 7: test_sim_attgt_matches_r (24 tests)
# ═══════════════════════════════════════════════════════════════
println("\n" * "=" ^ 70)
println("TEST GROUP 7: test_sim_attgt_matches_r (24 tests)")
println("=" ^ 70)

# Build unique (dataset, control, est) combos from r_sim
sim_combos = unique(select(r_sim, [:dataset, :control, :est]))

for row in eachrow(sim_combos)
    ds, cg, est = row.dataset, row.control, row.est
    r_sub = filter(r -> r.dataset == ds && r.control == cg && r.est == est, r_sim)
    jl_name = "sim_$(ds)_$(cg)_$(est)"
    jl_sub = filter(j -> j.scenario == jl_name, jl_attgt)

    all_pass = true
    max_diff = 0.0
    n_match = 0

    for r_row in eachrow(r_sub)
        jl_row = filter(j -> j.group == r_row.group && j.t == r_row.t, jl_sub)
        if nrow(jl_row) == 0
            all_pass = false
            continue
        end
        n_match += 1
        d = abs(jl_row.att[1] - r_row.att)
        max_diff = max(max_diff, d)
        if d > 1e-6
            all_pass = false
        end
    end
    check_test("test_sim[$ds-$cg-$est]", all_pass,
        @sprintf("max_diff=%.2e, %d/%d", max_diff, n_match, nrow(r_sub)))
end

# ═══════════════════════════════════════════════════════════════
# TEST GROUP 8: test_jel_* (5 tests)
# ═══════════════════════════════════════════════════════════════
println("\n" * "=" ^ 70)
println("TEST GROUP 8: test_jel_* (5 tests)")
println("=" ^ 70)

# JEL results use different scenario naming
# julia_jel_results.csv has: table7_reg_unwt, table7_ipw_unwt, table7_dr_unwt,
#                             table7_reg_wt, table7_ipw_wt, table7_dr_wt
# julia_jel_aggte.csv has: 2xt_event, 2xt_cov_reg, 2xt_cov_ipw, 2xt_cov_dr,
#                           gxt_nocov, gxt_dr_cov

# Test 1: JEL Table 7 2x2
jel_t7_wt = filter(row -> occursin("table7_", row.scenario) && occursin("_wt", row.scenario) && !occursin("unwt", row.scenario), jl_jel_agg)
jel_t7_overall = filter(row -> ismissing(row.egt), jel_t7_wt)
expected_table7 = Dict("table7_reg_wt" => 2.7268, "table7_ipw_wt" => 2.5963, "table7_dr_wt" => 2.6274)
global t7_pass = nrow(jel_t7_overall) >= 3
for row in eachrow(jel_t7_overall)
    if haskey(expected_table7, row.scenario)
        d = abs(row.overall_att - expected_table7[row.scenario])
        if d > 0.05
            t7_pass = false
        end
    end
end
check_test("test_jel_table7_2x2", t7_pass, "$(nrow(jel_t7_overall)) method-weight combos")

# Test 2: JEL 2xT event study
jel_es = filter(row -> row.scenario == "2xt_event", jl_jel_agg)
jel_es_egt = filter(row -> !ismissing(row.egt), jel_es)
expected_es = Dict(-5.0 => 2.6685, -4.0 => 1.5784, -3.0 => 0.7475, -2.0 => 0.5821, -1.0 => 0.2274,
                   0.0 => 1.5462, 1.0 => 1.9817, 2.0 => 2.8364, 3.0 => 3.5697, 4.0 => 4.4193, 5.0 => 7.4683)
global es_pass = nrow(jel_es_egt) >= 11
for (e, exp_val) in expected_es
    jl_row = filter(row -> !ismissing(row.egt) && abs(Float64(row.egt) - e) < 0.5, jel_es_egt)
    if nrow(jl_row) > 0
        d = abs(jl_row.att_egt[1] - exp_val)
        if d > 0.05
            es_pass = false
        end
    else
        es_pass = false
    end
end
check_test("test_jel_2xt_event_study", es_pass, "$(nrow(jel_es_egt)) event-time coeffs")

# Test 3: JEL 2xT with covariates (tests reg, ipw, dr)
# Get unique scenarios with "2xt_cov_" prefix — get overall from first row of each
jel_cov_methods = String[]
for scn in ["2xt_cov_reg", "2xt_cov_ipw", "2xt_cov_dr"]
    sub = filter(row -> row.scenario == scn, jl_jel_agg)
    if nrow(sub) > 0
        push!(jel_cov_methods, scn)
    end
end
global t3_pass = length(jel_cov_methods) >= 3
check_test("test_jel_2xt_with_covariates", t3_pass, "$(length(jel_cov_methods)) methods")

# Test 4: JEL GxT no covs — Python checks dynamic(min_e=0,max_e=5) overall ≈ 0.0867675805
jel_gxt = filter(row -> row.scenario == "gxt_nocov_05", jl_jel_agg)
global t4_pass = nrow(jel_gxt) > 0
if t4_pass
    d = abs(jel_gxt.overall_att[1] - 0.0867675805)
    t4_pass = d < 0.01
end
check_test("test_jel_gxt_no_covs", t4_pass, nrow(jel_gxt) > 0 ? @sprintf("att=%.4f", jel_gxt.overall_att[1]) : "MISSING")

# Test 5: JEL GxT DR with covs — Python checks dynamic(min_e=0,max_e=5) overall ≈ -2.2469982988
jel_gxt_dr = filter(row -> row.scenario == "gxt_dr_cov_05", jl_jel_agg)
global t5_pass = nrow(jel_gxt_dr) > 0
if t5_pass
    d = abs(jel_gxt_dr.overall_att[1] - (-2.2469982988))
    t5_pass = d < 0.05
end
check_test("test_jel_gxt_dr_covs", t5_pass, nrow(jel_gxt_dr) > 0 ? @sprintf("att=%.4f", jel_gxt_dr.overall_att[1]) : "MISSING")

# ═══════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════
println("\n" * "=" ^ 70)
println("VERIFICATION RESULTS")
println("=" ^ 70)
for d in test_details
    println(d)
end
println("=" ^ 70)
println("TOTAL: $pass_count PASS, $fail_count FAIL out of $(pass_count + fail_count) tests")
if fail_count == 0
    println("ALL TESTS PASS ✓")
else
    println("SOME TESTS FAILED ✗")
end
println("=" ^ 70)
