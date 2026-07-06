*! csdid_jl_update 0.2.1  06jul2026
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

  di as txt "CSDid.jl updated. Run any csdid_jl command to use the new version."
end
