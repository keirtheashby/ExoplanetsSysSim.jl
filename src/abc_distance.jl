## ExoplanetsSysSims/src/abc_distance.jl
## (c) 2015 Eric B. Ford

dist_L1_fractional(x::Real, y::Real) =  (x==y==0.0) ? 0.0 : abs( (x-y)*2/(x+y) )
dist_L1_abs(x::Real, y::Real) =  abs(x-y)
dist_L2_fractional(x::Real, y::Real) =  (x==y==0.0) ? 0.0 : abs( (x-y)^2*2/(x^2+y^2) )
dist_L2_abs(x::Real, y::Real) =  (x-y)^2

# Library of functions to convert distance vector into a scalar distance
calc_scalar_distance_sum(d::Vector{Float64}) = sum(d)
calc_scalar_distance_rms(d::Vector{Float64}) = sqrt(sumsq(d))
calc_scalar_distance_max(d::Vector{Float64}) = maximum(d)

# How to combine two distances based on subsets of the full distance vector (should always be greater than either for two pass algorithm to work)
combine_scalar_distances_sum(d1::Float64, d2::Float64) = d1+d2
combine_scalar_distances_rms(d1::Float64, d2::Float64) = sqrt(d1*d1+d2*d2)
combine_scalar_distances_max(d1::Float64, d2::Float64) = max(d1,d2)

# Pick which one to be used
calc_scalar_distance(d::Vector{Float64}) = calc_scalar_distance_sum(d)
combine_scalar_distances(d1::Float64, d2::Float64) = combine_scalar_distances_sum(d1,d2)

# compute supremum of differences between empirical cdfs.
# Borrowed from JuliaStats/HypothesisTests.jl
function ksstats{T<:Real, S<:Real}(x::AbstractVector{T}, y::AbstractVector{S})
    n_x, n_y = length(x), length(y)
    sort_idx = sortperm([x; y])
    pdf_diffs = [ones(n_x)/n_x; -ones(n_y)/n_y][sort_idx]
    cdf_diffs = cumsum(pdf_diffs)
    deltap = maximum(cdf_diffs)
    deltan = -minimum(cdf_diffs)
    delta = max(deltap,deltan)
    (n_x, n_y, deltap, deltan, delta)
end
# weighted version   # WARNING:  Function is untested
function ksstats{T<:Real, S<:Real}(x::AbstractVector{T}, y::AbstractVector{S}, wx::AbstractVector{T}, wy::AbstractVector{T})
    n_x, n_y = length(x), length(y)
    wx .*= 1.0/sum(wx)
    wy .*= 1.0/sum(wy)
    sort_idx = sortperm([x; y])
    pdf_diffs = [wx; -wy][sort_idx]
    cdf_diffs = cumsum(pdf_diffs)
    deltap = maximum(cdf_diffs)
    deltan = -minimum(cdf_diffs)
    delta = max(deltap,deltan)
    (n_x, n_y, deltap, deltan, delta)  # should the first two values returned here be sum(wx) and sum(wy) before normalizing?  For now, we ignore all but the final delta anyway.
end

dist_KS{T<:Real, S<:Real}(x::AbstractVector{T}, y::AbstractVector{S}) = ksstats(x,y)[5]
dist_KS{T<:Real, S<:Real}(x::AbstractVector{T}, y::AbstractVector{S}, wx::AbstractVector{T}, wy::AbstractVector{T}) = ksstats(x,y,wx,wy)[5]

# TODO SCI: IMPORTANT:  Replace this distance function with something well thought out
function calc_distance_vector_demo(summary1::CatalogSummaryStatistics, summary2::CatalogSummaryStatistics, pass::Int64, sim_param::SimParam ; verbose::Bool = false)
  d = Array{Float64}(0)
  if pass == 1
    if verbose
      println("# Summary 1, pass 1: ",summary1)
      println("# Summary 2, pass 1: ",summary2)
    end
    d = zeros(3)
    # Since observed and simulated catalogs can have different summary statistics for the number of planets, prefer detections if avaliable (e.g., after pass2), otherwise use expected (e.g., from pass 1)
    np1 = haskey(summary1.stat,"planets detected") ? summary1.stat["planets detected"] : summary1.stat["expected planets detected"]
    np2 = haskey(summary2.stat,"planets detected") ? summary2.stat["planets detected"] : summary2.stat["expected planets detected"]
    d[1] = dist_L1_abs(np1/summary1.stat["num targets"],np2/summary2.stat["num targets"])    #  Normalize so different statistics weighted appropriately and not dominated by this one
    #println("np1 = ",np1,", np2 = ",np2)
    #println("np1 (normalized) = ",np1/summary1.stat["num targets"],", np2 (normalized) = ",np2/summary2.stat["num targets"],", d[1] = ",d[1])
    #d[2] = dist_L1_abs(summary1.stat["mean log10 P"],summary2.stat["mean log10 P"])
    #d[3] = dist_L1_abs(summary1.stat["mean log10 depth"],summary2.stat["mean log10 depth"])
    #d[4] = dist_L1_abs(summary1.stat["std log10 P"],summary2.stat["std log10 P"])
    #d[5] = dist_L1_abs(summary1.stat["std log10 depth"],summary2.stat["std log10 depth"])
    #d[2] = dist_KS(summary1.stat["P list"], summary2.stat["P list"])
    #d[3] = dist_KS(summary1.stat["depth list"], summary2.stat["depth list"])
    # EDITS for christiansen-single-bin
    #d[2] = dist_KS(summary1.stat["P list"], summary2.stat["P list"],summary1.stat["weight list"],summary2.stat["weight list"])
    #d[3] = dist_KS(summary1.stat["depth list"], summary2.stat["depth list"],summary1.stat["weight list"],summary2.stat["weight list"])
    # END EDITS
  elseif pass == 2
    max_tranets_in_sys = get_int(sim_param,"max_tranets_in_sys")
    d = zeros(max_tranets_in_sys)
    for n in 1:max_tranets_in_sys
      d[n] = n*dist_L1_abs(summary1.stat["num_sys_tranets"][n]/summary1.stat["num targets"],summary2.stat["num_sys_tranets"][n]/summary2.stat["num targets"])
    end
  else
    println("# calc_distance_vector_demo doesn't know what to do for pass= ", pass)
  end
  return d
end

function test_abc_distance(cat_obs::KeplerObsCatalog, cat_phys::KeplerPhysicalCatalog, sim_param::SimParam)
  ss_pass1 = calc_summary_stats_sim_pass_one_demo(cat_obs,cat_phys,sim_param)
  ss_pass2 = calc_summary_stats_sim_pass_two_demo(cat_obs,cat_phys,ss_pass1,sim_param)
  d1 = calc_distance_vector_demo(ss_pass1,ss_pass1, 1, sim_param)
  d2 = calc_distance_vector_demo(ss_pass2,ss_pass2, 2, sim_param)
end





