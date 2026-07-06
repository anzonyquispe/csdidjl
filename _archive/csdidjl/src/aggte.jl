# ──────────────────────────────────────────────────────────────
#  aggte()  –  Aggregate group‑time ATTs
#  Matches R  did::aggte  for types: dynamic, group, calendar, simple
# ──────────────────────────────────────────────────────────────

"""
    aggte(result; type="group", ...) → AGGTEResult

Aggregate group‑time ATT estimates.

# Types
- `"dynamic"` : event‑study (by event time e = t − g)
- `"group"`   : by treatment cohort
- `"calendar"`: by calendar period
- `"simple"`  : single weighted average of post‑treatment ATTs
"""
function aggte(result::CSDidResult;
               type::String         = "group",
               min_e::Union{Nothing,Int} = nothing,
               max_e::Union{Nothing,Int} = nothing,
               balance_e::Union{Nothing,Int} = nothing,
               bstrap::Bool         = true,
               biters::Int          = 1000,
               cband::Bool          = true,
               alp::Float64         = 0.05,
               seed::Int            = 12345)

    group     = result.group
    tt        = result.t
    att       = result.att
    inf_func  = result.inf_func
    n         = result.n
    dp        = result.dp

    glist = dp[:glist]
    tlist = dp[:tlist]
    anticipation = dp[:anticipation]
    g_vec = haskey(dp, :g_vec) ? dp[:g_vec] : zeros(Int, n)
    w_ind = haskey(dp, :w_ind) ? dp[:w_ind] : ones(n)

    # group sizes (weighted by sampling weights, matching R/Python)
    pg = Dict{Int,Float64}()
    for g in glist
        pg[g] = sum(w_ind[i] * (g_vec[i] == g ? 1.0 : 0.0) for i in 1:n) / n
    end

    if type == "dynamic"
        return _aggte_dynamic(group, tt, att, inf_func, n,
                              glist, pg, g_vec, w_ind, anticipation,
                              min_e, max_e, balance_e,
                              biters, cband, alp, seed)
    elseif type == "group"
        return _aggte_group(group, tt, att, inf_func, n,
                            glist, pg, g_vec, w_ind, max_e,
                            biters, cband, alp, seed)
    elseif type == "calendar"
        return _aggte_calendar(group, tt, att, inf_func, n,
                               glist, tlist, pg, g_vec, w_ind,
                               biters, cband, alp, seed)
    elseif type == "simple"
        return _aggte_simple(group, tt, att, inf_func, n,
                             glist, pg, g_vec, w_ind, max_e,
                             biters, cband, alp, seed)
    else
        error("type must be \"dynamic\", \"group\", \"calendar\", or \"simple\"")
    end
end

# ──────────────────────────────────────────────────────────────
#  Dynamic / event‑study
# ──────────────────────────────────────────────────────────────
function _aggte_dynamic(group, tt, att, inf_func, n,
                        glist, pg, g_vec, w_ind, anticipation,
                        min_e, max_e, balance_e,
                        biters, cband, alp, seed)
    evec = tt .- group
    eseq = sort(unique(evec))
    !isnothing(min_e) && (eseq = filter(e -> e >= min_e, eseq))
    !isnothing(max_e) && (eseq = filter(e -> e <= max_e, eseq))

    n_e   = length(eseq)
    att_e = zeros(n_e)
    se_e  = zeros(n_e)
    inf_e = zeros(n, n_e)

    for (ei, e) in enumerate(eseq)
        idx = findall(evec .== e)
        if !isnothing(balance_e)
            max_t_avail = maximum(tt)
            idx = filter(i -> group[i] + balance_e <= max_t_avail + anticipation, idx)
        end
        isempty(idx) && continue

        wts = [pg[group[i]] for i in idx]
        sw  = sum(wts);  sw == 0 && continue
        wts ./= sw
        att_e[ei] = sum(wts .* att[idx])

        inf_agg = zeros(n)
        for (k, i) in enumerate(idx)
            inf_agg .+= wts[k] .* @view(inf_func[:, i])
        end
        inf_agg .+= _wif(n, group, idx, pg, att, g_vec, w_ind)
        inf_e[:, ei] = inf_agg
    end

    # SEs
    for ei in 1:n_e
        se_e[ei] = sqrt(sum(inf_e[:, ei] .^ 2) / n) / sqrt(n)
    end

    # overall (post‑treatment)
    post = findall(eseq .>= 0)
    if isempty(post)
        ov_att, ov_se = 0.0, 0.0
    else
        ov_att = mean(att_e[post])
        ov_inf = vec(mean(inf_e[:, post], dims=2))
        ov_se  = sqrt(sum(ov_inf .^ 2) / n) / sqrt(n)
    end

    _, cv = _multiplier_bootstrap(inf_e, n, n_e, biters, alp, cband, seed)

    AGGTEResult(ov_att, ov_se, "dynamic", Float64.(eseq), att_e, se_e, cv,
                inf_e,
                isnothing(min_e) ? (isempty(eseq) ? 0 : Int(minimum(eseq))) : min_e,
                isnothing(max_e) ? (isempty(eseq) ? 0 : Int(maximum(eseq))) : max_e)
end

# ──────────────────────────────────────────────────────────────
#  Group
# ──────────────────────────────────────────────────────────────
function _aggte_group(group, tt, att, inf_func, n,
                      glist, pg, g_vec, w_ind, max_e,
                      biters, cband, alp, seed)
    n_g   = length(glist)
    att_g = zeros(n_g)
    se_g  = zeros(n_g)
    inf_g = zeros(n, n_g)

    for (gi, g) in enumerate(glist)
        idx = findall((group .== g) .& (tt .>= g))
        !isnothing(max_e) && (idx = filter(i -> tt[i] <= g + max_e, idx))
        isempty(idx) && continue
        wts = fill(1.0 / length(idx), length(idx))
        att_g[gi] = sum(wts .* att[idx])
        inf_agg = zeros(n)
        for (k, i) in enumerate(idx)
            inf_agg .+= wts[k] .* @view(inf_func[:, i])
        end
        inf_g[:, gi] = inf_agg
    end

    for gi in 1:n_g
        se_g[gi] = sqrt(sum(inf_g[:, gi] .^ 2) / n) / sqrt(n)
    end

    wt_ov = [pg[g] for g in glist]; wt_ov ./= sum(wt_ov)
    ov_att = sum(wt_ov .* att_g)
    ov_inf = inf_g * wt_ov
    # add weight-estimation influence function (accounts for uncertainty
    # in estimated group proportions, matching R/Python did)
    ov_inf .+= _wif(n, glist, collect(1:n_g), pg, att_g, g_vec, w_ind)
    ov_se  = sqrt(sum(ov_inf .^ 2) / n) / sqrt(n)

    _, cv = _multiplier_bootstrap(inf_g, n, n_g, biters, alp, cband, seed)

    AGGTEResult(ov_att, ov_se, "group", Float64.(glist), att_g, se_g, cv,
                inf_g, nothing, nothing)
end

# ──────────────────────────────────────────────────────────────
#  Calendar time
# ──────────────────────────────────────────────────────────────
function _aggte_calendar(group, tt, att, inf_func, n,
                         glist, tlist, pg, g_vec, w_ind,
                         biters, cband, alp, seed)
    cal_list = sort(unique(tt[tt .>= minimum(group)]))
    n_c   = length(cal_list)
    att_c = zeros(n_c)
    se_c  = zeros(n_c)
    inf_c = zeros(n, n_c)

    for (ci, ct) in enumerate(cal_list)
        idx = findall((tt .== ct) .& (group .<= ct))
        isempty(idx) && continue
        wts = [pg[group[i]] for i in idx]
        sw = sum(wts); sw == 0 && continue
        wts ./= sw
        att_c[ci] = sum(wts .* att[idx])

        inf_agg = zeros(n)
        for (k, i) in enumerate(idx)
            inf_agg .+= wts[k] .* @view(inf_func[:, i])
        end
        inf_agg .+= _wif(n, group, idx, pg, att, g_vec, w_ind)
        inf_c[:, ci] = inf_agg
    end

    for ci in 1:n_c
        se_c[ci] = sqrt(sum(inf_c[:, ci] .^ 2) / n) / sqrt(n)
    end

    valid = findall(se_c .> 0)
    if isempty(valid)
        ov_att, ov_se = 0.0, 0.0
    else
        ov_att = mean(att_c[valid])
        ov_inf = vec(mean(inf_c[:, valid], dims=2))
        ov_se  = sqrt(sum(ov_inf .^ 2) / n) / sqrt(n)
    end

    _, cv = _multiplier_bootstrap(inf_c, n, n_c, biters, alp, cband, seed)

    AGGTEResult(ov_att, ov_se, "calendar", Float64.(cal_list), att_c, se_c,
                cv, inf_c, nothing, nothing)
end

# ──────────────────────────────────────────────────────────────
#  Simple / overall
# ──────────────────────────────────────────────────────────────
function _aggte_simple(group, tt, att, inf_func, n,
                       glist, pg, g_vec, w_ind, max_e,
                       biters, cband, alp, seed)
    idx = findall(group .<= tt)
    !isnothing(max_e) && (idx = filter(i -> tt[i] <= group[i] + max_e, idx))

    if isempty(idx)
        return AGGTEResult(0.0, 0.0, "simple", Float64[], Float64[],
                           Float64[], 1.96, nothing, nothing, nothing)
    end

    wts = [pg[group[i]] for i in idx]
    wts ./= sum(wts)
    ov_att = sum(wts .* att[idx])

    inf_agg = zeros(n)
    for (k, i) in enumerate(idx)
        inf_agg .+= wts[k] .* @view(inf_func[:, i])
    end
    inf_agg .+= _wif(n, group, idx, pg, att, g_vec, w_ind)
    ov_se = sqrt(sum(inf_agg .^ 2) / n) / sqrt(n)

    cv = quantile(Normal(), 1 - alp / 2)

    AGGTEResult(ov_att, ov_se, "simple", Float64[], Float64[], Float64[],
                cv, reshape(inf_agg, n, 1), nothing, nothing)
end

# ──────────────────────────────────────────────────────────────
#  Weight‑estimation influence function
# ──────────────────────────────────────────────────────────────
function _wif(n, group_gt, idx, pg, att, g_vec, w_ind)
    k = length(idx)
    k == 0 && return zeros(n)

    keepers_pg  = [pg[group_gt[i]] for i in idx]
    keepers_att = [att[i]          for i in idx]
    S = sum(keepers_pg)
    S == 0.0 && return zeros(n)

    wif = zeros(n)
    @inbounds for i_obs in 1:n
        g_i = g_vec[i_obs]
        wi  = w_ind[i_obs]
        sum_c = 0.0
        for j in 1:k
            g_k = group_gt[idx[j]]
            sum_c += wi * (g_i == g_k ? 1.0 : 0.0) - pg[g_k]
        end
        val = 0.0
        for j in 1:k
            g_k = group_gt[idx[j]]
            c_ij = wi * (g_i == g_k ? 1.0 : 0.0) - pg[g_k]
            w_ij = c_ij / S - sum_c * keepers_pg[j] / (S * S)
            val += w_ij * keepers_att[j]
        end
        wif[i_obs] = val
    end
    return wif
end
