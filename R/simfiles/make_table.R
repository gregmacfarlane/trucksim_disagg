# Truck Productions ------------------------------------------------------------
library(dplyr, warn.conflicts = FALSE)
library(foreign)
cat("  Calculating truck productions coefficients\n")
# In this section we determine the origin locations of our trucks based on 
# national county business patterns (where industries are located) and Table 7
# of the commodity flow survey (which industries create commodities). To join
# these tables to the FAF data we also need the lookup table of counties to 
# FAF zones.

load("./data/cbp_data.Rdata")
load("./data/io/make_table.Rdata")

cnty2faf <- read.dbf("./data_raw/shapefiles/cnty2faf.dbf") %>%
  transmute(
    GEOID = as.character(GEOID), 
    F3Z = as.character(F3Z)
  ) %>%
  mutate(F3Z = ifelse(F3Z == "441", "440", F3Z))

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
  mutate(F3Z = as.character(F3Z)) %>%
  
  # What is the county's share of the FAF-zone employment?
  group_by(F3Z, sctg) %>% 
  mutate(
    prob = emp/sum(emp), 
    # origin name
    name = GEOID
  ) %>% ungroup() %>%
  
  # cleanup
  select(F3Z, sctg, name, prob) %>%
  arrange(F3Z, sctg) %>% tbl_df()

write.csv(CountyLabor, "./data/simfiles/make_table.csv", row.names = FALSE)

