*! csdid_jl_load 0.5.2  06jul2026
*! Loads CSDid.jl into Julia — the reghdfejl pattern.
*!
*! v0.5.2: added optional $csdid_jl_github_rev global for branch/tag pinning.
*!         Useful for pre-merge testing off a feature branch.
*! v0.5.1: dropped $csdid_jl_loaded fast-path cache; it caused stale-state
*!         bugs when upgrading from an earlier .ado (e.g. skipped the
*!         `using CSDid` step and later left CSDid undefined). Now we
*!         verify CSDid is importable on every call — cheap when already
*!         installed, correct when not.
*! v0.5.0: rewritten to use Roodman's `jl start` for Julia detection.
*!         No shared env. No manual $csdid_jl_julia_lib. Install-and-go.

cap program drop csdid_jl_load
program define csdid_jl_load
  version 15

  * URL + subdir + revision for CSDid.jl on GitHub.
  * Colleagues can override in profile.do:
  *   global csdid_jl_github_url    "https://github.com/YOUR-FORK/csdidjl"
  *   global csdid_jl_github_subdir "CSDid.jl"
  *   global csdid_jl_github_rev    "path_install"     // branch or tag
  if `"$csdid_jl_github_url"' == "" {
    global csdid_jl_github_url "https://github.com/anzonyquispe/csdidjl"
  }
  if `"$csdid_jl_github_subdir"' == "" {
    global csdid_jl_github_subdir "CSDid.jl"
  }
  local repo   `"$csdid_jl_github_url"'
  local subdir `"$csdid_jl_github_subdir"'
  local rev    `"$csdid_jl_github_rev"'

  * ── Start Julia (no-op if already running) ──
  qui jl start

  * ── Fast path: CSDid already importable? Just re-run `using` and exit ──
  * This works whether or not a previous session loaded CSDid, and avoids
  * relying on a Stata global that can be stale after an .ado upgrade.
  cap _jl: import CSDid
  if !_rc {
    _jl: using CSDid, DataFrames, CategoricalArrays
    exit
  }

  * ── First-time install path ──
  di as txt ""
  di as txt "─────────────────────────────────────────────────────────────"
  di as txt " First-run install of CSDid.jl from GitHub"
  di as txt "   Source: `repo'"
  if "`subdir'" != "" di as txt "   Subdir: `subdir'"
  if "`rev'"    != "" di as txt "   Branch/tag: `rev'"
  di as txt " Julia will download ~30 dependencies and precompile them."
  di as txt " ONE-TIME cost, 5-15 min. Progress shown below."
  di as txt "─────────────────────────────────────────────────────────────"
  mata displayflush()

  _jl: import Pkg
  if "`subdir'" != "" & "`rev'" != "" {
    cap noi _jl: Pkg.add(url=raw"`repo'", subdir=raw"`subdir'", rev=raw"`rev'")
  }
  else if "`subdir'" != "" {
    cap noi _jl: Pkg.add(url=raw"`repo'", subdir=raw"`subdir'")
  }
  else if "`rev'" != "" {
    cap noi _jl: Pkg.add(url=raw"`repo'", rev=raw"`rev'")
  }
  else {
    cap noi _jl: Pkg.add(url=raw"`repo'")
  }
  if _rc {
    di as err ""
    di as err "Pkg.add failed. See the Julia error above."
    di as err "  URL:    `repo'"
    if "`subdir'" != "" di as err "  Subdir: `subdir'"
    exit 199
  }

  * ── Verify Pkg.add actually made CSDid importable ──
  cap _jl: import CSDid
  if _rc {
    di as err ""
    di as err "Pkg.add appeared to succeed but CSDid is still not importable."
    di as err "The URL/subdir combo may not point at a CSDid package."
    di as err "  URL:    `repo'"
    di as err "  Subdir: `subdir'"
    exit 199
  }

  * ── Bring API + data-transfer helpers into Main ──
  cap noi _jl: using CSDid, DataFrames, CategoricalArrays
  if _rc {
    di as err "using CSDid failed. Try:  {stata csdid_jl_update}"
    exit 199
  }
end
