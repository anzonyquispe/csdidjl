# ═══════════════════════════════════════════════════════════════
#  Generate Julia CSDid.jl results for JEL replication tests
#  Matches test_jel_replication.py scenarios exactly
#  Output: julia_jel_results.csv
# ═══════════════════════════════════════════════════════════════

include(joinpath(@__DIR__, "src", "CSDid.jl"))
using .CSDid
using DataFrames, CSV, Printf, Statistics

println("Julia version: ", VERSION)
println("CSDid.jl loaded\n")

# ── Load and prepare data (matches Python _load_jel_data) ──────

function load_jel_data(path; filter_2xt=true)
    df = CSV.read(path, DataFrame; types=Dict(:county => String), missingstring=["NA", ""])

    # state = last 2 chars of county
    df.state = [c[end-1:end] for c in df.county]

    # exclude DC, DE, MA, NY, VT
    df = df[.!in.(df.state, Ref(Set(["DC", "DE", "MA", "NY", "VT"]))), :]

    if filter_2xt
        # keep only yaca==2014 or missing or >2019
        df = df[(coalesce.(df.yaca .== 2014, false)) .|
                ismissing.(df.yaca) .|
                (coalesce.(df.yaca .> 2019, false)), :]
    end

    # derived columns
    df.perc_white = df.population_20_64_white ./ df.population_20_64 .* 100
    df.perc_hispanic = df.population_20_64_hispanic ./ df.population_20_64 .* 100
    df.perc_female = df.population_20_64_female ./ df.population_20_64 .* 100
    df.unemp_rate = df.unemp_rate .* 100
    df.median_income = df.median_income ./ 1000

    # keep columns
    keep = [:county_code, :year, :population_20_64, :yaca, :crude_rate_20_64,
            :perc_female, :perc_white, :perc_hispanic, :unemp_rate, :poverty_rate,
            :median_income]
    df = df[:, keep]

    # drop rows with missing in non-yaca columns
    non_yaca = setdiff(keep, [:yaca])
    df = df[completecases(df[:, non_yaca]), :]

    # keep only counties with both 2013 and 2014
    both = combine(groupby(df[in.(df.year, Ref(Set([2013, 2014]))), :], :county_code), nrow)
    valid = both[both.nrow .== 2, :county_code]
    df = df[in.(df.county_code, Ref(Set(valid))), :]

    # keep only counties with full panel (11 periods)
    full = combine(groupby(df, :county_code), nrow)
    valid2 = full[full.nrow .== 11, :county_code]
    df = df[in.(df.county_code, Ref(Set(valid2))), :]

    return df
end

data_path = joinpath(@__DIR__, "data", "county_mortality_data.csv")
println("Loading JEL data...")
mydata_2xt = load_jel_data(data_path; filter_2xt=true)
mydata_gxt = load_jel_data(data_path; filter_2xt=false)
println("  2xT data: ", nrow(mydata_2xt), " obs, ",
        length(unique(mydata_2xt.county_code)), " units")
println("  GxT data: ", nrow(mydata_gxt), " obs, ",
        length(unique(mydata_gxt.county_code)), " units")

# ── Prepare 2xT data ──────────────────────────────────────────

# treat_year for 2xT: 2014 if yaca==2014, else 0
mydata_2xt.treat_year = [ismissing(y) ? 0 : (y == 2014 ? 2014 : 0) for y in mydata_2xt.yaca]
mydata_2xt.county_code = Float64.(mydata_2xt.county_code)

# 2x2 subset (only 2013, 2014)
short_2x2 = mydata_2xt[in.(mydata_2xt.year, Ref(Set([2013, 2014]))), :]
# weights from 2013
wt_df = short_2x2[short_2x2.year .== 2013, [:county_code, :population_20_64]]
rename!(wt_df, :population_20_64 => :set_wt)
short_2x2 = innerjoin(short_2x2, wt_df, on=:county_code)

# 2xT full panel with weights
wt_df2 = mydata_2xt[mydata_2xt.year .== 2013, [:county_code, :population_20_64]]
rename!(wt_df2, :population_20_64 => :set_wt)
mydata_2xt = innerjoin(mydata_2xt, wt_df2, on=:county_code)

# ── Prepare GxT data ──────────────────────────────────────────

# treat_year for GxT: yaca if <= 2019, else 0
mydata_gxt.treat_year = [ismissing(y) ? 0 : (y <= 2019 ? Int(y) : 0) for y in mydata_gxt.yaca]
mydata_gxt.county_code = Float64.(mydata_gxt.county_code)

wt_df3 = mydata_gxt[mydata_gxt.year .== 2013, [:county_code, :population_20_64]]
rename!(wt_df3, :population_20_64 => :set_wt)
mydata_gxt = innerjoin(mydata_gxt, wt_df3, on=:county_code)

# ── Covariate list ─────────────────────────────────────────────
covs = [:perc_female, :perc_white, :perc_hispanic, :unemp_rate, :poverty_rate, :median_income]

# ── Scenarios ──────────────────────────────────────────────────
attgt_rows = NamedTuple[]
aggte_rows = NamedTuple[]

println("\n", "=" ^ 70)
println("JEL SCENARIO 1: Table 7 — 2x2 CS-DiD")
println("=" ^ 70)

for (method, wt_name) in [("reg", nothing), ("ipw", nothing), ("dr", nothing),
                           ("reg", "set_wt"), ("ipw", "set_wt"), ("dr", "set_wt")]
    label = "table7_$(method)_$(isnothing(wt_name) ? "unwt" : "wt")"
    println("  Running: $label")
    result = att_gt(yname="crude_rate_20_64", tname="year", idname="county_code",
                    gname="treat_year", data=short_2x2, est_method=method,
                    control_group="nevertreated", base_period="universal",
                    xformla=covs, weights_name=wt_name, bstrap=false)
    agg = aggte(result, type="simple")
    @Printf.printf("    overall_att = %12.6f\n", agg.overall_att)

    for i in eachindex(result.group)
        push!(attgt_rows, (scenario=label, group=result.group[i], t=result.t[i],
                           att=result.att[i], se=result.se[i]))
    end
    push!(aggte_rows, (scenario=label, agg_type="simple",
                       egt=missing, att_egt=missing, se_egt=missing,
                       overall_att=agg.overall_att, overall_se=agg.overall_se))
end

println("\n", "=" ^ 70)
println("JEL SCENARIO 2: 2xT Event Study (no covs, weighted)")
println("=" ^ 70)

result_2xt = att_gt(yname="crude_rate_20_64", tname="year", idname="county_code",
                    gname="treat_year", data=mydata_2xt, est_method="reg",
                    control_group="nevertreated", base_period="universal",
                    weights_name="set_wt", bstrap=false)

for i in eachindex(result_2xt.group)
    g, t, a = result_2xt.group[i], result_2xt.t[i], result_2xt.att[i]
    se_val = result_2xt.se[i]
    push!(attgt_rows, (scenario="2xt_event", group=g, t=t, att=a, se=se_val))
    if isnan(se_val)
        @Printf.printf("  ATT(g=%d, t=%d) = %12.6f  SE = NaN\n", g, t, a)
    else
        @Printf.printf("  ATT(g=%d, t=%d) = %12.6f  SE = %12.6f\n", g, t, a, se_val)
    end
end

agg_dyn = aggte(result_2xt, type="dynamic")
push!(aggte_rows, (scenario="2xt_event", agg_type="dynamic",
                   egt=missing, att_egt=missing, se_egt=missing,
                   overall_att=agg_dyn.overall_att, overall_se=agg_dyn.overall_se))
for j in eachindex(agg_dyn.egt)
    push!(aggte_rows, (scenario="2xt_event", agg_type="dynamic",
                       egt=agg_dyn.egt[j], att_egt=agg_dyn.att_egt[j],
                       se_egt=agg_dyn.se_egt[j],
                       overall_att=agg_dyn.overall_att, overall_se=agg_dyn.overall_se))
end

# min_e=0, max_e=5
agg_dyn_05 = aggte(result_2xt, type="dynamic", min_e=0, max_e=5)
@Printf.printf("  Dynamic (e in 0..5) overall: %12.6f\n", agg_dyn_05.overall_att)

println("\n", "=" ^ 70)
println("JEL SCENARIO 3: 2xT with covariates (reg/ipw/dr)")
println("=" ^ 70)

for method in ["reg", "ipw", "dr"]
    label = "2xt_cov_$(method)"
    println("  Running: $label")
    result = att_gt(yname="crude_rate_20_64", tname="year", idname="county_code",
                    gname="treat_year", data=mydata_2xt, est_method=method,
                    control_group="nevertreated", base_period="universal",
                    xformla=covs, weights_name="set_wt", bstrap=false)
    agg = aggte(result, type="dynamic")

    for i in eachindex(result.group)
        push!(attgt_rows, (scenario=label, group=result.group[i], t=result.t[i],
                           att=result.att[i], se=result.se[i]))
    end
    for j in eachindex(agg.egt)
        push!(aggte_rows, (scenario=label, agg_type="dynamic",
                           egt=agg.egt[j], att_egt=agg.att_egt[j],
                           se_egt=agg.se_egt[j],
                           overall_att=agg.overall_att, overall_se=agg.overall_se))
    end
    @Printf.printf("    dynamic overall: %12.6f\n", agg.overall_att)
end

println("\n", "=" ^ 70)
println("JEL SCENARIO 4: GxT no covariates (reg, nyt, weighted)")
println("=" ^ 70)

result_gxt = att_gt(yname="crude_rate_20_64", tname="year", idname="county_code",
                    gname="treat_year", data=mydata_gxt, est_method="reg",
                    control_group="notyettreated", base_period="universal",
                    weights_name="set_wt", bstrap=false)

for i in eachindex(result_gxt.group)
    push!(attgt_rows, (scenario="gxt_nocov", group=result_gxt.group[i],
                       t=result_gxt.t[i], att=result_gxt.att[i], se=result_gxt.se[i]))
end

agg_gxt_simple = aggte(result_gxt, type="simple")
push!(aggte_rows, (scenario="gxt_nocov", agg_type="simple",
                   egt=missing, att_egt=missing, se_egt=missing,
                   overall_att=agg_gxt_simple.overall_att, overall_se=agg_gxt_simple.overall_se))
@Printf.printf("  Simple overall: %12.6f\n", agg_gxt_simple.overall_att)

agg_gxt = aggte(result_gxt, type="dynamic")
for j in eachindex(agg_gxt.egt)
    push!(aggte_rows, (scenario="gxt_nocov", agg_type="dynamic",
                       egt=agg_gxt.egt[j], att_egt=agg_gxt.att_egt[j],
                       se_egt=agg_gxt.se_egt[j],
                       overall_att=agg_gxt.overall_att, overall_se=agg_gxt.overall_se))
    @Printf.printf("  e=%d: %12.6f\n", agg_gxt.egt[j], agg_gxt.att_egt[j])
end

agg_gxt_05 = aggte(result_gxt, type="dynamic", min_e=0, max_e=5)
push!(aggte_rows, (scenario="gxt_nocov_05", agg_type="dynamic",
                   egt=missing, att_egt=missing, se_egt=missing,
                   overall_att=agg_gxt_05.overall_att, overall_se=agg_gxt_05.overall_se))
@Printf.printf("  Dynamic (e in 0..5) overall: %12.6f\n", agg_gxt_05.overall_att)

println("\n", "=" ^ 70)
println("JEL SCENARIO 5: GxT DR with covariates (nyt, weighted)")
println("=" ^ 70)

result_gxt_dr = att_gt(yname="crude_rate_20_64", tname="year", idname="county_code",
                       gname="treat_year", data=mydata_gxt, est_method="dr",
                       control_group="notyettreated", base_period="universal",
                       xformla=covs, weights_name="set_wt", bstrap=false)

for i in eachindex(result_gxt_dr.group)
    push!(attgt_rows, (scenario="gxt_dr_cov", group=result_gxt_dr.group[i],
                       t=result_gxt_dr.t[i], att=result_gxt_dr.att[i], se=result_gxt_dr.se[i]))
end

agg_gxt_dr_simple = aggte(result_gxt_dr, type="simple")
push!(aggte_rows, (scenario="gxt_dr_cov", agg_type="simple",
                   egt=missing, att_egt=missing, se_egt=missing,
                   overall_att=agg_gxt_dr_simple.overall_att, overall_se=agg_gxt_dr_simple.overall_se))
@Printf.printf("  Simple overall: %12.6f\n", agg_gxt_dr_simple.overall_att)

agg_gxt_dr = aggte(result_gxt_dr, type="dynamic")
for j in eachindex(agg_gxt_dr.egt)
    push!(aggte_rows, (scenario="gxt_dr_cov", agg_type="dynamic",
                       egt=agg_gxt_dr.egt[j], att_egt=agg_gxt_dr.att_egt[j],
                       se_egt=agg_gxt_dr.se_egt[j],
                       overall_att=agg_gxt_dr.overall_att, overall_se=agg_gxt_dr.overall_se))
    @Printf.printf("  e=%d: %12.6f\n", agg_gxt_dr.egt[j], agg_gxt_dr.att_egt[j])
end

agg_gxt_dr_05 = aggte(result_gxt_dr, type="dynamic", min_e=0, max_e=5)
push!(aggte_rows, (scenario="gxt_dr_cov_05", agg_type="dynamic",
                   egt=missing, att_egt=missing, se_egt=missing,
                   overall_att=agg_gxt_dr_05.overall_att, overall_se=agg_gxt_dr_05.overall_se))
@Printf.printf("  Dynamic (e in 0..5) overall: %12.6f\n", agg_gxt_dr_05.overall_att)

# ── Save results ───────────────────────────────────────────────
CSV.write(joinpath(@__DIR__, "julia_jel_results.csv"), DataFrame(attgt_rows))
CSV.write(joinpath(@__DIR__, "julia_jel_aggte.csv"), DataFrame(aggte_rows))

println("\n", "=" ^ 70)
println("DONE: Saved ", length(attgt_rows), " ATT(g,t) rows to julia_jel_results.csv")
println("DONE: Saved ", length(aggte_rows), " aggregation rows to julia_jel_aggte.csv")
println("=" ^ 70)
