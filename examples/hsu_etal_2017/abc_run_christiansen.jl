## ExoplanetsSysSim/examples/run_abc.jl
## (c) 2015 Eric B. Ford

include(joinpath(Pkg.dir(),"ExoplanetsSysSim","examples","hsu_etal_2017", "abc_setup_christiansen.jl"))
include(joinpath(Pkg.dir(),"ExoplanetsSysSim","examples","hsu_etal_2017", "process_abc_output.jl"))


using SysSimABC
using JLD

start_ind = 1
final_ind = 1

for n in start_ind:final_ind
  abc_plan = setup_abc(1)
  @time output = SysSimABC.run_abc(abc_plan)
  make_plots(output, EvalSysSimModel.get_ss_obs(), n)

  println("")
  println("Test ", n)
  println("")
  println("Mean = ")
  println(reshape(mean(output.theta,2), (1, size(output.theta,1))))
  println("")
  println("Standard deviation = ")
  println(reshape(std(output.theta,2), (1, size(output.theta,1))))
  println("")
  println(EvalSysSimModel.get_ss_obs())
  println("-----------------------------")
  save(string("test-",n,"-out.jld"), "output", output, "ss_true", EvalSysSimModel.get_ss_obs())
end
