*! csdid_jl_load 0.4.1  06jul2026
*! Loads Julia environment for csdid_jl
*! v0.4.1: Pkg.add errors are no longer swallowed by io=devnull; users see
*!         real Julia errors (bad URL, no network, old Julia) instead of a
*!         cryptic "Package CSDid not found" downstream.
*! v0.4: shared-env install pattern. CSDid.jl is auto-installed from GitHub
*!       on first use into a dedicated Julia env, so the .ado files can be
*!       distributed standalone via `net install`. No co-located Project.toml
*!       required. Follows the reghdfejl (Roodman) pattern.
*! v0.3: auto-instantiate project on first load.
*! v0.2: loads stataplugininterface after project activation.

cap program drop csdid_jl_load
program define csdid_jl_load
  version 15

  * Fast path: already loaded in this Stata session
  if `"$csdid_jl_loaded"' != "" exit

  * URL + subdir for CSDid.jl on GitHub. Colleagues can override in profile.do:
  *   global csdid_jl_github_url    "https://github.com/YOUR-FORK/csdidjl"
  *   global csdid_jl_github_subdir "CSDid.jl"    // "" if Project.toml at repo root
  if `"$csdid_jl_github_url"' == "" {
    global csdid_jl_github_url "https://github.com/anzonyquispe/csdidjl"
  }
  if `"$csdid_jl_github_subdir"' == "" {
    global csdid_jl_github_subdir "CSDid.jl"
  }
  local repo   `"$csdid_jl_github_url"'
  local subdir `"$csdid_jl_github_subdir"'

  * ── Activate a dedicated shared Julia environment ──
  * shared=true puts it under ~/.julia/environments/csdid_jl so we don't
  * touch the user's default env or any of their project envs.
  _jl: import Pkg
  _jl: Pkg.activate("csdid_jl"; shared=true, io=devnull);

  * ── Ensure CSDid is installed in this env ──
  cap _jl: import CSDid
  if _rc {
    di as txt ""
    di as txt "──────────────────────────────────────────────────────────────"
    di as txt " First-run install: fetching CSDid.jl from GitHub."
    di as txt "   Source: `repo'"
    if "`subdir'" != "" di as txt "   Subdir: `subdir'"
    di as txt " Julia will download ~30 dependencies and precompile them."
    di as txt " This is a ONE-TIME cost, 5–15 min. Progress shown below."
    di as txt "──────────────────────────────────────────────────────────────"
    mata displayflush()

    * Do NOT suppress output — the user needs to see progress and any error.
    if "`subdir'" != "" {
      cap noi _jl: Pkg.add(url=raw"`repo'", subdir=raw"`subdir'")
    }
    else {
      cap noi _jl: Pkg.add(url=raw"`repo'")
    }
    if _rc {
      di as err ""
      di as err "Pkg.add failed. Common causes:"
      di as err "  • No internet connection"
      di as err "  • Wrong repo URL: check {stata di \"\$csdid_jl_github_url\"}"
      di as err "  • Wrong subdir: check {stata di \"\$csdid_jl_github_subdir\"}"
      di as err "  • Julia version too old (need 1.10+; you can check with"
      di as err `"       . julia -e "println(VERSION)")"'
      exit 199
    }
  }

  * ── Instantiate to pull any missing deps (silent no-op after first run) ──
  cap noi _jl: Pkg.instantiate()
  if _rc {
    di as err "Pkg.instantiate failed. See error above."
    exit 199
  }

  * ── Load CSDid and its data-transfer helpers ──
  cap noi _jl: using CSDid, DataFrames, CategoricalArrays
  if _rc {
    di as err ""
    di as err "using CSDid failed even after Pkg.add succeeded. This is unusual."
    di as err "Try:  {stata csdid_jl_update}   to force a clean re-install."
    exit 199
  }

  * ── Load stataplugininterface (needed for jl PutVarsToDF) ──
  if `"$julia_loaded"' == "" {
    qui findfile stataplugininterface.jl
    local spijl `"`r(fn)'"'
    local spijl_esc = subinstr(`"`spijl'"', "\", "/", .)
    _jl: pushfirst!(LOAD_PATH, dirname(expanduser(raw"`spijl_esc'")));
    _jl: using stataplugininterface;

    qui findfile jl.plugin
    local plugpath `"`r(fn)'"'
    local plugpath_esc = subinstr(`"`plugpath'"', "\", "/", .)
    _jl: stataplugininterface.setdllpath(expanduser(raw"`plugpath_esc'"));
    global julia_loaded 1
  }

  global csdid_jl_loaded 1
  di as txt "(CSDid.jl loaded from shared env csdid_jl)"
end
