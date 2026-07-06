*! _csdid_jl_start_julia 0.4.1  04jul2026
*! Starts Julia plugin for csdid_jl (cross-platform: Windows, macOS, Linux)
*! v0.4.1: added juliaup auto-detection on macOS/Linux (~/.julia/juliaup/julia-*)
*! v0.4: added macOS/Linux support (libjulia.dylib / libjulia.so)
*! v0.3: always use direct plugin start to avoid console windows on Windows.
*! v0.2: removed Stata shared-env activation (caused CategoricalArraysStatsBaseExt
*!       error in batch mode); package loading deferred to csdid_jl_load.

* Define _julia plugin at top level (required for plugin call)
cap program drop _julia
program _julia, plugin using(jl.plugin)

cap program drop _csdid_jl_start_julia
program define _csdid_jl_start_julia
  version 15

  * Skip if Julia is already running (started by us or by jl start)
  if 0$julia_loaded exit
  if 0$julia_started exit

  * ── Determine libjulia file name by OS ──
  if "`c(os)'" == "Windows" {
    local libname "libjulia.dll"
  }
  else if "`c(os)'" == "MacOSX" {
    local libname "libjulia.dylib"
  }
  else {
    local libname "libjulia.so"
  }

  * ── Find libdir: user override wins ──
  local libdir ""
  if `"$csdid_jl_julia_lib"' != "" {
    local libdir `"$csdid_jl_julia_lib"'
  }
  else if "`c(os)'" == "Windows" {
    * Try common Julia installation paths on Windows (backslash paths)
    local uname `"`c(username)'"'

    local trydir "C:\Users\\`uname'\AppData\Local\Programs\Julia-1.12.6\bin"
    cap confirm file "`trydir'\\`libname'"
    if !_rc local libdir "`trydir'"

    if "`libdir'" == "" {
      local trydir "C:\Users\\`uname'\AppData\Local\Programs\Julia-1.12\bin"
      cap confirm file "`trydir'\\`libname'"
      if !_rc local libdir "`trydir'"
    }

    if "`libdir'" == "" {
      local trydir "C:\Users\\`uname'\AppData\Local\Programs\Julia\bin"
      cap confirm file "`trydir'\\`libname'"
      if !_rc local libdir "`trydir'"
    }

    if "`libdir'" == "" {
      local trydir "C:\Users\\`uname'\AppData\Local\Julia\bin"
      cap confirm file "`trydir'\\`libname'"
      if !_rc local libdir "`trydir'"
    }

    if "`libdir'" == "" {
      local trydir "C:\Julia\bin"
      cap confirm file "`trydir'\\`libname'"
      if !_rc local libdir "`trydir'"
    }
  }
  else if "`c(os)'" == "MacOSX" {
    * Try common Julia installation paths on macOS
    local trydir "/Applications/Julia-1.12.app/Contents/Resources/julia/lib"
    cap confirm file "`trydir'/`libname'"
    if !_rc local libdir "`trydir'"

    if "`libdir'" == "" {
      local trydir "/Applications/Julia-1.11.app/Contents/Resources/julia/lib"
      cap confirm file "`trydir'/`libname'"
      if !_rc local libdir "`trydir'"
    }

    if "`libdir'" == "" {
      local trydir "/Applications/Julia.app/Contents/Resources/julia/lib"
      cap confirm file "`trydir'/`libname'"
      if !_rc local libdir "`trydir'"
    }

    if "`libdir'" == "" {
      local trydir "/opt/homebrew/lib"
      cap confirm file "`trydir'/`libname'"
      if !_rc local libdir "`trydir'"
    }

    if "`libdir'" == "" {
      local trydir "/usr/local/lib"
      cap confirm file "`trydir'/`libname'"
      if !_rc local libdir "`trydir'"
    }

    * juliaup installs under ~/.julia/juliaup/julia-<version>/lib
    if "`libdir'" == "" {
      local home : environment HOME
      if `"`home'"' != "" {
        local jupbase `"`home'/.julia/juliaup"'
        cap local jdirs : dir `"`jupbase'"' dirs "julia-*"
        foreach jd of local jdirs {
          if "`libdir'" == "" {
            cap confirm file `"`jupbase'/`jd'/lib/`libname'"'
            if !_rc local libdir `"`jupbase'/`jd'/lib"'
          }
        }
      }
    }
  }
  else {
    * Try common Julia installation paths on Linux
    local trydir "/opt/julia-1.12.6/lib"
    cap confirm file "`trydir'/`libname'"
    if !_rc local libdir "`trydir'"

    if "`libdir'" == "" {
      local trydir "/opt/julia/lib"
      cap confirm file "`trydir'/`libname'"
      if !_rc local libdir "`trydir'"
    }

    if "`libdir'" == "" {
      local trydir "/usr/local/julia/lib"
      cap confirm file "`trydir'/`libname'"
      if !_rc local libdir "`trydir'"
    }

    * juliaup installs under ~/.julia/juliaup/julia-<version>/lib
    if "`libdir'" == "" {
      local home : environment HOME
      if `"`home'"' != "" {
        local jupbase `"`home'/.julia/juliaup"'
        cap local jdirs : dir `"`jupbase'"' dirs "julia-*"
        foreach jd of local jdirs {
          if "`libdir'" == "" {
            cap confirm file `"`jupbase'/`jd'/lib/`libname'"'
            if !_rc local libdir `"`jupbase'/`jd'/lib"'
          }
        }
      }
    }
  }

  if "`libdir'" == "" {
    di as err "Cannot find `libname'."
    di as err `"Set the path in Stata:  {stata global csdid_jl_julia_lib "/path/to/julia/lib"}"'
    di as err `"Find the path in Terminal:  julia -e 'println(dirname(Sys.BINDIR))'"'
    di as err `"then append /lib (macOS/Linux) or use \bin (Windows)."'
    exit 198
  }

  di as txt "Starting Julia from `libdir' ..."
  mata displayflush()

  * Start Julia via plugin (loads libjulia in-process, no windows on Windows)
  if "`c(os)'" == "Windows" {
    plugin call _julia, start "`libdir'\\`libname'" "`libdir'"
  }
  else {
    plugin call _julia, start "`libdir'/`libname'" "`libdir'"
  }

  * Minimal initialization: just Pkg.
  * stataplugininterface and packages are loaded by csdid_jl_load
  * AFTER activating the CSDid.jl project (which provides CategoricalArrays
  * that stataplugininterface depends on).
  plugin call _julia, evalqui "using Pkg"

  * Mark Julia as started (but not fully loaded — $julia_loaded stays unset
  * until csdid_jl_load finishes initialising stataplugininterface).
  global julia_started 1
  di as txt "(Julia started successfully)"
end
