## ExoplanetsSysSim/examples/setup_abc_christiansen.jl
## (c) 2016 Eric B. Ford & Danley C. Hsu

module EvalSysSimModel
  export setup, get_param_vector, get_ss_obs #, evaluate_model
  export gen_data, calc_summary_stats, calc_distance, is_valid
  using ExoplanetsSysSim
  include(joinpath(Pkg.dir(),"ExoplanetsSysSim","examples","hsu_etal_2017", "christiansen_func.jl"))
  include(joinpath(pwd(), "param_file.jl"))

  sim_param_closure = SimParam()
  summary_stat_ref_closure =  CatalogSummaryStatistics()

    function is_valid(param_vector::Vector{Float64})
      global sim_param_closure
      update_sim_param_from_vector!(param_vector,sim_param_closure)
      const sigma_log_r = get_real(sim_param_closure,"sigma_log_planet_radius")
      const sigma_log_P = get_real(sim_param_closure,"sigma_log_planet_period")
      const rate_tab::Array{Float64,2} = get_any(sim_param_closure, "obs_par", Array{Float64,2})
      const lambda = sum_kbn(rate_tab)
    # println("Lambda = ", lambda)
      if sigma_log_r <= 0. || sigma_log_P<=0. || lambda > 10. || any(x -> x < 0., rate_tab)
         return false
      end
      return true
    end

#=
    function norm_christiansen(param_vector::Vector{Float64})
      log_z_sum = logsumexp(param_vector)
      param_vector = exp(param_vector-z_sum)
    end
=#

    function gen_data(param_vector::Vector{Float64})
      global sim_param_closure
      update_sim_param_from_vector!(param_vector,sim_param_closure)
      cat_phys = generate_kepler_physical_catalog(sim_param_closure)
      cat_phys_cut = ExoplanetsSysSim.generate_obs_targets(cat_phys, sim_param_closure)
      cat_obs = ExoplanetsSysSim.observe_kepler_targets_single_obs(cat_phys_cut, sim_param_closure)
      return cat_obs
    end

    function calc_summary_stats(cat::KeplerObsCatalog )
      global sim_param_closure
      #sum_stat = calc_summary_stats_obs_binned_rates(cat[1], sim_param_closure)
      sum_stat = calc_summary_stats_obs_binned_rates(cat, sim_param_closure)
      return sum_stat
    end

    function calc_distance(sum_stat_obs::CatalogSummaryStatistics,sum_stat_sim::CatalogSummaryStatistics, n::Integer = 0)
      global sim_param_closure
      dist1 = calc_distance_vector_binned(sum_stat_obs,sum_stat_sim, 1, sim_param_closure)
      num_available = length(dist1)
      num_to_use = n>0 ? min(n,num_available) : num_available
      return calc_scalar_distance(dist1[1:num_to_use])
    end

  function setup()
    global sim_param_closure = setup_sim_param_christiansen()

    sim_param_closure = set_test_param(sim_param_closure)
    add_param_fixed(sim_param_closure,"stellar_catalog","q1_q12_christiansen.jld")
    
    ### Use simulated planet candidate catalog data
    add_param_fixed(sim_param_closure,"num_kepler_targets",150969)  # For "observed" catalog
    cat_obs = simulated_read_kepler_observations(sim_param_closure)
    #inv_det_prob(cat_obs, sim_param_closure)
    #println("------------------------")
    global summary_stat_ref_closure = calc_summary_stats_obs_binned_rates(cat_obs,sim_param_closure, trueobs_cat = true)
    ###
    
    ### Use real planet candidate catalog data
    #add_param_fixed(sim_param_closure,"koi_catalog","q1_q16_koi_cand.csv")
    #cat_obs = setup_actual_planet_candidate_catalog(setup_star_table_christiansen(sim_param_closure), sim_param_closure)
    #global summary_stat_ref_closure = calc_summary_stats_obs_binned_rates(cat_obs,sim_param_closure, trueobs_cat = true)
    ###

    num_targ = get_int(sim_param_closure,"num_kepler_targets")
    add_param_fixed(sim_param_closure,"num_targets_sim_pass_one",num_targ)  # Set universal simulated catalog size

  end

  get_param_vector() = make_vector_of_sim_param(sim_param_closure)
  get_ss_obs() = summary_stat_ref_closure

  function set_simparam_ss(sim_param::ExoplanetsSysSim.SimParam, ss_true::ExoplanetsSysSim.CatalogSummaryStatistics)
    global sim_param_closure = sim_param
    global summary_stat_ref_closure = ss_true
  end

end  # module EvalSysSimModel

include(joinpath(Pkg.dir("ABC"),"src/composite.jl"))

module SysSimABC
  export setup_abc, run_abc
  import ABC
  import Distributions
  using CompositeDistributions
  import ExoplanetsSysSim
  import EvalSysSimModel
  include(joinpath(Pkg.dir(),"ExoplanetsSysSim","examples","hsu_etal_2017", "christiansen_func.jl"))
  include(joinpath(pwd(), "param_file.jl"))

  function setup_abc(num_dist::Integer = 0)
    EvalSysSimModel.setup()
    #println("# setup_abc: ",EvalSysSimModel.sim_param_closure)
    theta_true = EvalSysSimModel.get_param_vector()
    param_prior = CompositeDist( Distributions.ContinuousDistribution[Distributions.Uniform(0., 1.) for x in 1:length(theta_true)] )
    in_parallel = nworkers() > 1 ? true : false

    calc_distance_ltd(sum_stat_obs::ExoplanetsSysSim.CatalogSummaryStatistics,sum_stat_sim::ExoplanetsSysSim.CatalogSummaryStatistics) = EvalSysSimModel.calc_distance(sum_stat_obs,sum_stat_sim,num_dist)

    global abc_plan = ABC.abc_pmc_plan_type(EvalSysSimModel.gen_data,EvalSysSimModel.calc_summary_stats,calc_distance_ltd, param_prior, make_proposal_dist=ABC.make_proposal_dist_gaussian_diag_covar, is_valid=EvalSysSimModel.is_valid,
                                     num_part=40, num_max_attempt=50, num_max_times=200, epsilon_init=9.9e99, target_epsilon=1.0e-100, in_parallel=in_parallel, adaptive_quantiles = false, epsilon_reduction_factor=0.9, tau_factor=2.0);
  end

  function run_abc_largegen(pop::ABC.abc_population_type, ss_true::ExoplanetsSysSim.CatalogSummaryStatistics, epshist_targ::Float64, npart::Integer = 1000, num_dist::Integer = 0)
    sim_param_closure = setup_sim_param_christiansen()
    sim_param_closure = set_test_param(sim_param_closure)
    #add_param_fixed(sim_param_closure,"num_kepler_targets",150000)  # For "observed" catalog
    EvalSysSimModel.set_simparam_ss(sim_param_closure, ss_true)	

    theta_true = EvalSysSimModel.get_param_vector()
    param_prior = CompositeDist( Distributions.ContinuousDistribution[Distributions.Uniform(0., 1.) for x in 1:length(theta_true)] )
    in_parallel = nworkers() > 1 ? true : false

    calc_distance_ltd(sum_stat_obs::ExoplanetsSysSim.CatalogSummaryStatistics,sum_stat_sim::ExoplanetsSysSim.CatalogSummaryStatistics) = EvalSysSimModel.calc_distance(sum_stat_obs,sum_stat_sim,num_dist)

    global abc_plan = ABC.abc_pmc_plan_type(EvalSysSimModel.gen_data,EvalSysSimModel.calc_summary_stats,calc_distance_ltd, param_prior, is_valid=EvalSysSimModel.is_valid,
                                     num_part=npart, num_max_attempt=50, num_max_times=1, epsilon_init=9.9e99, target_epsilon=1.0e-100, in_parallel=in_parallel);

    println("# run_abc_largegen: ",EvalSysSimModel.sim_param_closure)
    sampler_plot = abc_plan.make_proposal_dist(pop, abc_plan.tau_factor)
    theta_plot = Array{Float64}(size(pop.theta, 1), npart)
    for i in 1:npart
      theta_plot[:,i], dist_plot, attempts_plot = ABC.generate_theta(abc_plan, sampler_plot, ss_true, epshist_targ)
    end
    return theta_plot
  end

  function run_abc(abc_plan::ABC.abc_pmc_plan_type)
    println("# run_abc: ",EvalSysSimModel.sim_param_closure)
    ss_true = EvalSysSimModel.get_ss_obs()
    #println("True catalog SS: ", ss_true)
    pop_out = ABC.run_abc(abc_plan,ss_true;verbose=true)
  end

  function run_abc(abc_plan::ABC.abc_pmc_plan_type, pop::ABC.abc_population_type)
    dist_threshold = maximum(pop.dist)
    EvalSysSimModel.add_param_fixed(EvalSysSimModel.sim_param_closure,"minimum ABC dist skip pass 2",dist_threshold)
    println("# run_abc: ",EvalSysSimModel.sim_param_closure)
    ss_true = EvalSysSimModel.get_ss_obs()
    pop_out = ABC.run_abc(abc_plan,ss_true,pop;verbose=true)
  end

end # module SysSimABC
