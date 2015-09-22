function dictionary=parse(FileName,varargin)
% parse -- parser for dsge models
%
% Syntax
% -------
% ::
%
%   dictionary=parse(FileName,varargin)
%
% Inputs
% -------
%
% - **FileName** [char]: name of the model file. The file should have
% extensions rs, rz or dsge
%
% - **varargin** []: pairwise arguments with possiblities as follows:
%   - **parameter_differentiation** [true|{false}]: compute or not
%   parameter derivatives
%   - **definitions_inserted** [true|{false}]: substitute definitions  
%   - **definitions_in_param_differentiation** [true|{false}]: insert or
%   not definitions in equations before differentiating with respect to
%   parameters  
%   - **rise_save_macro** [true|{false}]: save the macro file in case of
%   insertions of sub-files
%   - **max_deriv_order** [integer|{2}]: order for symbolic
%   differentiation. It is recommended to set to 1, especially for large
%   models in case one does not intend to solve higher-order approximations
%   - **parse_debug** [true|{false}]: debugging in the parser
%   - **add_welfare** [true|{false}]: add the welfare equation when doing
%   optimal policy. N.B: The welfare variable, WELF is the true welfare
%   multiplied by (1-discount). The within-period utility variable, UTIL is
%   automatically added. The reason why welfare is not automatically added
%   is that oftentimes models with that equation do not solve.
%   - **rise_flags** [struct|cell]: instructions for the partial parsing of
%   the rise file. In case of a cell, the cell should be a k x 2 cell,
%   where the first column collects the conditional parsing names and the
%   second column the values.
%   - **stationary_model** [{empty}|true|false]: decides whether the model
%   is stationary in which case, the Balance growth path is not computed.
%
% Outputs
% --------
%
% - **dictionary** [struct]: elements need by the dsge class for
% constructing an instance.
%
% More About
% ------------
%
% - In RISE it is possible to declare exogenous and make them observable at
% the same time. The exogenous that are observed are determisitic. This
% is the way to introduce e.g. time trends. This strategy also opens the
% door for estimating partial equilibrium models 
%
% Examples
% ---------
%
% See also:

DefaultOptions=...
    struct('definitions_in_param_differentiation',false,...
    'rise_save_macro',false,...
    'max_deriv_order',2,'definitions_inserted',false,...
    'parse_debug',false,...
    'add_welfare',false,...
    'parameter_differentiation',false,...
    'stationary_model',[]);
DefaultOptions=utils.miscellaneous.mergestructures(DefaultOptions,...
    parser.preparse());
if nargin<1
    dictionary=DefaultOptions;
    return
end

%%
lv=length(varargin);
if rem(lv,2)~=0
    error('arguments must come in pairs')
end
if lv
    ccc=reshape(varargin(:),2,[]); clear varargin
    for ii=1:0.5*lv
        str=ccc{1,ii};
        if ~isfield(DefaultOptions,str)
            error([str,' Not an option for ',mfilename])
        end
        DefaultOptions.(str)=ccc{2,ii};
    end
end
%% general initializations

dictionary = parser.initialize_dictionary();
dictionary.definitions_inserted=DefaultOptions.definitions_inserted;
dictionary.parse_debug=DefaultOptions.parse_debug;
dictionary.add_welfare=DefaultOptions.add_welfare;
parameter_differentiation=DefaultOptions.parameter_differentiation;
dictionary.is_stationary_model=DefaultOptions.stationary_model;
is_bgp_model=isempty(dictionary.is_stationary_model)||~dictionary.is_stationary_model;
%% set various blocks

% first output: the dictionary.filename

FileName(isspace(FileName))=[];
loc=strfind(FileName,'.');
valid_extensions={'.rs','.rz','.dsge'};
if isempty(loc)
    dictionary.filename=FileName;
    found=false;
    iext=0;
    while ~found && iext<numel(valid_extensions)
        iext=iext+1;
        found=exist([FileName,valid_extensions{iext}],'file');
    end
    if ~found
        error([mfilename,':: ',FileName,'.rs or ',FileName,'.rz  or ',FileName,'.dsge not found'])
    end
    FileName=[FileName,valid_extensions{iext}];
else
    ext=FileName(loc:end);
    if ~any(strcmp(ext,valid_extensions))
        disp(valid_extensions)
        error([mfilename,':: Input file is expected to have one of the above extenstions'])
    end
    dictionary.filename=FileName(1:loc-1);
end

% read file and remove comments
% RawFile=read_file(FileName,DefaultOptions.rise_flags);
[RawFile,has_macro]=parser.preparse(FileName,DefaultOptions.rise_flags);

% write the expanded version
if has_macro && DefaultOptions.rise_save_macro
    newfile='';
    thedot=strfind(FileName,'.');
    fid=fopen([FileName(1:thedot-1),'_expanded.dsge'],'w');
    for irow=1:size(RawFile,1)
        write_newfilename=isempty(newfile)||~strcmp(newfile,RawFile{irow,2});
        if write_newfilename
            newfile=RawFile{irow,2};
            fprintf(fid,'%s\n',['// ',newfile,' line ',sprintf('%0.0f',RawFile{irow,3})]);
        end
        fprintf(fid,'%s\n',RawFile{irow,1});
    end
    fclose(fid);
end

[blocks,dictionary.markov_chains]=parser.file2blocks(RawFile);

dictionary.raw_file=cell2struct(RawFile,{'code','filename','line_numbers'},2);
dictionary.rawfile_triggers={blocks.trigger};

clear RawFile

%% Populate the dictionary
[dictionary,blocks]=parser.declarations2dictionary(dictionary,blocks);

%% add the chain names to dictionary so that the parsing of the model does
% not complain although the chain names acquired so far through the
% parameters are not expected to enter the model block
dictionary.chain_names={dictionary.markov_chains.name};

%% turn all log_vars into exp(log_vars) both in the model block
% and update the names of the variables in the process
[dictionary,blocks,old_endo_names]=parser.logvars2logvars(dictionary,blocks);

%% Model block
% now with the endogenous, exogenous, parameters in hand, we can process

[Model_block,dictionary,blocks]=parser.parse_model(dictionary,blocks);

%% optimal policy and optimal simple rule block

[dictionary,blocks,Model_block,PlannerObjective_block,jac_toc_]=...
            parser.parse_optimal_policy(Model_block,dictionary,blocks);        
        
if ~isempty(jac_toc_)
    disp([mfilename,':: First-order conditions of optimal policy :',sprintf('%0.4f',jac_toc_),' seconds'])
end

%% after parsing the model block, update the markov chains (time-varying probabilities)
% sorting the endogenous switching probabilities is more or less useless
dictionary.time_varying_probabilities=sort(dictionary.time_varying_probabilities);

%% Now we can re-order the original (and augmented) endogenous
[~,tags]=sort({dictionary.endogenous.name});
dictionary.endogenous=dictionary.endogenous(tags);
% also renew the endogenous quick list for status determination under
% shadowization, where the precise locations now matter!!!
%----------------------------------------------------------------------
dictionary.endogenous_list={dictionary.endogenous.name};
% no need to renew the parameters and the exogenous since new ones have not
% been created

%% Now we re-write the model and update leads and lags
% at the same time, construct the incidence and occurrence matrices
orig_endo_nbr=numel(dictionary.endogenous);

[equation_type,Occurrence]=equation_types_and_variables_occurrences();


%% Steady state Model block
% now with the endogenous, exogenous, parameters in hand, we can process
% the steady state model block
[static,SteadyStateModel_block,auxiliary_steady_state_equations,dictionary,blocks]=...
            parser.parse_steady_state(dictionary,blocks);
%% exogenous definitions block

[dictionary,blocks]=parser.parse_exogenous_definitions(dictionary,blocks);

%% parameterization block

do_parameterization();

%% parameter restrictions block.

do_parameter_restrictions();

%% Lump together the model and steady-state model
static_mult_equations=[];
if dictionary.is_optimal_policy_model
    static_mult_equations=dictionary.planner_system.static_mult_equations{1};
end
osr_derivatives=[];
if dictionary.is_optimal_simple_rule_model
    osr_derivatives=dictionary.planner_system.osr.derivatives;
end
AllModels=[Model_block
    SteadyStateModel_block
    auxiliary_steady_state_equations
    PlannerObjective_block
    osr_derivatives
    static_mult_equations];
% steady state equations (including auxiliary) are identified by number 5
aux_ss_eq_nbr=size(auxiliary_steady_state_equations,1);
ss_eq_nbr=size(SteadyStateModel_block,1);
% dictionary.planner_system objective equations are identified by number 6
planobj_eq_nbr=size(PlannerObjective_block,1);
osr_derivs_eqn_nbr=size(osr_derivatives,1);
% mult steady state identified by number 7
stat_mult_eq_nbr=size(static_mult_equations,1);
equation_type=[equation_type
    5*ones(ss_eq_nbr+aux_ss_eq_nbr,1)
    6*ones(planobj_eq_nbr+osr_derivs_eqn_nbr,1)
    7*ones(stat_mult_eq_nbr,1)];

clear Model_block SteadyStateModel_block PlannerObjective_block
%% Incidence matrix
% Now and only now can we build the incidence matrix
do_incidence_matrix();

%% models in shadow/technical/tactical form

overall_max_lead_lag=max([dictionary.endogenous.max_lead]);
overall_max_lead_lag=max([abs([dictionary.endogenous.max_lag]),overall_max_lead_lag]);

[dictionary,...
    dynamic,...
    stat,...
    defs,...
    shadow_tvp,...
    shadow_complementarity]=parser.shadowize(dictionary,AllModels,...
    equation_type,overall_max_lead_lag);
orig_definitions=defs.original;
shadow_definitions=defs.shadow;
static=utils.miscellaneous.mergestructures(static,stat);

if dictionary.is_optimal_policy_model
    dictionary.planner_system.static_mult_equations{1}=...
        static.steady_state_shadow_model(ss_eq_nbr+aux_ss_eq_nbr+1:end);
end

static.steady_state_auxiliary_eqtns=...
    static.steady_state_shadow_model(ss_eq_nbr+(1:aux_ss_eq_nbr));

static.steady_state_shadow_model(ss_eq_nbr+1:end)=[];

dictionary.is_param_changed_in_ssmodel=parser.parameters_changed_in_ssmodel(...
    static.steady_state_shadow_model,'param',numel(dictionary.parameters));

static.steady_state_shadow_model=strrep(static.steady_state_shadow_model,...
    'x1_=','[x1_,fval,exitflag]=');
static.steady_state_shadow_model=strrep(static.steady_state_shadow_model,...
    ',x0_,',',x0_,options,');
old_shadow_steady_state_model=static.steady_state_shadow_model;
static.steady_state_shadow_model=cell(0,1);
fsolve_nbr=0;
for ii=1:numel(old_shadow_steady_state_model)
    eq_i=old_shadow_steady_state_model{ii};
    if ~isempty(strfind(eq_i,'argzero'))
        eq_i=strrep(eq_i,'argzero','fsolve');
        static.steady_state_shadow_model=[static.steady_state_shadow_model;{eq_i}];
        eq_i={'retcode=1-(exitflag==1);'};
        if ii<numel(old_shadow_steady_state_model)
            eq_i=[eq_i;{'if ~retcode,'}]; %#ok<*AGROW>
            fsolve_nbr=fsolve_nbr+1;
        end
        static.steady_state_shadow_model=[static.steady_state_shadow_model;eq_i];
    else
        static.steady_state_shadow_model=[static.steady_state_shadow_model;{eq_i}];
    end
end
for ii=1:fsolve_nbr
    static.steady_state_shadow_model=[static.steady_state_shadow_model;{'end;'}];
end
clear old_shadow_steady_state_model
% now add the prelude
if ~isempty(static.steady_state_shadow_model)
    static.steady_state_shadow_model=[{['if ~exist(''y'',''var''),y=zeros(',sprintf('%0.0f',orig_endo_nbr),',1); end;']};static.steady_state_shadow_model];
end
%% replace the list of definition names with definition equations
dictionary.definitions=struct('name',dictionary.definitions(:),...
    'model',orig_definitions(:),'shadow',shadow_definitions(:));

%% Routines structure
routines=struct();

% With all variables known, we can do the complementarity
%---------------------------------------------------------
routines.complementarity=utils.code.code2func(shadow_complementarity,parser.input_list);

% definitions routine
%---------------------
routines.definitions=utils.code.code2func(...
    parser.substitute_definitions(shadow_definitions),'param');

% steady state model routine (cannot be written as a function)
%--------------------------------------------------------------
routines.steady_state_model=parser.substitute_definitions(...
    static.steady_state_shadow_model,shadow_definitions);
routines.steady_state_model=struct('code',cell2mat(routines.steady_state_model(:)'),...
    'argins',{parser.input_list},...
    'argouts',{{'y','param'}});

routines.steady_state_auxiliary_eqtns=parser.substitute_definitions(...
    static.steady_state_auxiliary_eqtns,shadow_definitions);
routines.steady_state_auxiliary_eqtns=struct('code',cell2mat(routines.steady_state_auxiliary_eqtns(:)'),...
    'argins',{parser.input_list},...
    'argouts',{{'y'}});

%% load transition matrices and transform markov chains
% the Trans mat will go into the computation of derivatives
% dictionary=parser.transition_probabilities(dictionary,shadow_tvp);
bug_fix_shadow_defs=[];
if ~isempty(dictionary.definitions)
    bug_fix_shadow_defs=dictionary.definitions.shadow;
end
probability_of_commitment=[];
if ~isempty(dictionary.planner_system.shadow_model)
    probability_of_commitment=dictionary.planner_system.shadow_model{2};
    probability_of_commitment=strrep(probability_of_commitment,'commitment-','');
    probability_of_commitment=strrep(probability_of_commitment,';','');
    probability_of_commitment=probability_of_commitment(2:end-1);
end
[~,...
    routines.transition_matrix,...
    dictionary.markov_chains,...
    myifelseif...
    ]=parser.transition_probabilities(...
    dictionary.input_list,...
    {dictionary.parameters.name},dictionary.markov_chains,...
    shadow_tvp,bug_fix_shadow_defs,probability_of_commitment);
% flag for endogenous probabilities
%---------------------------------
dictionary.is_endogenous_switching_model=any(dictionary.markov_chains.chain_is_endogenous);
%% Computation of derivatives
%

disp(' ')
disp('Now computing symbolic derivatives...')
disp(' ')
max_deriv_order=max(1,DefaultOptions.max_deriv_order);
exo_nbr=numel(dictionary.exogenous);
% switching_ones=find([dictionary.parameters.is_switching]);

% dynamic model wrt endogenous, exogenous and leads of switching parameters
%--------------------------------------------------------------------------
% no leads or lags in the endogenous probabilities: then we know that the
% status (static,pred,both,frwrd) of the variables does not change.

% v=[f+,b+,s0,p_0,b_0,f_0,p_minus,b_minus,e_0]
routines.dynamic=utils.code.code2func(dynamic.shadow_model);

[wrt,dictionary.v,...
    dictionary.locations.before_solve,...
    dictionary.siz.before_solve,...
    dictionary.order_var,...
    dictionary.inv_order_var,...
    dictionary.steady_state_index]=dynamic_differentiation_list(...
    dictionary.lead_lag_incidence.before_solve,exo_nbr,[]);
%----------------------
if dictionary.parse_debug
    profile off
    profile on
end
routines.probs_times_dynamic=parser.burry_probabilities(dynamic.shadow_model,myifelseif);
[routines.probs_times_dynamic_derivatives,numEqtns,numVars,jac_toc,...
    original_funcs]=differentiate_system(...
    routines.probs_times_dynamic,...
    dictionary.input_list,...
    wrt,...
    max_deriv_order);
routines.probs_times_dynamic=utils.code.code2func(routines.probs_times_dynamic);
if dictionary.parse_debug
    profile off
    profile viewer
    keyboard
else
    disp([mfilename,':: Derivatives of dynamic model wrt y(+0-), x and theta up to order ',sprintf('%0.0f',max_deriv_order),'. ',...
        sprintf('%0.0f',numEqtns),' equations and ',sprintf('%0.0f',numVars),' variables :',sprintf('%0.4f',jac_toc),' seconds'])
end
%----------------------
routines.symbolic.probs_times_dynamic={original_funcs,wrt};

% static model wrt y
%--------------------
static_incidence=zeros(orig_endo_nbr,3);
static_incidence(:,2)=1:orig_endo_nbr;
wrt=dynamic_differentiation_list(static_incidence,0);

routines.static=utils.code.code2func(static.shadow_model);
[routines.static_derivatives,numEqtns,numVars,jac_toc,original_funcs]=...
    differentiate_system(routines.static,dictionary.input_list,wrt,1);
routines.symbolic.static={original_funcs,wrt};
disp([mfilename,':: 1st-order derivatives of static model wrt y(0). ',...
    sprintf('%0.0f',numEqtns),' equations and ',sprintf('%0.0f',numVars),' variables :',sprintf('%0.4f',jac_toc),' seconds'])

% balanced growth path model wrt y
%---------------------------------
bgp_incidence=zeros(2*orig_endo_nbr,3);
bgp_incidence(:,2)=1:2*orig_endo_nbr;
wrt=dynamic_differentiation_list(bgp_incidence,0);

if is_bgp_model
    routines.static_bgp=utils.code.code2func(static.shadow_BGP_model);
    [routines.static_bgp_derivatives,numEqtns,numVars,jac_toc,original_funcs]=...
        differentiate_system(...
        routines.static_bgp,...
        dictionary.input_list,wrt,1);
    routines.symbolic.static_bgp={original_funcs,wrt};
    disp([mfilename,':: 1st-order derivatives of static BGP model wrt y(0). ',...
        sprintf('%0.0f',numEqtns),' equations and ',sprintf('%0.0f',numVars),' variables :',sprintf('%0.4f',jac_toc),' seconds'])
end

% dynamic model wrt param
%------------------------
if parameter_differentiation
    param_nbr = numel(dictionary.parameters);
    wrt=dynamic_differentiation_list([],0,1:param_nbr);
    ppdd=@(x)x;%dynamic.shadow_model;
    if ~dictionary.definitions_inserted
        if DefaultOptions.definitions_in_param_differentiation
            ppdd=@(x)parser.replace_definitions(x,shadow_definitions);
        else
            disp([mfilename,':: definitions not taken into account in the computation of derivatives wrt parameters'])
        end
    end
    [routines.parameter_derivatives,numEqtns,numVars,jac_toc,original_funcs]=...
        differentiate_system(...
        ppdd(dynamic.shadow_model),...
        dictionary.input_list,wrt,1);
    routines.symbolic.parameters={original_funcs,wrt};
    disp([mfilename,':: first-order derivatives of dynamic model wrt param. ',...
        sprintf('%0.0f',numEqtns),' equations and ',sprintf('%0.0f',numVars),' variables :',sprintf('%0.4f',jac_toc),' seconds'])
end
%% optimal policy and optimal simple rules routines
%-----------------------------------------
if dictionary.is_model_with_planner_objective
    planner_shadow_model=strrep(strrep(dictionary.planner_system.shadow_model,'discount-',''),'commitment-','');
    
    if dictionary.is_optimal_policy_model
        tmp=parser.replace_steady_state_call(dictionary.planner_system.static_mult_equations{1});
        tmp=utils.code.code2func(tmp,parser.input_list);
        
        routines.planner_static_mult=tmp;
        routines.planner_static_mult_support=...
            dictionary.planner_system.static_mult_equations(2:end);
        dictionary.planner_system=rmfield(dictionary.planner_system,...
            'static_mult_equations');
    else
        osr_=dictionary.planner_system.osr;
        endo_names={dictionary.endogenous.name};
        ordered_endo_names=endo_names(dictionary.order_var);
        der_reo=locate_variables(ordered_endo_names,osr_.wrt);
        routines.planner_osr_support=struct('derivatives_re_order',der_reo,...
            'partitions',osr_.partitions,...
            'map',cell2mat(osr_.map(:,2)),'size',osr_.size);
        % we take the second column since the first column with the
        % equation numbers do not matter: originally we had only one equation
        clear osr_
    end
    % add the loss, the commitment degree and discount
    %-------------------------------------------------
    routines.planner_loss_commitment_discount=utils.code.code2func(planner_shadow_model,dictionary.input_list);
    
    routines.planner_objective=utils.code.code2func(dictionary.planner_system.shadow_model(1));

    dictionary.planner_system=rmfield(dictionary.planner_system,...
        {'shadow_model','model'});
end
%% Add final variables list to the dictionary
% the unsorted variables are variables sorted according to their order in
% during the solving of the model.
unsorted_endogenous=dictionary.endogenous(dictionary.order_var);
logical_incidence=dictionary.lead_lag_incidence.before_solve(dictionary.order_var,:);

dictionary.NumberOfEquations=sum(equation_type==1);

% now we can resort the final variables
[~,tags]=sort({unsorted_endogenous.name});
logical_incidence=logical_incidence(tags,:);
dictionary.endogenous=unsorted_endogenous(tags);

% update the lead-lag incidence and the order of the variables: with the
% new settings, this is not expected to ever change
%--------------------------------------------------------------------------
dictionary.lead_lag_incidence.after_solve=logical_incidence;
dictionary.lead_lag_incidence.after_solve(dictionary.lead_lag_incidence.after_solve~=0)=1:nnz(dictionary.lead_lag_incidence.after_solve);

% update the topology of the solution: with the new settings, this is not
% expected to ever change
%--------------------------------------------------------------------------
[dictionary.siz.after_solve,...
    dictionary.locations.after_solve.t,...
    dictionary.locations.after_solve.z]=...
    utils.solve.solution_topology(...
    dictionary.lead_lag_incidence.after_solve,...
    exo_nbr,... number of shocks
    0); % number of shocks periods beyond the current

clear unsorted_endogenous

%% give greek names to endogenous, exogenous, parameters
dictionary.endogenous=parser.greekify(dictionary.endogenous);
dictionary.endogenous=parser.greekify(dictionary.endogenous);
dictionary.exogenous=parser.greekify(dictionary.exogenous);
dictionary.parameters=parser.greekify(dictionary.parameters);

% format endogenous, parameters, observables, etc
endogenous=dictionary.endogenous;
dictionary.endogenous=struct();
dictionary.endogenous.name={endogenous.name};
dictionary.endogenous.tex_name={endogenous.tex_name};
dictionary.endogenous.current_name={endogenous.current_name};
dictionary.endogenous.is_original=sparse(ismember(dictionary.endogenous.name,old_endo_names));
dictionary.endogenous.number=numel(dictionary.endogenous.is_original);
dictionary.endogenous.is_lagrange_multiplier=sparse(strncmp('MULT_',{endogenous.name},5));
dictionary.endogenous.is_static=sparse((~logical_incidence(:,1)&~logical_incidence(:,3))');
dictionary.endogenous.is_predetermined=sparse((~logical_incidence(:,1)&logical_incidence(:,3))');
dictionary.endogenous.is_pred_frwrd_looking=sparse((logical_incidence(:,1) & logical_incidence(:,3))');
dictionary.endogenous.is_state=dictionary.endogenous.is_predetermined|...
    dictionary.endogenous.is_pred_frwrd_looking;
dictionary.endogenous.is_frwrd_looking=sparse((logical_incidence(:,1) & ~logical_incidence(:,3))');
dictionary.endogenous.is_log_var=sparse([endogenous.is_log_var]);
dictionary.endogenous.is_log_expanded=sparse(false(size(dictionary.endogenous.is_log_var)));
dictionary.endogenous.is_auxiliary=sparse([endogenous.is_auxiliary]);
dictionary.endogenous.is_affect_trans_probs=sparse([endogenous.is_trans_prob]);
hbe={dictionary.parameters.name};
hbe=hbe(strncmp(hbe,'hbe_param_',10));
hbe=regexprep(hbe,'hbe_param_(\w+)','$1');
dictionary.endogenous.is_hybrid_expect=ismember(dictionary.endogenous.name,hbe);

% re-encode the auxiliary variables
%------------------------------------
dictionary.auxiliary_variables.sstate_solved=...
    union(dictionary.auxiliary_variables.model,dictionary.auxiliary_variables.ssmodel_solved);
encode=@(x)vec(ismember(dictionary.endogenous.name,x)).';
fields=fieldnames(dictionary.auxiliary_variables);
for ifield=1:numel(fields)
    ff=fields{ifield};
    dictionary.auxiliary_variables.(ff)=encode(dictionary.auxiliary_variables.(ff));
end

clear endogenous logical_incidence

exogenous=dictionary.exogenous;
dictionary.exogenous=struct();
dictionary.exogenous.name={exogenous.name};
dictionary.exogenous.tex_name={exogenous.tex_name};
dictionary.exogenous.is_observed=sparse(ismember(dictionary.exogenous.name,{dictionary.observables.name}));
dictionary.exogenous.number=full([sum(~dictionary.exogenous.is_observed),sum(dictionary.exogenous.is_observed)]);
dictionary.exogenous.is_in_use=sparse([exogenous.is_in_use]);
dictionary.exogenous.shock_horizon=sparse(dictionary.markov_chains.regimes_number,...
    sum(dictionary.exogenous.number));%double(~dictionary.exogenous.is_observed);
clear exogenous

observables=dictionary.observables;
dictionary.observables=struct();
dictionary.observables.name={observables.name};
dictionary.observables.is_endogenous=sparse(ismember(dictionary.observables.name,dictionary.endogenous.name));
tex_names={observables.tex_name};
state_endo=locate_variables(dictionary.observables.name,dictionary.endogenous.name,true);
state_endo(isnan(state_endo))=0;
tex_names(state_endo>0)=dictionary.endogenous.tex_name(nonzeros(state_endo));
state_exo=locate_variables(dictionary.observables.name,dictionary.exogenous.name,true);
state_exo(isnan(state_exo))=0;
tex_names(state_exo>0)=dictionary.exogenous.tex_name(nonzeros(state_exo));
state_id=state_endo+state_exo*1i;
dictionary.observables.state_id=state_id(:).';
dictionary.observables.tex_name=tex_names;
dictionary.observables.number=full([sum(dictionary.observables.is_endogenous),sum(~dictionary.observables.is_endogenous)]);
clear observables

% parameters and model types
%----------------------------
dictionary.is_purely_forward_looking_model=false;
dictionary.is_purely_backward_looking_model=false;
dictionary.is_hybrid_model=any(dictionary.lead_lag_incidence.before_solve(:,1)) && any(dictionary.lead_lag_incidence.before_solve(:,3));
if ~dictionary.is_hybrid_model
    if any(dictionary.lead_lag_incidence.before_solve(:,1))
        dictionary.is_purely_forward_looking_model=true;
    elseif any(dictionary.lead_lag_incidence.before_solve(:,3))
        dictionary.is_purely_backward_looking_model=true;
    end
end

parameters=dictionary.parameters;
dictionary.parameters=struct();
dictionary.parameters.name={parameters.name};
dictionary.parameters.tex_name={parameters.tex_name};
dictionary.parameters.is_switching=sparse([parameters.is_switching]);
dictionary.parameters.is_trans_prob=sparse([parameters.is_trans_prob]);
dictionary.parameters.is_measurement_error=sparse([parameters.is_measurement_error]);
% after taking some sparse above, we have to make sure that the matrix
% below is full
dictionary.parameters.number=full([sum(~dictionary.parameters.is_switching),sum(dictionary.parameters.is_switching)]);
dictionary.parameters.is_in_use=sparse([parameters.is_in_use]);
dsge_var_id=strcmp(dictionary.parameters.name,parser.name4dsgevar());
dictionary.is_dsge_var_model=any(dsge_var_id);
dictionary.parameters.is_in_use(dsge_var_id)=true;
dictionary.parameters.governing_chain=[parameters.governing_chain];
clear parameters

% equations
%----------
dictionary.equations.dynamic=dynamic.model;
dictionary.equations.shadow_dynamic=dynamic.shadow_model;
dictionary.equations.static=static.model;
dictionary.equations.shadow_static=static.shadow_model;
dictionary.equations.shadow_balanced_growth_path=static.shadow_BGP_model;
dictionary.equations.number=numel(dynamic.model);
dictionary.is_imposed_steady_state=static.is_imposed_steady_state;
dictionary.is_unique_steady_state=static.is_unique_steady_state;
dictionary.is_initial_guess_steady_state=static.is_initial_guess_steady_state;

definitions=dictionary.definitions;
dictionary.definitions=struct();
dictionary.definitions.name={definitions.name};
dictionary.definitions.dynamic={definitions.model};
dictionary.definitions.dynamic=dictionary.definitions.dynamic(:);
dictionary.definitions.shadow_dynamic={definitions.shadow};
dictionary.definitions.shadow_dynamic=dictionary.definitions.shadow_dynamic(:);
dictionary.definitions.number=numel(definitions);
clear definitions static dynamic
dictionary.routines=routines;
dictionary=orderfields(dictionary);


    function do_incidence_matrix()
        
        before_solve=zeros(3,orig_endo_nbr);
        for iii=1:3
            for jj=1:orig_endo_nbr
                if any(Occurrence(:,jj,iii))
                    before_solve(iii,jj)=1;
                end
            end
        end
        before_solve=transpose(flipud(before_solve));
        before_solve(before_solve>0)=1:nnz(before_solve);
        
        appear_as_current=before_solve(:,2)>0;
        if any(~appear_as_current)
            disp('The following variables::')
            allendo={dictionary.endogenous.name};
            disp(allendo(~appear_as_current))
            error('do not appear as current')
        end
        dictionary.lead_lag_incidence.before_solve=before_solve;
    end

    function [equation_type,Occurrence]=equation_types_and_variables_occurrences()
        number_of_equations=size(Model_block,1);
        Occurrence=false(number_of_equations,orig_endo_nbr,3);
        equation_type=ones(number_of_equations,1);
        for iii=1:number_of_equations
            eq_i_= Model_block{iii,1};
            if strcmp(Model_block{iii,4},'def') % <---ismember(eq_i_{1,1},dictionary.definitions) && strcmp(eq_i_{1,2}(1),'=')
                equation_type(iii)=2;
            elseif strcmp(Model_block{iii,4},'tvp') % <---ismember(eq_i_{1,1},dictionary.time_varying_probabilities) && strcmp(eq_i_{1,2}(1),'=')
                equation_type(iii)=3;
            elseif strcmp(Model_block{iii,4},'mcp') % <---ismember(eq_i_{1,1},dictionary.time_varying_probabilities) && strcmp(eq_i_{1,2}(1),'=')
                equation_type(iii)=4;
            end
            for ii2=1:size(eq_i_,2)
                if ~isempty(eq_i_{2,ii2})
                    var_loc=strcmp(eq_i_{1,ii2},{dictionary.endogenous.name});
                    lag_or_lead=eq_i_{2,ii2}+2;
                    if any(var_loc) && equation_type(iii)==2
                        error([mfilename,':: equation (',sprintf('%0.0f',iii),') detected to be a definition cannot contain variables'])
                    elseif equation_type(iii)==3 && ismember(lag_or_lead,[3,1])
                        error([mfilename,':: equation (',sprintf('%0.0f',iii),') detected to describe endogenous switching cannot contain leads or lags'])
                    end
                    Occurrence(iii,var_loc,lag_or_lead)=true;
                end
            end
        end
        % keep only the structural equations
        Occurrence=Occurrence(equation_type==1,:,:);
    end

    function do_parameter_restrictions()
        
        current_block_id=find(strcmp('parameter_restrictions',{blocks.name}));
        
        [Param_rest_block,dictionary]=parser.capture_equations(dictionary,blocks(current_block_id).listing,'parameter_restrictions');
        % remove item from block
        blocks(current_block_id)=[];
        
        % remove the columns with information about the maxLead and maxLag: the
        % capture of parameterization does not require it and might even crash
        dictionary.Param_rest_block=Param_rest_block(:,1);
    end

    function do_parameterization()
        
        current_block_id=find(strcmp('parameterization',{blocks.name}));
        
        dictionary.Parameterization_block=parser.capture_parameterization(dictionary,blocks(current_block_id).listing);
        
        % remove item from block
        blocks(current_block_id)=[];
    end
end

function [derivs,numEqtns,numVars,jac_toc,original_funcs]=differentiate_system(myfunc,input_list,wrt,order)

numEqtns=numel(myfunc);

myfunc=parser.remove_handles(myfunc);

myfunc=parser.symbolic_model(myfunc,input_list);

% list of symbols
symb_list=parser.collect_symbolic_list(myfunc,strcat(input_list,'_'));
% force 's0' and 's1' to enter the list
state_inputs={'s0','s1'};
input_list=input_list(:)';
for ii=1:numel(state_inputs)
    if ~any(strcmp(symb_list,state_inputs{ii}))
        symb_list=[symb_list,state_inputs{ii}];
    end
end
% sorting will be useful if we need to debug
symb_list=sort(symb_list);

args=splanar.initialize(symb_list,wrt);
numVars=numel(wrt);
original_funcs=myfunc;
for ifunc=1:numEqtns
    [occur,myfunc{ifunc}]=parser.find_occurrences(myfunc{ifunc},symb_list);
    % re-create the function
    var_occur=symb_list(occur);
    argfun=cell2mat(strcat(var_occur,','));
    myfunc{ifunc}=str2func(['@(',argfun(1:end-1),')',myfunc{ifunc}]);
    original_funcs{ifunc}=myfunc{ifunc};
    arg_occur=args(occur);
    myfunc{ifunc}=myfunc{ifunc}(arg_occur{:});
end

verbose=false;
tic
derivs=splanar.differentiate(myfunc,numVars,order,verbose);
derivs=splanar.print(derivs,input_list);
jac_toc=toc;

end

function [wrt,v,locations,siz,order_var,inv_order_var,steady_state_index]=...
    dynamic_differentiation_list(LLI,exo_nbr,pindex)%% partition the endogenous
if nargin<3
    pindex=[];
end

% order the list of the variables to differentiate according to
%---------------------------------------------------------------
v={
    'b_plus',0
    'f_plus',0
    's_0',0
    'p_0',0
    'b_0',0
    'f_0',0
    'p_minus',0
    'b_minus',0
    'e_0',0
    };
fields=v(:,1);

locations=struct();

[siz,locations.t,locations.z,~,order_var,inv_order_var]=...
    utils.solve.solution_topology(...
    LLI,...
    exo_nbr,... number of shocks
    0);% number of shocks periods beyond the current
v{strcmp(v(:,1),'s_0'),2}=siz.ns;

v(strncmp(v(:,1),'p',1),2)={siz.np};

v(strncmp(v(:,1),'b',1),2)={siz.nb};

v(strncmp(v(:,1),'f',1),2)={siz.nf};

steady_state_index=struct();
if isempty(LLI)
    ywrt={};
else
    % endogenous
    %-----------
    llio=LLI(order_var,:);
    yindex=nonzeros(llio(:))';
    ywrt=cellstr(strcat('y_',num2str(yindex(:))));
    steady_state_index.y=order_var([find(llio(:,1))',find(llio(:,2))',find(llio(:,3))']); %<-- yindex=[LLI([both,frwrd],1)',LLI(order_var,2)',LLI([pred,both],3)];
    ywrt=cellfun(@(x)x(~isspace(x)),ywrt,'uniformOutput',false);
end
% exogenous
%----------
if exo_nbr
    xindex=1:exo_nbr;
    xwrt=cellstr(strcat('x_',num2str(xindex(:))));
    xwrt=cellfun(@(x)x(~isspace(x)),xwrt,'uniformOutput',false);
    steady_state_index.x=xindex(:)';
else
    xwrt={};
end
v{strcmp(v(:,1),'e_0'),2}=siz.ne;

% constant parameters
%--------------------
pwrt=process_parameters(pindex,'');

% differentiation list
%---------------------
wrt=[ywrt(:)',xwrt(:)',pwrt(:)'];
steady_state_index.wrt=wrt;

% v-locations
%------------
numbers=cell2mat(v(:,2));
for ifield=1:numel(fields)
    ff=fields{ifield};
    underscore=strfind(ff,'_');
    ff2=ff(1:underscore(1)-1);
    locations.v.(ff)=sum(numbers(1:ifield-1))+(1:siz.(['n',ff2]));
end
siz.nv=sum(numbers);
locations.v.bf_plus=[locations.v.b_plus,locations.v.f_plus];
locations.v.pb_minus=[locations.v.p_minus,locations.v.b_minus];
locations.v.t_0=siz.nb+siz.nf+(1:siz.ns+siz.np+siz.nb+siz.nf); % =[locations.v.s_0,locations.v.p_0,locations.v.b_0,locations.v.f_0];

    function pwrt=process_parameters(index,prefix)
        if isempty(index)
            pwrt={};
        else
            if ischar(index)
                index=cellstr(index);
            end
            pwrt=cellstr(strcat(prefix,'param_',num2str(index(:))));
            pwrt=cellfun(@(x)x(~isspace(x)),pwrt,'uniformOutput',false);
        end
    end
end
