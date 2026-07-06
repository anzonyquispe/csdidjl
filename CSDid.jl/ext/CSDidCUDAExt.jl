module CSDidCUDAExt

using CUDA
using CSDid
using CSDid: _gpu_backend, _multiplier_bootstrap_gpu, Normal, quantile
using Random
using Statistics

function __init__()
    if CUDA.functional()
        _gpu_backend[] = :cuda
        @info "CSDid: CUDA GPU acceleration enabled ($(CUDA.name(CUDA.device())))"
    else
        @warn "CSDid: CUDA.jl loaded but not functional — falling back to CPU"
    end
end

# ──────────────────────────────────────────────────────────────
#  Multiplier bootstrap on GPU
#  boot_estimates = xi_gpu' * inf_gpu / n  (single GEMM)
#  CPU RNG for bit-identical reproducibility
# ──────────────────────────────────────────────────────────────
function CSDid._multiplier_bootstrap_gpu(inf_func::Matrix{Float64},
                                          n::Int, n_gt::Int,
                                          biters::Int, alp::Float64,
                                          cband::Bool, seed::Int)
    rng = MersenneTwister(seed)

    # Analytic pointwise SE (computed on CPU)
    se = zeros(n_gt)
    for s in 1:n_gt
        col = @view inf_func[:, s]
        se[s] = sqrt(sum(col .^ 2) / n) / sqrt(n)
    end

    if !cband || n_gt <= 1
        crit_val = quantile(Normal(), 1 - alp / 2)
        return se, crit_val
    end

    # Generate ALL xi vectors on CPU (bit-identical to CPU path)
    xi_mat = Matrix{Float64}(undef, n, biters)
    for b in 1:biters
        xi_mat[:, b] = randn(rng, n)
    end

    # Transfer to GPU: single GEMM
    # boot_stats = xi_mat' * inf_func / n  →  (biters × n) × (n × n_gt) = (biters × n_gt)
    xi_d = CuMatrix{Float64}(xi_mat)
    inf_d = CuMatrix{Float64}(inf_func)

    boot_stats_d = (xi_d' * inf_d) ./ Float64(n)
    boot_stats = Array(boot_stats_d)

    CUDA.unsafe_free!(xi_d)
    CUDA.unsafe_free!(inf_d)
    CUDA.unsafe_free!(boot_stats_d)

    # Compute max t-stats on CPU
    max_t_stats = zeros(biters)
    for b in 1:biters
        for s in 1:n_gt
            if se[s] > 0
                t_stat = abs(boot_stats[b, s]) / se[s]
                if t_stat > max_t_stats[b]
                    max_t_stats[b] = t_stat
                end
            end
        end
    end
    sort!(max_t_stats)
    crit_val = max_t_stats[Int(ceil((1 - alp) * biters))]

    return se, crit_val
end

end # module
