module covid19abm
using Parameters, Distributions, StatsBase, StaticArrays, Random, Match, DataFrames

@enum HEALTH SUS LAT PRE ASYMP MILD MISO INF IISO HOS ICU REC DED UNDEF

Base.@kwdef mutable struct Human
    idx::Int64 = 0 
    health::HEALTH = SUS
    swap::HEALTH = UNDEF
    sickfrom::HEALTH = UNDEF
    wentTo::HEALTH = UNDEF
    sickby::Int64 = -1
    nextday_meetcnt::Int16 = 0 ## how many contacts for a single day
    age::Int16   = 0    # in years. don't really need this but left it incase needed later
    ag::Int16   = 0
    tis::Int16   = 0   # time in state 
    exp::Int16   = 0   # max statetime
    dur::NTuple{4, Int8} = (0, 0, 0, 0)   # Order: (latents, asymps, pres, infs) TURN TO NAMED TUPS LATER
    doi::Int16   = 999   # day of infection.
    iso::Bool = false  ## isolated (limited contacts)
    isovia::Symbol = :null ## isolated via quarantine (:qu), preiso (:pi), intervention measure (:im), or contact tracing (:ct)    
    tracing::Bool = false ## are we tracing contacts for this individual?
    tracestart::Int16 = -1 ## when to start tracing, based on values sampled for x.dur
    traceend::Int16 = -1 ## when to end tracing
    tracedby::UInt32 = 0 ## is the individual traced? property represents the index of the infectious person 
    tracedxp::Int16 = 0 ## the trace is killed after tracedxp amount of days
    comorbidity::Int8 = 0 ##does the individual has any comorbidity?
    vac_status::Int8 = 0 ##
    vac_ef_symp::Float16 = 0.0 
    vac_ef_inf::Float16 = 0.0 
    vac_ef_sev::Float16 = 0.0
    index_day::Int16 = 1 ## this index is used to account for the change in vaccine efficacy
    infby::Int64 = -1
    got_inf::Bool = false
    herd_im::Bool = false
    hospicu::Int8 = -1
    shelter_in::Bool = false
    hcw::Bool = false
    protection::Int64 = 0
    days_vac::Int64 = -1
    vac_red::Float64 = 0.0
    ag_new::Int16 = -1
end

## default system parameters
@with_kw mutable struct ModelParameters @deftype Float64    ## use @with_kw from Parameters
    β = 0.058       
    seasonal::Bool = false ## seasonal betas or not
    popsize::Int64 = 10000
    prov::Symbol = :ontario
    calibration::Bool = false
    calibration2::Bool = false  
    modeltime::Int64 = 500
    initialinf::Int64 = 1
    initialhi::Int64 = 0 ## initial herd immunity, inserts number of REC individuals
    τmild::Int64 = 0 ## days before they self-isolate for mild cases
    fmild::Float64 = 0.0  ## percent of people practice self-isolation
    fsevere::Float64 = 0.0 #
    eldq::Float64 = 0.0 ## complete isolation of elderly
    eldqag::Int8 = 5 ## default age group, if quarantined(isolated) is ag 5. 
    fpreiso::Float64 = 0.0 ## percent that is isolated at the presymptomatic stage
    fasymp::Float64 = 0.0 ## percent that is isolated at the presymptomatic stage
    tpreiso::Int64 = 1## preiso is only turned on at this time. 
    frelasymp::Float64 = 0.26 ## relative transmission of asymptomatic
    ctstrat::Int8 = 0 ## strategy 
    fctcapture::Float16 = 0.0 ## how many symptomatic people identified
    fcontactst::Float16 = 0.0 ## fraction of contacts being isolated/quarantined
    cidtime::Int8 = 0  ## time to identification (for CT) post symptom onset
    cdaysback::Int8 = 0 ## number of days to go back and collect contacts
    #vaccine_ef::Float16 = 0.0   ## change this to Float32 typemax(Float32) typemax(Float64)
    apply_vac::Bool = false
    apply_vac_com::Bool = true #will we focus vaccination on comorbidity?
    vac_com_dec_max::Float16 = 0.0#5 # how much the comorbidity decreases the vac eff
    vac_com_dec_min::Float16 = 0.0#1 # how much the comorbidity decreases the vac eff
    herd::Int8 = 0 #typemax(Int32) ~ millions
    set_g_cov::Bool = false ###Given proportion for coverage
    cov_val::Float64 = 0.7
    fixed_cov::Float64 = 0.4
    no_cap::Bool = true

    isoscenario::Int16 = 0
    maskcomp::Float64 = 0.0
    m_ef::Float64 = 0.0
    vaccinating_appendix::Bool = false
    
    hcw_vac_comp::Float64 = 0.95
    hcw_prop::Float64 = 0.05
    comor_comp::Float64 = 0.7
    eld_comp::Float64 = 0.95
    gen_cov::Float64 = 0.7
    young_comp::Float64 = 0.22
    vac_period::Int64 = 21
    sec_dose_comp::Float64 = 0.7

    days_to_protection::Array{Array{Int64,1},1} = [[14],[0;14]]
    vac_efficacy_inf::Array{Array{Float64,1},1} = [[0.46],[0.6;0.93]]  #### 50:5:80
    vac_efficacy_symp::Array{Array{Float64,1},1} = [[0.921],[0.921;0.941]]  #### 50:5:80
    vac_efficacy_sev::Array{Array{Float64,1},1} = [[0.802],[0.941;1.0]]  #### 50:5:80

    vaccinating::Bool = false
    days_before::Int64 = 0 ### six weeks of vaccination
    single_dose::Bool = false
    drop_rate::Float64 = 0.0

    decrease_protection::Float64 = 0.0

    fd_1::Array{Int64,1} = [0;1; 1; 2; 3; 8; 8; 8; 6; 3; 8; 6; 11; 16; 22; 24; 32; 38; 45; 50] #daily vaccination rate
    
    fd_2::Int64 = 0 #first-dose doses when second one is given
    sd1::Array{Int64,1} = fd_1 #second-dose doses
    sec_dose_delay::Int64 = vac_period #delay in second dose
    
    days_change_vac_rate::Array{Int64,1} = [75;map(y->y+75,map(x->(x-1)*6+1, 2:length(fd_1)-1))] #when the vaccination rate is changed
    

    max_vac_delay::Int64 = 42
    min_eff = 0.02
    ef_decrease_per_week = 0.0
    vac_effect::Int64 = 2

    time_increase::Int64 = 999
    much_increase::Float64 = 0.0
    n_days_inc::Int64 = 20
    rate_inc::Float64 = much_increase/n_days_inc
    time_change_contact::Array{Int64,1} = [1;map(y->76+y,0:9);map(y->88+y,0:19);map(y->136+y,0:4);map(y->time_increase+y,0:(n_days_inc-1))]#map(x->x-50,[231;233;235;237;239;241;243;245;247;249]) #times for change in contact average
    change_rate_values::Array{Float64,1} = [1.0;map(y->1+0.018*y,1:10);map(y->1.18-0.018*y,1:20);map(y->0.82+0.036*y,1:5);map(y->1.0+rate_inc*y,1:n_days_inc)]#map(x->x*2-1,[1.01;1.02;1.03;1.04;1.05;1.06;1.07;1.08;1.09;1.10]) # values of change rate
    contact_change_rate::Float64 = 1.0 #the rate
    priority::Bool = false
    contact_change_2::Float64 = 0.28
end

Base.@kwdef mutable struct ct_data_collect
    total_symp_id::Int64 = 0  # total symptomatic identified
    totaltrace::Int64 = 0     # total contacts traced
    totalisolated::Int64 = 0  # total number of people isolated
    totalisolated_init::Int64 = 0  # total number of people isolated
    iso_sus::Int64 = 0        # total susceptible isolated 
    iso_lat::Int64 = 0        # total latent isolated
    iso_asymp::Int64 = 0      # total asymp isolated
    iso_symp::Int64 = 0       # total symp (mild, inf) isolated
end

Base.show(io::IO, ::MIME"text/plain", z::Human) = dump(z)

## constants 
const humans = Array{Human}(undef, 0) 
const p = ModelParameters()  ## setup default parameters
const agebraks = @SVector [0:4, 5:19, 20:49, 50:64, 65:99]
const agebraks_new = @SVector [0:4, 5:19, 20:49, 50:64, 65:79, 80:99]
const BETAS = Array{Float64, 1}(undef, 0) ## to hold betas (whether fixed or seasonal), array will get resized
const ct_data = ct_data_collect()
export ModelParameters, HEALTH, Human, humans, BETAS

function runsim(simnum, ip::ModelParameters)
    # function runs the `main` function, and collects the data as dataframes. 
    hmatrix,h_init = main(ip,simnum)            
    # get infectors counters
    infectors = _count_infectors()

    ct_numbers = (ct_data.total_symp_id, ct_data.totaltrace, ct_data.totalisolated, ct_data.totalisolated_init,
                    ct_data.iso_sus, ct_data.iso_lat, ct_data.iso_asymp, ct_data.iso_symp)
    ###use here to create the vector of comorbidity
    # get simulation age groups
    ags = [x.ag_new for x in humans] # store a vector of the age group distribution 
    all = _collectdf(hmatrix)
    spl = _splitstate(hmatrix, ags)
    ag1 = _collectdf(spl[1])
    ag2 = _collectdf(spl[2])
    ag3 = _collectdf(spl[3])
    ag4 = _collectdf(spl[4])
    ag5 = _collectdf(spl[5])
    ag6 = _collectdf(spl[6])
    insertcols!(all, 1, :sim => simnum); insertcols!(ag1, 1, :sim => simnum); insertcols!(ag2, 1, :sim => simnum); 
    insertcols!(ag3, 1, :sim => simnum); insertcols!(ag4, 1, :sim => simnum); insertcols!(ag5, 1, :sim => simnum); insertcols!(ag6, 1, :sim => simnum)

    ##getting info about vac, comorbidity
   # vac_idx = [x.vac_status for x in humans]
    #vac_ef_i = [x.vac_ef for x in humans]
   # comorb_idx = [x.comorbidity for x in humans]
   # ageg = [x.ag for x = humans ]

    #n_vac = sum(vac_idx)
    n_vac_sus1::Int64 = 0
    n_vac_rec1::Int64 = 0
    n_inf_vac1::Int64 = 0
    n_dead_vac1::Int64 = 0
    n_hosp_vac1::Int64 = 0
    n_icu_vac1::Int64 = 0
    
    n_hosp_nvac::Int64 = 0
    n_dead_nvac::Int64 = 0
    n_inf_nvac::Int64 = 0
    n_icu_nvac::Int64 = 0

    n_vac_sus2::Int64 = 0
    n_vac_rec2::Int64 = 0
    n_inf_vac2::Int64 = 0
    n_dead_vac2::Int64 = 0
    n_hosp_vac2::Int64 = 0
    n_icu_vac2::Int64 = 0

    n_com_vac1 = zeros(Int64,6)
    n_ncom_vac1 = zeros(Int64,6)
    n_com_vac2 = zeros(Int64,6)
    n_ncom_vac2 = zeros(Int64,6)
    n_com_total = zeros(Int64,6)
    n_ncom_total = zeros(Int64,6)

    for x in humans
        if x.vac_status == 1
            if x.herd_im
                n_vac_rec1 += 1
            else
                n_vac_sus1 += 1
            end
            if x.got_inf
                n_inf_vac1 += 1
            end
            if x.health == DED
                n_dead_vac1 += 1
            end
            if x.hospicu == 1
                n_hosp_vac1 += 1
            elseif x.hospicu == 2
                n_icu_vac1 += 1
            end
            if x.comorbidity == 1
                n_com_vac1[x.ag_new] += 1
                n_com_total[x.ag_new] += 1
            else
                n_ncom_vac1[x.ag_new] += 1
                n_ncom_total[x.ag_new] += 1
            end
        elseif x.vac_status == 2
            if x.herd_im
                n_vac_rec2 += 1
            else
                n_vac_sus2 += 1
            end
            if x.got_inf
                n_inf_vac2 += 1
            end
            if x.health == DED
                n_dead_vac2 += 1
            end
            if x.hospicu == 1
                n_hosp_vac2 += 1
            elseif x.hospicu == 2
                n_icu_vac2 += 1
            end
            if x.comorbidity == 1
                n_com_vac2[x.ag_new] += 1
                n_com_total[x.ag_new] += 1
            else
                n_ncom_vac2[x.ag_new] += 1
                n_ncom_total[x.ag_new] += 1
            end
        else
            if x.got_inf
                n_inf_nvac += 1
            end
            if x.health == DED
                n_dead_nvac += 1
            end
            if x.hospicu == 1
                n_hosp_nvac += 1
            elseif x.hospicu == 2
                n_icu_nvac += 1
            end

            if x.comorbidity == 1
                n_com_total[x.ag_new] += 1
            else
                n_ncom_total[x.ag_new] += 1
            end
        end
      
    end
    
    aux_r0 = findall(y->y.infby in h_init, humans)
    R0 = length(aux_r0)/length(h_init)

    #return (a=all, g1=ag1, g2=ag2, g3=ag3, g4=ag4, g5=ag5, infectors=infectors, vi = vac_idx,ve=vac_ef_i,com = comorb_idx,n_vac = n_vac,n_inf_vac = n_inf_vac,n_inf_nvac = n_inf_nvac)
    return (a=all, g1=ag1, g2=ag2, g3=ag3, g4=ag4, g5=ag5, g6=ag6, infectors=infectors,
    com_v1 = n_com_vac1,ncom_v1 = n_ncom_vac1,
    com_v2 = n_com_vac2,ncom_v2 = n_ncom_vac2,
    com_t=n_com_total,ncom_t=n_ncom_total,
    n_vac_sus1 = n_vac_sus1,
    n_vac_rec1 = n_vac_rec1,
    n_inf_vac1 = n_inf_vac1,
    n_dead_vac1 = n_dead_vac1,
    n_hosp_vac1 = n_hosp_vac1,
    n_icu_vac1 = n_icu_vac1,
    n_vac_sus2 = n_vac_sus2,
    n_vac_rec2 = n_vac_rec2,
    n_inf_vac2 = n_inf_vac2,
    n_dead_vac2 = n_dead_vac2,
    n_hosp_vac2 = n_hosp_vac2,
    n_icu_vac2 = n_icu_vac2,
    n_inf_nvac = n_inf_nvac,
    n_dead_nvac = n_dead_nvac,
    n_hosp_nvac = n_hosp_nvac,
    n_icu_nvac = n_icu_nvac,
    iniiso = ct_data.totalisolated_init, R0 = R0)
end
export runsim

function main(ip::ModelParameters,sim::Int64)
    Random.seed!(sim*726)
    #println("$sim")
    ## datacollection            
    # matrix to collect model state for every time step

    # reset the parameters for the simulation scenario
    reset_params(ip)  #logic: outside "ip" parameters are copied to internal "p" which is a global const and available everywhere. 

    p.popsize == 0 && error("no population size given")
    
    hmatrix = zeros(Int16, p.popsize, p.modeltime)
    initialize() # initialize population
    
    # insert initial infected agents into the model
    # and setup the right swap function. 
    h_init::Int64 = 0
    # insert initial infected agents into the model
    # and setup the right swap function. 
    if p.calibration 
         herd_immu_dist(sim)
         h_init = insert_infected(PRE, p.initialinf, 4)[1]
    elseif p.calibration2 
        herd_immu_dist(sim)
        h_init = insert_infected(PRE, p.initialinf, 4)[1]
        #insert_infected(REC, p.initialhi, 4)
    else
        #applying_vac(sim)
        herd_immu_dist(sim)
        h_init = insert_infected(PRE, p.initialinf, 4)[1]
    end    
    
    #selecting people to be vaccinated
 
    ## save the preisolation isolation parameters
    _fpreiso = p.fpreiso
    p.fpreiso = 0

    # split population in agegroups 
    grps = get_ag_dist()
    count_change::Int64 = 1
   # iso_scenarios(humans)
    # start the time loop
    if p.vaccinating

        vac_ind2 = vac_selection(sim)
        vac_ind = Array{Int64,1}(undef,length(vac_ind2))
        for i = 1:length(vac_ind2)
            vac_ind[i] = vac_ind2[i]
        end
        v1,v2 = vac_index_new(length(vac_ind))
        
        time_vac::Int64 = 1
        
       #=  if p.days_before > 0
            tt = min(p.days_before,length(v1)-1)
            for time_vac_aux = 1:tt#p.days_before
               time_vac = time_vac_aux
                vac_ind2 = vac_time!(vac_ind,time_vac,v1,v2)
                resize!(vac_ind, length(vac_ind2))
                for i = 1:length(vac_ind2)
                    vac_ind[i] = vac_ind2[i]
                end
                for x in humans
                    vac_update(x)
                end
                if time_vac_aux%6 == 0
                    for x in humans
                        vac_update(x)
                    end
                end
            end
        end         =#
        for st = 1:p.modeltime
            # start of day
            #println("$st")
            if time_vac <= (length(v1)-1)
                
                vac_ind2 = vac_time!(vac_ind,time_vac,v1,v2)
                #vac_ind = [vac_ind vac_ind2]
                resize!(vac_ind, length(vac_ind2))
                for i = 1:length(vac_ind2)
                    vac_ind[i] = vac_ind2[i]
                end
                time_vac += 1
              
            end
            if length(p.time_change_contact) >= count_change && p.time_change_contact[count_change] == st
                setfield!(p, :contact_change_rate, p.change_rate_values[count_change])
                count_change += 1
            end
            #=if st == p.tpreiso ## time to introduce testing
            global  p.fpreiso = _fpreiso
            end=#
            _get_model_state(st, hmatrix) ## this datacollection needs to be at the start of the for loop
            dyntrans(st, grps)
            sw = time_update()
            # end of day
        end
    else
        for st = 1:p.modeltime
            if length(p.time_change_contact) >= count_change && p.time_change_contact[count_change] == st
                setfield!(p, :contact_change_rate, p.change_rate_values[count_change])
                count_change += 1
            end
            # start of day
            #println("$st")
            #=if st == p.tpreiso ## time to introduce testing
            global  p.fpreiso = _fpreiso
            end=#
            _get_model_state(st, hmatrix) ## this datacollection needs to be at the start of the for loop
            dyntrans(st, grps)
            sw = time_update()
            # end of day
        end
    end


    return hmatrix,h_init ## return the model state as well as the age groups. 
end
export main

function vac_selection(sim)
    rng = MersenneTwister(123*sim)

    pos = findall(x-> humans[x].age>=20 && humans[x].age<65,1:length(humans))
    pos_hcw = sample(rng,pos,Int(round(p.hcw_vac_comp*p.hcw_prop*p.popsize)),replace = false)
    
    for i in pos_hcw
        humans[i].hcw = true
    end

    pos_com = findall(x->humans[x].comorbidity == 1 && !(x in pos_hcw) && humans[x].age<65 && humans[x].age>=18, 1:length(humans))
    pos_com = sample(rng,pos_com,Int(round(p.comor_comp*length(pos_com))),replace=false)


    pos_eld = findall(x-> humans[x].age>=65, 1:length(humans))
    pos_eld = sample(rng,pos_eld,Int(round(p.eld_comp*length(pos_eld))),replace=false)

    pos_n_com = findall(x->humans[x].comorbidity == 0 && !(x in pos_hcw) && humans[x].age<65 && humans[x].age>=18, 1:length(humans))
    pos_n_com = sample(rng,pos_n_com,Int(round(p.gen_cov*length(pos_n_com))),replace=false)
    #pos_y = findall(x-> humans[x].age<18, 1:length(humans))
    #pos_y = sample(pos_y,Int(round(p.young_comp*length(pos_y))),replace=false)

    if p.priority
        aux1 = findall(y->humans[y].comorbidity==1,pos_eld)
        pos1 = shuffle(rng,[pos_com;pos_eld[aux1]])
        aux1 = findall(y->humans[y].comorbidity==0,pos_eld)
        pos1 = [pos1;pos_eld[aux1]]
    else
        pos1 = shuffle(rng,[pos_com;pos_eld])
    end
    #pos2 = shuffle([pos_n_com;pos_y])
    pos2 = shuffle(rng,pos_n_com)
    v = [pos_hcw; pos1; pos2]
    if p.set_g_cov
        if p.cov_val*p.popsize > length(v)
            error("general population compliance is not enough to reach the coverage.")
            exit(1)
        else
            aux = Int(round(p.cov_val*p.popsize))
            v = v[1:aux]
        end

    elseif p.no_cap
       
        ##nothing to do v is v

    else
        if p.fixed_cov*p.popsize > length(v)
            error("general population compliance is not enough to reach the coverage.")
            exit(1)
        else
            aux = Int(round(p.fixed_cov*p.popsize))
            v = v[1:aux]
        end
    end

    return v
end

function vac_index(l::Int64)

    daily_vac::Int64 = Int(round(p.daily_cov*p.popsize))
    prop::Float64 = p.single_dose ? 1.0 : 0.5

    if p.vac_period*daily_vac < l
        n1 = Int(ceil((l-p.vac_period*daily_vac)/(daily_vac*prop)))
        
        n2 = Int(ceil(((l-n1*Int(round(daily_vac*(1-prop))))/(daily_vac))))
        
        n1 = p.vac_period+n1+1

        n = Int(n1+n2)
        v1 = zeros(Int64,n)
        v2 = zeros(Int64,n)
        #First x days, there is only primary vac
        for i = 2:(p.vac_period+1)
            v1[i] = daily_vac+v1[i-1]
        end
        for i = (p.vac_period+2):(n1)
            v1[i] = Int(round(daily_vac*(prop)+v1[i-1]))
            v2[i] = Int(round(daily_vac*(1-prop)+v2[i-1]))
        end
        v1[n1] = l
        for i = (n1+1):n
            v2[i] = daily_vac+v2[i-1]
        end
        v2[n] = l

    else
        n1 = Int(ceil((l/(daily_vac))))
        
       # n2 = Int(ceil(((l-n1*Int(round(daily_vac*(1-prop))))/(daily_vac))))
        
        #n1 = p.vac_period+n1+1

        n = Int(p.vac_period+n1)
        v1 = zeros(Int64,n)
        v2 = zeros(Int64,n)
        #First x days, there is only primary vac
        for i = 2:(n1)
            v1[i] = daily_vac+v1[i-1]
        end

        v1[n1+1] = l
        for i = (p.vac_period+1):n
            v2[i] = daily_vac+v2[i-1]
        end
        v2[n] = l

    end
    if p.single_dose 
        for i = 1:length(v2)
            v2[i] = 0
        end
    end
    return v1,v2
end


function vac_index_new(l::Int64)

    v1 = Array{Int64,1}(undef,p.popsize);
    v2 = Array{Int64,1}(undef,p.popsize);
    #n::Int64 = p.fd_2+p.sd1
    v1_aux::Bool = false
    v2_aux::Bool = false
    kk::Int64 = 2

    if p.single_dose
        for i = 1:p.popsize
            v1[i] = -1
            v2[i] = -1
           
        end
        v1[1] = 0
        while !v1_aux
            v1[kk] = v1[kk-1]+n
            if v1[kk] >= l
                v1[kk] = l
                v1_aux = true
            end
            kk += 1

        end
        a = findfirst(x-> x == l, v1)

        for i = (a+1):length(v1)
            v1[i] = -1
        end
        a = a+1
    else
        for i = 1:p.popsize
            v1[i] = -1
            v2[i] = -1
        end
        jj::Int64 = 1 ###which vac rate we are looking at
        v1[1] = 0
        v2[1] = 0
        eligible::Int64 = 0
        extra_d::Int64 = 0
        for i = 2:(p.sec_dose_delay+1)
            #aux = map(x-> v1[x]-v1[x-1],1:(i-1))
            v1[i] = v1[i-1]+p.fd_1[jj]+extra_d
            v2[i] = 0
            if i > (p.vac_period+1)
                eligible = eligible+(v1[i-p.vac_period]-v1[i-p.vac_period-1])
            end
            if !(jj > length(p.days_change_vac_rate)) && i-1 == p.days_change_vac_rate[jj]
                jj += 1
            end
            #= if i-1 == p.extra_dose_day
                extra_d = p.extra_dose_n
            end =#
        end

        kk = p.sec_dose_delay+2
       

        #eligible::Int64 = 0
        last_v2::Int64 = 0
        while !v1_aux || !v2_aux
            
            n = p.sd1[jj]+p.fd_2+extra_d
            eligible = eligible+(v1[kk-p.vac_period]-v1[kk-p.vac_period-1])
            n1_a = v1_aux ? n : p.sd1[jj]+extra_d
            v2_1 = min(n1_a,eligible-last_v2)

            v2[kk] = last_v2+v2_1
            last_v2 = v2[kk]
            n_aux = n-v2_1
           
            v1[kk] = v1[kk-1]+n_aux

            if !(jj > length(p.days_change_vac_rate)) && kk-1 == p.days_change_vac_rate[jj] 
                jj += 1
            end
           #=  if kk-1 == p.extra_dose_day
                extra_d = p.extra_dose_n
            end =#
            
            if v1[kk] >= l
                v1[kk] = l
                v1_aux = true
            end

            if v2[kk] >= l
                v2[kk] = l
                v2_aux = true
            end
            kk += 1

        end

        a = findfirst(x-> x == l, v1)

        for i = (a+1):length(v1)
            v1[i] = -1
        end
        a = findfirst(x-> x == -1, v2)
    end

    return v1[1:(a-1)],v2[1:(a-1)]
end 

function vac_time!(vac_ind::Array{Int64,1},t::Int64,n_1_dose::Array{Int64,1},n_2_dose::Array{Int64,1})
    
    ##first dose
    for i = (n_1_dose[t]+1):1:n_1_dose[t+1]
        x = humans[vac_ind[i]]
        if x.vac_status == 0
            if x.health in (MILD, MISO, INF, IISO, HOS, ICU, DED)#,MILD2, MISO2, INF2, IISO2, HOS2, ICU2, DED2)
                #pos = findall(k-> !(humans[vac_ind[k]].health in (MILD, MISO, INF, IISO, HOS, ICU, DED,MILD2, MISO2, INF2, IISO2, HOS2, ICU2, DED2)) && k>n_1_dose[t+1],1:length(vac_ind))
                pos = findall(k-> !(humans[vac_ind[k]].health in (MILD, MISO, INF, IISO, HOS, ICU, DED)) && k>n_1_dose[t+1],1:length(vac_ind))
                
                if length(pos) > 0
                    r = rand(pos)
                    aux = vac_ind[i]
                    vac_ind[i] = vac_ind[r]
                    vac_ind[r] = aux
                    x = humans[vac_ind[i]]
                    x.days_vac = 0
                    x.vac_status = 1
                    x.index_day = 1
                end
            else
                x.days_vac = 0
                x.vac_status = 1
                x.index_day = 1
            end
            
        end
    end

    for i = (n_2_dose[t]+1):1:n_2_dose[t+1]
        x = humans[vac_ind[i]]

        if x.health in (MILD, MISO, INF, IISO, HOS, ICU, DED)#,MILD2, MISO2, INF2, IISO2, HOS2, ICU2, DED2)
            
            if t != (length(n_2_dose)-1)
                vac_ind = [vac_ind; x.idx]
                n_2_dose[end] += 1
            end
            
        else
            if !x.hcw
                 drop_out_rate = [p.drop_rate;p.drop_rate;p.drop_rate] 
               #= drop_out_rate = [0;0;0] =#
                ages_drop = [17;64;999]
                age_ind = findfirst(k->k>=x.age,ages_drop)
                if rand() < (1-drop_out_rate[age_ind])#p.sec_dose_comp
                    x = humans[vac_ind[i]]
                    #red_com = p.vac_com_dec_min+rand()*(p.vac_com_dec_max-p.vac_com_dec_min)
                    #x.vac_ef = ((1-red_com)^x.comorbidity)*(p.vac_efficacy/2.0)+(p.vac_efficacy/2.0)
                    x.days_vac = 0
                    x.vac_status = 2
                    x.index_day = 1
                end
            else
                #red_com = p.vac_com_dec_min+rand()*(p.vac_com_dec_max-p.vac_com_dec_min)
                #x.vac_ef = ((1-red_com)^x.comorbidity)*(p.vac_efficacy/2.0)+(p.vac_efficacy/2.0)
                x.days_vac = 0
                x.vac_status = 2
                x.index_day = 1
            end
        end
    end
    return vac_ind
end

function vac_update(x::Human)
    comm::Int64 = 0
    if x.age >= 65
        comm = 1
    else
        comm = x.comorbidity
    end

   #=  if x.vac_status > 0 
        if x.days_vac == p.days_to_protection[x.vac_status]
            if x.vac_status == 1
                red_com = x.vac_red #p.vac_com_dec_min+rand()*(p.vac_com_dec_max-p.vac_com_dec_min)
                aux = p.single_dose ? ((1-red_com)^comm)*(p.vac_efficacy) : ((1-red_com)^comm)*p.vac_efficacy_fd
                x.vac_ef = aux
            else
                red_com = x.vac_red#p.vac_com_dec_min+rand()*(p.vac_com_dec_max-p.vac_com_dec_min)
                x.vac_ef = ((1-red_com)^comm)*(p.vac_efficacy-p.vac_efficacy_fd)+x.vac_ef
            end
        end
        x.days_vac += 1
    end =#

    if x.vac_status == 1
        if x.days_vac == p.days_to_protection[x.vac_status][1]#14
            red_com = x.vac_red #p.vac_com_dec_min+rand()*(p.vac_com_dec_max-p.vac_com_dec_min)
            x.vac_ef_inf = p.vac_efficacy_inf[x.vac_status][1]
            x.vac_ef_symp = p.vac_efficacy_symp[x.vac_status][1]
            x.vac_ef_sev = p.vac_efficacy_sev[x.vac_status][1]

            x.index_day = min(length(p.days_to_protection[x.vac_status]),x.index_day+1)

        elseif x.days_vac == p.days_to_protection[x.vac_status][x.index_day]#14
            red_com = x.vac_red #p.vac_com_dec_min+rand()*(p.vac_com_dec_max-p.vac_com_dec_min)
            x.vac_ef_inf = (p.vac_efficacy_inf[x.vac_status][x.index_day]-p.vac_efficacy_inf[x.vac_status][x.index_day-1])+x.vac_ef_inf
            x.vac_ef_symp = (p.vac_efficacy_symp[x.vac_status][x.index_day]-p.vac_efficacy_symp[x.vac_status][x.index_day-1])+x.vac_ef_symp
            x.vac_ef_sev = (p.vac_efficacy_sev[x.vac_status][x.index_day]-p.vac_efficacy_sev[x.vac_status][x.index_day-1])+x.vac_ef_sev

            x.index_day = min(length(p.days_to_protection[x.vac_status]),x.index_day+1)

        end

        if !p.single_dose
            if x.days_vac > p.max_vac_delay #42
                x.vac_ef_inf = x.vac_ef_inf-(p.ef_decrease_per_week/7)#0.05/7
                if x.vac_ef_inf < p.min_eff #0.02
                    x.vac_ef_inf = p.min_eff
                end

                x.vac_ef_symp = x.vac_ef_symp-(p.ef_decrease_per_week/7)#0.05/7
                if x.vac_ef_symp < p.min_eff #0.02
                    x.vac_ef_symp = p.min_eff
                end

                x.vac_ef_sev = x.vac_ef_sev-(p.ef_decrease_per_week/7)#0.05/7
                if x.vac_ef_sev < p.min_eff #0.02
                    x.vac_ef_sev = p.min_eff
                end
            end
        end
        x.days_vac += 1
        
    elseif x.vac_status == 2
        if x.days_vac == p.days_to_protection[x.vac_status][1]#0
            if p.vac_effect == 1
                aux = (p.vac_efficacy_inf[x.vac_status][1]-p.vac_efficacy_inf[1][length(p.vac_efficacy_inf[1])])+x.vac_ef_inf #0.43 + x = second dose
                if aux < p.vac_efficacy_inf[1][length(p.vac_efficacy_inf[1])]
                    aux = p.vac_efficacy_inf[1][length(p.vac_efficacy_inf[1])]
                end
                aux1 = ((1-x.vac_red)^comm)*aux
                ##symp
                aux = (p.vac_efficacy_symp[x.vac_status][1]-p.vac_efficacy_symp[1][length(p.vac_efficacy_symp[1])])+x.vac_ef_symp #0.43 + x = second dose
                if aux < p.vac_efficacy_symp[1][length(p.vac_efficacy_symp[1])]
                    aux = p.vac_efficacy_symp[1][length(p.vac_efficacy_symp[1])]
                end
                aux2 = ((1-x.vac_red)^comm)*aux
                ##sev
                aux = (p.vac_efficacy_sev[x.vac_status][1]-p.vac_efficacy_sev[1][length(p.vac_efficacy_sev[1])])+x.vac_ef_sev #0.43 + x = second dose
                if aux < p.vac_efficacy_sev[1][length(p.vac_efficacy_sev[1])]
                    aux = p.vac_efficacy_sev[1][length(p.vac_efficacy_sev[1])]
                end
                aux3 = ((1-x.vac_red)^comm)*aux
            elseif p.vac_effect == 2
                aux1 = ((1- x.vac_red)^comm)*p.vac_efficacy_inf[x.vac_status][1] #0.95
                aux2 = ((1- x.vac_red)^comm)*p.vac_efficacy_symp[x.vac_status][1] #0.95
                aux3 = ((1- x.vac_red)^comm)*p.vac_efficacy_sev[x.vac_status][1] #0.95
            else
                error("Vaccinating but no vac effect")
            end
           #p.vac_com_dec_min+rand()*(p.vac_com_dec_max-p.vac_com_dec_min)
            x.vac_ef_inf = aux1
            x.vac_ef_symp = aux2
            x.vac_ef_sev = aux3

            x.index_day = min(length(p.days_to_protection[x.vac_status]),x.index_day+1)
        elseif x.days_vac == p.days_to_protection[x.vac_status][x.index_day]#7
            if p.vac_effect == 1
                aux = (p.vac_efficacy_inf[x.vac_status][x.index_day]-p.vac_efficacy_inf[x.vac_status][x.index_day-1])+x.vac_ef_inf #0.43 + x = second dose
                #= if aux < p.vac_efficacy_inf[1][length(p.vac_efficacy_inf[1])]
                    aux = p.vac_efficacy_inf[1][length(p.vac_efficacy_inf[1])]
                end =#
                aux1 = ((1-x.vac_red)^comm)*aux
                ##symp
                aux = (p.vac_efficacy_symp[x.vac_status][x.index_day]-p.vac_efficacy_symp[x.vac_status][x.index_day-1])+x.vac_ef_symp #0.43 + x = second dose
               #=  if aux < p.vac_efficacy_symp[1][length(p.vac_efficacy_symp[1])]
                    aux = p.vac_efficacy_symp[1][length(p.vac_efficacy_symp[1])]
                end =#
                aux2 = ((1-x.vac_red)^comm)*aux
                ##sev
                aux = (p.vac_efficacy_sev[x.vac_status][x.index_day]-p.vac_efficacy_sev[x.vac_status][x.index_day-1])+x.vac_ef_sev #0.43 + x = second dose
                #= if aux < p.vac_efficacy_sev[1][length(p.vac_efficacy_sev[1])]
                    aux = p.vac_efficacy_sev[1][length(p.vac_efficacy_sev[1])]
                end =#
                aux3 = ((1-x.vac_red)^comm)*aux
            elseif p.vac_effect == 2
                aux1 = ((1- x.vac_red)^comm)*p.vac_efficacy_inf[x.vac_status][x.index_day] #0.95
                aux2 = ((1- x.vac_red)^comm)*p.vac_efficacy_symp[x.vac_status][x.index_day] #0.95
                aux3 = ((1- x.vac_red)^comm)*p.vac_efficacy_sev[x.vac_status][x.index_day] #0.95
            else
                error("Vaccinating but no vac effect")
            end
           #p.vac_com_dec_min+rand()*(p.vac_com_dec_max-p.vac_com_dec_min)
            x.vac_ef_inf = aux1
            x.vac_ef_symp = aux2
            x.vac_ef_sev = aux3

            x.index_day = min(length(p.days_to_protection[x.vac_status]),x.index_day+1)
        end
        x.days_vac += 1
    end

end
reset_params_default() = reset_params(ModelParameters())
function reset_params(ip::ModelParameters)
    # the p is a global const
    # the ip is an incoming different instance of parameters 
    # copy the values from ip to p. 
    for x in propertynames(p)
        setfield!(p, x, getfield(ip, x))
    end

    # reset the contact tracing data collection structure
    for x in propertynames(ct_data)
        setfield!(ct_data, x, 0)
    end

    # resize and update the BETAS constant array
    init_betas()

    # resize the human array to change population size
    resize!(humans, p.popsize)
end
export reset_params, reset_params_default

function _model_check() 
    ## checks model parameters before running 
    (p.fctcapture > 0 && p.fpreiso > 0) && error("Can not do contact tracing and ID/ISO of pre at the same time.")
    (p.fctcapture > 0 && p.maxtracedays == 0) && error("maxtracedays can not be zero")
end

## Data Collection/ Model State functions
function _get_model_state(st, hmatrix)
    # collects the model state (i.e. agent status at time st)
    for i=1:length(humans)
        hmatrix[i, st] = Int(humans[i].health)
    end    
end
export _get_model_state

function _collectdf(hmatrix)
    ## takes the output of the humans x time matrix and processes it into a dataframe
    #_names_inci = Symbol.(["lat_inc", "mild_inc", "miso_inc", "inf_inc", "iiso_inc", "hos_inc", "icu_inc", "rec_inc", "ded_inc"])    
    #_names_prev = Symbol.(["sus", "lat", "mild", "miso", "inf", "iiso", "hos", "icu", "rec", "ded"])
    mdf_inc, mdf_prev = _get_incidence_and_prev(hmatrix)
    mdf = hcat(mdf_inc, mdf_prev)    
    _names_inc = Symbol.(string.((Symbol.(instances(HEALTH)[1:end - 1])), "_INC"))
    _names_prev = Symbol.(string.((Symbol.(instances(HEALTH)[1:end - 1])), "_PREV"))
    _names = vcat(_names_inc..., _names_prev...)
    datf = DataFrame(mdf, _names)
    insertcols!(datf, 1, :time => 1:p.modeltime) ## add a time column to the resulting dataframe
    return datf
end

function _splitstate(hmatrix, ags)
    #split the full hmatrix into 4 age groups based on ags (the array of age group of each agent)
    #sizes = [length(findall(x -> x == i, ags)) for i = 1:4]
    matx = []#Array{Array{Int64, 2}, 1}(undef, 4)
    for i = 1:6#length(agebraks)
        idx = findall(x -> x == i, ags)
        push!(matx, view(hmatrix, idx, :))
    end
    return matx
end
export _splitstate

function _get_incidence_and_prev(hmatrix)
    cols = instances(HEALTH)[1:end - 1] ## don't care about the UNDEF health status
    inc = zeros(Int64, p.modeltime, length(cols))
    pre = zeros(Int64, p.modeltime, length(cols))
    for i = 1:length(cols)
        inc[:, i] = _get_column_incidence(hmatrix, cols[i])
        pre[:, i] = _get_column_prevalence(hmatrix, cols[i])
    end
    return inc, pre
end

function _get_column_incidence(hmatrix, hcol)
    inth = Int(hcol)
    timevec = zeros(Int64, p.modeltime)
    for r in eachrow(hmatrix)
        idx = findfirst(x -> x == inth, r)
        if idx !== nothing 
            timevec[idx] += 1
        end
    end
    return timevec
end

function herd_immu_dist(sim::Int64)
    rng = MersenneTwister(200*sim)
    vec_n = zeros(Int32,5)
    if p.herd == 5
        vec_n = [11; 139; 254;  70; 26]
        
    elseif p.herd == 10
        vec_n = [34; 277; 482; 144; 63]
        
    elseif p.herd == 20
        vec_n = [77; 520; 944; 305; 154]
    elseif p.herd == 3
        vec_n = [7;84;150;43;16]
    end

    for g = 1:5

        pos = findall(y->y.ag == g,humans)
        n_dist = min(length(pos),vec_n[g])

        pos2 = sample(rng,pos,n_dist,replace=false)

        for i = pos2
            move_to_recovered(humans[i])
            humans[i].sickfrom = INF
            humans[i].herd_im = true
        end

    end

end

function _get_column_prevalence(hmatrix, hcol)
    inth = Int(hcol)
    timevec = zeros(Int64, p.modeltime)
    for (i, c) in enumerate(eachcol(hmatrix))
        idx = findall(x -> x == inth, c)
        if idx !== nothing
            ps = length(c[idx])    
            timevec[i] = ps    
        end
    end
    return timevec
end

function _count_infectors()     
    pre_ctr = asymp_ctr = mild_ctr = inf_ctr = 0
    for x in humans 
        if x.health != SUS ## meaning they got sick at some point
            if x.sickfrom == PRE
                pre_ctr += 1
            elseif x.sickfrom == ASYMP
                asymp_ctr += 1
            elseif x.sickfrom == MILD || x.sickfrom == MISO 
                mild_ctr += 1 
            elseif x.sickfrom == INF || x.sickfrom == IISO 
                inf_ctr += 1 
            else 
                error("sickfrom not set right: $(x.sickfrom)")
            end
        end
    end
    return (pre_ctr, asymp_ctr, mild_ctr, inf_ctr)
end

export _collectdf, _get_incidence_and_prev, _get_column_incidence, _get_column_prevalence, _count_infectors

## initialization functions 
function get_province_ag(prov) 
    ret = @match prov begin        
        #=:alberta => Distributions.Categorical(@SVector [0.0655, 0.1851, 0.4331, 0.1933, 0.1230])
        :bc => Distributions.Categorical(@SVector [0.0475, 0.1570, 0.3905, 0.2223, 0.1827])
        :canada => Distributions.Categorical(@SVector [0.0540, 0.1697, 0.3915, 0.2159, 0.1689])
        :manitoba => Distributions.Categorical(@SVector [0.0634, 0.1918, 0.3899, 0.1993, 0.1556])
        :newbruns => Distributions.Categorical(@SVector [0.0460, 0.1563, 0.3565, 0.2421, 0.1991])
        :newfdland => Distributions.Categorical(@SVector [0.0430, 0.1526, 0.3642, 0.2458, 0.1944])
        :nwterrito => Distributions.Categorical(@SVector [0.0747, 0.2026, 0.4511, 0.1946, 0.0770])
        :novasco => Distributions.Categorical(@SVector [0.0455, 0.1549, 0.3601, 0.2405, 0.1990])
        :nunavut => Distributions.Categorical(@SVector [0.1157, 0.2968, 0.4321, 0.1174, 0.0380])
        
        :pei => Distributions.Categorical(@SVector [0.0490, 0.1702, 0.3540, 0.2329, 0.1939])
        :quebec => Distributions.Categorical(@SVector [0.0545, 0.1615, 0.3782, 0.2227, 0.1831])
        :saskat => Distributions.Categorical(@SVector [0.0666, 0.1914, 0.3871, 0.1997, 0.1552])
        :yukon => Distributions.Categorical(@SVector [0.0597, 0.1694, 0.4179, 0.2343, 0.1187])=#
        ##:ontario => Distributions.Categorical(@SVector [0.0519, 0.1727, 0.3930, 0.2150, 0.1674])#old
        :ontario => Distributions.Categorical(@SVector [0.0490, 0.163, 0.408, 0.204, 0.132, 0.044])
        #:usa => Distributions.Categorical(@SVector [0.059444636404977,0.188450296592341,0.396101793107413,0.189694011721906,0.166309262173363])
       # :newyork   => Distributions.Categorical(@SVector [0.064000, 0.163000, 0.448000, 0.181000, 0.144000])
        _ => error("shame for not knowing your canadian provinces and territories")
    end       
    return ret  
end
export get_province_ag

function comorbidity(ag::Int16)
    agg = [4;17;39;59;79;999]
    g = findfirst(x->x>=ag,agg)
    prob = [0.05; 0.1;0.18; 0.38; 0.60; 0.72]
    com = rand() < prob[g] ? 1 : 0

    return com    
end
export comorbidity

function initialize() 
    agedist = get_province_ag(p.prov)
    for i = 1:p.popsize 
        humans[i] = Human()              ## create an empty human       
        x = humans[i]
        x.idx = i 
        x.ag_new = rand(agedist)
        x.age = rand(agebraks_new[x.ag_new])
        x.ag = findfirst(y-> x.age in y, agebraks)
        x.exp = 999  ## susceptible people don't expire.
        x.dur = sample_epi_durations() # sample epi periods   
        if rand() < p.eldq && x.ag == p.eldqag   ## check if elderly need to be quarantined.
            x.iso = true   
            x.isovia = :qu         
        end
        x.comorbidity = comorbidity(x.age)
        x.vac_red = p.vac_com_dec_min+rand()*(p.vac_com_dec_max-p.vac_com_dec_min)
        # initialize the next day counts (this is important in initialization since dyntrans runs first)
        get_nextday_counts(x)
    end
end
export initialize

function init_betas() 
    if p.seasonal  
        tmp = p.β .* td_seasonality()
    else 
        tmp = p.β .* ones(Float64, p.modeltime)
    end
    resize!(BETAS, length(tmp))
    for i = 1:length(tmp)
        BETAS[i] = tmp[i]
    end
end

function td_seasonality()
    ## returns a vector of seasonal oscillations
    t = 1:p.modeltime
    a0 = 6.261
    a1 = -11.81
    b1 = 1.817
    w = 0.022 #0.01815    
    temp = @. a0 + a1*cos((80-t)*w) + b1*sin((80-t)*w)  #100
    #temp = @. a0 + a1*cos((80-t+150)*w) + b1*sin((80-t+150)*w)  #100
    temp = (temp .- 2.5*minimum(temp))./(maximum(temp) .- minimum(temp)); # normalize  @2
    return temp
end

function get_ag_dist() 
    # splits the initialized human pop into its age groups
    grps =  map(x -> findall(y -> y.ag == x, humans), 1:length(agebraks)) 
    return grps
end

function insert_infected(health, num, ag) 
    ## inserts a number of infected people in the population randomly
    ## this function should resemble move_to_inf()
    l = findall(x -> x.health == SUS && x.ag == ag, humans)
    if length(l) > 0 && num < length(l)
        h = sample(l, num; replace = false)
        @inbounds for i in h 
            x = humans[i]
            if health == PRE 
                move_to_pre(x) ## the swap may be asymp, mild, or severe, but we can force severe in the time_update function
            elseif health == LAT 
                move_to_latent(x)
            elseif health == INF
                move_to_infsimple(x)
            elseif health == REC 
                move_to_recovered(x)
            else 
                error("can not insert human of health $(health)")
            end       
            x.sickfrom = INF # this will add +1 to the INF count in _count_infectors()... keeps the logic simple in that function.    
        end
    end    
    return h
end
export insert_infected

function time_update()
    # counters to calculate incidence
    lat=0; pre=0; asymp=0; mild=0; miso=0; inf=0; infiso=0; hos=0; icu=0; rec=0; ded=0;
    for x in humans 
        x.tis += 1 
        x.doi += 1 # increase day of infection. variable is garbage until person is latent
        if x.tis >= x.exp             
            @match Symbol(x.swap) begin
                :LAT  => begin move_to_latent(x); lat += 1; end
                :PRE  => begin move_to_pre(x); pre += 1; end
                :ASYMP => begin move_to_asymp(x); asymp += 1; end
                :MILD => begin move_to_mild(x); mild += 1; end
                :MISO => begin move_to_miso(x); miso += 1; end
                :INF  => begin move_to_inf(x); inf +=1; end    
                :IISO => begin move_to_iiso(x); infiso += 1; end
                :HOS  => begin move_to_hospicu(x); hos += 1; end 
                :ICU  => begin move_to_hospicu(x); icu += 1; end
                :REC  => begin move_to_recovered(x); rec += 1; end
                :DED  => begin move_to_dead(x); ded += 1; end
                _    => error("swap expired, but no swap set.")
            end
        end
        # run covid-19 functions for other integrated dynamics. 
        ct_dynamics(x)

        # get the meet counts for the next day 
        get_nextday_counts(x)

        if p.vaccinating
            vac_update(x)
        end
    end
    return (lat, mild, miso, inf, infiso, hos, icu, rec, ded)
end
export time_update

@inline _set_isolation(x::Human, iso) = _set_isolation(x, iso, x.isovia)
@inline function _set_isolation(x::Human, iso, via)
    # a helper setter function to not overwrite the isovia property. 
    # a person could be isolated in susceptible/latent phase through contact tracing
    # --> in which case it will follow through the natural history of disease 
    # --> if the person remains susceptible, then iso = off
    # a person could be isolated in presymptomatic phase through fpreiso
    # --> if x.iso == true from CT and x.isovia == :ct, do not overwrite
    # a person could be isolated in mild/severe phase through fmild, fsevere
    # --> if x.iso == true from CT and x.isovia == :ct, do not overwrite
    # --> if x.iso == true from PRE and x.isovia == :pi, do not overwrite
    x.iso = iso 
    x.isovia == :null && (x.isovia = via)
end

function sample_epi_durations()
    # when a person is sick, samples the 
    #lat_dist = Distributions.truncated(Gamma(3.122, 2.656),4,11.04) # truncated between 4 and 7
    lat_dist = Distributions.truncated(LogNormal(1.434, 0.661), 4, 7) # truncated between 4 and 7
    pre_dist = Distributions.truncated(Gamma(1.058, 5/2.3), 0.8, 3)#truncated between 0.8 and 3
    asy_dist = Gamma(5, 1)
    inf_dist = Gamma((3.2)^2/3.7, 3.7/3.2)

    latents = Int.(round.(rand(lat_dist)))
    pres = Int.(round.(rand(pre_dist)))
    latents = latents - pres # ofcourse substract from latents, the presymp periods
    asymps = Int.(ceil.(rand(asy_dist)))
    infs = Int.(ceil.(rand(inf_dist)))
    return (latents, asymps, pres, infs)
end

function move_to_latent(x::Human)
    ## transfers human h to the incubation period and samples the duration
    x.health = LAT
    x.doi = 0 ## day of infection is reset when person becomes latent
    x.tis = 0   # reset time in state 
    x.exp = x.dur[1] # get the latent period
    # the swap to asymptomatic is based on age group.
    # ask seyed for the references
    #asymp_pcts = (0.25, 0.25, 0.14, 0.07, 0.07)
    ##symp_pcts = map(y->1-y,asymp_pcts) 
    #symp_pcts = (0.75, 0.75, 0.86, 0.93, 0.93) 

    ##### for ontario canada
    symp_pcts = [0.7, 0.623, 0.672, 0.672, 0.812, 0.812] #[0.3 0.377 0.328 0.328 0.188 0.188]
    age_thres = [4, 19, 49, 64, 79, 999]
    g = findfirst(y-> y >= x.age, age_thres)
     
    x.swap = rand() < (symp_pcts[g])*(1-x.vac_ef_symp) ? PRE : ASYMP
    x.wentTo = x.swap
    x.got_inf = true
    ## in calibration mode, latent people never become infectious.
    if p.calibration 
        x.swap = LAT 
        x.exp = 999
    end
end
export move_to_latent

function move_to_asymp(x::Human)
    ## transfers human h to the asymptomatic stage 
    x.health = ASYMP     
    x.tis = 0 
    x.exp = x.dur[2] # get the presymptomatic period
    x.swap = REC 
    rand() < p.fasymp && _set_isolation(x, true, :ai)
    # x.iso property remains from either the latent or presymptomatic class
    # if x.iso is true, the asymptomatic individual has limited contacts
end
export move_to_asymp

function move_to_pre(x::Human)
    θ = (0.95, 0.9, 0.85, 0.6, 0.2)  # percentage of sick individuals going to mild infection stage
    x.health = PRE
    x.tis = 0   # reset time in state 
    x.exp = x.dur[3] # get the presymptomatic period

    if rand() < (1-θ[x.ag])*(1-x.vac_ef_sev)
        x.swap = INF
    else 
        x.swap = MILD
    end
    # calculate whether person is isolated
    rand() < p.fpreiso && _set_isolation(x, true, :pi)
end
export move_to_pre

function move_to_mild(x::Human)
    ## transfers human h to the mild infection stage for γ days
    x.health = MILD     
    x.tis = 0 
    x.exp = x.dur[4]
    x.swap = REC 
    # x.iso property remains from either the latent or presymptomatic class
    # if x.iso is true, staying in MILD is same as MISO since contacts will be limited. 
    # we still need the separation of MILD, MISO because if x.iso is false, then here we have to determine 
    # how many days as full contacts before self-isolation
    # NOTE: if need to count non-isolated mild people, this is overestimate as isolated people should really be in MISO all the time
    #   and not go through the mild compartment 
    if x.iso || rand() < p.fmild
        x.swap = MISO  
        x.exp = p.τmild
    end
end
export move_to_mild

function move_to_miso(x::Human)
    ## transfers human h to the mild isolated infection stage for γ days
    x.health = MISO
    x.swap = REC
    x.tis = 0 
    x.exp = x.dur[4] - p.τmild  ## since tau amount of days was already spent as infectious
    _set_isolation(x, true, :mi) 
end
export move_to_miso

function move_to_infsimple(x::Human)
    ## transfers human h to the severe infection stage for γ days 
    ## simplified function for calibration/general purposes
    x.health = INF
    x.tis = 0 
    x.exp = x.dur[4]
    x.swap = REC 
    _set_isolation(x, false, :null) 
end

function move_to_inf(x::Human)
    ## transfers human h to the severe infection stage for γ days
    ## for swap, check if person will be hospitalized, selfiso, die, or recover
 
    # h = prob of hospital, c = prob of icu AFTER hospital    
    
    h = x.comorbidity == 1 ? 0.235 : 0.089
    c = x.comorbidity == 1 ? 0.261 : 0.197
    
    groups = [0:34,35:54,55:69,70:84,85:100]
    gg = findfirst(y-> x.age in y,groups)

    mh = [0.0002; 0.0015; 0.011; 0.0802; 0.381]     # death rate for severe cases.
    if p.calibration && !p.calibration2
        h =  0#, 0, 0, 0)
        c =  0#, 0, 0, 0)
        mh = (0, 0, 0, 0, 0)
    end

    time_to_hospital = Int(round(rand(Uniform(2, 5)))) # duration symptom onset to hospitalization
   	
    x.health = INF
    x.swap = UNDEF
    x.tis = 0 
    if rand() < h     # going to hospital or ICU but will spend delta time transmissing the disease with full contacts 
        x.exp = time_to_hospital    
        x.swap = rand() < c ? ICU : HOS        
    else ## no hospital for this lucky (but severe) individual 
        if rand() < mh[gg]
            x.exp = x.dur[4]  
            x.swap = DED
        else 
            x.exp = x.dur[4]  
            x.swap = REC
            if x.iso || rand() < p.fsevere 
                x.exp = 1  ## 1 day isolation for severe cases     
                x.swap = IISO
            end  
        end
    end
    ## before returning, check if swap is set 
    x.swap == UNDEF && error("agent I -> ?")
end

function move_to_iiso(x::Human)
    ## transfers human h to the sever isolated infection stage for γ days
    x.health = IISO   
    x.swap = REC
    x.tis = 0     ## reset time in state 
    x.exp = x.dur[4] - 1  ## since 1 day was spent as infectious
    _set_isolation(x, true, :mi)
end 

function move_to_hospicu(x::Human)   
    #death prob taken from https://www.cdc.gov/nchs/nvss/vsrr/covid_weekly/index.htm#Comorbidities
    # on May 31th, 2020
    #=age_thres = [24;34;44;54;64;74;84;999]
    g = findfirst(y-> y >= x.age,age_thres)
    mh = [0.0005, 0.0022, 0.0057, 0.0160, 0.0401, 0.0696, 0.0893, 0.11]
    mc = [0.0009,0.0045,0.0115,0.0319,0.0801,0.1392,0.1786,0.22]=#

    #g = findfirst(y-> y >= x.age,age_thres) =#     #75-85
    aux = [0:4, 5:19, 20:44, 45:54, 55:64, 65:74, 75:84, 85:99]
   
    mh = [0.001, 0.001, 0.0015, 0.0065, 0.01, 0.02, 0.0735, 0.38]
    mc = [0.002,0.002,0.0022, 0.008, 0.022, 0.04, 0.08, 0.4]
    #if person recovers
    gg = findfirst(y-> x.age in y,aux)

    psiH = Int(round(rand(Distributions.truncated(Gamma(4.5, 2.75), 8, 17))))
    psiC = Int(round(rand(Distributions.truncated(Gamma(4.5, 2.75), 8, 17)))) + 2
    muH = Int(round(rand(Distributions.truncated(Gamma(5.3, 2.1), 9, 15))))
    muC = Int(round(rand(Distributions.truncated(Gamma(5.3, 2.1), 9, 15)))) + 2

    swaphealth = x.swap 
    x.health = swaphealth ## swap either to HOS or ICU
    x.swap = UNDEF
    x.tis = 0
    _set_isolation(x, true) # do not set the isovia property here.  

    if swaphealth == HOS
        x.hospicu = 1 
        if rand() < mh[gg] ## person will die in the hospital 
            x.exp = muH 
            x.swap = DED
        else 
            x.exp = psiH 
            x.swap = REC
        end        
    end
    if swaphealth == ICU
        x.hospicu = 2         
        if rand() < mc[gg] ## person will die in the ICU 
            x.exp = muC
            x.swap = DED
        else 
            x.exp = psiC
            x.swap = REC
        end
    end 
    ## before returning, check if swap is set 
    x.swap == UNDEF && error("agent H -> ?")    
end

function move_to_dead(h::Human)
    # no level of alchemy will bring someone back to life. 
    h.health = DED
    h.swap = UNDEF
    h.tis = 0 
    h.exp = 999 ## stay recovered indefinitely
    h.iso = true # a dead person is isolated
    _set_isolation(h, true)  # do not set the isovia property here.  
    # isolation property has no effect in contact dynamics anyways (unless x == SUS)
end

function move_to_recovered(h::Human)
    h.health = REC
    h.swap = UNDEF
    h.tis = 0 
    h.exp = 999 ## stay recovered indefinitely
    h.iso = false ## a recovered person has ability to meet others
    _set_isolation(h, false)  # do not set the isovia property here.  
    # isolation property has no effect in contact dynamics anyways (unless x == SUS)
end

function iso_scenarios(humans::Array{Human,1})

    if p.isoscenario == 1
        pos = findall(x->x.comorbidity==1,humans)
        for i = pos
            y = humans[i]
            #_set_isolation(y, true, :ct)
            iso = true
            y.shelter_in = true
            y.tracedxp = 999 ## trace isolation will last for 14 days before expiry                
            ct_data.totalisolated_init += 1  ## update counter
        end
    elseif p.isoscenario == 2
        pos = findall(x->x.age >= 50 && x.age<65,humans)
        for i = pos
            y = humans[i]
            #_set_isolation(y, true, :ct)
            iso = true
            y.shelter_in = true
            y.tracedxp = 999 ## trace isolation will last for 14 days before expiry                
            ct_data.totalisolated_init += 1  ## update counter
        end
    elseif p.isoscenario == 3
        pos = findall(x->x.age>=65,humans)
        for i = pos
            y = humans[i]
            #_set_isolation(y, true, :ct)
            iso = true
            y.shelter_in = true
            y.tracedxp = 999 ## trace isolation will last for 14 days before expiry                
            ct_data.totalisolated_init += 1  ## update counter
        end
    elseif p.isoscenario == 4
        pos = findall(x->x.age>=50,humans)
        for i = pos
            y = humans[i]
            #_set_isolation(y, true, :ct)
            iso = true
            y.shelter_in = true
            y.tracedxp = 999 ## trace isolation will last for 14 days before expiry                
            ct_data.totalisolated_init += 1  ## update counter
        end
    elseif p.isoscenario == 5
        pos = findall(x->x.age >= 5 && x.age<20,humans)
        for i = pos
            y = humans[i]
            #_set_isolation(y, true, :ct)
            iso = true
            y.shelter_in = true
            y.tracedxp = 999 ## trace isolation will last for 14 days before expiry                
            ct_data.totalisolated_init += 1  ## update counter
        end

    elseif p.isoscenario == 6
        pos = findall(x->(x.age >= 50 && x.age<65) || x.comorbidity == 1,humans)
        for i = pos
            y = humans[i]
            #_set_isolation(y, true, :ct)
            iso = true
            y.shelter_in = true
            y.tracedxp = 999 ## trace isolation will last for 14 days before expiry                
            ct_data.totalisolated_init += 1  ## update counter
        end
    elseif p.isoscenario == 7
        pos = findall(x->(x.age>=65) || x.comorbidity == 1,humans)
        for i = pos
            y = humans[i]
            #_set_isolation(y, true, :ct)
            iso = true
            y.shelter_in = true
            y.tracedxp = 999 ## trace isolation will last for 14 days before expiry                
            ct_data.totalisolated_init += 1  ## update counter
        end
    elseif p.isoscenario == 8
        pos = findall(x->(x.age>=50) || x.comorbidity == 1,humans)
        for i = pos
            y = humans[i]
            #_set_isolation(y, true, :ct)
            iso = true
            y.shelter_in = true
            y.tracedxp = 999 ## trace isolation will last for 14 days before expiry                
            ct_data.totalisolated_init += 1  ## update counter
        end
    end

end

function apply_ct_strategy(y::Human)
    iso = false  # to collect data at the end of the function
    yhealth = y.health
    if p.ctstrat == 1 
        # in strategy 1, all traced individuals are isolated for 14 days. 
        _set_isolation(y, true, :ct)
        iso = true
        y.tracedxp = 14 ## trace isolation will last for 14 days before expiry                
        ct_data.totalisolated += 1  ## update counter               
    end
    if p.ctstrat == 2 
        if y.health in (PRE, ASYMP, MILD, MISO, INF, IISO)
            _set_isolation(y, true, :ct)
            iso = true
            y.tracedxp = 14 ## trace isolation will last for 14 days before expiry                
            ct_data.totalisolated += 1  ## update counter
        else
            _set_isolation(y, false)
            # kill the trace
            y.tracedby = 0 
            y.tracedxp = 0 
        end
    end
    if p.ctstrat == 3
         # in strategy 3, all traced individuals are isolated for only 4 days. 
         _set_isolation(y, true, :ct)
         iso = true
         y.tracedxp = 4 ## trace isolation will last for 14 days before expiry                
         ct_data.totalisolated += 1  ## update counter 
    end
    # count data
    if yhealth == INF || yhealth == MILD 
        ct_data.iso_symp += 1
    elseif yhealth == LAT 
        ct_data.iso_lat += 1
    elseif yhealth == ASYMP 
        ct_data.iso_asymp += 1
    else        
        ct_data.iso_sus += 1 
    end
end

function ct_dynamics(x::Human)
    # main function for ct dynamics 
    # turns tracing on if person is infectious and in the right time window
    # applies isolation to all traced contacts
    # turns of isolation for susceptibles > 14 days
    # order of if statements matter here 
    (p.ctstrat == 0) && (return)
    xh = x.health 
    xs = x.swap
    dur = x.dur
    doi = x.doi
    #fctcapture::Float16 = 0.0 ## how many of contacts of the infected are we tracing.     
    #cidtime::Int8 = 0  ## time to identification (for CT) post symptom onset
    #cdaysback::Int8 = 0 ## number of days to go back and collect contacts
    # tracing::Bool = false ## are we tracing contacts for this individual?
    # tracestart::Int8 = -1 ## when to start tracing, based on values sampled for x.dur
    # traceend::Int8 = -1 ## when to end tracing
    # tracedby::UInt16 = 0 ## is the individual traced? property represents the index of the infectious person 
    # tracedxp::UInt16 = 0 ## the trace is killed after tracedxp amount of days

    ## person is newly infectious, calculate tracing numbers
    if xh == LAT && xs != ASYMP && doi == 0 
        if rand() < p.fctcapture 
            #delta = dur[1] + dur[3] + p.cidtime # the latent + presymp + time to identification time
            delta = dur[1] + dur[3] + Int(round(rand(Gamma(3.2, 1))))
            q = delta - p.cdaysback  
            #println("delta = $delta, q = $q")
            x.tracestart = max(0, q) # minimum of zero since delta < p.cdaysback
            x.traceend = delta
            (x.tracestart > x.traceend) && error("tracestart < traceend")
            ct_data.total_symp_id += 1 ## update the data collection counter
        end
    end

    ## turn on trace when day of infection == tracestart    
    if doi == x.tracestart 
        x.tracing = true 
    end 
    if doi == x.traceend 
        ## have to do more work here
        x.tracing = false 
        _set_isolation(x, true, :ct)
        alltraced = findall(y -> y.tracedby == x.idx, humans)
        for i in alltraced
            y = humans[i]
            yhealth = y.health
            apply_ct_strategy(y)
        end
    end

    if x.tracedxp > 0  # person was traced, isolated, and will be for x days
        x.tracedxp -= 1
        if x.tracedxp == 0 
            # check whether isolation is turned on/off based on ctstrat
            if p.ctstrat == 3 && x.health in (PRE, ASYMP, MILD, INF, MISO, IISO)
                # if strategy 3, only those that are tested positive are furthered isolated for 14 days.
                _set_isolation(x, true) ## isovia should already be set to :ct 
                x.tracedxp = 14 ## trace isolation will last for 14 days before expiry                
                ct_data.totalisolated += 1  ## update counter 
            else
                # else their trace is killed
                _set_isolation(x, false)
                x.isovia = :null # not isolated via contact tracing anymore
                x.tracedby = 0 # the trace is killed
            end            
        end
    end
    return
end
export ct_dynamics

@inline function _get_betavalue(sys_time, xhealth) 
    #bf = p.β ## baseline PRE
    length(BETAS) == 0 && return 0
    bf = BETAS[sys_time]
    # values coming from FRASER Figure 2... relative tranmissibilities of different stages.
    if xhealth == ASYMP
        bf = bf * p.frelasymp
    elseif xhealth == MILD || xhealth == MISO 
        bf = bf * 0.44
    elseif xhealth == INF || xhealth == IISO 
        bf = bf * 0.89
    end
    return bf
end
export _get_betavalue

@inline function get_nextday_counts(x::Human)
    # get all people to meet and their daily contacts to recieve
    # we can sample this at the start of the simulation to avoid everyday    
    cnt = 0
    ag = x.ag
    #if person is isolated, they can recieve only 3 maximum contacts
    
    if !x.iso 
        #cnt = rand() < 0.5 ? 0 : rand(1:3)
        cnt = rand(negative_binomials(ag,p.contact_change_rate*p.contact_change_2)) ##using the contact average for shelter-in
    else 
        cnt = rand(negative_binomials_shelter(ag,p.contact_change_2))  # expensive operation, try to optimize
    end
    
    if x.health == DED # || x.health==DED2
        cnt = 0 
    end
    x.nextday_meetcnt = cnt
    return cnt
end

function dyntrans(sys_time, grps)
    totalmet = 0 # count the total number of contacts (total for day, for all INF contacts)
    totalinf = 0 # count number of new infected 
    ## find all the people infectious
    infs = findall(x -> x.health in (PRE, ASYMP, MILD, MISO, INF, IISO), humans)
    
    # go through every infectious person
    for xid in infs 
        x = humans[xid]
        xhealth = x.health
        cnts = x.nextday_meetcnt
        if cnts > 0  
            gpw = Int.(round.(cm[x.ag]*cnts)) # split the counts over age groups
            for (i, g) in enumerate(gpw)
                # sample the people from each group
                meet = rand(grps[i], g)
                # go through each person
                for j in meet 
                    y = humans[j]
                    ycnt = y.nextday_meetcnt             
                    if ycnt > 0 
                        y.nextday_meetcnt = y.nextday_meetcnt - 1 # remove a contact
                        totalmet += 1
                        # there is a contact to recieve
                         # tracing dynamics
                        
                        if x.tracing  
                            if y.tracedby == 0 && rand() < p.fcontactst
                                y.tracedby = x.idx
                                ct_data.totaltrace += 1 
                            end
                        end
                        
                    # tranmission dynamics
                        if  y.health == SUS && y.swap == UNDEF                  
                            beta = _get_betavalue(sys_time, xhealth)
                            if (!x.iso && !x.shelter_in && x.age >= 2 && rand() < p.maskcomp)
                                beta = beta*(1-p.m_ef)
                            end
                            if (!y.iso && !y.shelter_in && y.age >= 2 && rand() < p.maskcomp)
                                beta = beta*(1-p.m_ef)
                            end
                            if rand() < beta*(1-y.vac_ef_inf)
                                totalinf += 1
                                y.swap = LAT
                                y.exp = y.tis   ## force the move to latent in the next time step.
                                y.sickfrom = xhealth ## stores the infector's status to the infectee's sickfrom
                                y.infby = xid
                            end  
                        end
    
                    end
                    
                end
            end
        end        
    end
    return totalmet, totalinf
end
export dyntrans

### old contact matrix
# function contact_matrix()
#     CM = Array{Array{Float64, 1}, 1}(undef, 4)
#     CM[1]=[0.5712, 0.3214, 0.0722, 0.0353]
#     CM[2]=[0.1830, 0.6253, 0.1423, 0.0494]
#     CM[3]=[0.1336, 0.4867, 0.2723, 0.1074]    
#     CM[4]=[0.1290, 0.4071, 0.2193, 0.2446]
#     return CM
# end

function contact_matrix()
    # regular contacts, just with 5 age groups. 
    #  0-4, 5-19, 20-49, 50-64, 65+
    CM = Array{Array{Float64, 1}, 1}(undef, 5)
    CM[1] = [0.2287, 0.1839, 0.4219, 0.1116, 0.0539]
    CM[2] = [0.0276, 0.5964, 0.2878, 0.0591, 0.0291]
    CM[3] = [0.0376, 0.1454, 0.6253, 0.1423, 0.0494]
    CM[4] = [0.0242, 0.1094, 0.4867, 0.2723, 0.1074]
    CM[5] = [0.0207, 0.1083, 0.4071, 0.2193, 0.2446]
    return CM
end
const cm = contact_matrix()
# 
# calibrate for 2.7 r0
# 20% selfisolation, tau 1 and 2.


function negative_binomials(ag,mult) #mult = 1-0.72 = 0.28
    ## the means/sd here are calculated using _calc_avgag
    means = [10.21, 16.793, 13.7950, 11.2669, 8.0027]
    sd = [7.65, 11.7201, 10.5045, 9.5935, 6.9638]
    #sd = [2.14, 3.28, 2.94, 2.66, 1.95]

    means = means*mult #0.28
    sd = sd*mult
    totalbraks = length(means)
    nbinoms = Vector{NegativeBinomial{Float64}}(undef, totalbraks)
    for i = 1:totalbraks
        p = 1 - (sd[i]^2-means[i])/(sd[i]^2)
        r = means[i]^2/(sd[i]^2-means[i])
        nbinoms[i] =  NegativeBinomial(r, p)
    end
    return nbinoms[ag]
end

function negative_binomials_shelter(ag,mult) #mult = 0.72
    ## the means/sd here are calculated using _calc_avgag
    means = [2.86, 4.7, 3.86, 3.15, 2.24]
    sd = [2.14, 3.28, 2.94, 2.66, 1.95]
####
   # means = [10.21, 16.793, 13.7950, 11.2669, 8.0027]
    #sd = [7.65, 11.7201, 10.5045, 9.5935, 6.9638]
#####
    means = means*mult
   # sd = sd*mult
    totalbraks = length(means)
    nbinoms = Vector{NegativeBinomial{Float64}}(undef, totalbraks)
    for i = 1:totalbraks
        p = 1 - (sd[i]^2-means[i])/(sd[i]^2)
        r = means[i]^2/(sd[i]^2-means[i])
        nbinoms[i] =  NegativeBinomial(r, p)
    end
    return nbinoms[ag]   
end

end#module end