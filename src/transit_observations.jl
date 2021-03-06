## ExoplanetsSysSim/src/transit_observations.jl
## (c) 2015 Eric B. Ford

#using Distributions
#include("constants.jl")

#  Starting Section of Observables that are actually used
immutable TransitPlanetObs
  # ephem::ephemeris_type     # For now hardcode P and t0, see transit_observation_unused.jl to reinstate
  period::Float64             # days
  t0::Float64                 # days
  depth::Float64              # fractional
  duration::Float64           # days; Full-width, half-max-duration until further notice  
  # ingress_duration::Float64   # days;  QUERY:  Will we want to use the ingress/egress duration for anything?
end
TransitPlanetObs() = TransitPlanetObs(0.0,0.0,0.0,0.0)

immutable StarObs
  radius::Float64      # in Rsol
  mass::Float64        # in Msol
end


semimajor_axis(P::Float64, M::Float64) = (grav_const/(4pi^2)*M*P*P)^(1/3)

function semimajor_axis(ps::PlanetarySystemAbstract, id::Integer)
  M = mass(ps.star) + ps.planet[id].mass   # TODO SCI DETAIL: Replace with Jacobi mass?  Probably not important unless start including TTVs at some point
  @assert(M>0.0)
  @assert(ps.orbit[id].P>0.0)
  return semimajor_axis(ps.orbit[id].P,M)
end

function calc_transit_depth(t::KeplerTarget, s::Integer, p::Integer)  # WARNING: IMPORTANT: Assumes non-grazing transit & no limb darkening
  depth = (t.sys[s].planet[p].radius/t.sys[s].star.radius)^2 # TODO SCI DETAIL: Include limb darkening?
  depth *=  flux(t.sys[s].star)/flux(t)                      # Flux ratio accounts for dillution
end

function calc_transit_duration_central_circ(ps::PlanetarySystemAbstract, pl::Integer)
  duration = rsol_in_au*ps.star.radius * ps.orbit[pl].P /(pi*semimajor_axis(ps,pl) )    
end
calc_transit_duration_central_circ(t::KeplerTarget, s::Integer, p::Integer) = calc_transit_duration_central_circ(t.sys[s],p)


function calc_transit_duration_central(ps::PlanetarySystemAbstract, pl::Integer)
  ecc = ps.orbit[pl].ecc
  vel_fac = sqrt((1+ecc)*(1-ecc))/(1+ecc*sin(ps.orbit[pl].omega))
  duration = calc_transit_duration_central_circ(ps,pl) * vel_fac
end
calc_transit_duration_central(t::KeplerTarget, s::Integer, p::Integer) = calc_transit_duration_central(t.sys[s],p)

function calc_transit_duration(ps::PlanetarySystemAbstract, pl::Integer)
  a = semimajor_axis(ps,pl)
  @assert a>=zero(a)
  ecc = ps.orbit[pl].ecc
  @assert zero(ecc)<=ecc<=one(ecc)
  b = (a*abs(cos(ps.orbit[pl].incl))/(ps.star.radius*rsol_in_au)) * (1+ecc)*(1-ecc)/(1+ecc*sin(ps.orbit[pl].omega))
  @assert !isnan(b)
  @assert zero(b)<=b
  vel_fac = sqrt((1+ecc)*(1-ecc))/(1+ecc*sin(ps.orbit[pl].omega))
  duration = 0.0<=b<1.0 ? calc_transit_duration_central_circ(ps,pl) * vel_fac * sqrt((1-b)*(1+b)) : 0.0
end
calc_transit_duration(t::KeplerTarget, s::Integer, p::Integer ) = calc_transit_duration(t.sys[s],p)

function calc_expected_num_transits(t::KeplerTarget, s::Integer, p::Integer, sim_param::SimParam)  
 period = t.sys[s].orbit[p].P
 exp_num_transits = t.duty_cycle * t.data_span/period
 #= 
 if exp_num_transits <=6 
 end
 # TODO SCI DETAIL: Calculate more accurat number of transits, perhaps using star and specific window function or perhaps specific times of data gaps more given module
 =#
 return exp_num_transits
end

include("transit_detection_model.jl")
include("transit_prob_geometric.jl")

type KeplerTargetObs                        # QUERY:  Do we want to make this type depend on whether the catalog is based on simulated or real data?
  obs::Vector{TransitPlanetObs}
  sigma::Vector{TransitPlanetObs}           # Simplistic approach to uncertainties for now.  QUERY: Should estimated uncertainties be part of Observations type?
  # snr::Vector{Float64}                      # Dimensionless SNR of detection for each planet QUERY: Should we store this here?
  # phys_id::Vector{tuple(Int32,Int32)}       # So we can lookup the system's properties for 0.3.*
  phys_id::Vector{Tuple{Int32,Int32}}     # So we can lookup the system's properties for 0.4

  prob_detect::SystemDetectionProbsAbstract  # QUERY: Specialize type of prob_detect depending on whether for simulated or real data?

  has_sc::Vector{Bool}                      # TODO OPT: Make Immutable Vector or BitArray to reduce memory use?  QUERY: Should this go in KeplerTargetObs?

  star::StarObs                             # TODO SCI DETAIL: Add more members to StarObs, so can used observed rather than actual star properties
end
KeplerTargetObs(n::Integer) = KeplerTargetObs( fill(TransitPlanetObs(),n), fill(TransitPlanetObs(),n), fill(tuple(0,0),n),  ObservedSystemDetectionProbsEmpty(),  fill(false,num_quarters), StarObs(0.0,0.0) )
num_planets(t::KeplerTargetObs) = length(t.obs)

function calc_target_obs_sky_ave(t::KeplerTarget, sim_param::SimParam)
  const max_tranets_in_sys = get_int(sim_param,"max_tranets_in_sys")
  const transit_noise_model = get_function(sim_param,"transit_noise_model")
  const min_detect_prob_to_be_included = 0.0  # get_real(sim_param,"min_detect_prob_to_be_included")
  const num_observer_samples = 1 # get_int(sim_param,"num_viewing_geometry_samples")

  np = num_planets(t)
  obs = Array{TransitPlanetObs}(np)
  sigma = Array{TransitPlanetObs}(np)
  #id = Array{Tuple{Int32,Int32}}(np)
  id = Array{Tuple{Int32,Int32}}(np)
  ns = length(t.sys)
  sdp_sys = Array{SystemDetectionProbsAbstract}(ns)
  i = 1
  for (s,sys) in enumerate(t.sys)
    pdet = zeros(num_planets(sys))
    for (p,planet) in enumerate(sys.planet)
      if get(sim_param,"verbose",false)
         println("# s=",s, " p=",p," num_sys= ",length(t.sys), " num_pl= ",num_planets(sys) )
      end
        ntr = calc_expected_num_transits(t, s, p, sim_param)
        period = sys.orbit[p].P
        # t0 = rand(Uniform(0.0,period))   # WARNING: Not being calculated from orbit
        depth = calc_transit_depth(t,s,p)
        duration_central = calc_transit_duration_central(t,s,p)
	snr_central = calc_snr_if_transit(t, depth, duration_central, sim_param, num_transit=ntr)
	pdet_ave = calc_ave_prob_detect_if_transit(t, snr_central, sim_param, num_transit=ntr)
	add_to_catalog = pdet_ave > min_detect_prob_to_be_included  # Include all planets with sufficient detection probability
	if add_to_catalog
	   const hard_max_num_b_tries = 100
	   max_num_b_tries = min_detect_prob_to_be_included == 0. ? hard_max_num_b_tries : min(hard_max_num_b_tries,convert(Int64,1/min_detect_prob_to_be_included))
           pdet_this_b = 0.0
           for j in 1:max_num_b_tries
              b = rand()  # WARNING: Making an approximation: Using a uniform distribution for b (truncated to ensure detection probability >0) when generating measurement uncertainties, rather than accounting for increased detection probability for longer duration transits
              transit_duration_factor = sqrt((1+b)*(1-b)) 
	      duration = duration_central * transit_duration_factor
	      snr = snr_central * transit_duration_factor
              pdet_this_b = calc_prob_detect_if_transit(t, snr, sim_param, num_transit=ntr)
              if pdet_this_b > 0.0 
	         pdet[p] = pdet_ave  
                 obs[i], sigma[i] = transit_noise_model(t, s, p, depth, duration, snr, ntr)   # WARNING: noise properties don't have correct dependance on b
                 id[i] = tuple(convert(Int32,s),convert(Int32,p))
      	         i += 1
                 break 
              end
           end
	else
	   # Do anything for planets that are extremely unlikely to be detected even if they were to transit?
	end
    end
    resize!(obs,i-1)
    resize!(sigma,i-1)
    resize!(id,i-1)
    sdp_sys[s] = calc_simulated_system_detection_probs(sys, pdet, max_tranets_in_sys=max_tranets_in_sys, min_detect_prob_to_be_included=min_detect_prob_to_be_included, num_samples=num_observer_samples)
  end
  # TODO SCI DETAIL: Combine sdp_sys to allow for target to have multiple planetary systems
  s1 = findfirst(x->num_planets(x)>0,sdp_sys)  # WARNING IMPORTANT: For now just take first system with planets
  if s1 == 0 
     s1 = 1
  end
  sdp_target = sdp_sys[s1]

  has_no_sc = fill(false,num_quarters)
  star_obs = StarObs( t.sys[1].star.radius, t.sys[1].star.mass )  # TODO SCI DETAIL: Could improve.  WARNING: ASSUMES STAR IS KNOWN PERFECTLY
  return KeplerTargetObs(obs, sigma, id, sdp_target, has_no_sc, star_obs )
end


function calc_target_obs_single_obs(t::KeplerTarget, sim_param::SimParam)
  #const max_tranets_in_sys = get_int(sim_param,"max_tranets_in_sys")
  const transit_noise_model = get_function(sim_param,"transit_noise_model")
  const min_detect_prob_to_be_included = 0.0  # get_real(sim_param,"min_detect_prob_to_be_included")

  np = num_planets(t)
  obs = Array{TransitPlanetObs}(np)
  sigma = Array{TransitPlanetObs}(np)
  #id = Array{Tuple{Int32,Int32}}(np)
  id = Array{Tuple{Int32,Int32}}(np)
  ns = length(t.sys)
  #sdp_sys = Array{SystemDetectionProbsAbstract}(ns)
  sdp_sys = Array{ObservedSystemDetectionProbs}(ns)
  i = 1
  for (s,sys) in enumerate(t.sys)
    pdet = zeros(num_planets(sys))
    for (p,planet) in enumerate(sys.planet)
      if get(sim_param,"verbose",false)
         println("# s=",s, " p=",p," num_sys= ",length(t.sys), " num_pl= ",num_planets(sys) )
      end
        duration = calc_transit_duration(t,s,p)
	if duration <= 0.
	   continue
	end
        ntr = calc_expected_num_transits(t, s, p, sim_param)
        period = sys.orbit[p].P
        # t0 = rand(Uniform(0.0,period))   # WARNING: Not being calculated from orbit
        depth = calc_transit_depth(t,s,p)
	snr = calc_snr_if_transit(t, depth, duration, sim_param, num_transit=ntr)
	pdet[p] = calc_prob_detect_if_transit(t, snr, sim_param, num_transit=ntr)
	if pdet[p] > min_detect_prob_to_be_included   
           obs[i], sigma[i] = transit_noise_model(t, s, p, depth, duration, snr, ntr) 
           id[i] = tuple(convert(Int32,s),convert(Int32,p))
      	   i += 1
	end
    end
    resize!(obs,i-1)
    resize!(sigma,i-1)
    resize!(id,i-1)
    sdp_sys[s] = ObservedSystemDetectionProbs(pdet)
  end
  # TODO SCI DETAIL: Combine sdp_sys to allow for target to have multiple planetary systems
  s1 = findfirst(x->num_planets(x)>0,sdp_sys)  # WARNING: For now just take first system with planets, assumes not two stars wht planets in one target
  if s1 == 0 
     s1 = 1
  end
  sdp_target = sdp_sys[s1]

  has_no_sc = fill(false,num_quarters)
  star_obs = StarObs( t.sys[1].star.radius, t.sys[1].star.mass )  # TODO SCI DETAIL: Could improve.  WARNING: ASSUMES STAR IS KNOWN PERFECTLY
  return KeplerTargetObs(obs, sigma, id, sdp_target, has_no_sc, star_obs )
end


function test_transit_observations(sim_param::SimParam; verbose::Bool=false)  # TODO TEST: Add more tests
  #transit_param = TransitParameter( EphemerisLinear(10.0, 0.0), TransitShape(0.01, 3.0/24.0, 0.5) )
  generate_kepler_target = get_function(sim_param,"generate_kepler_target")
  const max_it = 100000
  local obs
  for i in 1:max_it
    target = generate_kepler_target(sim_param)::KeplerTarget
    while num_planets(target) == 0
      target = generate_kepler_target(sim_param)::KeplerTarget
    end
    calc_transit_prob_single_planet_one_obs(target,1,1)
    calc_transit_prob_single_planet_obs_ave(target,1,1)
    obs = calc_target_obs_single_obs(target,sim_param)
    obs = calc_target_obs_sky_ave(target,sim_param)
    if verbose && (num_planets(obs) > 0)
      println("# i= ",string(i)," np= ",num_planets(obs), " obs= ", obs )
      break
    end
  end
  return obs
end


randtn() = rand(TruncatedNormal(0.0,1.0,-0.999,0.999))

function transit_noise_model_no_noise(t::KeplerTarget, s::Integer, p::Integer, depth::Float64, duration::Float64, snr::Float64)   
  period = t.sys[s].orbit[p].P
  t0 = rand(Uniform(0.0,period))    # WARNING: Not being calculated from orbit
  sigma_period = 0.0
  sigma_t0 = 0.0
  sigma_depth =  0.0
  sigma_duration =  0.0
  sigma = TransitPlanetObs( sigma_period, sigma_t0, sigma_depth, sigma_duration )
  obs = TransitPlanetObs( period, t0, depth,duration)
  return obs, sigma
end

function transit_noise_model_fixed_noise(t::KeplerTarget, s::Integer, p::Integer, depth::Float64, duration::Float64, snr::Float64, num_tr::Real) 
  period = t.sys[s].orbit[p].P
  t0 = rand(Uniform(0.0,period))   # WARNING: Not being calculated from orbit

  sigma_period = 1e-6
  sigma_t0 = 1e-4
  sigma_depth =  0.01
  sigma_duration =  0.01

  sigma = TransitPlanetObs( sigma_period, sigma_t0, sigma_depth, sigma_duration)
  #obs = TransitPlanetObs( period, t0, depth, duration)
  obs = TransitPlanetObs( period*(1.0+sigma.period*randtn()), t0*(1.0+sigma.period*randtn()), depth*(1.0+sigma.depth*randtn()),duration*(1.0+sigma.duration*randtn()))
  return obs, sigma
end

function transit_noise_model_diagonal(t::KeplerTarget, s::Integer, p::Integer, depth::Float64, duration::Float64, snr::Float64, num_tr::Real) 
  period = t.sys[s].orbit[p].P
  t0 = rand(Uniform(0.0,period))    # WARNING: Not being calculated from orbit

	# Use variable names from Price & Rogers
	one_minus_e2 = (1-t.sys[s].orbit[p].ecc)*(1+t.sys[s].orbit[p].ecc)
	a_semimajor_axis = semimajor_axis(t.sys[s],p)
	b = a_semimajor_axis *cos(t.sys[s].orbit[p].incl)/t.sys[s].star.radius
        b *= one_minus_e2/(1+t.sys[s].orbit[p].ecc*sin(t.sys[s].orbit[p].omega))
	tau0 = t.sys[s].star.radius*period/(a_semimajor_axis*2pi)
	tau0 *= sqrt(one_minus_e2)/(1+t.sys[s].orbit[p].ecc*sin(t.sys[s].orbit[p].omega))
	r = t.sys[s].planet[p].radius/t.sys[s].star.radius
	sqrt_one_minus_b2 = (0.0<=b<1.0) ? sqrt((1-b)*(1+b)) : 0.0
 	T = 2*tau0*sqrt_one_minus_b2
	tau = 2*tau0*r/sqrt_one_minus_b2
	Ttot = period
	I = LC_integration_time      # WARNING: Assumes LC only
	Lambda_eff = LC_rate * num_tr # calc_expected_num_transits(t, s, p, sim_param)
	delta = depth
	sigma = t.cdpp[1,1]

	# Price & Rogers Eqn A8 & Table 1 # WARNING: Someone should check Eqns
	tau3 = tau^3
	I3 = I^3
	#a1 = (10*tau3+2*I^3-5*tau*I^2)/tau3
	a2 = (5*tau3+I3-5*tau*tau*I)/tau3
	a3 = (9*I^5*Ttot-40*tau3+I*I*Ttot+120*tau^4*I*(3*Ttot-2*tau))/tau^6
	a4 = (a3*tau^5+I^4*(54*tau-35*Ttot)-12*tau*I3*(4*tau+Ttot)+360*tau^4*(tau-Ttot))/tau^5
	a5 = a2*(24T*T*(I-3*tau)-24*T*Ttot*(I-3*tau)+tau3*a4)/tau3
	#a6 = (3*tau*tau+T*(I-3*tau))/(tau*tau)
	#a7 = (-60*tau^4+12*a2*tau3*T-9*I^4+8*tau*I3+40*tau3*I)/(tau^4)
	#a8 = (2T-Ttot)/tau
	#a9 = (-3*tau*tau*I*(-10*T*T+10*T*Ttot+I*(2*I+5*Ttot))-I^4*Ttot+8*tau*I3*Ttot)/(tau^5)
	#a10 = ((a9+60)*tau*tau+10*(-9*T*T+9*T*Tot+I*(3*I+Tot))-75*tau*Ttot)/(tau*tau)
	a11 = (I*Ttot-3tau*(Ttot-2*tau))/(tau*tau)
	#a12 = (-360*tau^5-24*a2*tau3*T*(I-3tau)+9*I^5-35tau*I^4-12tau*tau*I3-40tau^3*I*I+360*tau^4*I)/(tau^5)
	a13 = (-3*I3*(8*T*T-8*T*Ttot+3*I*Ttot)+120*tau*tau*T*I*(T-Ttot)+8tau*I3*Ttot)/tau^5
	a14 = (a13*tau*tau+40*(-3*T*T+3*T*Ttot+I*Ttot)-60*tau*Ttot)/tau^5
	a15 = (2I-6tau)/tau
	b1  = (6*I*I-3*I*Ttot+tau*Ttot)/(I*I)
	b2  = (tau*T+3*I*(I-T))/(I*I)
	b3 = (tau3-12T*I*I+8I3+20tau*I*I-8*tau*tau*I)/I3
	b4 = (6*T*T-6*T*Ttot+I*(5Ttot-4I))/(I*I)
	b5 = (10I-3tau)/I
	b6 = (12b4*I3+4tau*(-6*T*T+6T*Ttot+I*(13*Ttot-30I)))/I3
	b7 = (b6*I^5+4*tau*tau*I*I*(12I-11Ttot)+tau3*I*(11Ttot-6I)-tau^4*Ttot)/I^5
	b8 = (3T*T-3*T*Ttot+I*Ttot)/(I*I)
	b9 = (8*b8*I^4+20*tau*I*I*Ttot-8*tau*tau*I*Ttot+tau3*Ttot)/I^4
	#b10 =  (-tau^4+24*T*I*I*(tau-3I)+60*I^4+52*tau*I3-44*tau*tau*I*I+11*tau3*I)/I^4
	#b11 =  (-15b4*i3+10b8*tau*I*I+15*tau*tau*(2I-Ttot))/I3
	#b12 =  (b11*I^5+2tau3*I*(4Ttot-3I)-tau^4*Ttot)/I^5
	#b13 =  (Ttot-2T)/I
	#b14 =  (6I-2tau)/I
	
        Q = snr/sqrt(num_tr)
        sigma_t0 = tau>=I ?  sqrt(0.5*tau*T/(1-I/(3tau)))/Q : sqrt(0.5*I  *T/(1-tau/(3I)))/Q
        sigma_period = sigma_t0/sqrt(num_tr)                 
        sigma_duration = tau>=I ? sigma*sqrt(abs(6*tau*a14/(delta*delta*a5)) /Lambda_eff )  : sigma*sqrt(abs(6*I*b9/(delta*delta*b7)) / Lambda_eff)
        sigma_depth = tau>=I ? sigma*sqrt(abs(-24*a11*a2/(tau*a5)) / Lambda_eff)  : sigma*sqrt(abs(24*b1/(I*b7)) / Lambda_eff)

  	sigma = TransitPlanetObs( sigma_period, sigma_t0, sigma_depth, sigma_duration )

        local obs
        if true     # Assume uncertainties uncorrelated (Diagonal)
  	    obs = TransitPlanetObs( period*(1.0+sigma.period*randtn()), t0*(1.0+sigma.period*randtn()), depth*(1.0+sigma.depth*randtn()),duration*(1.0+sigma.duration*randtn()))
        else        # TODO SCI DETAIL:  Account for correlated uncertaintties in transit parameters
            cov = zeros(4,4)
        if tau>=I 
	#cov[0,0] = -3tau/(delta*delta*a15)
	cov[1,1] = 24*tau*a10/(delta*delta*a5)
	cov[1,2] = cov[2,1] = 36*a8*tau*a1/(delta*delta*a5) 
	cov[1,3] = cov[3,1] = -12*a11*a1/(delta*a5) 
	cov[1,4] = cov[4,1] = -12*a6*a1/(delta*a5)
	cov[2,2] = 6*tau*a14/(delta*delta*a5)
	cov[2,3] = cov[3,2] = 72*a8*a2/(delta*a5)
	cov[2,4] = cov[4,2] = 6*a7/(delta*a5)
	cov[3,3] = -24*a11*a2/(tau*a5)
	cov[3,4] = cov[4,3] = -24*a6*a2/(tau*a5)
	cov[4,4] = a12/(tau*a5)
        else
	#cov[0,0] = -3I/(delta*delta*b14)
	cov[1,1] = -24*I*I*b12/(delta*delta*b7)
	cov[1,2] = cov[2,1] = 36*I*b13*b5/(delta*delta*b7) 
	cov[1,3] = cov[3,1] = 12*b5*b1/(delta*b7) 
	cov[1,4] = cov[4,1] = 12*b5*b2/(delta*b7)
	cov[2,2] = 6*I*b9/(delta*delta*b7)
	cov[2,3] = cov[3,2] = 72*b13/(delta*b7)
	cov[2,4] = cov[4,2] = 6*b3/(delta*b7)
	cov[3,3] = 24*b1/(I*b7)
	cov[3,4] = cov[4,3] = 24*b2/(I*b7)
	cov[4,4] = b10/(I*b7)
	end
	cov .*= sigma*sigma/Lambda_eff
	obs_dist = MvNormal(zeros(4),cov)	     

	local obs_duration, obs_depth, sigma_duration, sigma_depth
        isvalid = false
	while !isvalid
	  obs_vec = rand(obs_dist)
          obs_duration = duration + obs_vec[2]
          obs_depth = depth + obs_vec[3]	
          if (obs_duration>0.0) && (obs_depth>0.0)
             isvalid = true
	  end
	end
     	    obs = TransitPlanetObs( period*(1.0+sigma.period*randtn()), t0*(1.0+sigma.period*randtn()), obs_depth,obs_duration)
        end
  	return obs, sigma
end

