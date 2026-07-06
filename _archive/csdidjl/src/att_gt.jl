# ──────────────────────────────────────────────────────────────
#  att_gt()  –  Group‑time ATT estimator (Callaway & Sant'Anna 2021)
# ──────────────────────────────────────────────────────────────

"""
    att_gt(; yname, tname, idname, gname, data, kwargs...) → CSDidResult

Estimate group‑time average treatment effects following
Callaway & Sant'Anna (2021).

# Keyword arguments
- `yname`         : outcome variable name
- `tname`         : time variable name
- `idname`        : unit‑id variable name
- `gname`         : first‑treatment‑period variable (0 = never treated)
- `data`          : DataFrame (balanced panel)
- `xformla`       : `@formula(0 ~ x1 + x2)`, `[:x1,:x2]`, or `nothing`
- `control_group` : `"nevertreated"` (default) or `"notyettreated"`
- `est_method`    : `"dr"` (default), `"ipw"`, `"reg"`
- `base_period`   : `"varying"` (default) or `"universal"`
- `anticipation`  : integer, default 0
- `bstrap`        : bootstrap inference, default `true`
- `biters`        : bootstrap iterations, default 1000
- `cband`         : simultaneous confidence bands, default `true`
- `alp`           : significance level, default 0.05
- `panel`         : panel data, default `true`
- `weights_name`  : column name for sampling weights (or `nothing`)
- `clustervar`    : column name for cluster variable (or `nothing`)
- `fix_weights`   : `nothing` (default), `"base_period"`, or `"first_period"`
- `use_gpu`       : placeholder for GPU acceleration, default `false`
- `seed`          : random seed, default 12345
"""
function att_gt(;
        yname::String,
        tname::String,
        idname::String,
        gname::String,
        data::DataFrame,
        xformla::Union{Nothing, FormulaTerm, AbstractVector} = nothing,
        control_group::String = "nevertreated",
        est_method::String    = "dr",
        base_period::String   = "varying",
        anticipation::Int     = 0,
        weights_name::Union{Nothing, String} = nothing,
        clustervar::Union{Nothing, String} = nothing,
        fix_weights::Union{Nothing, String} = nothing,
        faster_mode::Bool     = false,
        bstrap::Bool          = true,
        biters::Int           = 1000,
        cband::Bool           = true,
        alp::Float64          = 0.05,
        panel::Bool           = true,
        allow_unbalanced_panel::Bool = false,
        use_gpu::Bool         = false,
        seed::Int             = 12345)

    # ── GPU validation ─────────────────────────────────────
    if use_gpu && !gpu_available()
        error("use_gpu=true requires CUDA.jl. Install with: ] add CUDA")
    end

    # ── 0. copy & validate ──────────────────────────────────
    df = copy(data)
    rename_map = Dict{String,Symbol}()
    # normalise the gname column (R uses "first.treat", Julia "first_treat")
    for col in names(df)
        if col == gname
            rename_map[col] = :G
        end
    end

    sort!(df, [idname, tname])

    # ── 1. extract basic info ───────────────────────────────
    tlist  = sort(unique(df[!, tname]))
    glist  = sort(unique(df[df[!, gname] .> 0, gname]))
    idlist = sort(unique(df[!, idname]))
    n      = length(idlist)
    nT     = length(tlist)
    nG     = length(glist)

    # ── balanced panel check ────────────────────────────────
    if panel && !allow_unbalanced_panel
        expected_rows = n * nT
        if nrow(df) != expected_rows
            error("Panel is unbalanced: expected $expected_rows rows " *
                  "($n units × $nT periods) but got $(nrow(df)). " *
                  "Use allow_unbalanced_panel=true to proceed anyway.")
        end
    end

    # ── 2. build wide‑format panel ──────────────────────────
    # y_wide: n × nT  matrix  (row = unit, col = period)
    id2row = Dict(idlist[i] => i for i in 1:n)
    t2col  = Dict(tlist[j]  => j for j in 1:nT)

    y_wide = zeros(n, nT)
    g_vec  = zeros(Int, n)      # group of each unit
    for row in eachrow(df)
        i = id2row[row[idname]]
        j = t2col[row[tname]]
        y_wide[i, j] = row[yname]
        g_vec[i] = row[gname]
    end

    # weights – wide matrix (n × nT) for time-varying support
    w_wide = _build_weight_matrix(df, weights_name, idname, tname, id2row, t2col, n, nT)

    # cluster IDs – extract from first period (time-invariant)
    cluster_ids = _build_cluster_ids(df, clustervar, idname, tname, tlist[1], idlist)

    # covariates – build per-period matrices (R extracts from base period)
    cov_period_mats = _build_covariates_per_period(df, xformla, idname, tname, tlist, idlist)

    # ── 3. enumerate (g,t) pairs ────────────────────────────
    gt_pairs  = Tuple{Int,Int}[]
    base_periods = Int[]
    identity_cells = Set{Int}()   # indices of (g, bp) cells in universal mode
    for g in glist
        # effective treatment period accounting for anticipation
        g_eff = g - anticipation
        for t in tlist
            if base_period == "varying"
                bp = t >= g_eff ? g_eff - 1 : t - 1
            else  # universal: always compare to last pre-treatment period
                bp = g_eff - 1
            end
            bp < tlist[1] && continue
            if base_period == "universal" && t == bp
                # identity cell: att=0, se=NaN by construction (include for R parity)
                push!(gt_pairs, (g, t))
                push!(base_periods, bp)
                push!(identity_cells, length(gt_pairs))
                continue
            end
            push!(gt_pairs, (g, t))
            push!(base_periods, bp)
        end
    end
    n_gt = length(gt_pairs)

    # ── 4. estimate each ATT(g,t) ───────────────────────────

    # detect whether to use RC path
    # fix_weights="varying" on balanced panel forces RC estimators (matches R did 2.5)
    use_rc = !panel || fix_weights == "varying"
    varying_forced_rc_balanced = (fix_weights == "varying" && panel &&
                                  nrow(df) == n * nT)

    # effective sample size: for true RC, use total rows; for panel/forced-RC, use n_units
    n_eff = (use_rc && !varying_forced_rc_balanced) ? nrow(df) : n

    atts     = zeros(n_gt)
    inf_full = zeros(n_eff, n_gt)   # influence function: n_eff × n_gt

    # For true RC, build row-level mapping: (unit_row, period_col) → position in inf_full
    # inf_full rows correspond to original data rows (sorted by id, then time)
    if use_rc && !varying_forced_rc_balanced
        # row_pos[i, j] = position in inf_full for unit i, period j
        row_pos = zeros(Int, n, nT)
        pos = 0
        for i in 1:n
            for j in 1:nT
                pos += 1
                row_pos[i, j] = pos
            end
        end
        # g_vec_long: group for each row (length n_eff)
        g_vec_long = zeros(Int, n_eff)
        for i in 1:n
            for j in 1:nT
                g_vec_long[row_pos[i, j]] = g_vec[i]
            end
        end
    end

    panel_estimator = if est_method == "dr"
        drdid_panel
    elseif est_method == "ipw"
        ipw_did_panel
    elseif est_method == "reg"
        reg_did_panel
    else
        error("est_method must be \"dr\", \"ipw\", or \"reg\"")
    end

    rc_estimator = if est_method == "reg"
        reg_did_rc
    else
        # DR and IPW RC not yet implemented; fall back to reg for now
        reg_did_rc
    end

    for s in 1:n_gt
        # identity cells (universal base period: t == bp → att=0, se=NaN)
        if s in identity_cells
            atts[s] = 0.0
            continue
        end

        g, t = gt_pairs[s]
        bp   = base_periods[s]

        j_t  = t2col[t]
        j_bp = t2col[bp]

        # treatment indicator (group g)
        D_g = Float64.(g_vec .== g)

        # comparison group indicator
        if control_group == "nevertreated"
            C_g = Float64.(g_vec .== 0)
        else  # notyettreated
            threshold = max(t, bp) + anticipation
            C_g = Float64.((g_vec .== 0) .| ((g_vec .> threshold) .& (g_vec .!= g)))
        end

        # keep only treated + comparison units
        keep = (D_g .+ C_g) .> 0
        idx  = findall(keep)
        n1   = length(idx)
        n1 < 2 && continue

        if use_rc
            # ── RC path: stack two periods in long format ──
            n_stack = 2 * n1
            Y_rc   = vcat(y_wide[idx, j_bp], y_wide[idx, j_t])
            post_rc = vcat(zeros(n1), ones(n1))
            D_rc   = vcat(D_g[idx], D_g[idx])

            # covariates: for varying_forced_rc_balanced, use earlier period
            # for true RC, use per-row period covariates
            cov_period = min(t, bp)
            if isnothing(cov_period_mats)
                X_rc = nothing
            elseif varying_forced_rc_balanced
                X_one = cov_period_mats[cov_period][idx, :]
                X_rc = vcat(X_one, X_one)
            else
                X_bp = cov_period_mats[bp][idx, :]
                X_t  = cov_period_mats[t][idx, :]
                X_rc = vcat(X_bp, X_t)
            end

            # weights
            if isnothing(w_wide)
                w_rc = nothing
            elseif fix_weights == "varying"
                w_rc = vcat(w_wide[idx, j_bp], w_wide[idx, j_t])
            elseif fix_weights == "base_period"
                g_eff_w = g - anticipation
                w_fixed = w_wide[idx, t2col[g_eff_w - 1]]
                w_rc = vcat(w_fixed, w_fixed)
            elseif fix_weights == "first_period"
                w_fixed = w_wide[idx, 1]
                w_rc = vcat(w_fixed, w_fixed)
            else
                w_fixed = w_wide[idx, j_bp]
                w_rc = vcat(w_fixed, w_fixed)
            end

            att_s, inf_s = rc_estimator(Y_rc, post_rc, D_rc, X_rc; w=w_rc)
            atts[s] = att_s

            if varying_forced_rc_balanced
                # forced-RC on balanced panel: aggregate IF to unit level
                # fold_factor=0.5 matches R did 2.5.1 normalization
                scale = 0.5 * (n / n1)
                for k_idx in 1:n1
                    unit_if = (inf_s[k_idx] + inf_s[k_idx + n1]) * scale
                    inf_full[idx[k_idx], s] = unit_if
                end
            else
                # true RC: store IF per-row (n_eff = nrow(df))
                # scale by n_eff / n_stack (matches R did RC path)
                scale = n_eff / n_stack
                for k_idx in 1:n1
                    # bp row
                    inf_full[row_pos[idx[k_idx], j_bp], s] = inf_s[k_idx] * scale
                    # t row
                    inf_full[row_pos[idx[k_idx], j_t], s] = inf_s[k_idx + n1] * scale
                end
            end
        else
            # ── Panel path ──
            y1_s = y_wide[idx, j_t]
            y0_s = y_wide[idx, j_bp]
            D_s  = D_g[idx]
            # covariates from earlier period (matches Python panel2cs2 which keeps earlier row)
            cov_period = min(t, bp)
            X_s  = isnothing(cov_period_mats) ? nothing : cov_period_mats[cov_period][idx, :]
            # weight period: default=bp, base_period=g_eff-1, first_period=tlist[1]
            if isnothing(w_wide)
                w_s = nothing
            elseif isnothing(fix_weights)
                w_s = w_wide[idx, j_bp]
            elseif fix_weights == "base_period"
                g_eff_w = g - anticipation
                w_s = w_wide[idx, t2col[g_eff_w - 1]]
            elseif fix_weights == "first_period"
                w_s = w_wide[idx, 1]
            else
                w_s = w_wide[idx, j_bp]
            end

            att_s, inf_s = panel_estimator(y1_s, y0_s, D_s, X_s; w=w_s)
            atts[s] = att_s
            # scale influence function: multiply by n/n1
            inf_full[idx, s] .= inf_s .* (n / n1)
        end
    end

    # ── 5. bootstrap inference ──────────────────────────────
    if use_gpu && gpu_available()
        ses, crit_val = _multiplier_bootstrap_gpu(inf_full, n_eff, n_gt,
                                                   biters, alp, cband, seed)
    else
        ses, crit_val = _multiplier_bootstrap(inf_full, n_eff, n_gt,
                                               biters, alp, cband, seed;
                                               cluster_ids=cluster_ids)
    end

    # identity cells (universal base period) get NaN SE
    for s in identity_cells
        ses[s] = NaN
    end

    groups_out = [p[1] for p in gt_pairs]
    times_out  = [p[2] for p in gt_pairs]

    # For true RC, g_vec and w_ind must match n_eff (per-row, not per-unit)
    g_vec_out = (use_rc && !varying_forced_rc_balanced) ? g_vec_long : g_vec
    w_ind_out = if use_rc && !varying_forced_rc_balanced
        # expand per-unit weights to per-row
        w_long = ones(n_eff)
        if !isnothing(w_wide)
            for i in 1:n, j in 1:nT
                w_long[row_pos[i, j]] = w_wide[i, j]
            end
        end
        w_long
    else
        isnothing(w_wide) ? ones(n) : w_wide[:, 1]
    end

    dp = Dict{Symbol,Any}(
        :yname         => yname,
        :tname         => tname,
        :idname        => idname,
        :gname         => gname,
        :est_method    => est_method,
        :control_group => control_group,
        :base_period   => base_period,
        :anticipation  => anticipation,
        :bstrap        => bstrap,
        :biters        => biters,
        :alp           => alp,
        :tlist         => tlist,
        :glist         => glist,
        :n             => n,
        :n_obs         => nrow(df),
        :nT            => nT,
        :panel         => panel,
        :g_vec         => g_vec_out,
        :w_ind         => w_ind_out,
    )

    return CSDidResult(groups_out, times_out, atts, ses, crit_val,
                       inf_full, n_eff, alp, dp)
end

# ──────────────────────────────────────────────────────────────
#  Helpers
# ──────────────────────────────────────────────────────────────

"""
Build covariate matrix from formula or column names, using first‑period data.
Returns `nothing` when no covariates (intercept‑only).
"""
function _build_covariates(df, xformla, idname, tname, first_t, idlist)
    isnothing(xformla) && return nothing

    # ── handle Vector{Symbol} / Vector{String} (from Stata wrapper) ──
    if xformla isa AbstractVector
        entries = String.(xformla)
        isempty(entries) && return nothing
        df1 = df[df[!, tname] .== first_t, :]
        sort!(df1, idname)

        cols = Vector{Float64}[]
        for entry in entries
            m = match(r"^C\((\w+)\)$", entry)
            if !isnothing(m)
                # categorical: create dummy columns (drop first level)
                varname = m.captures[1]
                raw = df1[!, varname]
                levels = sort(unique(raw))
                for lv in levels[2:end]
                    push!(cols, Float64.(raw .== lv))
                end
            else
                push!(cols, Float64.(df1[!, Symbol(entry)]))
            end
        end
        isempty(cols) && return nothing
        return hcat(cols...)
    end

    # ── handle FormulaTerm ──
    rhs = xformla.rhs
    if rhs isa ConstantTerm || rhs isa InterceptTerm
        return nothing
    end

    df1 = df[df[!, tname] .== first_t, :]
    sort!(df1, idname)

    sch  = schema(xformla, df1)
    ff   = apply_schema(xformla, sch)
    resp, pred = modelcols(ff, df1)
    if size(pred, 2) > 1
        return Float64.(pred[:, 2:end])
    else
        return nothing
    end
end

"""
Build covariate matrices for each period.
Returns `nothing` when no covariates, or `Dict{Int,Matrix{Float64}}` keyed by period.
For C(var) entries, dummy levels are determined globally across all periods.
"""
function _build_covariates_per_period(df, xformla, idname, tname, tlist, idlist)
    isnothing(xformla) && return nothing

    if xformla isa AbstractVector
        entries = String.(xformla)
        isempty(entries) && return nothing

        # determine global levels for C() variables
        cat_levels = Dict{String, Vector}()
        for entry in entries
            m = match(r"^C\((\w+)\)$", entry)
            if !isnothing(m)
                varname = m.captures[1]
                cat_levels[varname] = sort(unique(df[!, varname]))
            end
        end

        result = Dict{Int, Matrix{Float64}}()
        for t_val in tlist
            df1 = df[df[!, tname] .== t_val, :]
            sort!(df1, idname)
            cols = Vector{Float64}[]
            for entry in entries
                m = match(r"^C\((\w+)\)$", entry)
                if !isnothing(m)
                    varname = m.captures[1]
                    raw = df1[!, varname]
                    levels = cat_levels[varname]
                    for lv in levels[2:end]
                        push!(cols, Float64.(raw .== lv))
                    end
                else
                    push!(cols, Float64.(df1[!, Symbol(entry)]))
                end
            end
            isempty(cols) && return nothing
            result[t_val] = hcat(cols...)
        end
        return result
    end

    # FormulaTerm: build from first period only (time-invariant assumed)
    mat = _build_covariates(df, xformla, idname, tname, tlist[1], idlist)
    isnothing(mat) && return nothing
    result = Dict{Int, Matrix{Float64}}()
    for t_val in tlist
        result[t_val] = mat
    end
    return result
end

"""
Build weight matrix (n × nT) from data.
Returns `nothing` when no weights.
"""
function _build_weight_matrix(df, weights_name, idname, tname, id2row, t2col, n, nT)
    isnothing(weights_name) && return nothing
    w_wide = ones(n, nT)
    for row in eachrow(df)
        i = id2row[row[idname]]
        j = t2col[row[tname]]
        w_wide[i, j] = Float64(row[weights_name])
    end
    return w_wide
end

"""
Build cluster ID vector (length n, one per unit) from first-period data.
Returns `nothing` when no clustering.
"""
function _build_cluster_ids(df, clustervar, idname, tname, first_t, idlist)
    isnothing(clustervar) && return nothing
    df1 = df[df[!, tname] .== first_t, :]
    sort!(df1, idname)
    return Vector{Int}(df1[!, clustervar])
end

"""
Multiplier bootstrap for simultaneous inference.
Returns `(se_vector, critical_value)`.
When `cluster_ids` is provided, uses clustered SEs:
  se[s] = sqrt(sum_c (sum_{i in c} IF[i,s])^2) / n
and draws one multiplier per cluster in the bootstrap.
"""
function _multiplier_bootstrap(inf_func::Matrix{Float64},
                                n::Int, n_gt::Int,
                                biters::Int, alp::Float64,
                                cband::Bool, seed::Int;
                                cluster_ids::Union{Nothing, Vector{Int}} = nothing)
    rng = MersenneTwister(seed)

    # precompute cluster structure if needed
    if !isnothing(cluster_ids)
        unique_clusters = sort(unique(cluster_ids))
        n_clusters = length(unique_clusters)
        # cluster_indices[c] = indices of units in cluster c
        cluster_map = Dict{Int, Vector{Int}}()
        for (i, cid) in enumerate(cluster_ids)
            if haskey(cluster_map, cid)
                push!(cluster_map[cid], i)
            else
                cluster_map[cid] = [i]
            end
        end
        cluster_indices = [cluster_map[c] for c in unique_clusters]

        # aggregate influence function by cluster: sum IF within each cluster
        inf_clustered = zeros(n_clusters, n_gt)
        for (ci, idx) in enumerate(cluster_indices)
            for s in 1:n_gt
                for i in idx
                    inf_clustered[ci, s] += inf_func[i, s]
                end
            end
        end
    end

    # analytic pointwise SE
    se = zeros(n_gt)
    if !isnothing(cluster_ids)
        # clustered SE: se[s] = sqrt(sum_c (sum_{i in c} IF[i,s])^2) / n
        for s in 1:n_gt
            se[s] = sqrt(sum(inf_clustered[:, s] .^ 2)) / n
        end
    else
        for s in 1:n_gt
            col = @view inf_func[:, s]
            se[s] = sqrt(sum(col .^ 2) / n) / sqrt(n)
        end
    end

    if !cband || n_gt <= 1
        crit_val = quantile(Normal(), 1 - alp / 2) # ≈ 1.96 for α=0.05
        return se, crit_val
    end

    # multiplier bootstrap for simultaneous critical value
    max_t_stats = zeros(biters)
    if !isnothing(cluster_ids)
        # clustered bootstrap: one multiplier per cluster
        for b in 1:biters
            xi = randn(rng, n_clusters)
            for s in 1:n_gt
                if se[s] > 0
                    boot_stat = abs(sum(inf_clustered[:, s] .* xi) / n) / se[s]
                    if boot_stat > max_t_stats[b]
                        max_t_stats[b] = boot_stat
                    end
                end
            end
        end
    else
        for b in 1:biters
            xi = randn(rng, n)
            for s in 1:n_gt
                if se[s] > 0
                    boot_stat = abs(sum(inf_func[:, s] .* xi) / n) / se[s]
                    if boot_stat > max_t_stats[b]
                        max_t_stats[b] = boot_stat
                    end
                end
            end
        end
    end
    sort!(max_t_stats)
    crit_val = max_t_stats[Int(ceil((1 - alp) * biters))]

    return se, crit_val
end

# Normal quantile without Distributions.jl
struct Normal end
function quantile(::Normal, p::Float64)
    # Rational approximation (Abramowitz & Stegun 26.2.23)
    if p < 0.5
        return -quantile(Normal(), 1.0 - p)
    end
    t = sqrt(-2.0 * log(1.0 - p))
    c0, c1, c2 = 2.515517, 0.802853, 0.010328
    d1, d2, d3 = 1.432788, 0.189269, 0.001308
    return t - (c0 + c1 * t + c2 * t^2) / (1.0 + d1 * t + d2 * t^2 + d3 * t^3)
end
