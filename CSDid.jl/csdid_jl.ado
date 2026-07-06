*! csdid_jl 0.3.0  05jul2026
*! Callaway & Sant'Anna (2021) DID estimator via Julia
*! Wrapper for CSDid.jl following the reghdfejl pattern (Roodman)
*! v0.3: added parity options with R did::att_gt:
*!       unbalanced, nobstrap, nocband.
*! v0.2: added `graph` option — replicates R ggdid plots
*!       (attgt faceted by group, event study, calendar, group horizontal).

* Julia startup (_julia plugin + _csdid_jl_start_julia) now lives in its
* own file, _csdid_jl_start_julia.ado, so that `program _julia, plugin`
* sits at the top level of ITS file rather than being redefined every
* time csdid_jl.ado is reloaded (which was killing the running Julia
* session). Stata autoloads it on first call below.

* ═══════════════════════════════════════════════════════════════
*  Main entry
* ═══════════════════════════════════════════════════════════════
cap program drop csdid_jl
program define csdid_jl, eclass
  version 15

  if replay() {
    if `"`e(cmd)'"' != "csdid_jl" error 301
    _csdid_jl_display
    exit
  }

  * Check jl is installed
  cap which jl
  if _rc {
    di as err `"csdid_jl requires the {cmd:jl} command (julia.ado)."'
    di as err `"Install it with: {stata ssc install julia}"'
    exit 198
  }

  * Start Julia (with batch mode fallback)
  _csdid_jl_start_julia

  * Load CSDid.jl project (activates env, loads module)
  csdid_jl_load

  * Run estimator
  _csdid_jl `0'
end

* ═══════════════════════════════════════════════════════════════
*  Workhorse
* ═══════════════════════════════════════════════════════════════
cap program drop _csdid_jl
program define _csdid_jl, eclass
  version 15

  * ── parse syntax ────────────────────────────────────────────
  syntax varlist(min=1 numeric) [if] [in] , ///
    Tname(varname)  Gname(varname)  IDname(varname)  ///
    [ ///
      est_method(string)       /// dr | ipw | reg
      control_group(string)    /// nevertreated | notyettreated
      base_period(string)      /// varying | universal
      NOTYet                   /// shortcut for control_group(notyettreated)
      ANTicipation(integer 0)  ///
      Weights(varname)         /// sampling weights column
      CLuster(varname)         /// cluster variable for SEs
      noPANel                  /// nopanel for repeated cross-sections
      fix_weights(string)      /// base_period | first_period | varying
      ALPha(real 0.05)         ///
      BITERS(integer 1000)     ///
      SEED(integer 12345)      ///
      gpu                      ///
      AGGregate(string)        /// att | event | group | calendar | simple | all
      balance_e(integer -99999) ///
      min_e(integer -99999)    ///
      max_e(integer  99999)    ///
      Level(cilevel)           ///
      GRAPH                    /// draw plots matching R ggdid
      UNBalanced               /// allow_unbalanced_panel=true
      noBSTrap                 /// bstrap=false (analytical SEs, no bootstrap)
      noCBand                  /// cband=false (pointwise, not uniform band)
    ]

  * ── separate depvar from covariates ─────────────────────────
  gettoken depvar indepvars : varlist
  local indepvars = strtrim("`indepvars'")

  * ── defaults ────────────────────────────────────────────────
  if "`est_method'"    == "" local est_method    "dr"
  if "`control_group'" == "" {
    if "`notyet'" != "" local control_group "notyettreated"
    else                local control_group "nevertreated"
  }
  if "`base_period'" == "" local base_period "varying"
  if "`aggregate'"   == "" local aggregate   "att"

  * ── mark sample ────────────────────────────────────────────
  marksample touse
  markout `touse' `tname' `gname' `idname'

  qui count if `touse'
  if r(N) == 0 error 2000

  * ── weights option ─────────────────────────────────────────
  if "`weights'" != "" {
    local wt_opt , weights_name="`weights'"
  }
  else {
    local wt_opt
  }

  * ── cluster option ─────────────────────────────────────────
  if "`cluster'" != "" {
    local cl_opt , clustervar="`cluster'"
  }
  else {
    local cl_opt
  }

  * ── panel option ──────────────────────────────────────────
  if "`panel'" == "nopanel" {
    local pan_opt , panel=false
  }
  else {
    local pan_opt , panel=true
  }

  * ── fix_weights option ───────────────────────────────────
  if "`fix_weights'" != "" {
    local fw_opt , fix_weights="`fix_weights'"
  }
  else {
    local fw_opt
  }

  * ── allow_unbalanced_panel option ────────────────────────
  if "`unbalanced'" != "" {
    local ub_opt , allow_unbalanced_panel=true
  }
  else {
    local ub_opt
  }

  * ── bstrap option (default true; nobstrap disables) ─────
  if "`bstrap'" == "nobstrap" {
    local bs_opt , bstrap=false
  }
  else {
    local bs_opt
  }

  * ── cband option (default true; nocband gives pointwise) ─
  if "`cband'" == "nocband" {
    local cb_opt , cband=false
  }
  else {
    local cb_opt
  }

  * ── transfer data to Julia DataFrame  ───────────────────────
  local allvars `depvar' `indepvars' `tname' `gname' `idname' `weights' `cluster'
  local allvars : list uniq allvars
  jl PutVarsToDF `allvars' if `touse', nomissing doubleonly nolabel

  * ── build covariates argument for Julia ─────────────────────
  if "`indepvars'" != "" {
    local jlcov ""
    foreach v of local indepvars {
      if "`jlcov'" == "" local jlcov ":`v'"
      else               local jlcov "`jlcov', :`v'"
    }
    local xf_opt , xformla=[`jlcov']
  }
  else {
    local xf_opt
  }

  * ── GPU option ──────────────────────────────────────────────
  if "`gpu'" != "" {
    local gpu_opt , use_gpu=true
    * Load CUDA.jl to trigger the GPU extension
    cap _jl: using CUDA
    * Verify GPU is actually available after loading CUDA
    _jl: st_numscalar("__gpu_ok", CSDid.gpu_available() ? 1.0 : 0.0)
    if scalar(__gpu_ok) != 1 {
      cap scalar drop __gpu_ok
      di as err "gpu option specified but CUDA is not available on this machine."
      di as err "Check that you have an NVIDIA GPU and CUDA toolkit installed."
      exit 198
    }
    cap scalar drop __gpu_ok
  }
  else {
    local gpu_opt
  }

  * ── invalidate previous result to prevent stale data ──────
  cap _jl: _csdid_r = nothing

  * ── call CSDid.att_gt() ────────────────────────────────────
  _jl: _csdid_r = CSDid.att_gt(yname="`depvar'", tname="`tname'", idname="`idname'", gname="`gname'", data=df, est_method="`est_method'", control_group="`control_group'", base_period="`base_period'", anticipation=`anticipation', alp=`alpha', biters=`biters', seed=`seed' `xf_opt' `gpu_opt' `wt_opt' `cl_opt' `pan_opt' `fw_opt' `ub_opt' `bs_opt' `cb_opt')

  * ── extract results ─────────────────────────────────────────
  _jl: st_numscalar("__ngt", length(_csdid_r.att))
  local ngt = scalar(__ngt)

  _jl: _csdid_att_v = reshape(_csdid_r.att, 1, :)
  _jl: _csdid_se_v  = reshape(_csdid_r.se,  1, :)
  _jl: _csdid_g_v   = reshape(Float64.(_csdid_r.group), 1, :)
  _jl: _csdid_t_v   = reshape(Float64.(_csdid_r.t),     1, :)
  _jl: st_numscalar("__cv", _csdid_r.crit_val)
  _jl: st_numscalar("__N",  _csdid_r.n)
  _jl: st_numscalar("__Nobs", get(_csdid_r.dp, :n_obs, _csdid_r.n * get(_csdid_r.dp, :nT, 0)))

  jl GetMatFromMat __att, source(_csdid_att_v)
  jl GetMatFromMat __se,  source(_csdid_se_v)
  jl GetMatFromMat __grp, source(_csdid_g_v)
  jl GetMatFromMat __tt,  source(_csdid_t_v)

  * ── build coefficient vector and VCV ────────────────────────
  tempname b V att_e se_e grp_e tt_e

  * Replace NaN with 0 in __att (base period cells have ATT=0, SE=NaN in universal mode)
  forvalues i = 1/`ngt' {
    if __att[1, `i'] >= . {
      matrix __att[1, `i'] = 0
    }
  }
  matrix `b' = __att
  matrix `V' = J(`ngt', `ngt', 0)
  forvalues i = 1/`ngt' {
    local se_i = __se[1, `i']
    if `se_i' < . {
      matrix `V'[`i', `i'] = `se_i'^2
    }
  }

  local colnames ""
  forvalues i = 1/`ngt' {
    local g = __grp[1, `i']
    local t = __tt[1, `i']
    local g : di %9.0f `g'
    local t : di %9.0f `t'
    local g = strtrim("`g'")
    local t = strtrim("`t'")
    local colnames `colnames' g`g':t`t'
  }
  matrix colnames `b' = `colnames'
  matrix colnames `V' = `colnames'
  matrix rownames `V' = `colnames'

  matrix `att_e' = __att
  matrix `se_e'  = __se
  matrix `grp_e' = __grp
  matrix `tt_e'  = __tt
  local N    = scalar(__N)
  local Nobs = scalar(__Nobs)
  local cv   = scalar(__cv)

  cap matrix drop __att __se __grp __tt
  cap scalar drop __ngt __cv __N __Nobs

  * ── post e-class results ────────────────────────────────────
  ereturn post `b' `V', obs(`Nobs') esample(`touse')

  ereturn scalar N        = `N'
  ereturn scalar N_obs    = `Nobs'
  ereturn scalar crit_val = `cv'
  ereturn scalar alpha    = `alpha'
  ereturn scalar ngt      = `ngt'

  ereturn matrix att   = `att_e'
  ereturn matrix se    = `se_e'
  ereturn matrix group = `grp_e'
  ereturn matrix t     = `tt_e'

  ereturn local cmd           "csdid_jl"
  ereturn local cmdline       `"csdid_jl `0'"'
  ereturn local depvar        "`depvar'"
  ereturn local indepvars     "`indepvars'"
  ereturn local est_method    "`est_method'"
  ereturn local control_group "`control_group'"
  ereturn local base_period   "`base_period'"
  ereturn local agg           "`aggregate'"

  * ── display ATT(g,t) table ─────────────────────────────────
  _csdid_jl_display

  * ── aggregation (if requested) ─────────────────────────────
  if "`aggregate'" != "att" & "`aggregate'" != "" {
    if "`aggregate'" == "all" {
      foreach atype in event group simple {
        _csdid_jl_aggte `atype' `balance_e' `min_e' `max_e' `alpha' `biters' `seed'
      }
    }
    else {
      _csdid_jl_aggte `aggregate' `balance_e' `min_e' `max_e' `alpha' `biters' `seed'
    }
  }

  * ── graphs (if requested) ──────────────────────────────────
  if "`graph'" != "" {
    if inlist("`aggregate'", "att", "", "all") {
      _csdid_jl_plot_attgt
    }
    if inlist("`aggregate'", "event", "dynamic", "all") {
      _csdid_jl_plot_es dynamic
    }
    if inlist("`aggregate'", "calendar", "all") {
      _csdid_jl_plot_es calendar
    }
    if inlist("`aggregate'", "group", "all") {
      _csdid_jl_plot_group
    }
  }
end

* ═══════════════════════════════════════════════════════════════
*  Display ATT(g,t) table
* ═══════════════════════════════════════════════════════════════
cap program drop _csdid_jl_display
program define _csdid_jl_display
  version 15

  local ngt   = e(ngt)
  local cv    = e(crit_val)
  local alpha = e(alpha)
  local pct : di %4.1f (1 - `alpha') * 100

  tempname att se grp tt
  matrix `att' = e(att)
  matrix `se'  = e(se)
  matrix `grp' = e(group)
  matrix `tt'  = e(t)

  di ""
  di as txt "Callaway & Sant'Anna (2021) Estimator" ///
     _col(50) "Number of obs   = " as res %9.0fc e(N_obs)
  di as txt "Outcome variable:  " as res "`e(depvar)'" ///
     _col(50) "Number of units = " as res %9.0fc e(N)
  di as txt "                   " ///
     _col(50) "Num. (g,t) cells = " as res %6.0f `ngt'
  di as txt "Estimator:         " as res "`e(est_method)'" ///
     _col(50) "Control group  = " as res "`e(control_group)'"
  if "`e(indepvars)'" != "" {
    di as txt "Covariates:        " as res "`e(indepvars)'"
  }
  di ""

  di as txt "{hline 13}{c TT}{hline 64}"
  di as txt %6s "Group" " " %4s "Time" " {c |}" ///
     %12s " ATT(g,t)" %12s " Std. Err." ///
     "     [`pct'% Conf. Band]"
  di as txt "{hline 13}{c +}{hline 64}"

  forvalues i = 1/`ngt' {
    local g = `grp'[1, `i']
    local t = `tt'[1, `i']
    local a = `att'[1, `i']
    local s = `se'[1, `i']

    * Universal base-period identity cell: SE is missing (from Julia NaN).
    * Show SE and CI as missing; do NOT mark as significant (missing > 0 is
    * TRUE in Stata and would otherwise flag identity cells with a spurious *).
    if `s' >= . {
      local lo = .
      local hi = .
      local star ""
    }
    else {
      local lo = `a' - `cv' * `s'
      local hi = `a' + `cv' * `s'
      local star ""
      if (`lo' > 0) | (`hi' < 0) local star "*"
    }

    di as txt %6.0f `g' "  " %4.0f `t' " {c |}" ///
       as res %12.4f `a' %12.4f `s'  ///
       "    " %9.4f `lo' "   " %9.4f `hi' ///
       _col(76) "`star'"
  }

  di as txt "{hline 13}{c BT}{hline 64}"
  di as txt " * Confidence band does not cover zero."
end

* ═══════════════════════════════════════════════════════════════
*  Aggregation subroutine
* ═══════════════════════════════════════════════════════════════
cap program drop _csdid_jl_aggte
program define _csdid_jl_aggte, eclass
  version 15

  args atype balance_e min_e max_e alpha biters seed

  if "`atype'" == "event"   local jltype "dynamic"
  else if "`atype'" == "dynamic" local jltype "dynamic"
  else                           local jltype "`atype'"

  local opts type="`jltype'"
  if `balance_e' != -99999 local opts `opts', balance_e=`balance_e'
  if "`jltype'" == "dynamic" {
    if `min_e' != -99999 local opts `opts', min_e=`min_e'
    if `max_e' !=  99999 local opts `opts', max_e=`max_e'
  }
  local opts `opts', alp=`alpha', biters=`biters', seed=`seed'

  _jl: _csdid_agg = CSDid.aggte(_csdid_r; `opts')

  _jl: st_numscalar("__agg_ov",    _csdid_agg.overall_att)
  _jl: st_numscalar("__agg_ov_se", _csdid_agg.overall_se)
  _jl: st_numscalar("__agg_cv",    _csdid_agg.crit_val)
  _jl: st_numscalar("__agg_n",     length(_csdid_agg.egt))

  local n_agg = scalar(__agg_n)

  if `n_agg' > 0 {
    _jl: _csdid_agg_egt = reshape(_csdid_agg.egt,     1, :)
    _jl: _csdid_agg_att = reshape(_csdid_agg.att_egt,  1, :)
    _jl: _csdid_agg_se  = reshape(_csdid_agg.se_egt,   1, :)

    jl GetMatFromMat __agg_egt, source(_csdid_agg_egt)
    jl GetMatFromMat __agg_att, source(_csdid_agg_att)
    jl GetMatFromMat __agg_se,  source(_csdid_agg_se)

    * Universal base + dynamic aggregation: the reference event time
    * e = -1 aggregates only over identity cells (att=0, inf=0), so
    * CSDid.jl returns SE=0.0 for it. R's did returns NA. Force missing
    * so the printed CI, stored e() matrix, and plotted error bar all
    * behave the same way (missing / absent), while ATT stays at 0.
    if "`e(base_period)'" == "universal" & "`jltype'" == "dynamic" {
      forvalues i = 1/`n_agg' {
        if __agg_egt[1, `i'] == -1 {
          matrix __agg_se[1, `i'] = .
        }
      }
    }
  }

  local ov_att = scalar(__agg_ov)
  local ov_se  = scalar(__agg_ov_se)
  local agg_cv = scalar(__agg_cv)

  di ""
  if "`jltype'" == "dynamic" {
    di as txt "{hline 77}"
    di as txt "Event-Study Estimates"
  }
  else if "`jltype'" == "group" {
    di as txt "{hline 77}"
    di as txt "Group-Level Estimates"
  }
  else if "`jltype'" == "calendar" {
    di as txt "{hline 77}"
    di as txt "Calendar-Time Estimates"
  }
  else {
    di as txt "{hline 77}"
    di as txt "Overall Treatment Effect"
  }

  di as txt "Overall ATT = " as res %9.4f `ov_att' ///
     as txt "  (Std. Err. = " as res %7.4f `ov_se' as txt ")"
  di ""

  if `n_agg' > 0 {
    local pct : di %4.1f (1 - `alpha') * 100

    if "`jltype'" == "dynamic"    local elabel "Event time"
    else if "`jltype'" == "group" local elabel "     Group"
    else                          local elabel "      Time"

    di as txt "{hline 13}{c TT}{hline 64}"
    di as txt %10s "`elabel'" "   {c |}" ///
       %12s " Estimate" %12s " Std. Err." ///
       "     [`pct'% Conf. Band]"
    di as txt "{hline 13}{c +}{hline 64}"

    forvalues i = 1/`n_agg' {
      local e = __agg_egt[1, `i']
      local a = __agg_att[1, `i']
      local s = __agg_se[1, `i']

      * Guard against missing SE (e = -1 under universal base).
      if `s' >= . {
        local lo = .
        local hi = .
        local star ""
      }
      else {
        local lo = `a' - `agg_cv' * `s'
        local hi = `a' + `agg_cv' * `s'
        local star ""
        if (`lo' > 0) | (`hi' < 0) local star "*"
      }

      di as txt %10.0f `e' "   {c |}" ///
         as res %12.4f `a' %12.4f `s' ///
         "    " %9.4f `lo' "   " %9.4f `hi' ///
         _col(76) "`star'"
    }

    di as txt "{hline 13}{c BT}{hline 64}"
    di as txt " * Confidence band does not cover zero."
  }

  ereturn scalar agg_att_`jltype' = `ov_att'
  ereturn scalar agg_se_`jltype'  = `ov_se'
  ereturn scalar agg_cv_`jltype'  = `agg_cv'

  if `n_agg' > 0 {
    tempname ae as ag
    matrix `ae' = __agg_att
    matrix `as' = __agg_se
    matrix `ag' = __agg_egt

    ereturn matrix agg_att_egt_`jltype' = `ae'
    ereturn matrix agg_se_egt_`jltype'  = `as'
    ereturn matrix agg_egt_`jltype'     = `ag'

    cap matrix drop __agg_egt __agg_att __agg_se
  }

  cap scalar drop __agg_ov __agg_ov_se __agg_cv __agg_n
end

* ═══════════════════════════════════════════════════════════════
*  Plot ATT(g,t) — one panel per group (mirrors R ggdid.MP)
* ═══════════════════════════════════════════════════════════════
cap program drop _csdid_jl_plot_attgt
program define _csdid_jl_plot_attgt
  version 15

  local ngt = e(ngt)
  local cv  = e(crit_val)
  if `ngt' <= 0 exit

  tempname att se grp tt
  matrix `att' = e(att)
  matrix `se'  = e(se)
  matrix `grp' = e(group)
  matrix `tt'  = e(t)

  preserve
  clear
  qui set obs `ngt'
  qui gen double _grp = .
  qui gen double _t   = .
  qui gen double _att = .
  qui gen double _se  = .
  forvalues i = 1/`ngt' {
    qui replace _grp = `grp'[1, `i'] in `i'
    qui replace _t   = `tt'[1, `i']  in `i'
    qui replace _att = `att'[1, `i'] in `i'
    qui replace _se  = `se'[1, `i']  in `i'
  }
  qui gen double _cil  = _att - `cv' * _se
  qui gen double _ciu  = _att + `cv' * _se
  qui gen byte   _post = (_t >= _grp)

  twoway ///
    (rcap _ciu _cil _t if _post==0, lcolor("232 125 114") lwidth(medthick)) ///
    (rcap _ciu _cil _t if _post==1, lcolor("86 188 194")  lwidth(medthick)) ///
    (scatter _att _t if _post==0, mcolor("232 125 114") msymbol(O) msize(medium)) ///
    (scatter _att _t if _post==1, mcolor("86 188 194")  msymbol(O) msize(medium)) ///
    , by(_grp, cols(1) yrescale xrescale note("") ///
                title("ATT(g,t) by Group", color(gs4) size(medium))) ///
      yline(0, lpattern(dash) lcolor(gs10)) ///
      xtitle("") ytitle("ATT") ///
      legend(order(3 "Pre" 4 "Post") position(6) rows(1) region(lstyle(none))) ///
      name(csdid_attgt, replace)

  restore
end

* ═══════════════════════════════════════════════════════════════
*  Plot event study (dynamic) or calendar aggregation
*  (mirrors R ggdid.AGGTEobj gplot branch)
* ═══════════════════════════════════════════════════════════════
cap program drop _csdid_jl_plot_es
program define _csdid_jl_plot_es
  version 15
  args jltype

  cap confirm matrix e(agg_egt_`jltype')
  if _rc exit
  local n = colsof(e(agg_egt_`jltype'))
  if `n' <= 0 exit

  local cv = e(agg_cv_`jltype')

  tempname egt att se
  matrix `egt' = e(agg_egt_`jltype')
  matrix `att' = e(agg_att_egt_`jltype')
  matrix `se'  = e(agg_se_egt_`jltype')

  preserve
  clear
  qui set obs `n'
  qui gen double _e   = .
  qui gen double _att = .
  qui gen double _se  = .
  forvalues i = 1/`n' {
    qui replace _e   = `egt'[1, `i'] in `i'
    qui replace _att = `att'[1, `i'] in `i'
    qui replace _se  = `se'[1, `i']  in `i'
  }
  qui gen double _cil = _att - `cv' * _se
  qui gen double _ciu = _att + `cv' * _se

  if "`jltype'" == "dynamic" {
    qui gen byte _post = (_e >= 0)
    local xt "Length of exposure (t - g)"
    local ttl "Average Effect by Length of Exposure"
    local refx "xline(0, lpattern(dash) lcolor(gs10))"
  }
  else {
    qui gen byte _post = 1
    local xt "Time period"
    local ttl "Average Effect by Time Period"
    local refx ""
  }

  twoway ///
    (rcap _ciu _cil _e if _post==0, lcolor("232 125 114") lwidth(medthick)) ///
    (rcap _ciu _cil _e if _post==1, lcolor("86 188 194")  lwidth(medthick)) ///
    (scatter _att _e if _post==0, mcolor("232 125 114") msymbol(O) msize(medium)) ///
    (scatter _att _e if _post==1, mcolor("86 188 194")  msymbol(O) msize(medium)) ///
    , yline(0, lpattern(dash) lcolor(gs10)) `refx' ///
      title("`ttl'", color(gs4) size(medium)) ///
      xtitle("`xt'") ytitle("ATT") ///
      legend(order(3 "Pre" 4 "Post") position(6) rows(1) region(lstyle(none))) ///
      name(csdid_`jltype', replace)

  restore
end

* ═══════════════════════════════════════════════════════════════
*  Plot group-level aggregation — horizontal (mirrors R splot)
* ═══════════════════════════════════════════════════════════════
cap program drop _csdid_jl_plot_group
program define _csdid_jl_plot_group
  version 15

  cap confirm matrix e(agg_egt_group)
  if _rc exit
  local n = colsof(e(agg_egt_group))
  if `n' <= 0 exit

  local cv = e(agg_cv_group)

  tempname grp att se
  matrix `grp' = e(agg_egt_group)
  matrix `att' = e(agg_att_egt_group)
  matrix `se'  = e(agg_se_egt_group)

  preserve
  clear
  qui set obs `n'
  qui gen double _g   = .
  qui gen double _att = .
  qui gen double _se  = .
  forvalues i = 1/`n' {
    qui replace _g   = `grp'[1, `i'] in `i'
    qui replace _att = `att'[1, `i'] in `i'
    qui replace _se  = `se'[1, `i']  in `i'
  }
  qui gen double _cil = _att - `cv' * _se
  qui gen double _ciu = _att + `cv' * _se

  sort _g
  qui gen int _idx = _n

  * Build y-axis labels from sorted group values
  local ylabs ""
  forvalues i = 1/`n' {
    local gv = _g[`i']
    local gv : di %5.0f `gv'
    local gv = strtrim("`gv'")
    local ylabs `"`ylabs' `i' "`gv'""'
  }

  twoway ///
    (pcspike _idx _cil _idx _ciu, lcolor("86 188 194") lwidth(medthick)) ///
    (scatter _idx _att, mcolor("86 188 194") msymbol(O) msize(medium)) ///
    , xline(0, lpattern(dash) lcolor(gs10)) ///
      title("Average Effect by Group", color(gs4) size(medium)) ///
      xtitle("ATT") ytitle("Group") ///
      ylabel(`ylabs', angle(horizontal)) ///
      legend(off) ///
      name(csdid_group, replace)

  restore
end
