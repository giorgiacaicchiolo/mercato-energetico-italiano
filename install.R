# Installa i pacchetti R necessari a rigenerare i dati e compilare il report.
# Uso:  Rscript install.R
pkgs <- c(
  "here", "rmarkdown", "knitr", "kableExtra",
  "tidyverse", "readxl", "lubridate",
  "forecast", "vars", "urca", "dynlm", "lmtest", "MTS"
)
to_install <- setdiff(pkgs, rownames(installed.packages()))
if (length(to_install) > 0) {
  install.packages(to_install, repos = "https://cloud.r-project.org")
} else {
  message("Tutti i pacchetti sono gia' installati.")
}
