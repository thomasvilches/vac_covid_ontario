This is an ABM, implemented in Julia Language, that mimics vaccination strategies and the spread of COVID-19 used in the work "Projecting the impact of a two-dose COVID-19 vaccination campaign in Ontario, Canada"

The code is based on the one created by Affan Shoukat https://github.com/affans/covid19abm.jl

We impplemented vaccination that provides a level of individual immunity againt COVID-19. The population-based parameters are adjusted to populationof Ontario-Canada.

In order to run the simulations, inside the Julia software, use

include("simulations.jl") if you are using a regular hardware

or

include("simulations_cluster.jl") if you are using a cluster

WARNING: Note that, in those files, you can change the number of nodes and cores that are used for paralelization.
Also, make sure that the path inside function "create_folder()" exists

In file "covid19_abm2.jl" you can find the parameters of the model. In special, one can turn on and off the complete isolation of severe cases setting fsevere to 1.0 (complete isolation) or zero (no isolation)

You can run the scenarios using the function run_param() which needs 9 arguments

1 - beta - probability of transmission
2 - herd immunity proportion - it is a vector... the accepted values are [0; 3; 5; 10; 20]
3 - vaccine efficacy - vector with the values of vaccine efficacy one wants to run: values between 0 and 1
4 - vac_bool - apply vaccination?
5 - db - how many days before the epidemics the vaccination starts?
6 - vr - vaccination rate - proportion of population that is vaccinated per day. It is used 0.8% and 0.6%
7 - nsims - number of monte carlo simulations
