# ──────────────────────────────────────────────────────────────
#  DRDID‑style estimators for panel and repeated cross-section data
#  Matches R packages DRDID::drdid_panel, reg_did_panel,
#  std_ipw_did_panel, reg_did_rc exactly.
# ──────────────────────────────────────────────────────────────

"""
    _logit_fit(D, X, w)

Weighted logistic regression via IRLS (matches R's glm binomial-logit).
Returns fitted probabilities for every row of X.
"""
function _logit_fit(D::Vector{Float64}, X::Matrix{Float64},
                    w::Vector{Float64})
    n, k = size(X)
    beta = zeros(k)
    maxiter = 50
    tol = 1e-10
    for _ in 1:maxiter
        eta = X * beta
        mu  = 1.0 ./ (1.0 .+ exp.(-eta))
        mu  = clamp.(mu, 1e-10, 1.0 - 1e-10)
        vv  = mu .* (1.0 .- mu)
        zz  = eta .+ (D .- mu) ./ vv
        W   = w .* vv
        XtWX = X' * (W .* X)
        XtWz = X' * (W .* zz)
        beta_new = XtWX \ XtWz
        if maximum(abs.(beta_new .- beta)) < tol
            beta = beta_new
            break
        end
        beta = beta_new
    end
    eta = X * beta
    ps  = 1.0 ./ (1.0 .+ exp.(-eta))
    return ps, beta
end

"""
    _wols(y, X, w)

Weighted OLS. Returns coefficients.
"""
function _wols(y::Vector{Float64}, X::Matrix{Float64},
               w::Vector{Float64})
    W = Diagonal(w)
    return (X' * W * X) \ (X' * W * y)
end

# ──────────────────────────────────────────────────────────────
#  Doubly‑Robust DiD for panel data  (DRDID::drdid_panel)
# ──────────────────────────────────────────────────────────────
"""
    drdid_panel(y1, y0, D, X; w=nothing) → (att, inf_func)

Standard doubly‑robust DiD estimator for panel data.
`y1`, `y0` : outcome in post and pre periods.
`D`        : 1 = treated, 0 = comparison.
`X`        : covariate matrix (WITHOUT intercept); pass `nothing` for
             unconditional.
`w`        : observation weights (or `nothing` for equal weights).
"""
function drdid_panel(y1::Vector{Float64}, y0::Vector{Float64},
                     D::Vector{Float64},
                     X::Union{Nothing, Matrix{Float64}};
                     w::Union{Nothing, Vector{Float64}} = nothing)
    n  = length(y1)
    dy = y1 .- y0

    # --- weights ---
    iw = isnothing(w) ? ones(n) : copy(w)
    iw ./= mean(iw)

    # --- covariate matrix with intercept ---
    Xint = isnothing(X) || size(X, 2) == 0 ?
           ones(n, 1) : hcat(ones(n), X)
    k = size(Xint, 2)
    intercept_only = (k == 1)

    # --- propensity score ---
    if intercept_only
        ps = fill(mean(iw .* D) / mean(iw), n)
    else
        ps, _ = _logit_fit(D, Xint, iw)
    end
    ps = min.(ps, 1.0 - 1e-6)

    # --- trimming (match R trim default = 0.995) ---
    trim = trues(n)
    for i in 1:n
        if D[i] == 0.0 && ps[i] >= 0.995
            trim[i] = false
        end
    end

    # --- outcome regression (WLS on ALL controls, no trimming — matches R DRDID) ---
    idx_c = findall(D .== 0.0)
    beta_or = _wols(dy[idx_c], Xint[idx_c, :], iw[idx_c])
    or_pred = Xint * beta_or   # predicted for ALL obs

    # --- ATT ---
    w_treat = Float64.(trim) .* iw .* D
    w_cont  = Float64.(trim) .* iw .* ps .* (1.0 .- D) ./ (1.0 .- ps)
    mean_w_treat = mean(w_treat)
    mean_w_cont  = mean(w_cont)

    eta_treat = mean(w_treat .* (dy .- or_pred)) / mean_w_treat
    eta_cont  = mean(w_cont  .* (dy .- or_pred)) / mean_w_cont

    att_dr = eta_treat - eta_cont

    # --- influence function (full, accounts for estimation) ---
    # OLS component
    w_ols  = iw .* (1.0 .- D)
    XtWX   = (Xint' * (w_ols .* Xint)) ./ n
    XtWXinv = inv(XtWX)
    psi_beta = ((w_ols .* (dy .- or_pred)) .* Xint) * XtWXinv  # n × k

    # PS score component
    Wps   = ps .* (1.0 .- ps) .* iw
    Hps   = (Xint' * (Wps .* Xint)) ./ n
    Hpsinv = inv(Hps)
    score_ps = (iw .* (D .- ps)) .* Xint  # n × k
    psi_ps   = score_ps * Hpsinv            # n × k

    # Treated-side influence
    dr_treat   = w_treat .* (dy .- or_pred)
    psi_treat1 = dr_treat .- w_treat .* eta_treat
    M1 = vec(mean(w_treat .* Xint, dims=1))  # k-vector
    psi_treat2 = psi_beta * M1
    psi_treat  = (psi_treat1 .- psi_treat2) ./ mean_w_treat

    # Control-side influence
    dr_cont   = w_cont .* (dy .- or_pred)
    psi_cont1 = dr_cont .- w_cont .* eta_cont
    M2_mat    = w_cont .* (dy .- or_pred .- eta_cont) .* Xint
    M2 = vec(mean(M2_mat, dims=1))           # k-vector
    psi_cont2 = psi_ps * M2
    M3 = vec(mean(w_cont .* Xint, dims=1))   # k-vector
    psi_cont3 = psi_beta * M3
    psi_cont  = (psi_cont1 .+ psi_cont2 .- psi_cont3) ./ mean_w_cont

    inf_func = psi_treat .- psi_cont

    return att_dr, inf_func
end

# ──────────────────────────────────────────────────────────────
#  Outcome Regression DiD for panel data  (DRDID::reg_did_panel)
# ──────────────────────────────────────────────────────────────
function reg_did_panel(y1::Vector{Float64}, y0::Vector{Float64},
                       D::Vector{Float64},
                       X::Union{Nothing, Matrix{Float64}};
                       w::Union{Nothing, Vector{Float64}} = nothing)
    n  = length(y1)
    dy = y1 .- y0

    iw = isnothing(w) ? ones(n) : copy(w)
    iw ./= mean(iw)

    Xint = isnothing(X) || size(X, 2) == 0 ?
           ones(n, 1) : hcat(ones(n), X)
    k = size(Xint, 2)

    # outcome regression on controls
    idx_c  = findall(D .== 0.0)
    beta_or = _wols(dy[idx_c], Xint[idx_c, :], iw[idx_c])
    or_pred = Xint * beta_or

    # ATT
    w_treat = iw .* D
    mean_w_treat = mean(w_treat)
    eta_treat = mean(w_treat .* dy) / mean_w_treat
    eta_cont  = mean(w_treat .* or_pred) / mean_w_treat
    att_reg = eta_treat - eta_cont

    # influence function
    w_ols  = iw .* (1.0 .- D)
    XtWX   = (Xint' * (w_ols .* Xint)) ./ n
    XtWXinv = inv(XtWX)
    psi_beta = ((w_ols .* (dy .- or_pred)) .* Xint) * XtWXinv

    # treated-side
    psi_treat = (w_treat .* (dy .- eta_treat)) ./ mean_w_treat

    # control-side
    psi_cont1 = (w_treat .* (or_pred .- eta_cont)) ./ mean_w_treat
    M1 = vec(mean(w_treat .* Xint, dims=1))
    psi_cont2 = psi_beta * M1 ./ mean_w_treat
    # Note: the sign — the OR regression adjustment adds to treated
    # so influence = treat - (cont1 + cont2)
    # Actually from R: IF = IF_treat - IF_cont
    # where IF_cont = psi_cont1 + psi_cont2

    inf_func = psi_treat .- psi_cont1 .- psi_cont2

    return att_reg, inf_func
end

# ──────────────────────────────────────────────────────────────
#  Standard IPW DiD for panel data  (DRDID::std_ipw_did_panel)
# ──────────────────────────────────────────────────────────────
function ipw_did_panel(y1::Vector{Float64}, y0::Vector{Float64},
                       D::Vector{Float64},
                       X::Union{Nothing, Matrix{Float64}};
                       w::Union{Nothing, Vector{Float64}} = nothing)
    n  = length(y1)
    dy = y1 .- y0

    iw = isnothing(w) ? ones(n) : copy(w)
    iw ./= mean(iw)

    Xint = isnothing(X) || size(X, 2) == 0 ?
           ones(n, 1) : hcat(ones(n), X)
    k = size(Xint, 2)
    intercept_only = (k == 1)

    # propensity score
    if intercept_only
        ps = fill(mean(iw .* D) / mean(iw), n)
    else
        ps, _ = _logit_fit(D, Xint, iw)
    end
    ps = min.(ps, 1.0 - 1e-6)

    trim = trues(n)
    for i in 1:n
        if D[i] == 0.0 && ps[i] >= 0.995
            trim[i] = false
        end
    end

    # IPW weights (Hajek-style, separate denominators — matches R DRDID)
    w_treat = Float64.(trim) .* iw .* D
    w_cont  = Float64.(trim) .* iw .* ps .* (1.0 .- D) ./ (1.0 .- ps)
    mean_w_treat = mean(w_treat)
    mean_w_cont  = mean(w_cont)

    eta_treat = mean(w_treat .* dy) / mean_w_treat
    eta_cont  = mean(w_cont  .* dy) / mean_w_cont

    att_ipw = eta_treat - eta_cont

    # influence function (Hajek-style, matches R DRDID::std_ipw_did_panel)
    # PS estimation adjustment
    Wps      = ps .* (1.0 .- ps) .* iw
    Hps      = (Xint' * (Wps .* Xint)) ./ n
    Hpsinv   = inv(Hps)
    score_ps = (iw .* (D .- ps)) .* Xint
    asy_lin_rep_ps = score_ps * Hpsinv          # n × k

    # Treated influence
    att_treat = w_treat .* dy
    inf_treat = (att_treat .- w_treat .* eta_treat) ./ mean_w_treat

    # Control influence
    att_cont   = w_cont .* dy
    inf_cont_1 = att_cont .- w_cont .* eta_cont
    M2 = vec(mean((w_cont .* (dy .- eta_cont)) .* Xint, dims=1))
    inf_cont_2 = asy_lin_rep_ps * M2
    inf_control = (inf_cont_1 .+ inf_cont_2) ./ mean_w_cont

    inf_func = inf_treat .- inf_control

    return att_ipw, inf_func
end

# ──────────────────────────────────────────────────────────────
#  Outcome Regression DiD for repeated cross-sections
#  (DRDID::reg_did_rc)
# ──────────────────────────────────────────────────────────────
"""
    reg_did_rc(y, post, D, X; w=nothing) → (att, inf_func)

Outcome-regression DiD estimator for repeated cross-sections.
`y`    : outcome (long, stacked pre+post).
`post` : 1 = post-treatment period, 0 = pre-treatment period.
`D`    : 1 = treated, 0 = comparison.
`X`    : covariate matrix (WITHOUT intercept); `nothing` for unconditional.
`w`    : observation weights (or `nothing` for equal weights).
"""
function reg_did_rc(y::Vector{Float64}, post::Vector{Float64},
                    D::Vector{Float64},
                    X::Union{Nothing, Matrix{Float64}};
                    w::Union{Nothing, Vector{Float64}} = nothing)
    n = length(y)

    iw = isnothing(w) ? ones(n) : copy(w)
    iw ./= mean(iw)

    Xint = isnothing(X) || size(X, 2) == 0 ?
           ones(n, 1) : hcat(ones(n), X)
    k = size(Xint, 2)

    # --- pre-treatment regression: y ~ X for D=0, post=0 ---
    mask_pre  = findall((D .== 0.0) .& (post .== 0.0))
    beta_pre  = _wols(y[mask_pre], Xint[mask_pre, :], iw[mask_pre])
    out_y_pre = Xint * beta_pre

    # --- post-treatment regression: y ~ X for D=0, post=1 ---
    mask_post = findall((D .== 0.0) .& (post .== 1.0))
    beta_post = _wols(y[mask_post], Xint[mask_post, :], iw[mask_post])
    out_y_post = Xint * beta_post

    # --- ATT ---
    w_treat_pre  = iw .* D .* (1.0 .- post)
    w_treat_post = iw .* D .* post
    w_cont       = iw .* D

    eta_treat_pre  = mean(w_treat_pre  .* y) / mean(w_treat_pre)
    eta_treat_post = mean(w_treat_post .* y) / mean(w_treat_post)
    eta_cont       = mean(w_cont .* (out_y_post .- out_y_pre)) / mean(w_cont)

    att_reg = (eta_treat_post - eta_treat_pre) - eta_cont

    # --- influence function ---
    # OLS influence (pre-period controls)
    w_ols_pre  = iw .* (1.0 .- D) .* (1.0 .- post)
    wols_eX_pre = (w_ols_pre .* (y .- out_y_pre)) .* Xint
    XpX_inv_pre = inv((w_ols_pre .* Xint)' * Xint ./ n)
    asy_lin_pre = wols_eX_pre * XpX_inv_pre   # n × k

    # OLS influence (post-period controls)
    w_ols_post  = iw .* (1.0 .- D) .* post
    wols_eX_post = (w_ols_post .* (y .- out_y_post)) .* Xint
    XpX_inv_post = inv((w_ols_post .* Xint)' * Xint ./ n)
    asy_lin_post = wols_eX_post * XpX_inv_post  # n × k

    # treated influence
    inf_treat_pre  = (w_treat_pre  .* y .- w_treat_pre  .* eta_treat_pre)  ./ mean(w_treat_pre)
    inf_treat_post = (w_treat_post .* y .- w_treat_post .* eta_treat_post) ./ mean(w_treat_post)
    inf_treat = inf_treat_post .- inf_treat_pre

    # control influence
    inf_cont_1 = w_cont .* (out_y_post .- out_y_pre) .- w_cont .* eta_cont
    M1 = vec(mean(w_cont .* Xint, dims=1))   # k-vector
    inf_cont_2_post = asy_lin_post * M1
    inf_cont_2_pre  = asy_lin_pre  * M1
    inf_control = (inf_cont_1 .+ inf_cont_2_post .- inf_cont_2_pre) ./ mean(w_cont)

    inf_func = inf_treat .- inf_control

    return att_reg, inf_func
end
