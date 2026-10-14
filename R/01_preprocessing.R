# ==============================================================================
# 01_preprocessing.R
# ------------------------------------------------------------------------------
# Legge i dati grezzi (Excel) scaricati dai portali GME e Terna e produce la
# serie giornaliera allineata usata da tutte le analisi:
#
#     data/processed/energy_daily.csv   (colonne: data, pun, gas, renew)
#
# I dati grezzi NON sono versionati nel repository (vedi README, sezione Dataset).
# Per rigenerare il file processato:
#   1. scaricare gli Excel dai portali indicati nel README in data/raw/
#   2. lanciare:  Rscript R/01_preprocessing.R
#
# Frequenze grezze:  PUN = oraria, Rinnovabili = 15 min, Gas = giornaliera.
# Tutte vengono aggregate a media giornaliera e allineate per data.
# ==============================================================================

suppressPackageStartupMessages({
  library(here)
  library(readxl)
  library(dplyr)
  library(lubridate)
  library(tidyr)
  library(readr)
  library(purrr)
})

raw_dir <- here("data", "raw")
out_dir <- here("data", "processed")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ------------------------------------------------------------------------------
# 1. GAS  (GME - MGP-GAS, gia' giornaliero). File per "anno termico" (ott-set),
#    quindi il primo file va tagliato per iniziare dal 2021-01-01.
# ------------------------------------------------------------------------------
gas_files <- c(
  "Annotermico_2020-2021_09.xlsx", "Annotermico_2021-2022_09.xlsx",
  "Annotermico_2022-2023_09.xlsx", "Annotermico_2023-2024_09.xlsx",
  "Annotermico_2024-2025_09.xlsx", "Annotermico_2025-2026_12.xlsx"
)

read_gas <- function(file, drop_head = 0) {
  df <- read_excel(file.path(raw_dir, file),
                   sheet = "MGP-GAS - Negoziazione continua", skip = 5)[, 1:2]
  df <- set_names(df, c("data", "gas"))
  if (drop_head > 0) df <- df[-(1:drop_head), ]
  df
}

gas <- bind_rows(
  read_gas(gas_files[1], drop_head = 92),  # taglia ott-dic 2020
  map(gas_files[-1], read_gas)
) %>%
  mutate(
    data = ymd(as.character(as.integer(data))),  # date in formato YYYYMMDD
    gas  = as.numeric(gas)
  ) %>%
  filter(!is.na(data)) %>%
  arrange(data)

# ------------------------------------------------------------------------------
# 2. PUN  (GME - MGP Elettricita', orario) -> media giornaliera
# ------------------------------------------------------------------------------
pun_files <- c("Anno 2021_12.xlsx", "Anno 2022_12.xlsx", "Anno 2023_12.xlsx",
               "Anno 2024_12.xlsx", "Anno 2025_12.xlsx")

read_pun <- function(file) {
  df <- read_excel(file.path(raw_dir, file), sheet = "Prezzi-Prices")
  d <- df[[1]]
  # la colonna data puo' arrivare come testo, seriale Excel o intero YYYYMMDD
  if (is.character(d)) {
    d <- ymd(d)
  } else if (is.numeric(d)) {
    d <- if (max(d, na.rm = TRUE) > 1e6) ymd(as.character(d)) else as.Date(d, origin = "1899-12-30")
  } else {
    d <- as.Date(d)
  }
  tibble(data = d, pun = as.numeric(df[[3]]))
}

pun <- map(pun_files, read_pun) %>%
  bind_rows() %>%
  group_by(data) %>%
  summarise(pun = mean(pun, na.rm = TRUE), .groups = "drop") %>%
  arrange(data)

# ------------------------------------------------------------------------------
# 3. RINNOVABILI  (Terna - Total Load, 15 min) -> media giornaliera
# ------------------------------------------------------------------------------
renew_files <- c("Rinnovabili 2021.xlsx", "Rinnovabili 2022.xlsx",
                 "Rinnovabili 2023.xlsx", "Rinnovabili 2024.xlsx",
                 "Rinnovabili 2025.xlsx")

read_renew <- function(file) {
  df <- read_excel(file.path(raw_dir, file))
  stopifnot(all(c("Date", "Total Load [MW]") %in% names(df)))
  df %>%
    transmute(ts = as.POSIXct(Date), renew = `Total Load [MW]`) %>%
    filter(!is.na(ts))
}

renew <- map(renew_files, read_renew) %>%
  bind_rows() %>%
  mutate(data = as.Date(ts)) %>%
  group_by(data) %>%
  summarise(renew = mean(renew, na.rm = TRUE), .groups = "drop") %>%
  arrange(data)

# ------------------------------------------------------------------------------
# 4. Allineamento per data e salvataggio
# ------------------------------------------------------------------------------
energy_daily <- pun %>%
  inner_join(gas,   by = "data") %>%
  inner_join(renew, by = "data") %>%
  arrange(data) %>%
  select(data, pun, gas, renew)

# controlli di sanita' (la pipeline si ferma se qualcosa non torna)
stopifnot(
  nrow(energy_daily) > 0,
  !anyNA(energy_daily),
  min(energy_daily$data) == as.Date("2021-01-01"),
  max(energy_daily$data) == as.Date("2025-12-31")
)

write_csv(energy_daily, file.path(out_dir, "energy_daily.csv"))

cat(sprintf("OK: %d righe scritte in data/processed/energy_daily.csv (%s -> %s)\n",
            nrow(energy_daily), min(energy_daily$data), max(energy_daily$data)))
