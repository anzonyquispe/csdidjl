*! csdid_jl_update 0.2.0  06jul2026
*! Pulls the latest CSDid.jl from GitHub.
*!
*!   . csdid_jl_update

cap program drop csdid_jl_update
program define csdid_jl_update
  version 15

  qui jl start
  di as txt "Updating CSDid.jl ..."
  mata displayflush()

  _jl: import Pkg
  cap noi _jl: Pkg.update("CSDid")
  if _rc {
    di as err "Pkg.update failed — see the Julia error above."
    exit 199
  }

  * Force the next csdid_jl call to re-import the fresh version.
  global csdid_jl_loaded ""

  di as txt "CSDid.jl updated. Run any csdid_jl command to load the new version."
end
