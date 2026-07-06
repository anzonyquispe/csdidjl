# ═══════════════════════════════════════════════════════════════
#  ARTEFACTO 2 — R reference values for ALL 12 scenarios
#  Uses: R did package (Callaway & Sant'Anna)
#  Dataset: mpdta (500 counties × 5 years)
# ═══════════════════════════════════════════════════════════════

cat("R version:", R.version.string, "\n")

if (!requireNamespace("did", quietly = TRUE)) {
  install.packages("did", repos = "https://cran.r-project.org")
}
library(did)
cat("did package version:", as.character(packageVersion("did")), "\n\n")

data(mpdta)
cat("Dataset: mpdta\n")
cat("  Observations:", nrow(mpdta), "\n")
cat("  Units:", length(unique(mpdta$countyreal)), "\n")
cat("  Periods:", length(unique(mpdta$year)), "\n")
cat("  Treatment groups:", paste(sort(unique(mpdta$first.treat[mpdta$first.treat > 0])), collapse=", "), "\n\n")

# ─── Define scenarios ──────────────────────────────────────
scenarios <- list(
  list(name="dr_nev_nocov",   xf=~1,    cg="nevertreated",  em="dr",  label="DR | nevertreated | no covariates"),
  list(name="ipw_nev_nocov",  xf=~1,    cg="nevertreated",  em="ipw", label="IPW | nevertreated | no covariates"),
  list(name="reg_nev_nocov",  xf=~1,    cg="nevertreated",  em="reg", label="REG | nevertreated | no covariates"),
  list(name="dr_nyt_nocov",   xf=~1,    cg="notyettreated", em="dr",  label="DR | notyettreated | no covariates"),
  list(name="ipw_nyt_nocov",  xf=~1,    cg="notyettreated", em="ipw", label="IPW | notyettreated | no covariates"),
  list(name="reg_nyt_nocov",  xf=~1,    cg="notyettreated", em="reg", label="REG | notyettreated | no covariates"),
  list(name="dr_nev_cov",     xf=~lpop, cg="nevertreated",  em="dr",  label="DR | nevertreated | xformla=~lpop"),
  list(name="ipw_nev_cov",    xf=~lpop, cg="nevertreated",  em="ipw", label="IPW | nevertreated | xformla=~lpop"),
  list(name="reg_nev_cov",    xf=~lpop, cg="nevertreated",  em="reg", label="REG | nevertreated | xformla=~lpop"),
  list(name="dr_nyt_cov",     xf=~lpop, cg="notyettreated", em="dr",  label="DR | notyettreated | xformla=~lpop"),
  list(name="ipw_nyt_cov",    xf=~lpop, cg="notyettreated", em="ipw", label="IPW | notyettreated | xformla=~lpop"),
  list(name="reg_nyt_cov",    xf=~lpop, cg="notyettreated", em="reg", label="REG | notyettreated | xformla=~lpop")
)

attgt_all  <- data.frame()
aggte_all  <- data.frame()

for (scn in scenarios) {
  cat(strrep("=", 70), "\n")
  cat("=== SCENARIO:", scn$name, "===\n")
  cat("   ", scn$label, "\n")
  cat(strrep("=", 70), "\n")

  tryCatch({
    out <- att_gt(
      yname = "lemp", tname = "year", idname = "countyreal",
      gname = "first.treat", xformla = scn$xf, data = mpdta,
      est_method = scn$em, control_group = scn$cg,
      base_period = "varying", bstrap = FALSE, print_details = FALSE
    )

    for (i in seq_along(out$group)) {
      attgt_all <- rbind(attgt_all, data.frame(
        scenario = scn$name, group = out$group[i], t = out$t[i],
        att = out$att[i], se = out$se[i], stringsAsFactors = FALSE
      ))
      cat(sprintf("  ATT(g=%d, t=%d) = %20.15f  SE = %20.15f\n",
                  out$group[i], out$t[i], out$att[i], out$se[i]))
    }

    for (atype in c("simple", "dynamic", "group", "calendar")) {
      tryCatch({
        agg <- aggte(out, type = atype)
        aggte_all <- rbind(aggte_all, data.frame(
          scenario = scn$name, agg_type = atype, egt = NA,
          att_egt = NA, se_egt = NA,
          overall_att = agg$overall.att, overall_se = agg$overall.se,
          stringsAsFactors = FALSE
        ))
        cat(sprintf("  aggte(%s): overall_att = %20.15f  SE = %20.15f\n",
                    atype, agg$overall.att, agg$overall.se))

        if (atype != "simple") {
          for (j in seq_along(agg$egt)) {
            aggte_all <- rbind(aggte_all, data.frame(
              scenario = scn$name, agg_type = atype, egt = agg$egt[j],
              att_egt = agg$att.egt[j], se_egt = agg$se.egt[j],
              overall_att = agg$overall.att, overall_se = agg$overall.se,
              stringsAsFactors = FALSE
            ))
          }
        }
      }, error = function(e) {
        cat(sprintf("  aggte(%s): ERROR - %s\n", atype, e$message))
      })
    }
  }, error = function(e) {
    cat("  SCENARIO FAILED:", e$message, "\n")
  })
  cat("\n")
}

write.csv(attgt_all, "C:/Users/Usuario/CSDid.jl/r_results.csv", row.names = FALSE)
write.csv(aggte_all, "C:/Users/Usuario/CSDid.jl/r_aggte_results_full.csv", row.names = FALSE)

cat(strrep("=", 70), "\n")
cat("DONE: Saved", nrow(attgt_all), "ATT(g,t) rows to r_results.csv\n")
cat("DONE: Saved", nrow(aggte_all), "aggregation rows to r_aggte_results_full.csv\n")
cat(strrep("=", 70), "\n")
