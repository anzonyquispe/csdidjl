*! csdid_jl_load 0.5.0  06jul2026
*! Loads CSDid.jl into Julia (default env) — the reghdfejl pattern.
*!
*! v0.5.0: rewritten to use Roodman's `jl start` for Julia detection instead
*!         of home-grown libjulia searching. Removed the shared-env dance.
*!         No manual $csdid_jl_julia_lib or Project.toml co-location ever
*!         required — colleagues just `net install` and run.

cap program drop csdid_jl_load
program define csdid_jl_load
  version 15

  * Fast path: already loaded in this Stata session
  if `"$csdid_jl_loaded"' != "" exit

  * URL + subdir for CSDid.jl on GitHub. Users can override in profile.do
  * to point at a fork; otherwise the defaults kick in.
  if `"$csdid_jl_github_url"' == "" {
    global csdid_jl_github_url "https://github.com/anzonyquispe/csdidjl"
  }
  if `"$csdid_jl_github_subdir"' == "" {
    global csdid_jl_github_subdir "CSDid.jl"
  }
  local repo   `"$csdid_jl_github_url"'
  local subdir `"$csdid_jl_github_subdir"'

  * ── Start Julia via Roodman's jl (handles all detection) ──
  qui jl start

  * ── Install CSDid on first use ──
  cap _jl: import CSDid
  if _rc {
    di as txt ""
    di as txt "─────────────────────────────────────────────────────────────"
    di as txt " First-run install of CSDid.jl from GitHub"
    di as txt "   Source: `repo'"
    if "`subdir'" != "" di as txt "   Subdir: `subdir'"
    di as txt " Julia will download ~30 dependencies and precompile them."
    di as txt " ONE-TIME cost, 5-15 min. Progress shown below."
    di as txt "─────────────────────────────────────────────────────────────"
    mata displayflush()

    _jl: import Pkg
    if "`subdir'" != "" {
      cap noi _jl: Pkg.add(url=raw"`repo'", subdir=raw"`subdir'")
    }
    else {
      cap noi _jl: Pkg.add(url=raw"`repo'")
    }
    if _rc {
      di as err "Pkg.add failed — see the Julia error above."
      exit 199
    }
  }

  * ── Bring the API and Stata-transfer helpers into scope ──
  cap noi _jl: using CSDid, DataFrames, CategoricalArrays
  if _rc {
    di as err "using CSDid failed. Try:  {stata csdid_jl_update}"
    exit 199
  }

  global csdid_jl_loaded 1
end
