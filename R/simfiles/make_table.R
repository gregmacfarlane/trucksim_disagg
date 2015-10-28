# Truck Productions ------------------------------------------------------------
library(dplyr, warn.conflicts = FALSE)
library(foreign)
cat("  Calculating truck productions coefficients\n")
# In this section we determine the origin locations of our trucks based on
# national county business patterns (where industries are located) and make
# coefficients calculated from the Commodity Flow Survey. To join
# these tables to the FAF data we also need the lookup table of counties to
# FAF zones.

load("./data/cbp_data.Rdata")

library(readr)
library(dplyr)
library(tidyr)

set.seed(2)

# Construct make coefficients from PUMS data =========
# to protect from disclosure, some shipments are given a range of sctg codes. We
# simply impute from within the range.
impute_sctg <- function(sctg){
  
  # if the sctg value is a range, then pick a random category from with the range
  if(sctg == "01-05"){
    sample(sprintf("%02d", 1:5), 1)
  } else if(sctg == "06-09"){
    sample(sprintf("%02d", 6:9), 1)
  } else if(sctg == "10-14"){
    sample(sprintf("%02d", 10:14), 1)
  } else if(sctg == "15-19"){
    sample(sprintf("%02d", 15:19), 1)
  } else if(sctg == "20-24"){
    sample(sprintf("%02d", 20:24), 1)
  } else if(sctg == "25-30"){
    sample(sprintf("%02d", 25:30), 1)
  } else if(sctg == "31-34"){
    sample(sprintf("%02d", 31:34), 1)
  } else if(sctg == "35-38"){
    sample(sprintf("%02d", 35:38), 1)
  } else if(sctg == "39-99"){
    sample(sprintf("%02s", c("39", "40", "41", "43", "99")), 1)
  } else if(sctg == "00"){
    sample(sprintf("%02d", c(1:41, 43, 99)), 1)
  } else {
    sctg
  }
}

# Read the CFS PUMS data
cfs <- read_csv(
  "data_raw/cfs_pums.csv",
  col_types = list(
    NAICS = col_character(),
    SCTG = col_character()
  )
) %>%
  transmute(
    id = SHIPMT_ID,
    sctg = sapply(SCTG, function(x) impute_sctg(x)),
    naics = NAICS,
    value = SHIPMT_VALUE,
    weight = WGT_FACTOR
  )
  
# The make coefficient is the proportion of industry output consisting of each
# good.

maketable <- cfs %>%
  group_by(naics, sctg) %>%
  summarise(value = sum(value * weight)) %>%
  group_by(naics) %>%
  mutate(makecoef = value / sum(value))

# you will need the make coefficients to consruct the use table.
saveRDS(maketable, "data/io/makecoefs.rds")

#
cnty2faf <- read.dbf("./data_raw/shapefiles/cnty2faf.dbf") %>%
  tbl_df() %>%
  transmute(
    GEOID = as.character(ANSI_ST_CO),
    F4Z = as.character(F4Z)
  )

# Lookup table with the probability of a county within a FAF zone producing
# a given commodity determined as the county's share of relevant NAICS
# employment.
CountyLabor <- inner_join(CBP, maketable, by = "naics") %>%
  
  # employment in industry-commodity pair
  mutate(emp = emp * makecoef) %>%
  
  # All employees making commodity in the county
  group_by(GEOID, sctg) %>%
  summarise(emp = sum(emp)) %>%
  ungroup(.) %>%
  
  # which FAF zone is the county in?
  left_join(., cnty2faf, by = "GEOID") %>%
  mutate(F4Z = as.character(F4Z)) %>%
  
  # What is the county's share of the FAF-zone employment?
  group_by(F4Z, sctg) %>%
  mutate(
    prob = emp/sum(emp),
    # origin name
    name = GEOID
  ) %>% ungroup() %>%
  
  # cleanup
  select(F4Z, sctg, name, prob) %>%
  arrange(F4Z, sctg) %>% tbl_df()

write.csv(CountyLabor, "./data/simfiles/make_table.csv", row.names = FALSE)
