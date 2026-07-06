*! _csdid_jl_start_julia 0.5.0  06jul2026
*! Starts Julia plugin for csdid_jl (cross-platform: Windows, macOS, Linux)
*! v0.5.0: primary detection now shells out to `julia -e "print(Sys.BINDIR)"`,
*!         which works for ANY Julia on PATH (juliaup, official installer,
*!         Homebrew, Winget, custom).  Hardcoded paths are a fallback.
*!         Result is cached in $csdid_jl_julia_lib so subsequent sessions
*!         skip the shell-out.
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

  * ── Primary auto-detect: shell out to Julia itself ──
  * Works for any `julia` on PATH (juliaup, official installer, Homebrew,
  * Winget, custom builds).  Only runs once per Stata session (result is
  * cached in $csdid_jl_julia_lib for future sessions after success).
  if "`libdir'" == "" {
    tempfile _bindir_file
    if "`c(os)'" == "Windows" {
      cap qui !julia -e "print(Sys.BINDIR)" > "`_bindir_file'" 2>nul
    }
    else {
      cap qui !julia -e 'print(Sys.BINDIR)' > "`_bindir_file'" 2>/dev/null
    }
    cap confirm file "`_bindir_file'"
    if !_rc {
      tempname _fh
      cap file open `_fh' using "`_bindir_file'", read text
      if !_rc {
        file read `_fh' _line
        file close `_fh'
        local _bindir = strtrim(`"`_line'"')
        if "`_bindir'" != "" & !regexm("`_bindir'", "not found|not recognized|error|Error") {
          * Windows: libjulia.dll lives in bin/.  macOS/Linux: parent(bin)/lib.
          if "`c(os)'" == "Windows" {
            local _cand "`_bindir'"
          }
          else {
            if regexm(`"`_bindir'"', "^(.+)[/\\][Bb]in[/\\]?$") {
              local _cand "`=regexs(1)'/lib"
            }
            else {
              local _cand "`_bindir'"
            }
          }
          * Verify libjulia is actually there (try both slash directions)
          cap confirm file "`_cand'/`libname'"
          if !_rc  local libdir "`_cand'"
          if "`libdir'" == "" {
            cap confirm file "`_cand'\\`libname'"
            if !_rc local libdir "`_cand'"
          }
        }
      }
    }
  }

  * ── Fallback: hardcoded common install paths ──
  if "`libdir'" == "" & "`c(os)'" == "Windows" {
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
  if "`libdir'" == "" & "`c(os)'" == "MacOSX" {
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
  if "`libdir'" == "" & "`c(os)'" != "Windows" & "`c(os)'" != "MacOSX" {
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
    di as err ""
    di as err "Auto-detect tried three strategies and all failed:"
    di as err "  1. \$csdid_jl_julia_lib override — not set"
    di as err `"  2. Shell-out to  julia -e "print(Sys.BINDIR)"  — Julia not on PATH"'
    di as err "  3. Common install locations — none had libjulia"
    di as err ""
    di as err "Fix (pick one):"
    di as err `"  A) Install Julia via juliaup so it ends up on PATH: {browse "https://julialang.org/downloads/"}"'
    di as err "  B) Add your existing Julia's bin directory to PATH."
    di as err "  C) Set the path manually in Stata:"
    di as err `"       . global csdid_jl_julia_lib "<path>""'
    di as err `"     Find <path> by running in a terminal:  julia -e "print(Sys.BINDIR)""'
    di as err "     Use that output as <path> on Windows; on macOS/Linux, strip"
    di as err "     the trailing /bin and append /lib."
    exit 198
  }

  * Cache the detected libdir so future Stata calls skip the shell-out.
  global csdid_jl_julia_lib "`libdir'"

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
