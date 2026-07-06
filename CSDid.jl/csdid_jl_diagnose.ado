*! csdid_jl_diagnose 0.2.0  06jul2026
*! Health check for csdid_jl. Runs a series of independent probes and
*! reports PASS / FAIL for each so users can see exactly what's broken.
*!
*!   . csdid_jl_diagnose
*!
*! Each step is captured; a failure in one step does NOT abort the rest.
*! Users can paste the whole output when asking for help.
*!
*! v0.2.0: rewrote [4]/[5] to use simple Julia expressions (multi-statement
*!         `import` inside parens isn't valid Julia). Removed the network
*!         probe [7] — it wasn't essential and its command-quoting was
*!         fighting both Stata and Julia parsers.

cap program drop csdid_jl_diagnose
program define csdid_jl_diagnose
  version 15

  di as txt ""
  di as txt "═══════════════════════════════════════════════════════════"
  di as txt " csdid_jl_diagnose — health check"
  di as txt "═══════════════════════════════════════════════════════════"

  * ── 1. Julia on PATH ────────────────────────────────────────
  di as txt ""
  di as txt "[1] Julia on system PATH"
  tempfile _jver
  if "`c(os)'" == "Windows" {
    cap qui !julia --version > "`_jver'" 2>nul
  }
  else {
    cap qui !julia --version > "`_jver'" 2>/dev/null
  }
  local _julia_ok = 0
  cap confirm file "`_jver'"
  if !_rc {
    tempname _fh
    cap file open `_fh' using "`_jver'", read text
    if !_rc {
      file read `_fh' _line
      file close `_fh'
      local _line = strtrim(`"`_line'"')
      if regexm("`_line'", "julia version") {
        di as res "    PASS: `_line'"
        local _julia_ok = 1
      }
    }
  }
  if !`_julia_ok' {
    di as err "    FAIL: `julia --version` did not respond."
    di as err "    Fix: install Julia and ensure it is on PATH."
    di as err "         https://julialang.org/downloads/"
  }

  * ── 2. jl.ado (Roodman's julia.ado) present ─────────────────
  di as txt ""
  di as txt "[2] jl.ado (Roodman's Stata-Julia bridge)"
  cap which jl
  if _rc {
    di as err "    FAIL: jl not installed."
    di as err "    Fix:  ssc install julia, replace"
  }
  else {
    di as res "    PASS: jl is installed."
  }

  * ── 3. jl start ─────────────────────────────────────────────
  di as txt ""
  di as txt "[3] jl start (starts Julia in-process)"
  cap noi qui jl start
  if _rc {
    di as err "    FAIL: jl start returned rc=`=_rc'. See message above."
    di as err "    Cannot continue past this step (need Julia running)."
    exit
  }
  di as res "    PASS: Julia started."

  * ── 4. Julia version (from the running session) ─────────────
  di as txt ""
  di as txt "[4] Julia version (from the running Julia session)"
  cap noi _jl: println(VERSION)
  if _rc {
    di as err "    FAIL: could not query VERSION — see error above."
  }

  * ── 5. Active Julia project (Pkg env) ──────────────────────
  * NOTE: `import` cannot be inside an expression, so we split into
  * two independent _jl calls.
  di as txt ""
  di as txt "[5] Active Julia project (Pkg env)"
  cap noi _jl: import Pkg
  if _rc {
    di as err "    FAIL: import Pkg errored — see above."
  }
  else {
    cap noi _jl: println(Pkg.project().path)
    if _rc di as err "    FAIL: could not read Pkg.project() — see above."
  }

  * ── 6. Can we import CSDid? ────────────────────────────────
  di as txt ""
  di as txt "[6] import CSDid"
  cap _jl: import CSDid
  if _rc {
    di as err "    FAIL: CSDid is not installed or not accessible."
    di as err "    Fix (auto-installs on next csdid_jl call, or run now):"
    di as err `"      . _jl: import Pkg"'
    di as err `"      . _jl: Pkg.add(url="https://github.com/anzonyquispe/csdidjl", subdir="CSDid.jl")"'
  }
  else {
    di as res "    PASS: CSDid is importable."
  }

  * ── 7. Verify `using CSDid` also brings the API into scope ─
  di as txt ""
  di as txt "[7] using CSDid, DataFrames, CategoricalArrays"
  cap noi _jl: using CSDid, DataFrames, CategoricalArrays
  if _rc {
    di as err "    FAIL: `using` failed — see error above."
    di as err "    This is unusual if [6] passed. Try:  csdid_jl_update"
  }
  else {
    di as res "    PASS: API in scope."
  }

  * ── 8. Environment globals ─────────────────────────────────
  di as txt ""
  di as txt "[8] Environment globals (from the current Stata session)"
  local _any = 0
  foreach g in csdid_jl_loaded csdid_jl_path csdid_jl_julia_lib csdid_jl_github_url csdid_jl_github_subdir csdid_jl_github_rev julia_loaded julia_started {
    if `"$`g'"' != "" {
      di as txt "    $" as res "`g'" as txt " = " as res `"$`g'"'
      local _any = 1
    }
  }
  if !`_any' di as txt "    (none set — clean session)"

  di as txt ""
  di as txt "═══════════════════════════════════════════════════════════"
  di as txt " Done. If [4]-[7] all PASS, `csdid_jl` is ready to use."
  di as txt " Paste this whole output when asking for help."
  di as txt "═══════════════════════════════════════════════════════════"
end
