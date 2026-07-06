*! csdid_jl_update 0.1.0  06jul2026
*! Pulls the latest CSDid.jl from GitHub into the shared Julia env.
*! Colleagues run this whenever they hear a new version has landed.
*!
*!   . csdid_jl_update
*!
*! Roughly equivalent (in Julia) to:
*!   Pkg.activate("csdid_jl"; shared=true); Pkg.update("CSDid")

cap program drop csdid_jl_update
program define csdid_jl_update
  version 15

  * Make sure Julia is running (starts it if not).
  _csdid_jl_start_julia

  di as txt "Updating CSDid.jl in shared env csdid_jl ..."
  mata displayflush()

  _jl: import Pkg
  _jl: Pkg.activate("csdid_jl"; shared=true, io=devnull);
  _jl: Pkg.update("CSDid");
  _jl: Pkg.precompile(; io=devnull);

  * Drop cached load state so next csdid_jl call re-imports the new version.
  global csdid_jl_loaded ""

  di as txt "CSDid.jl updated. Run any csdid_jl command to load the new version."
end
