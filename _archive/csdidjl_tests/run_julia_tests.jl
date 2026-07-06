# Run all CSDid.jl test scenarios and export results to CSV for comparison
using DelimitedFiles

include(joinpath(@__DIR__, "src", "CSDid.jl"))
using .CSDid
using DataFrames, CSV

df = mpdta()
println("Loaded mpdta: $(nrow(df)) rows, $(ncol(df)) cols")
println("Groups: ", sort(unique(df.first_treat)))

# Output arrays
attgt_rows = []
aggte_rows = []

# Define scenarios matching the Python test suite
scenarios = [
    ("mpdta_nev_dr",      "dr",  "nevertreated",   nothing,                       "DR, nevertreated, no covariates"),
    ("mpdta_nev_ipw",     "ipw", "nevertreated",   nothing,                       "IPW, nevertreated, no covariates"),
    ("mpdta_nev_reg",     "reg", "nevertreated",   nothing,                       "Reg, nevertreated, no covariates"),
    ("mpdta_nyt_dr",      "dr",  "notyettreated",  nothing,                       "DR, notyettreated, no covariates"),
    ("mpdta_nyt_ipw",     "ipw", "notyettreated",  nothing,                       "IPW, notyettreated, no covariates"),
    ("mpdta_nyt_reg",     "reg", "notyettreated",  nothing,                       "Reg, notyettreated, no covariates"),
    ("mpdta_nev_dr_cov",  "dr",  "nevertreated",   [:lpop],                       "DR, nevertreated, covariates (lpop)"),
    ("mpdta_nev_ipw_cov", "ipw", "nevertreated",   [:lpop],                       "IPW, nevertreated, covariates (lpop)"),
    ("mpdta_nev_reg_cov", "reg", "nevertreated",   [:lpop],                       "Reg, nevertreated, covariates (lpop)"),
    ("mpdta_nyt_dr_cov",  "dr",  "notyettreated",  [:lpop],                       "DR, notyettreated, covariates (lpop)"),
    ("mpdta_nyt_ipw_cov", "ipw", "notyettreated",  [:lpop],                       "IPW, notyettreated, covariates (lpop)"),
    ("mpdta_nyt_reg_cov", "reg", "notyettreated",  [:lpop],                       "Reg, notyettreated, covariates (lpop)"),
]

for (scn_name, est, cg, xf, label) in scenarios
    println("\n", "="^60)
    println("Running: $scn_name ($label)")
    println("="^60)

    try
        result = att_gt(
            yname  = "lemp",
            tname  = "year",
            idname = "countyreal",
            gname  = "first_treat",
            data   = df,
            est_method    = est,
            control_group = cg,
            base_period   = "varying",
            xformla       = xf,
            bstrap = true,
            biters = 1000,
            alp    = 0.05,
        )

        for i in eachindex(result.group)
            push!(attgt_rows, (
                scenario = scn_name,
                label    = label,
                group    = result.group[i],
                t        = result.t[i],
                att      = result.att[i],
                se       = result.se[i],
            ))
            println("  ATT(g=$(result.group[i]), t=$(result.t[i])) = $(round(result.att[i], digits=10))  (SE=$(round(result.se[i], digits=10)))")
        end

        # Run aggregations
        for agg_type in ["simple", "dynamic", "group", "calendar"]
            try
                agg = aggte(result, type=agg_type)
                push!(aggte_rows, (
                    scenario    = scn_name,
                    label       = label,
                    agg_type    = agg_type,
                    egt         = missing,
                    att_egt     = missing,
                    se_egt      = missing,
                    overall_att = agg.overall_att,
                    overall_se  = agg.overall_se,
                ))
                println("  Aggte($agg_type): overall_att=$(round(agg.overall_att, digits=10)), overall_se=$(round(agg.overall_se, digits=10))")

                if agg_type != "simple"
                    for j in eachindex(agg.egt)
                        push!(aggte_rows, (
                            scenario    = scn_name,
                            label       = label,
                            agg_type    = agg_type,
                            egt         = agg.egt[j],
                            att_egt     = agg.att_egt[j],
                            se_egt      = agg.se_egt[j],
                            overall_att = agg.overall_att,
                            overall_se  = agg.overall_se,
                        ))
                        println("    egt=$(agg.egt[j]): att=$(round(agg.att_egt[j], digits=10)), se=$(round(agg.se_egt[j], digits=10))")
                    end
                end
            catch ex
                println("  Aggte($agg_type): FAILED - $ex")
            end
        end
    catch ex
        println("  FAILED: $ex")
        for (exc, bt) in Base.catch_stack()
            showerror(stdout, exc, bt)
            println()
        end
    end
end

# Save to CSV
df_attgt = DataFrame(attgt_rows)
df_aggte = DataFrame(aggte_rows)

CSV.write(joinpath(@__DIR__, "julia_attgt_results.csv"), df_attgt)
CSV.write(joinpath(@__DIR__, "julia_aggte_results.csv"), df_aggte)

println("\n\nSaved $(nrow(df_attgt)) ATT(g,t) results and $(nrow(df_aggte)) aggregation results")
println("Files: julia_attgt_results.csv, julia_aggte_results.csv")
