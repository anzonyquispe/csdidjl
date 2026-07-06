"""
Result type from `att_gt()`.
"""
struct CSDidResult
    group::Vector{Int}
    t::Vector{Int}
    att::Vector{Float64}
    se::Vector{Float64}
    crit_val::Float64
    inf_func::Matrix{Float64}   # n_units × n_gt
    n::Int
    alp::Float64
    dp::Dict{Symbol, Any}       # stores estimation parameters
end

"""
Result type from `aggte()`.
"""
struct AGGTEResult
    overall_att::Float64
    overall_se::Float64
    typec::String
    egt::Vector{Float64}
    att_egt::Vector{Float64}
    se_egt::Vector{Float64}
    crit_val::Float64
    inf_func::Union{Nothing, Matrix{Float64}}
    min_e::Union{Nothing, Int}
    max_e::Union{Nothing, Int}
end

function Base.show(io::IO, r::CSDidResult)
    n_obs = get(r.dp, :n_obs, r.n * get(r.dp, :nT, 0))
    println(io, "Call: att_gt()")
    @printf(io, "Number of units: %d\n", r.n)
    @printf(io, "Number of obs:   %d\n", n_obs)
    println(io, "")
    @printf(io, "%-8s %-8s %12s %12s  [%g%% Conf. Band]\n",
            "Group", "Time", "ATT", "Std. Error", (1 - r.alp) * 100)
    println(io, repeat("-", 65))
    for i in eachindex(r.group)
        lo = r.att[i] - r.crit_val * r.se[i]
        hi = r.att[i] + r.crit_val * r.se[i]
        sig = (lo > 0 || hi < 0) ? " *" : ""
        @printf(io, "%-8d %-8d %12.4f %12.4f  [%7.4f, %7.4f]%s\n",
                r.group[i], r.t[i], r.att[i], r.se[i], lo, hi, sig)
    end
    println(io, repeat("-", 65))
    println(io, "Signif: * indicates confidence band does not cover 0")
    @printf(io, "Control group: %s, ", get(r.dp, :control_group, "nevertreated"))
    @printf(io, "Anticipation periods: %d\n", get(r.dp, :anticipation, 0))
    @printf(io, "Estimation method: %s\n", get(r.dp, :est_method, "dr"))
end

function Base.show(io::IO, r::AGGTEResult)
    println(io, "")
    println(io, "Call: aggte(type=\"$(r.typec)\")")
    println(io, "")
    if r.typec != "simple"
        @printf(io, "Overall ATT: %10.4f  (Std. Error: %.4f)\n", r.overall_att, r.overall_se)
        println(io, "")
        @printf(io, "%12s %12s %12s  [Conf. Band]\n",
                r.typec == "dynamic" ? "Event Time" : (r.typec == "group" ? "Group" : "Time"),
                "Estimate", "Std. Error")
        println(io, repeat("-", 60))
        for i in eachindex(r.egt)
            lo = r.att_egt[i] - r.crit_val * r.se_egt[i]
            hi = r.att_egt[i] + r.crit_val * r.se_egt[i]
            sig = (lo > 0 || hi < 0) ? " *" : ""
            @printf(io, "%12.1f %12.4f %12.4f  [%7.4f, %7.4f]%s\n",
                    r.egt[i], r.att_egt[i], r.se_egt[i], lo, hi, sig)
        end
    else
        @printf(io, "ATT: %10.4f  (Std. Error: %.4f)\n", r.overall_att, r.overall_se)
    end
    println(io, repeat("-", 60))
end

# Convenience aliases for Stata interop
summary_attgt(r::CSDidResult) = r
summary_aggte(r::AGGTEResult) = r
