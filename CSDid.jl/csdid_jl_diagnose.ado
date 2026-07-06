*! csdid_jl_diagnose 0.1.0  06jul2026
*! Health check for csdid_jl. Runs a series of independent probes and
*! reports PASS / FAIL for each, so users can see exactly what's broken
*! without having to interpret cascading Julia stack traces.
*!
*!   . csdid_jl_diagnose
*!
*! Every step is captured; a failure in one step does NOT abort the rest.
*! Users can paste the whole output when asking for help.

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
    di as err "    This usually means Julia was not found by julia.ado."
    di as err "    Ensure `julia --version` works in a terminal."
    di as err ""
    di as err "Cannot continue past this step (need Julia running)."
    exit
  }
  di as res "    PASS: Julia started."

  * ── 4. Julia version (from the running session) ─────────────
  di as txt ""
  di as txt "[4] Julia version (from the running Julia session)"
  cap noi _jl: println("    ", VERSION)
  if _rc di as err "    FAIL: could not query VERSION."

  * ── 5. Active Pkg env ───────────────────────────────────────
  di as txt ""
  di as txt "[5] Active Julia project"
  cap noi _jl: (import Pkg; println("    ", Pkg.project().path))
  if _rc di as err "    FAIL: could not query Pkg.project()."

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

  * ── 7. GitHub reachability (only useful when [6] failed) ──
  di as txt ""
  di as txt "[7] Network: reach github.com"
  cap noi _jl: try; run(pipeline(`Cmd(["git", "ls-remote", "https://github.com/anzonyquispe/csdidjl", "HEAD"])`, devnull, devnull)); println("    reachable"); catch e; println("    UNREACHABLE: ", e); end
  if _rc di as err "    FAIL: could not probe network (Julia error above)."

  * ── 8. globals still in use ────────────────────────────────
  di as txt ""
  di as txt "[8] Environment globals (all should be empty for a clean install)"
  foreach g in csdid_jl_loaded csdid_jl_path csdid_jl_julia_lib julia_loaded julia_started {
    if `"$`g'"' != "" {
      di as txt "    $" as res "`g'" as txt " = " as res `"$`g'"'
    }
  }

  di as txt ""
  di as txt "═══════════════════════════════════════════════════════════"
  di as txt " Done. Paste the whole output when asking for help."
  di as txt "═══════════════════════════════════════════════════════════"
end
