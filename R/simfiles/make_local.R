# County to TAZ disaggregation
library(readr)
library(dplyr, warn.conflicts = FALSE)
library(tidyr)
library(feather)
library(foreign)

numa_lookup <- readRDS("data/numa_lookup.rds")


se <- read.dbf("data_raw/shapefiles/numa.dbf", as.is = TRUE) %>%
  tbl_df() %>%
  transmute(
    numa = as.character(ID),
    hh = TOTALHH,
    retail = RETAILEMP,
    nonretail = NONRETAILE
  ) %>%
  left_join(numa_lookup, by = "numa") %>%
  gather(industry, count, hh:nonretail)


# Make term --------
make_coefs <-
  read_csv("data_raw/io/make_local.csv") %>%
  # combine fields to numa variables
  transmute(
    sctg = substr(Industry, 5, 6),
    retail = (RET + HI_RET)/2,
    nonretail = (IND + HI_IND + OFF + SERV + GOV + EDU + HOSP)/7
  ) %>%
  gather(industry, value, -sctg) %>%

  # join se data and multiply coefficients
  inner_join(se, by = "industry") %>%
  mutate(size = value * count) %>%
  
  # sum all industries in taz
  group_by(county, numa, sctg) %>%
  summarise(size = sum(size)) %>%
  
  # calculate within-county probability
  group_by(county, sctg) %>%
  mutate(
    p = size / sum(size),
    p = ifelse(is.nan(p), 1 / n(), p)
  ) %>%
  select(county, sctg, numa, p)

# output =======
write_feather(make_coefs, "data/simfiles/make_local.feather")
