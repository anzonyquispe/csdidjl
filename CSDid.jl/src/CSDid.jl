module CSDid

using DataFrames
using CSV
using Statistics
using SparseArrays
using LinearAlgebra
using StatsModels
using StatsBase
using Random
using Printf

include("types.jl")
include("gpu_stubs.jl")
include("mpdta.jl")
include("estimators.jl")
include("att_gt.jl")
include("aggte.jl")

export att_gt, aggte, mpdta
export CSDidResult, AGGTEResult
export summary_attgt, summary_aggte
export gpu_available

end # module
