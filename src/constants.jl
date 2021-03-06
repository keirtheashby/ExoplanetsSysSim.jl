## ExoplanetsSysSim/src/mission_constants.jl
## (c) 2015 Eric B. Ford

const global num_channels = 84
 const global num_modules = 42
 const global num_quarters = 17              # QUERY:  I'm favoring leaving out quarter 0, since that was engineering data.  Agree?
 const global num_cdpp_timescales = 1        # TODO SCI: Increase if incorporate CDPPs for multiple timescales, also LC/SC issue
 const global mission_data_span = 1459.789   # maximum(ExoplanetsSysSim.StellarTable.df[:dataspan])
 const global mission_duty_cycle = 0.8751    # median(ExoplanetsSysSim.StellarTable.df[:dutycycle])

 const global kepler_exp_time_internal  =  6.019802903/(24*60*60)    # https://archive.stsci.edu/kepler/manuals/archive_manual.pdf
 const global kepler_read_time_internal = 0.5189485261/(24*60*60)    # https://archive.stsci.edu/kepler/manuals/archive_manual.pdf
 const global num_exposures_per_LC = 270
 const global num_exposures_per_SC = 9
 const global LC_integration_time = kepler_exp_time_internal*num_exposures_per_LC
 const global SC_integration_time = kepler_exp_time_internal*num_exposures_per_SC
 const global LC_read_time = kepler_read_time_internal*num_exposures_per_LC
 const global SC_read_time = kepler_read_time_internal*num_exposures_per_SC
 const global LC_duration = LC_integration_time +  LC_read_time 
 const global SC_duration = SC_integration_time +  SC_read_time
 const global LC_rate = 1.0/LC_duration
 const global SC_rate = 1.0/SC_duration

# Standard conversion factors on which unit system is based
const global AU_in_m_IAU2012 = 149597870700.0
 const global G_in_mks_IAU2015 = 6.67384e-11
 const global G_mass_sun_in_mks = 1.3271244e20
 const global G_mass_earth_in_mks = 3.986004e8
 const global sun_radius_in_m_IAU2015 = 6.9566e8
 const global earth_radius_eq_in_m_IAU2015 = 6.3781e6
 const global sun_mass_in_kg_IAU2010 = 1.988547e30

# Constants used by this code
const global sun_mass = 1.0
 const global earth_mass = G_mass_earth_in_mks/G_mass_sun_in_mks  # about 3.0024584e-6
 const global earth_radius = earth_radius_eq_in_m_IAU2015 / sun_radius_in_m_IAU2015 # about 0.0091705248
 const global rsol_in_au = sun_radius_in_m_IAU2015 / AU_in_m_IAU2012  # about 0.00464913034   
 const global sec_in_day = 24*60*60
 const global grav_const = G_in_mks_IAU2015 * sec_in_day^2 * sun_mass_in_kg_IAU2010 / AU_in_m_IAU2012^3 # about 2.9591220363e-4 in AU^3/(day^2 Msol) 


