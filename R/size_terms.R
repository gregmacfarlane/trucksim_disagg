# Allocate Trucks to Facilities
# ==============================================================
# This script assigns the trucks flowing between two FAF regions to counties
# based on county business patterns and macroeconomic IO tables.
library(methods)
require(dplyr)
require(dplyrExtras)
require(foreign)
require(reshape2)
require(maptools)
require(sp)
require(rgdal)


# Truck Productions ------------------------------------------------------------
cat("Calculating truck productions coefficients\n")
# In this section we determine the origin locations of our trucks based on 
# national county business patterns (where industries are located) and Table 7
# of the commodity flow survey (which industries create commodities). To join
# these tables to the FAF data we also need the lookup table of counties to 
# FAF zones.

load("./data/cbp_data.Rdata")
load("./data/io/make_table.Rdata")

cnty2faf <- read.dbf("./data_raw/shapefiles/cnty2faf.dbf") %>%
  select(GEOID, F3Z)
  
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

write.csv(CountyLabor, "./data/make_table.csv", row.names = FALSE)



# Truck Attractions ------------------------------------------------------------
cat("Calculating truck attractions coefficients\n")
# In this section we determine the destination locations of our trucks based on 
# national county business patterns (where industries are located), Table 7
# of the commodity flow survey (which industries create commodities), and national
# IO tables (which industries buy stuff from other industries). 
load("./data/io/use_table.Rdata")

CountyDemand <- inner_join(CBP, usetable, by = "naics") %>%
  
  # employment in industry-commodity pair
  mutate(emp = emp * usecoef) %>%
  
  # employment using commodity, summed across industries within county
  group_by(GEOID, sctg) %>% 
  summarise(emp = sum(emp)) %>% ungroup(.)  %>%
  
  # which FAF zone is the county in?
  left_join(., cnty2faf, by = "GEOID") %>% 
  mutate(F3Z = as.character(F3Z)) %>%
  group_by(F3Z, sctg) %>% 
  
  mutate(
    prob = emp/sum(emp), 
    name = GEOID
  ) %>% ungroup(.) %>%
  
  # cleanup
  select(F3Z, sctg, name, prob) %>%
  arrange(F3Z, sctg) %>% tbl_df()

write.csv(CountyDemand, "./data/use_table.csv", row.names = FALSE)

# Imports and Exports ----------------------------------------------------------
cat("Determining import and export nodes\n")
# For imports and exports,  we are told the initial or final FAF zone in the 
# United States. Because there are a limited number of border crossings, airports,
# or ports, we can determine the probability that a truck uses each port as a 
# function of the departure mode and the volume of freight we observe passing 
# through the port. 

# First, we load the shapefiles for ports, airports, and border crossings and
# determine which FAF zone they are located in.
WGS84 <- CRS("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs +towgs84=0,0,0")

FAFzones <- readShapePoly("./data_raw/shapefiles/faf3zone.shp", 
                          proj4string = WGS84)

# Seaports
seaports <- readShapePoints("./data_raw/shapefiles/ntad/ports_major.shp",
                            proj4string = WGS84)

seaports <- seaports@data %>% 
  mutate(
    name = PORT, 
    mode = 2,
    freight = EXPORTS + IMPORTS,
    F3Z = over(seaports, FAFzones)$F3Z
  )  %>%
  
  # FAF zone probability
  group_by(F3Z) %>% 
  mutate(prob = freight/sum(freight)) %>% 
  ungroup(.) %>%
  
  # don't bother keeping stuff we don't need
  filter(prob > 0) %>%  # empty ports
  select(name, prob, mode, F3Z) 

# Airports
airports <- readShapePoints("./data_raw/shapefiles/ntad/airports.shp",
                            proj4string = WGS84)

# air freight statistics
airfreight <- read.csv("./data_raw/shapefiles/ntad/2006-2010AirFreight.txt", 
                       sep = "#",  stringsAsFactors = FALSE) %>%
  mutate(Year = substr(Date, 0, 4), name = substr(Origin, 0,3)) %>%
  filter(Year == "2007") %>%  group_by(name) %>% 
  summarise(freight = sum(Total))


airports <- airports@data %>%
  mutate(
    name = LOCID, 
    mode = 3, 
    F3Z = over(airports, FAFzones)$F3Z
  ) %>%
  select(name, F3Z, mode) %>% 
  
  # calculate probability of airport by FAF zone
  inner_join(., airfreight, by = "name")  %>%
  group_by(F3Z) %>%  
  mutate(prob = freight/sum(freight)) %>% ungroup(.) %>%
  
  # keep only what we need
  select(name, prob, mode, F3Z)


# Border crossings
crossings <- readShapePoints("./data_raw/shapefiles/ntad/border_x.shp",
                             proj4string = WGS84)

crossings <- crossings@data %>% 
  mutate(
    name = PortCode, mode = 1,
    F3Z = over(crossings, FAFzones)$F3Z
    )  %>%
  filter(Trucks > 0) %>% 
  
  group_by(F3Z) %>%
  mutate(prob = Trucks / sum(Trucks)) %>% ungroup(.) %>%
  select(name, prob, mode, F3Z)

# Bind the three crossing types into a single lookup table. We haven't considered
# sctg codes to this point, but we need to retain them in the join. This means
# we need to expand across all sctg codes.
ienodes <- rbind_list(seaports, airports, crossings) %>%
  left_join(
    ., 
    expand.grid(mode = c(1:3), sctg = sprintf("%02d", c(1:41, 43, 99))), 
    by = "mode") %>%
  mutate(
    F3Z = as.character(F3Z), 
    sctg = as.character(sctg)
  ) %>%
  select(F3Z, mode, sctg, name, prob) %>%
  arrange(F3Z, mode, sctg)

write.csv(ienodes, "./data/ienodes.csv", row.names = FALSE)
