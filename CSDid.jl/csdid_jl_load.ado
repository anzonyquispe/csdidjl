*! csdid_jl_load 0.4.0  06jul2026
*! Loads Julia environment for csdid_jl
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
    di as txt "(First run: installing CSDid.jl from `repo' — 5-15 min)"
    mata displayflush()
    if "`subdir'" != "" {
      _jl: Pkg.add(url=raw"`repo'", subdir=raw"`subdir'"; io=devnull);
    }
    else {
      _jl: Pkg.add(url=raw"`repo'"; io=devnull);
    }
  }

  * ── Instantiate to pull any missing deps (no-op after first run) ──
  _jl: Pkg.instantiate(; io=devnull);

  _jl: using CSDid, DataFrames, CategoricalArrays;

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
