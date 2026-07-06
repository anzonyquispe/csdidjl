## gpu_tests.jl — GPU acceleration tests for CSDid
##
## Usage:
##   set JULIA_CUDA_USE_BINARYBUILDER=false
##   julia --project=C:/Users/Usuario/CSDid.jl test/gpu_tests.jl
##
## Auto-skips if CUDA is not available.

using Test
using DataFrames

# ── Check CUDA availability first ─────────────────────────────
has_cuda = false
try
    @eval using CUDA
    global has_cuda = CUDA.functional()
catch
end

if !has_cuda
    @info "CUDA not available — skipping GPU tests"
    @testset "GPU (skipped)" begin
        @test true
    end
    exit(0)
end

@info "CUDA available: $(CUDA.name(CUDA.device())) — running GPU tests"

# Load CSDid AFTER CUDA so the extension triggers
using CSDid

@test gpu_available()

@testset "CSDid GPU Acceleration" begin

    df = mpdta()

    @testset "att_gt GPU vs CPU — DR" begin
        result_cpu = att_gt(
            yname="lemp", tname="year", idname="countyreal",
            gname="first_treat", data=df,
            est_method="dr", use_gpu=false, seed=12345)

        result_gpu = att_gt(
            yname="lemp", tname="year", idname="countyreal",
            gname="first_treat", data=df,
            est_method="dr", use_gpu=true, seed=12345)

        # Point estimates must be identical (GPU only affects bootstrap)
        for i in eachindex(result_cpu.att)
            @test result_gpu.att[i] ≈ result_cpu.att[i] atol=1e-10
        end

        # SEs should match to high precision
        for i in eachindex(result_cpu.se)
            @test result_gpu.se[i] ≈ result_cpu.se[i] atol=1e-10
        end

        # Critical value should match
        @test result_gpu.crit_val ≈ result_cpu.crit_val atol=1e-10
    end

    @testset "att_gt GPU vs CPU — IPW" begin
        result_cpu = att_gt(
            yname="lemp", tname="year", idname="countyreal",
            gname="first_treat", data=df,
            est_method="ipw", use_gpu=false, seed=12345)

        result_gpu = att_gt(
            yname="lemp", tname="year", idname="countyreal",
            gname="first_treat", data=df,
            est_method="ipw", use_gpu=true, seed=12345)

        for i in eachindex(result_cpu.att)
            @test result_gpu.att[i] ≈ result_cpu.att[i] atol=1e-10
        end
        for i in eachindex(result_cpu.se)
            @test result_gpu.se[i] ≈ result_cpu.se[i] atol=1e-10
        end
    end

    @testset "att_gt GPU vs CPU — Reg" begin
        result_cpu = att_gt(
            yname="lemp", tname="year", idname="countyreal",
            gname="first_treat", data=df,
            est_method="reg", use_gpu=false, seed=12345)

        result_gpu = att_gt(
            yname="lemp", tname="year", idname="countyreal",
            gname="first_treat", data=df,
            est_method="reg", use_gpu=true, seed=12345)

        for i in eachindex(result_cpu.att)
            @test result_gpu.att[i] ≈ result_cpu.att[i] atol=1e-10
        end
        for i in eachindex(result_cpu.se)
            @test result_gpu.se[i] ≈ result_cpu.se[i] atol=1e-10
        end
    end

    @testset "gpu_available() returns true" begin
        @test gpu_available() == true
    end
end

println("\nAll CSDid GPU tests passed.")
