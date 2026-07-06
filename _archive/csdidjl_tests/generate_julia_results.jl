# ═══════════════════════════════════════════════════════════════
#  Generate Julia CSDid.jl results
#  Section A: test_r_parity scenarios (from csdid Python repo)
#  Section B: 12-scenario coverage grid
#  Output: julia_results.csv, julia_aggte_results_full.csv
# ═══════════════════════════════════════════════════════════════

include(joinpath(@__DIR__, "src", "CSDid.jl"))
using .CSDid
using DataFrames, CSV, Printf

println("Julia version: ", VERSION)
println("CSDid.jl loaded\n")

# --- Load datasets ---
df_mpdta = mpdta()
println("Dataset: mpdta  (", nrow(df_mpdta), " obs, ",
        length(unique(df_mpdta.countyreal)), " units, ",
        length(unique(df_mpdta.year)), " periods)")

df_sim = CSV.read(joinpath(@__DIR__, "data", "sim_data.csv"), DataFrame)
println("Dataset: sim_data  (", nrow(df_sim), " obs, ",
        length(unique(df_sim.id)), " units, ",
        length(unique(df_sim.period)), " periods)")

df_extra = CSV.read(joinpath(@__DIR__, "data", "mpdta_extra.csv"), DataFrame)
# R uses "first.treat", normalize to Julia convention
if "first.treat" in names(df_extra)
    rename!(df_extra, "first.treat" => "first_treat")
end
println("Dataset: mpdta_extra  (", nrow(df_extra), " obs, ",
        length(unique(df_extra.countyreal)), " units, ",
        length(unique(df_extra.year)), " periods)")

df_tvw = CSV.read(joinpath(@__DIR__, "data", "mpdta_tvw.csv"), DataFrame)
if "first.treat" in names(df_tvw)
    rename!(df_tvw, "first.treat" => "first_treat")
end
println("Dataset: mpdta_tvw  (", nrow(df_tvw), " obs, ",
        length(unique(df_tvw.countyreal)), " units, ",
        length(unique(df_tvw.year)), " periods)")

df_factor = CSV.read(joinpath(@__DIR__, "data", "factor_cov.csv"), DataFrame)
println("Dataset: factor_cov  (", nrow(df_factor), " obs, ",
        length(unique(df_factor.id)), " units, ",
        length(unique(df_factor.period)), " periods)")

# Load 6 sim datasets
sim_datasets = Dict{String, DataFrame}()
for dsname in ["tp2_const", "tp4_const", "tp4_dyn", "tp5_dyn", "tp8_dyn", "tp10_const"]
    sim_datasets[dsname] = CSV.read(joinpath(@__DIR__, "data", "$dsname.csv"), DataFrame)
    d = sim_datasets[dsname]
    println("Dataset: $dsname  (", nrow(d), " obs, ",
            length(unique(d.id)), " units, ",
            length(unique(d.period)), " periods)")
end
println()

# Scenario struct: (name, label, kwargs_dict)
# kwargs_dict contains ALL keyword arguments for att_gt
scenarios = [
    # --- Section A: test_r_parity scenarios (repo test suite) ---
    ("mpdta_nev_dr",      "REPO: mpdta DR nevertreated nocov",
     Dict(:data=>df_mpdta, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"dr", :control_group=>"nevertreated",
          :bstrap=>false)),
    ("mpdta_nyt_dr",      "REPO: mpdta DR notyettreated nocov",
     Dict(:data=>df_mpdta, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"dr", :control_group=>"notyettreated",
          :bstrap=>false)),
    ("mpdta_nev_reg_cov", "REPO: mpdta Reg nevertreated lpop",
     Dict(:data=>df_mpdta, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"reg", :control_group=>"nevertreated",
          :xformla=>[:lpop], :bstrap=>false)),
    ("mpdta_nev_ipw",     "REPO: mpdta IPW nevertreated nocov",
     Dict(:data=>df_mpdta, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"ipw", :control_group=>"nevertreated",
          :bstrap=>false)),
    ("sim_nev_dr",        "REPO: sim_data DR nevertreated X",
     Dict(:data=>df_sim, :yname=>"Y", :tname=>"period", :idname=>"id",
          :gname=>"G", :est_method=>"dr", :control_group=>"nevertreated",
          :xformla=>[:X], :bstrap=>false)),

    # --- Section C: gap scenarios (test_r_parity advanced) ---
    ("universal",         "GAP: universal base period",
     Dict(:data=>df_extra, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"reg", :control_group=>"nevertreated",
          :base_period=>"universal", :bstrap=>false)),
    ("weighted",          "GAP: sampling weights",
     Dict(:data=>df_extra, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"reg", :control_group=>"nevertreated",
          :weights_name=>"wt", :bstrap=>false)),
    ("fix_weights_none",  "FIX_WEIGHTS: none (time-varying wt, default bp)",
     Dict(:data=>df_tvw, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"reg", :control_group=>"nevertreated",
          :weights_name=>"wt", :bstrap=>false)),
    ("fix_weights_base",  "FIX_WEIGHTS: base_period",
     Dict(:data=>df_tvw, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"reg", :control_group=>"nevertreated",
          :weights_name=>"wt", :fix_weights=>"base_period", :bstrap=>false)),
    ("fix_weights_first", "FIX_WEIGHTS: first_period",
     Dict(:data=>df_tvw, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"reg", :control_group=>"nevertreated",
          :weights_name=>"wt", :fix_weights=>"first_period", :bstrap=>false)),
    ("clustered",         "GAP: clustered SEs",
     Dict(:data=>df_extra, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"reg", :control_group=>"nevertreated",
          :clustervar=>"clust", :bstrap=>false)),
    ("anticipation1",     "GAP: anticipation=1",
     Dict(:data=>df_extra, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"reg", :control_group=>"nevertreated",
          :anticipation=>1, :bstrap=>false)),
    ("factor_cov",        "FACTOR: categorical covariate C(cat)",
     Dict(:data=>df_factor, :yname=>"Y", :tname=>"period", :idname=>"id",
          :gname=>"G", :est_method=>"reg", :control_group=>"nevertreated",
          :xformla=>["C(cat)"], :bstrap=>false)),
    ("rc",                "GAP: repeated cross-sections (panel=false)",
     Dict(:data=>df_extra, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"reg", :control_group=>"nevertreated",
          :panel=>false, :bstrap=>false)),
    ("fix_weights_varying", "FIX_WEIGHTS: varying (RC path)",
     Dict(:data=>df_tvw, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"reg", :control_group=>"nevertreated",
          :weights_name=>"wt", :fix_weights=>"varying", :bstrap=>false)),

    # --- Section D: 24 sim dataset scenarios ---
    # 6 datasets × 2 control groups × 2 methods (dr, reg)
    [("sim_$(dsname)_$(cg)_$(est)",
      "SIM: $dsname $est $cg X",
      Dict(:data=>sim_datasets[dsname], :yname=>"Y", :tname=>"period", :idname=>"id",
           :gname=>"G", :est_method=>est, :control_group=>cg,
           :xformla=>[:X], :bstrap=>false))
     for dsname in ["tp2_const", "tp4_const", "tp4_dyn", "tp5_dyn", "tp8_dyn", "tp10_const"]
     for cg in ["nevertreated", "notyettreated"]
     for est in ["dr", "reg"]]...,

    # --- Section B: 12-scenario coverage grid ---
    ("dr_nev_nocov",  "GRID: DR nevertreated nocov",
     Dict(:data=>df_mpdta, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"dr", :control_group=>"nevertreated",
          :bstrap=>false)),
    ("ipw_nev_nocov", "GRID: IPW nevertreated nocov",
     Dict(:data=>df_mpdta, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"ipw", :control_group=>"nevertreated",
          :bstrap=>false)),
    ("reg_nev_nocov", "GRID: REG nevertreated nocov",
     Dict(:data=>df_mpdta, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"reg", :control_group=>"nevertreated",
          :bstrap=>false)),
    ("dr_nyt_nocov",  "GRID: DR notyettreated nocov",
     Dict(:data=>df_mpdta, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"dr", :control_group=>"notyettreated",
          :bstrap=>false)),
    ("ipw_nyt_nocov", "GRID: IPW notyettreated nocov",
     Dict(:data=>df_mpdta, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"ipw", :control_group=>"notyettreated",
          :bstrap=>false)),
    ("reg_nyt_nocov", "GRID: REG notyettreated nocov",
     Dict(:data=>df_mpdta, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"reg", :control_group=>"notyettreated",
          :bstrap=>false)),
    ("dr_nev_cov",    "GRID: DR nevertreated lpop",
     Dict(:data=>df_mpdta, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"dr", :control_group=>"nevertreated",
          :xformla=>[:lpop], :bstrap=>false)),
    ("ipw_nev_cov",   "GRID: IPW nevertreated lpop",
     Dict(:data=>df_mpdta, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"ipw", :control_group=>"nevertreated",
          :xformla=>[:lpop], :bstrap=>false)),
    ("reg_nev_cov",   "GRID: REG nevertreated lpop",
     Dict(:data=>df_mpdta, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"reg", :control_group=>"nevertreated",
          :xformla=>[:lpop], :bstrap=>false)),
    ("dr_nyt_cov",    "GRID: DR notyettreated lpop",
     Dict(:data=>df_mpdta, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"dr", :control_group=>"notyettreated",
          :xformla=>[:lpop], :bstrap=>false)),
    ("ipw_nyt_cov",   "GRID: IPW notyettreated lpop",
     Dict(:data=>df_mpdta, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"ipw", :control_group=>"notyettreated",
          :xformla=>[:lpop], :bstrap=>false)),
    ("reg_nyt_cov",   "GRID: REG notyettreated lpop",
     Dict(:data=>df_mpdta, :yname=>"lemp", :tname=>"year", :idname=>"countyreal",
          :gname=>"first_treat", :est_method=>"reg", :control_group=>"notyettreated",
          :xformla=>[:lpop], :bstrap=>false)),
]

attgt_rows = NamedTuple[]
aggte_rows = NamedTuple[]

for (name, label, kwargs) in scenarios
    println(repeat("=", 70))
    println("=== SCENARIO: $name ===")
    println("    $label")
    println(repeat("=", 70))

    try
        result = att_gt(; kwargs...)

        for i in eachindex(result.group)
            g, t = result.group[i], result.t[i]
            a, s = result.att[i], result.se[i]
            push!(attgt_rows, (scenario=name, group=g, t=t, att=a, se=s))
            if isnan(s)
                @Printf.printf("  ATT(g=%d, t=%d) = %20.15f  SE = NaN\n", g, t, a)
            else
                @Printf.printf("  ATT(g=%d, t=%d) = %20.15f  SE = %20.15f\n", g, t, a, s)
            end
        end

        for atype in ["simple", "dynamic", "group", "calendar"]
            try
                agg = aggte(result, type=atype)
                push!(aggte_rows, (scenario=name, agg_type=atype,
                    egt=missing, att_egt=missing, se_egt=missing,
                    overall_att=agg.overall_att, overall_se=agg.overall_se))
                @Printf.printf("  aggte(%s): overall_att = %20.15f  SE = %20.15f\n",
                    atype, agg.overall_att, agg.overall_se)

                if atype != "simple"
                    for j in eachindex(agg.egt)
                        push!(aggte_rows, (scenario=name, agg_type=atype,
                            egt=agg.egt[j], att_egt=agg.att_egt[j],
                            se_egt=agg.se_egt[j],
                            overall_att=agg.overall_att, overall_se=agg.overall_se))
                    end
                end
            catch ex
                @Printf.printf("  aggte(%s): ERROR - %s\n", atype, ex)
            end
        end
    catch ex
        println("  SCENARIO FAILED: $ex")
        for (name2, msg) in Base.catch_stack()
            println("    ", msg)
        end
    end
    println()
end

CSV.write(joinpath(@__DIR__, "julia_results.csv"), DataFrame(attgt_rows))
CSV.write(joinpath(@__DIR__, "julia_aggte_results_full.csv"), DataFrame(aggte_rows))

println(repeat("=", 70))
println("DONE: Saved $(length(attgt_rows)) ATT(g,t) rows to julia_results.csv")
println("DONE: Saved $(length(aggte_rows)) aggregation rows to julia_aggte_results_full.csv")
println(repeat("=", 70))
