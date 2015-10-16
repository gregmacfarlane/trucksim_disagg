# Truck Attractions ------------------------------------------------------------
library(dplyr, warn.conflicts = FALSE)
library(foreign)
cat("   Calculating truck attractions coefficients\n")
# In this section we determine the destination locations of our trucks based on 
# national county business patterns (where industries are located), Table 7
# of the commodity flow survey (which industries create commodities), and national
# IO tables (which industries buy stuff from other industries). 
load("./data/cbp_data.Rdata")
load("./data/io/use_table.Rdata")

# County-to-FAF lookup table
cnty2faf <- read.dbf("./data_raw/shapefiles/cnty2faf.dbf") %>%
  transmute(
    GEOID = as.character(ANSI_ST_CO), 
    F4Z = as.character(F4Z)
  ) 
  

CountyDemand <- inner_join(CBP, usetable, by = "naics") %>%
  
  # employment in industry-commodity pair
  mutate(emp = emp * usecoef) %>%
  
  # employment using commodity, summed across industries within county
  group_by(GEOID, sctg) %>% 
  summarise(emp = sum(emp)) %>% ungroup(.)  %>%
  
  # which FAF zone is the county in?
  left_join(., cnty2faf, by = "GEOID") %>% 
  mutate(F4Z = as.character(F4Z)) %>%
  group_by(F4Z, sctg) %>% 
  
  mutate(
    prob = emp/sum(emp), 
    name = GEOID
  ) %>% ungroup(.) %>%
  
  # cleanup
  select(F4Z, sctg, name, prob) %>%
  arrange(F4Z, sctg) %>% tbl_df()

write.csv(CountyDemand, "./data/simfiles/use_table.csv", row.names = FALSE)