{smcl}
{* *! version 0.3.0 05jul2026}{...}

{title:Title}

{p2colset 5 18 20 2}{...}
{p2col :{cmd:csdid_jl} {hline 2}}Callaway & Sant'Anna (2021) difference-in-differences, accelerated by Julia{p_end}
{p2colreset}{...}


{marker syntax}{...}
{title:Syntax}

{p 8 15 2} {cmd:csdid_jl}
{depvar} [{indepvars}]
{ifin}{cmd:,}
{cmdab:t:name}({varname})
{cmdab:g:name}({varname})
{cmdab:id:name}({varname})
[{it:options}]
{p_end}


{marker options_table}{...}
{synoptset 32 tabbed}{...}
{synopthdr:option}
{synoptline}
{syntab:Required}
{synopt: {opth t:name(varname)}}time-period variable{p_end}
{synopt: {opth g:name(varname)}}first-treatment-period variable (0 = never treated){p_end}
{synopt: {opth id:name(varname)}}unit identifier variable{p_end}

{syntab:Estimation}
{synopt: {opt est_method(string)}}estimation method: {bf:dr} (default), {bf:ipw}, or {bf:reg}{p_end}
{synopt: {opt control_group(string)}}comparison group: {bf:nevertreated} (default) or {bf:notyettreated}{p_end}
{synopt: {opt notyet}}shorthand for {cmd:control_group(notyettreated)}{p_end}
{synopt: {opt base_period(string)}}base period: {bf:varying} (default) or {bf:universal}{p_end}
{synopt: {opt ant:icipation(#)}}number of anticipation periods; default 0{p_end}

{syntab:Weights and clustering}
{synopt: {opth w:eights(varname)}}sampling-weights variable{p_end}
{synopt: {opt fix_weights(string)}}time-varying weight rule: {bf:base_period}, {bf:first_period}, or {bf:varying}{p_end}
{synopt: {opth cl:uster(varname)}}cluster variable for standard errors{p_end}

{syntab:Panel}
{synopt: {opt nopan:el}}treat data as repeated cross-sections{p_end}
{synopt: {opt unb:alanced}}allow an unbalanced panel ({bf:allow_unbalanced_panel=true} in R){p_end}

{syntab:Inference}
{synopt: {opt alp:ha(#)}}significance level for confidence bands; default 0.05{p_end}
{synopt: {opt biters(#)}}multiplier-bootstrap iterations; default 1000{p_end}
{synopt: {opt seed(#)}}random seed for bootstrap; default 12345{p_end}
{synopt: {opt nobst:rap}}disable multiplier bootstrap ({bf:bstrap=false} in R); use analytical SEs{p_end}
{synopt: {opt nocb:and}}pointwise CI instead of uniform confidence band ({bf:cband=false} in R){p_end}
{synopt: {opt l:evel(#)}}confidence level for display; default {cmd:c(level)}{p_end}

{syntab:Aggregation}
{synopt: {opt agg:regate(string)}}aggregation type: {bf:att} (default, no aggregation), {bf:event}/{bf:dynamic}, {bf:group}, {bf:calendar}, {bf:simple}, {bf:all}{p_end}
{synopt: {opt balance_e(#)}}balance event time for dynamic aggregation{p_end}
{synopt: {opt min_e(#)}}minimum event time to display{p_end}
{synopt: {opt max_e(#)}}maximum event time to display{p_end}

{syntab:Graph}
{synopt: {opt graph}}draw plots matching R {bf:ggdid()}; see {help csdid_jl##graph:Graph}{p_end}

{syntab:Performance}
{synopt: {opt gpu}}use GPU acceleration (requires CUDA.jl and an NVIDIA GPU){p_end}
{synoptline}

{p 4 6 2}{it:depvar} is the outcome variable.  {it:indepvars} are optional covariates
used in the propensity score and/or outcome regression.{p_end}

{p 4 6 2}The variable specified in {opt gname()} must equal 0 for never-treated
units.{p_end}


{marker description}{...}
{title:Description}

{pstd}
{cmd:csdid_jl} estimates group-time average treatment effects ATT(g,t)
using the method of Callaway & Sant'Anna (2021, {it:Journal of Econometrics}).
It is a Stata wrapper around the Julia package {bf:CSDid.jl}, connected via
Roodman's {cmd:jl} command ({stata ssc install julia:julia.ado}).

{pstd}
{cmd:csdid_jl} supports three estimation methods:

{p 8 12 2}{bf:dr} (doubly robust, default){break}
Uses both inverse-probability weighting and outcome regression,
providing consistency when either the propensity score or the
outcome model is correctly specified.{p_end}

{p 8 12 2}{bf:ipw} (inverse probability weighting){break}
Weights comparison-group outcomes by the estimated propensity score.{p_end}

{p 8 12 2}{bf:reg} (outcome regression){break}
Adjusts for covariates through a regression model for the
comparison group.{p_end}

{pstd}
When no covariates are specified, all three methods produce identical
results (standard 2x2 DiD).

{pstd}
Aggregation of ATT(g,t) into interpretable summary measures is
available through the {opt aggregate()} option:

{p 8 12 2}{bf:event} / {bf:dynamic}: event-study estimates by time relative to treatment (e = t - g).{break}
{bf:group}: average effects by treatment cohort.{break}
{bf:calendar}: average effects by calendar period.{break}
{bf:simple}: single weighted average of all post-treatment effects.{break}
{bf:all}: displays event, group, and simple aggregations in sequence.{p_end}


{marker parity}{...}
{title:Parity with R did::att_gt}

{pstd}
The option names below have direct equivalents in R's {bf:did::att_gt()}.
Everything else on the R side is supported with a different name (see the
options table above), except:

{p 8 12 2}{bf:print_details}: CSDid.jl is silent by default; nothing to toggle.{p_end}
{p 8 12 2}{bf:pl}, {bf:cores}: Julia parallelism is controlled by the environment
variable {bf:JULIA_NUM_THREADS}, set before Stata launches Julia. There is no
per-call flag.{p_end}
{p 8 12 2}{bf:compute_inffunc}: CSDid.jl always computes the influence function
internally (it drives the SEs and the bootstrap); there is no toggle.{p_end}
{p 8 12 2}{bf:faster_mode}: CSDid.jl's implementation is matrix-based in native
Julia and already uses the equivalent efficient path unconditionally; there is
no separate mode to switch on.{p_end}


{marker setup}{...}
{title:Setup}

{pstd}
{bf:Requirements:} Julia 1.12+ from {browse "https://julialang.org/downloads/"},
Stata 17+, and the {cmd:jl} package ({stata ssc install julia}).

{pstd}
{bf:First-time setup} (per session, or add to your {cmd:profile.do}):

{phang}{cmd:. adopath + "/path/to/csdidjl"}{p_end}

{pstd}
On {bf:Windows}, {cmd:csdid_jl} auto-detects Julia in the standard
{cmd:AppData\Local\Programs\Julia-*} locations.  On {bf:macOS} and
{bf:Linux}, it auto-detects Julia installed via {browse "https://github.com/JuliaLang/juliaup":juliaup}
or into {cmd:/Applications/Julia-*.app}.  If auto-detect fails, set:

{phang}{cmd:. global csdid_jl_julia_lib "/path/to/julia/lib"}{p_end}

{pstd}
To find the correct path on macOS or Linux, run in a terminal:

{phang}{cmd:. julia -e 'println(dirname(Sys.BINDIR))'}{p_end}

{pstd}
and append {cmd:/lib} to the result.  On Windows, use the {cmd:bin} subfolder
containing {cmd:libjulia.dll}.

{pstd}
{bf:First run precompiles the Julia project.}  This takes 5-15 minutes on the
first call, during which many "Precompiling ..." lines will scroll by in the
Stata output window.  Subsequent calls start in a few seconds.  Deps
are installed automatically on first load.


{marker examples}{...}
{title:Examples}

{pstd}Basic estimation (doubly robust, no covariates):{p_end}
{phang}{cmd:. csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal)}{p_end}

{pstd}With covariates:{p_end}
{phang}{cmd:. csdid_jl lemp lpop, tname(year) gname(firsttreat) idname(countyreal)}{p_end}

{pstd}IPW estimator with not-yet-treated control group:{p_end}
{phang}{cmd:. csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) est_method(ipw) notyet}{p_end}

{pstd}Sampling weights:{p_end}
{phang}{cmd:. csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) weights(pop)}{p_end}

{pstd}Clustered standard errors:{p_end}
{phang}{cmd:. csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) cluster(state)}{p_end}

{pstd}Repeated cross-sections:{p_end}
{phang}{cmd:. csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) nopanel}{p_end}

{pstd}Unbalanced panel:{p_end}
{phang}{cmd:. csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) unbalanced}{p_end}

{pstd}Universal base period with anticipation:{p_end}
{phang}{cmd:. csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) base_period(universal) anticipation(1)}{p_end}

{pstd}Time-varying weights:{p_end}
{phang}{cmd:. csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) weights(wt) fix_weights(base_period)}{p_end}

{pstd}Analytical SEs, no bootstrap:{p_end}
{phang}{cmd:. csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) nobstrap}{p_end}

{pstd}Pointwise CI (no simultaneous band):{p_end}
{phang}{cmd:. csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) nocband}{p_end}

{pstd}Event-study aggregation with plot:{p_end}
{phang}{cmd:. csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) agg(event) graph}{p_end}

{pstd}All aggregations and all plots at once:{p_end}
{phang}{cmd:. csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) agg(all) graph}{p_end}


{marker graph}{...}
{title:Graph}

{pstd}
The {opt graph} option produces plots that mirror the R {bf:did::ggdid()}
function.  Colors match R exactly: pre-treatment estimates in salmon
({bf:#e87d72}), post-treatment estimates in teal ({bf:#56bcc2}).  A dashed
reference line is drawn at zero.

{pstd}
Which plot is drawn depends on {opt aggregate()}:

{synoptset 26 tabbed}{...}
{synopt:{opt agg(att)} (default)}ATT(g,t) faceted by group, one panel per cohort (like {bf:ggdid.MP}){p_end}
{synopt:{opt agg(event)}/{opt agg(dynamic)}}event study, x = length of exposure{p_end}
{synopt:{opt agg(calendar)}}average effect by time period{p_end}
{synopt:{opt agg(group)}}horizontal cohort plot (like R {bf:splot}){p_end}
{synopt:{opt agg(all)}}all four plots at once{p_end}

{pstd}
Each plot is saved as a named Stata graph you can export or combine:

{synoptset 26 tabbed}{...}
{synopt:{cmd:csdid_attgt}}ATT(g,t) facet plot{p_end}
{synopt:{cmd:csdid_dynamic}}event study{p_end}
{synopt:{cmd:csdid_calendar}}calendar aggregation{p_end}
{synopt:{cmd:csdid_group}}group-cohort aggregation{p_end}

{pstd}
Confidence bands use {cmd:e(agg_cv_}{it:type}{cmd:)} for aggregations and
{cmd:e(crit_val)} for ATT(g,t).  These match R's uniform critical values when
{cmd:cband=TRUE}.  With {opt nocband}, the band collapses to the pointwise
normal critical value.

{pstd}
Example: export an event-study plot.

{phang}{cmd:. csdid_jl lemp, tname(year) gname(firsttreat) idname(countyreal) agg(event) graph}{p_end}
{phang}{cmd:. graph export event_study.png, name(csdid_dynamic) replace}{p_end}


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:csdid_jl} stores the following in {cmd:e()}:

{synoptset 32 tabbed}{...}
{syntab:Scalars}
{synopt:{cmd:e(N)}}number of cross-sectional units{p_end}
{synopt:{cmd:e(N_obs)}}number of observations used{p_end}
{synopt:{cmd:e(ngt)}}number of (group, time) cells{p_end}
{synopt:{cmd:e(crit_val)}}critical value for ATT(g,t) simultaneous band{p_end}
{synopt:{cmd:e(alpha)}}significance level{p_end}
{synopt:{cmd:e(agg_att_}{it:type}{cmd:)}}overall aggregated ATT{p_end}
{synopt:{cmd:e(agg_se_}{it:type}{cmd:)}}overall aggregated standard error{p_end}
{synopt:{cmd:e(agg_cv_}{it:type}{cmd:)}}critical value used for the aggregated band{p_end}

{syntab:Macros}
{synopt:{cmd:e(cmd)}}{cmd:csdid_jl}{p_end}
{synopt:{cmd:e(cmdline)}}command as typed{p_end}
{synopt:{cmd:e(depvar)}}outcome variable{p_end}
{synopt:{cmd:e(indepvars)}}covariate list{p_end}
{synopt:{cmd:e(est_method)}}estimation method{p_end}
{synopt:{cmd:e(control_group)}}control-group type{p_end}
{synopt:{cmd:e(base_period)}}base-period type{p_end}
{synopt:{cmd:e(agg)}}aggregation requested{p_end}

{syntab:Matrices}
{synopt:{cmd:e(b)}}1 x ngt vector of ATT(g,t) estimates{p_end}
{synopt:{cmd:e(V)}}ngt x ngt diagonal variance-covariance matrix{p_end}
{synopt:{cmd:e(att)}}ATT(g,t) point estimates{p_end}
{synopt:{cmd:e(se)}}standard errors{p_end}
{synopt:{cmd:e(group)}}group identifiers for each (g,t) cell{p_end}
{synopt:{cmd:e(t)}}time identifiers for each (g,t) cell{p_end}
{synopt:{cmd:e(agg_att_egt_}{it:type}{cmd:)}}aggregated ATT by event/group/calendar{p_end}
{synopt:{cmd:e(agg_se_egt_}{it:type}{cmd:)}}aggregated SE by event/group/calendar{p_end}
{synopt:{cmd:e(agg_egt_}{it:type}{cmd:)}}event-time/group/calendar identifiers{p_end}
{p2colreset}{...}

{pstd}
For aggregations, {it:type} is one of {bf:dynamic}, {bf:group}, {bf:calendar},
or {bf:simple} depending on which aggregation was requested.


{marker references}{...}
{title:References}

{p 4 8 2}Callaway, B. and P.H.C. Sant'Anna. 2021.
Difference-in-differences with multiple time periods.
{it:Journal of Econometrics} 225(2): 200-230.
{browse "https://doi.org/10.1016/j.jeconom.2020.12.001"}{p_end}

{p 4 8 2}Sant'Anna, P.H.C. and J. Zhao. 2020.
Doubly robust difference-in-differences estimators.
{it:Journal of Econometrics} 219(1): 101-122.{p_end}

{p 4 8 2}Roodman, D. julia.ado: Stata-Julia bridge.
{browse "https://github.com/droodman/julia.ado"}{p_end}


{marker author}{...}
{title:Author}

{pstd}
CSDid.jl - Julia implementation of Callaway & Sant'Anna (2021).{break}
Stata wrapper follows the {cmd:reghdfejl} pattern by David Roodman.
{p_end}
