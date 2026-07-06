*! csdid_jl_load 0.3.0  04jul2026
*! Loads Julia environment for csdid_jl
*! Follows the reghdfejl pattern (Roodman, julia.ado)
*! v0.3: auto-instantiate project on first load (installs missing deps)
*! v0.2: also loads stataplugininterface after project activation (batch mode)

cap program drop csdid_jl_load
program define csdid_jl_load
  version 15

  * ── Locate the CSDid.jl package directory ──
  * Re-detect if never set, or if a prior run cached a bad "." result.
  if `"$csdid_jl_path"' == "" | `"$csdid_jl_path"' == "." {
    qui findfile csdid_jl_load.ado
    local loadado `"`r(fn)'"'

    * findfile can return a RELATIVE path (e.g. ".\csdid_jl_load.ado")
    * when the ado is found via the current working directory. Anchor
    * it to an absolute path first, or pathgetparent() below will just
    * hand back "." again.
    local first1 = substr(`"`loadado'"', 1, 1)
    * haschar > 0 means the path already has a drive letter, e.g. "C:\..."
    local haschar = strpos(`"`loadado'"', ":")
    if `"`first1'"' != "/" & `"`first1'"' != "\" & `haschar' == 0 {
      local loadado `"`c(pwd)'/`loadado'"'
    }

    * Get directory containing this ado file
    mata: st_local("pkgdir", pathgetparent(`"`loadado'"'))

    * Final safety net: never let pkgdir end up empty or "."
    if `"`pkgdir'"' == "" | `"`pkgdir'"' == "." {
      local pkgdir `"`c(pwd)'"'
    }

    global csdid_jl_path `"`pkgdir'"'
  }
  else {
    local pkgdir `"$csdid_jl_path"'
  }

  * Normalise to forward slashes (Julia on Windows)
  local pkgdir = subinstr(`"`pkgdir'"', "\", "/", .)

  * ── Activate the CSDid.jl Julia project ──
  * Always activate (in case env was changed between calls)
  _jl: import Pkg; Pkg.activate("`pkgdir'"; io=devnull);

  if `"$csdid_jl_loaded"' == "" {
    * ── Ensure deps are installed (no-op if already instantiated) ──
    * First run downloads/precompiles all deps (5-15 min). Subsequent
    * runs are near-instant because Pkg checks the Manifest is satisfied.
    di as txt "(Checking CSDid.jl dependencies — first run installs everything, 5-15 min)"
    mata displayflush()
    _jl: Pkg.instantiate(; io=devnull);

    _jl: using CSDid;
    * Make DataFrames & CategoricalArrays available in Main scope
    * (needed by jl PutVarsToDF for data transfer from Stata)
    _jl: using DataFrames, CategoricalArrays;

    * ── Load stataplugininterface (batch mode) ──
    * In batch mode, _csdid_jl_start_julia only starts the plugin and
    * loads Pkg.  stataplugininterface depends on CategoricalArrays,
    * which is now available from the CSDid.jl project we just activated.
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
    di as txt "(CSDid.jl loaded from `pkgdir')"
  }
end
