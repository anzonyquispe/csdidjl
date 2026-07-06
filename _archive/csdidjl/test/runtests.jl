using Test
using DataFrames

# load CSDid from source
include(joinpath(@__DIR__, "..", "src", "CSDid.jl"))
using .CSDid

# ─────────────────────────────────────────────────────────────
#  Reference values from R:
#    library(did)
#    data(mpdta)
#    out <- att_gt(yname="lemp", gname="first.treat",
#                  idname="countyreal", tname="year",
#                  xformla=~1, data=mpdta)
# ─────────────────────────────────────────────────────────────

# Expected ATT(g,t) from R (rounded to 4 decimals)
const R_ATT = Dict(
    (2004, 2004) => -0.0105,
    (2004, 2005) => -0.0704,
    (2004, 2006) => -0.1373,
    (2004, 2007) => -0.1008,
    (2006, 2004) =>  0.0065,
    (2006, 2005) => -0.0028,
    (2006, 2006) => -0.0046,
    (2006, 2007) => -0.0412,
    (2007, 2004) =>  0.0305,
    (2007, 2005) => -0.0027,
    (2007, 2006) => -0.0311,
    (2007, 2007) => -0.0261,
)

# Expected dynamic aggregation from R
const R_DYN_ATT = Dict(
    -3 =>  0.0305,
    -2 => -0.0006,
    -1 => -0.0245,
     0 => -0.0199,
     1 => -0.0510,
     2 => -0.1373,
     3 => -0.1008,
)
const R_DYN_OVERALL = -0.0772

@testset "CSDid.jl" begin

    # ── Load data ──────────────────────────────────────────
    @testset "mpdta loading" begin
        df = mpdta()
        @test nrow(df) == 2500
        @test ncol(df) >= 5
        @test "lemp" in names(df)
        @test "first_treat" in names(df)
        @test length(unique(df.year)) == 5
        @test length(unique(df.countyreal)) == 500
    end

    df = mpdta()

    # ── ATT(g,t) — unconditional DR ───────────────────────
    @testset "att_gt (DR, no covariates)" begin
        result = att_gt(
            yname  = "lemp",
            tname  = "year",
            idname = "countyreal",
            gname  = "first_treat",
            data   = df,
            est_method    = "dr",
            control_group = "nevertreated",
            base_period   = "varying",
            bstrap = true,
            biters = 1000,
            alp    = 0.05,
        )

        @test length(result.group) == 12
        @test length(result.att) == 12

        println("\n--- ATT(g,t) results ---")
        for i in eachindex(result.group)
            g, t = result.group[i], result.t[i]
            a = result.att[i]
            s = result.se[i]
            ref = get(R_ATT, (g, t), NaN)
            diff = abs(a - ref)
            status = diff < 0.002 ? "✓" : "✗"
            println("  ATT($g,$t) = $(round(a, digits=4))  " *
                    "(R = $ref, diff = $(round(diff, digits=6)))  $status")
            @test diff < 0.002  # tolerance for point estimate
        end
    end

    # ── ATT(g,t) — IPW ────────────────────────────────────
    @testset "att_gt (IPW, no covariates)" begin
        result_ipw = att_gt(
            yname  = "lemp",
            tname  = "year",
            idname = "countyreal",
            gname  = "first_treat",
            data   = df,
            est_method = "ipw",
        )
        # Without covariates IPW = DR = Reg (simple DiD)
        result_dr = att_gt(
            yname  = "lemp",
            tname  = "year",
            idname = "countyreal",
            gname  = "first_treat",
            data   = df,
            est_method = "dr",
        )
        for i in eachindex(result_ipw.att)
            @test abs(result_ipw.att[i] - result_dr.att[i]) < 1e-8
        end
    end

    # ── ATT(g,t) — Reg ────────────────────────────────────
    @testset "att_gt (Reg, no covariates)" begin
        result_reg = att_gt(
            yname  = "lemp",
            tname  = "year",
            idname = "countyreal",
            gname  = "first_treat",
            data   = df,
            est_method = "reg",
        )
        result_dr = att_gt(
            yname  = "lemp",
            tname  = "year",
            idname = "countyreal",
            gname  = "first_treat",
            data   = df,
            est_method = "dr",
        )
        for i in eachindex(result_reg.att)
            @test abs(result_reg.att[i] - result_dr.att[i]) < 1e-8
        end
    end

    # ── Dynamic aggregation ───────────────────────────────
    @testset "aggte (dynamic)" begin
        result = att_gt(
            yname  = "lemp",
            tname  = "year",
            idname = "countyreal",
            gname  = "first_treat",
            data   = df,
        )
        dyn = aggte(result, type="dynamic")

        println("\n--- Dynamic aggregation ---")
        println("  Overall ATT = $(round(dyn.overall_att, digits=4))  " *
                "(R = $R_DYN_OVERALL)")
        @test abs(dyn.overall_att - R_DYN_OVERALL) < 0.005

        for i in eachindex(dyn.egt)
            e = Int(dyn.egt[i])
            ref = get(R_DYN_ATT, e, NaN)
            isnan(ref) && continue
            diff = abs(dyn.att_egt[i] - ref)
            println("  e=$e: $(round(dyn.att_egt[i], digits=4))  " *
                    "(R = $ref, diff = $(round(diff, digits=6)))")
            @test diff < 0.002
        end
    end

    # ── Group aggregation ─────────────────────────────────
    @testset "aggte (group)" begin
        result = att_gt(
            yname  = "lemp",
            tname  = "year",
            idname = "countyreal",
            gname  = "first_treat",
            data   = df,
        )
        grp = aggte(result, type="group")
        println("\n--- Group aggregation ---")
        println("  Overall ATT = $(round(grp.overall_att, digits=4))")
        @test length(grp.att_egt) == 3
        @test !isnan(grp.overall_att)
    end

    # ── Simple aggregation ────────────────────────────────
    @testset "aggte (simple)" begin
        result = att_gt(
            yname  = "lemp",
            tname  = "year",
            idname = "countyreal",
            gname  = "first_treat",
            data   = df,
        )
        s = aggte(result, type="simple")
        println("\n--- Simple aggregation ---")
        println("  Overall ATT = $(round(s.overall_att, digits=4))")
        @test !isnan(s.overall_att)
    end

    # ══════════════════════════════════════════════════════════
    #  Covariates validation (xformla=~lpop) against R did
    # ══════════════════════════════════════════════════════════

    # ── DR with covariates, nevertreated ─────────────────────
    @testset "att_gt (DR, covariates, nevertreated)" begin
        R_REF = Dict(
            (2004, 2004) => -0.0145296683111165,
            (2004, 2005) => -0.0764218817440482,
            (2004, 2006) => -0.1404483368202380,
            (2004, 2007) => -0.1069038981217290,
            (2006, 2004) => -0.0004721460884859,
            (2006, 2005) => -0.0062025245797964,
            (2006, 2006) =>  0.0009605737466988,
            (2006, 2007) => -0.0412938655881805,
            (2007, 2004) =>  0.0267277962037011,
            (2007, 2005) => -0.0045765707635256,
            (2007, 2006) => -0.0284474871975600,
            (2007, 2007) => -0.0287813610394872,
        )
        result = att_gt(
            yname="lemp", tname="year", idname="countyreal",
            gname="first_treat", data=df,
            est_method="dr", control_group="nevertreated",
            xformla=[:lpop], bstrap=false,
        )
        @test length(result.att) == 12
        for i in eachindex(result.group)
            g, t = result.group[i], result.t[i]
            ref = R_REF[(g, t)]
            @test abs(result.att[i] - ref) < 1e-6
        end
    end

    # ── Reg with covariates, nevertreated ────────────────────
    @testset "att_gt (Reg, covariates, nevertreated)" begin
        R_REF = Dict(
            (2004, 2004) => -0.0149112377903622,
            (2004, 2005) => -0.0769963229660537,
            (2004, 2006) => -0.1410801046285890,
            (2004, 2007) => -0.1075442746730470,
            (2006, 2004) => -0.0020660581184398,
            (2006, 2005) => -0.0069682830672705,
            (2006, 2006) =>  0.0007655250263964,
            (2006, 2007) => -0.0415356365293255,
            (2007, 2004) =>  0.0263658317469795,
            (2007, 2005) => -0.0047598353386691,
            (2007, 2006) => -0.0285021064138582,
            (2007, 2007) => -0.0287894881938249,
        )
        result = att_gt(
            yname="lemp", tname="year", idname="countyreal",
            gname="first_treat", data=df,
            est_method="reg", control_group="nevertreated",
            xformla=[:lpop], bstrap=false,
        )
        for i in eachindex(result.group)
            g, t = result.group[i], result.t[i]
            ref = R_REF[(g, t)]
            @test abs(result.att[i] - ref) < 1e-6
        end
    end

    # ── DR with covariates, notyettreated ────────────────────
    @testset "att_gt (DR, covariates, notyettreated)" begin
        R_REF = Dict(
            (2004, 2004) => -0.0211830534787591,
            (2004, 2005) => -0.0816031858556810,
            (2004, 2006) => -0.1381918226084280,
            (2004, 2007) => -0.1069038981217290,
            (2006, 2004) => -0.0074552361119483,
            (2006, 2005) => -0.0045633769933057,
            (2006, 2006) =>  0.0086606998677135,
            (2006, 2007) => -0.0412938655881805,
            (2007, 2004) =>  0.0269326529006586,
            (2007, 2005) => -0.0042009804699794,
            (2007, 2006) => -0.0284474871975600,
            (2007, 2007) => -0.0287813610394872,
        )
        result = att_gt(
            yname="lemp", tname="year", idname="countyreal",
            gname="first_treat", data=df,
            est_method="dr", control_group="notyettreated",
            xformla=[:lpop], bstrap=false,
        )
        for i in eachindex(result.group)
            g, t = result.group[i], result.t[i]
            ref = R_REF[(g, t)]
            @test abs(result.att[i] - ref) < 1e-6
        end
    end

    # ── Reg with covariates, notyettreated ───────────────────
    @testset "att_gt (Reg, covariates, notyettreated)" begin
        R_REF = Dict(
            (2004, 2004) => -0.0212480022225674,
            (2004, 2005) => -0.0818499992698798,
            (2004, 2006) => -0.1384690035246500,
            (2004, 2007) => -0.1075442746730470,
            (2006, 2004) => -0.0080820627626139,
            (2006, 2005) => -0.0062168590007064,
            (2006, 2006) =>  0.0093753999698969,
            (2006, 2007) => -0.0415356365293255,
            (2007, 2004) =>  0.0267182533263212,
            (2007, 2005) => -0.0042545917142429,
            (2007, 2006) => -0.0285021064138582,
            (2007, 2007) => -0.0287894881938249,
        )
        result = att_gt(
            yname="lemp", tname="year", idname="countyreal",
            gname="first_treat", data=df,
            est_method="reg", control_group="notyettreated",
            xformla=[:lpop], bstrap=false,
        )
        for i in eachindex(result.group)
            g, t = result.group[i], result.t[i]
            ref = R_REF[(g, t)]
            @test abs(result.att[i] - ref) < 1e-6
        end
    end

    # ── Notyettreated without covariates (all 3 methods) ─────
    @testset "att_gt (notyettreated, no covariates)" begin
        R_REF_NYT = Dict(
            (2004, 2004) => -0.0193723636759221,
            (2004, 2005) => -0.0783190990620607,
            (2004, 2006) => -0.1362743463286780,
            (2004, 2007) => -0.1008113630854040,
            (2006, 2004) => -0.0025625509426110,
            (2006, 2005) => -0.0019392460957888,
            (2006, 2006) =>  0.0046608763199762,
            (2006, 2007) => -0.0412244715462175,
            (2007, 2004) =>  0.0297593647610311,
            (2007, 2005) => -0.0024106128000969,
            (2007, 2006) => -0.0310871193896889,
            (2007, 2007) => -0.0260544107191966,
        )
        for em in ["dr", "ipw", "reg"]
            result = att_gt(
                yname="lemp", tname="year", idname="countyreal",
                gname="first_treat", data=df,
                est_method=em, control_group="notyettreated",
                bstrap=false,
            )
            for i in eachindex(result.group)
                g, t = result.group[i], result.t[i]
                ref = R_REF_NYT[(g, t)]
                @test abs(result.att[i] - ref) < 1e-6
            end
        end
    end

    # ── Aggregation with covariates and notyettreated ────────
    @testset "aggte with covariates (DR, notyettreated)" begin
        result = att_gt(
            yname="lemp", tname="year", idname="countyreal",
            gname="first_treat", data=df,
            est_method="dr", control_group="notyettreated",
            xformla=[:lpop], bstrap=false,
        )
        dyn = aggte(result, type="dynamic")
        @test abs(dyn.overall_att - (-0.0799926209618754)) < 1e-6

        grp = aggte(result, type="group")
        @test abs(grp.overall_att - (-0.0322640388005505)) < 1e-6

        s = aggte(result, type="simple")
        @test abs(s.overall_att - (-0.0413516292999431)) < 1e-6

        cal = aggte(result, type="calendar")
        @test abs(cal.overall_att - (-0.0456646328768679)) < 1e-6
    end

    # ══════════════════════════════════════════════════════════
    #  Unbalanced panel validation
    # ══════════════════════════════════════════════════════════
    @testset "unbalanced panel detection" begin
        using Random
        df_unbal = copy(df)
        rng = MersenneTwister(42)
        # Delete ~5% of rows
        n_drop = div(nrow(df_unbal), 20)
        drop_idx = sort(shuffle(rng, 1:nrow(df_unbal))[1:n_drop])
        df_unbal = df_unbal[setdiff(1:nrow(df_unbal), drop_idx), :]

        # Default (allow_unbalanced_panel=false) should error
        @test_throws ErrorException att_gt(
            yname="lemp", tname="year", idname="countyreal",
            gname="first_treat", data=df_unbal,
            est_method="dr",
        )
    end

    println("\n✓ All tests passed.\n")
end
