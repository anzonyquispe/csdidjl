* ═══════════════════════════════════════════════════════════════
*  Stata csdid_jl results — ALL scenarios
*  Uses: csdid_jl wrapper (CSDid.jl via Julia plugin)
*  Datasets: mpdta, sim_data, mpdta_tvw, mpdta_extra, factor_cov,
*            tp2_const–tp10_const
*  Output: stata_results.csv, stata_aggte_results_full.csv
* ═══════════════════════════════════════════════════════════════

set more off
clear all

di "Stata version: `c(stata_version)'"
di "Mode: `c(mode)'"
di ""

* ── Setup adopath ──────────────────────────────────────────────
* Run this .do file from the CSDid.jl project directory.
local projdir "`c(pwd)'"
adopath + "`projdir'"
local dpath "`projdir'/data"

* ── Open postfiles ─────────────────────────────────────────────
tempname att_h agg_h
tempfile att_f agg_f
postfile `att_h' str60 scenario double(group t att se) using `att_f', replace
postfile `agg_h' str60(scenario agg_type) double(egt att_egt se_egt overall_att overall_se) using `agg_f', replace


* ═══════════════════════════════════════════════════════════════
*  BLOCK 1: mpdta 12-scenario grid (3 methods × 2 cg × 2 cov)
* ═══════════════════════════════════════════════════════════════

import delimited "`dpath'/mpdta.csv", clear
cap rename firsttreat first_treat
di "Dataset: mpdta  N=`=_N'"

local methods    dr ipw reg
local cgroups    nevertreated notyettreated
local cgshort_nevertreated  nev
local cgshort_notyettreated nyt

foreach em of local methods {
  foreach cg of local cgroups {
    local cgs = "`cgshort_`cg''"
    foreach covtype in nocov cov {
      local scname "`em'_`cgs'_`covtype'"

      if "`covtype'" == "cov" {
        local covars "lpop"
      }
      else {
        local covars ""
      }

      di ""
      di as txt "{hline 70}"
      di as txt "=== SCENARIO: `scname' ==="
      di as txt "{hline 70}"

      cap noisily {
        csdid_jl lemp `covars', tname(year) gname(first_treat) ///
          idname(countyreal) est_method(`em') control_group(`cg')

        * ── Extract ATT(g,t) results ──
        local ngt = e(ngt)
        tempname att_m se_m grp_m tt_m
        matrix `att_m' = e(att)
        matrix `se_m'  = e(se)
        matrix `grp_m' = e(group)
        matrix `tt_m'  = e(t)

        forvalues i = 1/`ngt' {
          local g = `grp_m'[1, `i']
          local t = `tt_m'[1, `i']
          local a = `att_m'[1, `i']
          local s = `se_m'[1, `i']
          post `att_h' ("`scname'") (`g') (`t') (`a') (`s')
        }
        di as txt "  Posted `ngt' ATT(g,t) rows"

        * ── Run aggregations via Julia ──
        foreach atype in simple dynamic group calendar {
          cap noisily {
            _jl: _csdid_agg = CSDid.aggte(_csdid_r; type="`atype'")
            _jl: st_numscalar("__ov_att", _csdid_agg.overall_att)
            _jl: st_numscalar("__ov_se",  _csdid_agg.overall_se)
            _jl: st_numscalar("__nagg",   Float64(length(_csdid_agg.egt)))

            local ov_att = scalar(__ov_att)
            local ov_se  = scalar(__ov_se)

            post `agg_h' ("`scname'") ("`atype'") (.) (.) (.) (`ov_att') (`ov_se')

            local nagg = scalar(__nagg)
            if `nagg' > 0 {
              _jl: _csdid_agg_egt_v = reshape(_csdid_agg.egt,     1, :)
              _jl: _csdid_agg_att_v = reshape(_csdid_agg.att_egt,  1, :)
              _jl: _csdid_agg_se_v  = reshape(_csdid_agg.se_egt,   1, :)
              jl GetMatFromMat __agg_egt, source(_csdid_agg_egt_v)
              jl GetMatFromMat __agg_att, source(_csdid_agg_att_v)
              jl GetMatFromMat __agg_se,  source(_csdid_agg_se_v)

              forvalues j = 1/`nagg' {
                local e_j = __agg_egt[1, `j']
                local a_j = __agg_att[1, `j']
                local s_j = __agg_se[1, `j']
                post `agg_h' ("`scname'") ("`atype'") (`e_j') (`a_j') (`s_j') (`ov_att') (`ov_se')
              }
              cap matrix drop __agg_egt __agg_att __agg_se
            }
            cap scalar drop __ov_att __ov_se __nagg
          }
          if _rc {
            di as txt "  aggte(`atype'): ERROR (rc=" _rc ")"
          }
        }
      }
      if _rc {
        di as err "  SCENARIO FAILED (rc=" _rc ")"
      }
    }
  }
}


* ═══════════════════════════════════════════════════════════════
*  BLOCK 2: sim_nev_dr  (sim_data.csv, DR, nevertreated, cov=X)
* ═══════════════════════════════════════════════════════════════

import delimited "`dpath'/sim_data.csv", clear
di "Dataset: sim_data  N=`=_N'"
di "Variables: " _continue
describe, short

di ""
di as txt "{hline 70}"
di as txt "=== SCENARIO: sim_nev_dr ==="
di as txt "{hline 70}"

cap noisily {
  csdid_jl y x, tname(period) gname(g) idname(id) ///
    est_method(dr) control_group(nevertreated)

  local ngt = e(ngt)
  tempname att_m se_m grp_m tt_m
  matrix `att_m' = e(att)
  matrix `se_m'  = e(se)
  matrix `grp_m' = e(group)
  matrix `tt_m'  = e(t)

  forvalues i = 1/`ngt' {
    local g = `grp_m'[1, `i']
    local t = `tt_m'[1, `i']
    local a = `att_m'[1, `i']
    local s = `se_m'[1, `i']
    post `att_h' ("sim_nev_dr") (`g') (`t') (`a') (`s')
  }
  di as txt "  Posted `ngt' ATT(g,t) rows"

  * ── Aggregations ──
  foreach atype in simple dynamic group calendar {
    cap noisily {
      _jl: _csdid_agg = CSDid.aggte(_csdid_r; type="`atype'")
      _jl: st_numscalar("__ov_att", _csdid_agg.overall_att)
      _jl: st_numscalar("__ov_se",  _csdid_agg.overall_se)
      _jl: st_numscalar("__nagg",   Float64(length(_csdid_agg.egt)))

      local ov_att = scalar(__ov_att)
      local ov_se  = scalar(__ov_se)

      post `agg_h' ("sim_nev_dr") ("`atype'") (.) (.) (.) (`ov_att') (`ov_se')

      local nagg = scalar(__nagg)
      if `nagg' > 0 {
        _jl: _csdid_agg_egt_v = reshape(_csdid_agg.egt,     1, :)
        _jl: _csdid_agg_att_v = reshape(_csdid_agg.att_egt,  1, :)
        _jl: _csdid_agg_se_v  = reshape(_csdid_agg.se_egt,   1, :)
        jl GetMatFromMat __agg_egt, source(_csdid_agg_egt_v)
        jl GetMatFromMat __agg_att, source(_csdid_agg_att_v)
        jl GetMatFromMat __agg_se,  source(_csdid_agg_se_v)

        forvalues j = 1/`nagg' {
          local e_j = __agg_egt[1, `j']
          local a_j = __agg_att[1, `j']
          local s_j = __agg_se[1, `j']
          post `agg_h' ("sim_nev_dr") ("`atype'") (`e_j') (`a_j') (`s_j') (`ov_att') (`ov_se')
        }
        cap matrix drop __agg_egt __agg_att __agg_se
      }
      cap scalar drop __ov_att __ov_se __nagg
    }
    if _rc {
      di as txt "  aggte(`atype'): ERROR (rc=" _rc ")"
    }
  }
}
if _rc {
  di as err "  SCENARIO FAILED (rc=" _rc ")"
}


* ═══════════════════════════════════════════════════════════════
*  BLOCK 3: fix_weights (mpdta_tvw.csv, REG, nevertreated, wt)
*  Tags: none, base, first, varying
* ═══════════════════════════════════════════════════════════════

import delimited "`dpath'/mpdta_tvw.csv", clear
cap rename firsttreat first_treat
di "Dataset: mpdta_tvw  N=`=_N'"

local fw_tags       none base first varying
local fw_scn_none     fix_weights_none
local fw_scn_base     fix_weights_base
local fw_scn_first    fix_weights_first
local fw_scn_varying  fix_weights_varying
local fw_opt_none
local fw_opt_base     fix_weights(base_period)
local fw_opt_first    fix_weights(first_period)
local fw_opt_varying  fix_weights(varying)

foreach fwt of local fw_tags {
  local scname "`fw_scn_`fwt''"
  local fwopts "`fw_opt_`fwt''"

  di ""
  di as txt "{hline 70}"
  di as txt "=== SCENARIO: `scname' ==="
  di as txt "{hline 70}"

  cap noisily {
    csdid_jl lemp, tname(year) gname(first_treat) idname(countyreal) ///
      est_method(reg) control_group(nevertreated) weights(wt) `fwopts'

    local ngt = e(ngt)
    tempname att_m se_m grp_m tt_m
    matrix `att_m' = e(att)
    matrix `se_m'  = e(se)
    matrix `grp_m' = e(group)
    matrix `tt_m'  = e(t)

    forvalues i = 1/`ngt' {
      local g = `grp_m'[1, `i']
      local t = `tt_m'[1, `i']
      local a = `att_m'[1, `i']
      local s = `se_m'[1, `i']
      post `att_h' ("`scname'") (`g') (`t') (`a') (`s')
    }
    di as txt "  Posted `ngt' ATT(g,t) rows"
  }
  if _rc {
    di as err "  SCENARIO FAILED (rc=" _rc ")"
  }
}


* ═══════════════════════════════════════════════════════════════
*  BLOCK 4: factor_cov (factor_cov.csv, REG, nevertreated)
*  Direct Julia call needed for xformla=["C(cat)"]
* ═══════════════════════════════════════════════════════════════

import delimited "`dpath'/factor_cov.csv", clear
di "Dataset: factor_cov  N=`=_N'"

di ""
di as txt "{hline 70}"
di as txt "=== SCENARIO: factor_cov ==="
di as txt "{hline 70}"

cap noisily {
  _csdid_jl_start_julia
  csdid_jl_load

  * Transfer data to Julia DataFrame — use lowercase variable names
  * (Stata's import delimited may lowercase them)
  * cat is a string variable ('a','b','c') — encode to numeric so
  * PutVarsToDF (doubleonly) can transfer it. C(cat) in Julia will
  * then treat the integer levels as categorical (same dummy encoding).
  encode cat, gen(cat_n)
  drop cat
  rename cat_n cat
  local fcvars "id period g y x cluster cat"
  jl PutVarsToDF `fcvars', nomissing doubleonly nolabel

  * Direct Julia call with C(cat) categorical syntax
  * Use column names as they appear in the Stata dataset
  _jl: _csdid_r = CSDid.att_gt(yname="y", tname="period", idname="id", gname="g", data=df, est_method="reg", control_group="nevertreated", base_period="varying", xformla=["C(cat)"])

  _jl: st_numscalar("__ngt", length(_csdid_r.att))
  local ngt = scalar(__ngt)

  _jl: _csdid_att_v = reshape(_csdid_r.att, 1, :)
  _jl: _csdid_se_v  = reshape(_csdid_r.se,  1, :)
  _jl: _csdid_g_v   = reshape(Float64.(_csdid_r.group), 1, :)
  _jl: _csdid_t_v   = reshape(Float64.(_csdid_r.t),     1, :)

  jl GetMatFromMat __att, source(_csdid_att_v)
  jl GetMatFromMat __se,  source(_csdid_se_v)
  jl GetMatFromMat __grp, source(_csdid_g_v)
  jl GetMatFromMat __tt,  source(_csdid_t_v)

  forvalues i = 1/`ngt' {
    local g = __grp[1, `i']
    local t = __tt[1, `i']
    local a = __att[1, `i']
    local s = __se[1, `i']
    post `att_h' ("factor_cov") (`g') (`t') (`a') (`s')
  }
  di as txt "  Posted `ngt' ATT(g,t) rows"

  cap matrix drop __att __se __grp __tt
  cap scalar drop __ngt
}
if _rc {
  di as err "  SCENARIO FAILED (rc=" _rc ")"
}


* ═══════════════════════════════════════════════════════════════
*  BLOCK 5: gap scenarios (mpdta_extra.csv, REG, nevertreated)
* ═══════════════════════════════════════════════════════════════

import delimited "`dpath'/mpdta_extra.csv", clear
cap rename firsttreat first_treat
di "Dataset: mpdta_extra  N=`=_N'"

local gap_scns      rc universal anticipation1 weighted clustered
local gap_opt_rc            nopanel
local gap_opt_universal     base_period(universal)
local gap_opt_anticipation1 anticipation(1)
local gap_opt_weighted      weights(wt)
local gap_opt_clustered     cluster(clust)

foreach scn of local gap_scns {
  local extra "`gap_opt_`scn''"

  di ""
  di as txt "{hline 70}"
  di as txt "=== SCENARIO: `scn' ==="
  di as txt "{hline 70}"

  cap noisily {
    csdid_jl lemp, tname(year) gname(first_treat) idname(countyreal) ///
      est_method(reg) control_group(nevertreated) `extra'

    local ngt = e(ngt)
    tempname att_m se_m grp_m tt_m
    matrix `att_m' = e(att)
    matrix `se_m'  = e(se)
    matrix `grp_m' = e(group)
    matrix `tt_m'  = e(t)

    forvalues i = 1/`ngt' {
      local g = `grp_m'[1, `i']
      local t = `tt_m'[1, `i']
      local a = `att_m'[1, `i']
      local s = `se_m'[1, `i']
      post `att_h' ("`scn'") (`g') (`t') (`a') (`s')
    }
    di as txt "  Posted `ngt' ATT(g,t) rows"
  }
  if _rc {
    di as err "  SCENARIO FAILED (rc=" _rc ")"
  }
}


* ═══════════════════════════════════════════════════════════════
*  BLOCK 6: sim parity (24 scenarios)
*  6 datasets × 2 control groups × 2 estimators
* ═══════════════════════════════════════════════════════════════

local sim_datasets  tp2_const tp4_const tp4_dyn tp5_dyn tp8_dyn tp10_const
local sim_controls  nevertreated notyettreated
local sim_ests      dr reg

foreach ds of local sim_datasets {
  * Use local + forward slash to avoid Stata \` escaping issue
  import delimited "`dpath'/`ds'.csv", clear
  di ""
  di "Dataset: `ds'  N=`=_N'"

  foreach cg of local sim_controls {
    foreach em of local sim_ests {
      local scname "sim_`ds'_`cg'_`em'"

      di ""
      di as txt "{hline 70}"
      di as txt "=== SCENARIO: `scname' ==="
      di as txt "{hline 70}"

      cap noisily {
        csdid_jl y x, tname(period) gname(g) idname(id) ///
          est_method(`em') control_group(`cg')

        local ngt = e(ngt)
        tempname att_m se_m grp_m tt_m
        matrix `att_m' = e(att)
        matrix `se_m'  = e(se)
        matrix `grp_m' = e(group)
        matrix `tt_m'  = e(t)

        forvalues i = 1/`ngt' {
          local g = `grp_m'[1, `i']
          local t = `tt_m'[1, `i']
          local a = `att_m'[1, `i']
          local s = `se_m'[1, `i']
          post `att_h' ("`scname'") (`g') (`t') (`a') (`s')
        }
        di as txt "  Posted `ngt' ATT(g,t) rows"
      }
      if _rc {
        di as err "  SCENARIO FAILED (rc=" _rc ")"
      }
    }
  }
}


* ═══════════════════════════════════════════════════════════════
*  Close postfiles and export
* ═══════════════════════════════════════════════════════════════

postclose `att_h'
postclose `agg_h'

preserve
  use `att_f', clear
  export delimited "`projdir'/stata_results.csv", replace
  di ""
  di "Saved `=_N' ATT(g,t) rows to stata_results.csv"
restore

preserve
  use `agg_f', clear
  export delimited "`projdir'/stata_aggte_results_full.csv", replace
  di ""
  di "Saved `=_N' aggregation rows to stata_aggte_results_full.csv"
restore

di ""
di "{hline 70}"
di "DONE: All scenarios completed."
di "{hline 70}"
