## gpu_stubs.jl — GPU dispatch infrastructure for CSDid
##
## Provides a backend ref that the CUDA extension sets on load.

"""
    _gpu_backend

Internal ref set by the CUDA extension. `nothing` = CPU only.
"""
const _gpu_backend = Ref{Any}(nothing)

"""
    gpu_available() -> Bool

Returns `true` if a GPU backend (CUDA) is loaded and functional.
"""
gpu_available() = _gpu_backend[] !== nothing

# ── GPU-dispatched function stubs ──────────────────────────────

"""
    _multiplier_bootstrap_gpu(inf_func, n, n_gt, biters, alp, cband, seed)

GPU-accelerated multiplier bootstrap. The CUDA extension replaces this.
"""
function _multiplier_bootstrap_gpu end
