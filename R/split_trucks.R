# Allocate Trucks to Facilities
# ==============================================================
# This script assigns the trucks flowing between two FAF regions to counties
# based on county business patterns and macroeconomic IO tables.
library(methods)
suppressPackageStartupMessages(require(dplyr))
suppressPackageStartupMessages(require(dplyrExtras))
suppressPackageStartupMessages(require(foreign))
suppressPackageStartupMessages(require(reshape2))
suppressPackageStartupMessages(require(maptools))
suppressPackageStartupMessages(require(sp))
suppressPackageStartupMessages(require(rgdal))
suppressPackageStartupMessages(require(parallel))

# The user should enter the number of cores with the call.
args <-commandArgs(TRUE)
cores <- args[1]
if(is.na(cores)){stop("please submit the number of processes to use:
rscript Flows2Trucks.R 4")}
if(cores > detectCores()){stop("Requested processes exceeds available cores.") }

# FUNCTION TO SPLIT TRUCKS BASED ON PROBABILITY --------------------------------
splitorigin <- function(df){
  splittable <- df %>% ungroup() %>%
    group_by(id)  %>%
    do(data.frame(table(sample(factor(.$origin), .$trucks[1], .$prob, 
                               replace = TRUE))))
  return(splittable$Freq)
}

splitdest <- function(df){
  splittable <- df %>% ungroup() %>%
    group_by(id)  %>%
    do(data.frame(table(sample(factor(.$destination), .$trucks[1], .$prob, 
                               replace = TRUE))))
  return(splittable$Freq)
}
# Truck Productions ------------------------------------------------------------
cat("Calculating truck productions coefficients\n")
# In this section we determine the origin locations of our trucks based on 
# national county business patterns (where industries are located) and Table 7
# of the commodity flow survey (which industries create commodities). To join
# these tables to the FAF data we also need the lookup table of counties to 
# FAF zones.

load("./data/cbp_data.Rdata")
load("./data/io/make_table.Rdata")
WGS84 <- CRS("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs +towgs84=0,0,0")

cnty2faf <- readShapePoints("./data_raw/shapefiles/cnty2faf.shp",
                            proj4string = WGS84)

cnty2faf <- cnty2faf@data %>%
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
    name = GEOID, 
    # travel mode
    mode = 0) %>% ungroup() %>%
  
  # cleanup
  select(sctg, name, prob, mode, F3Z) %>%
  tbl_df()




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
    name = GEOID, 
    mode = 0) %>% ungroup(.) %>%
  
  select(sctg, name, prob, mode, F3Z) %>%
  tbl_df()

# Imports and Exports ----------------------------------------------------------
cat("Determining import and export nodes\n")
# For imports and exports,  we are told the initial or final FAF zone in the 
# United States. Because there are a limited number of border crossings, airports,
# or ports, we can determine the probability that a truck uses each port as a 
# function of the departure mode and the volume of freight we observe passing 
# through the port. 

# First, we load the shapefiles for ports, airports, and border crossings and
# determine which FAF zone they are located in.
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
  select(mode, name, prob, F3Z, sctg)

# Split FAF into production counties -------------------------------------------
cat("Allocating trucks to origins\n")
# Based on the point probability we calculated above, distribute the trucks to
# each point. To limit the amount of data splitting and recombining, we want 
# to split origins at once; this requires that we consolidate import and domestic
# mode information into a single variable
load("./data/faf_trucks.Rdata")
FAF <- FAF %>% ungroup() %>%
  mutate(
    # a new id
    id = 1:nrow(FAF), 
    # What import/export mode; if NA then set to 0
    inmode  = ifelse(is.na(fr_inmode), 0, fr_inmode), 
    outmode = ifelse(is.na(fr_outmode), 0, fr_outmode)
  ) %>% 
  select(-fr_inmode, -fr_outmode)

# join the origin node information together and to the FAF data
originnodes <- rbind_list(ienodes, CountyLabor)
names(originnodes) <- c("inmode", "origin", "prob", "dms_orig", "sctg")

FAF <- FAF %>%
  inner_join(originnodes, by = c("dms_orig", "sctg", "inmode"))

# split 
FAF$trucks <- unlist(
  mclapply(split(FAF, FAF$sctg),  mc.cores = cores, 
           function (x) splitorigin(x)), 
  use.names = FALSE
)

# filter out zeros to limit unnecessary memory use.
FAF <- FAF %>% 
  filter(trucks > 0) %>% select(-prob, -inmode)

# Split FAF into attraction counties -------------------------------------------
cat("Allocating trucks to destinations\n")
# Based on the point probability we calculated above, distribute the trucks to
# each point. To limit the amount of data splitting and recombining, we want 
# to split destinations at once. One important step will be to reassign each row
# a new id.
destinnodes <- rbind_list(ienodes, CountyDemand)
names(destinnodes) <- c("outmode", "destination", "prob",  
                        "dms_dest", "sctg")

FAF <- FAF %>% 
  # need a new id
  mutate(id = seq(1:nrow(FAF))) %>%  
  inner_join(., destinnodes, by = c("dms_dest", "sctg", "outmode"))

# split 
FAF$trucks <- unlist(
  mclapply(split(FAF, FAF$sctg),   mc.cores = cores,  
           function (x) splitdest(x)), 
  use.names = FALSE
)

FAF <- FAF %>% filter(trucks > 0) %>% select(-outmode, -prob)

# Dealing with Alaska ---------------------------------------------------------
# We are only interested (at this point) in trucks that travel within the 48 
# contiguous United States. So trucks that travel between Alaska and the lower
# 48 need to have their origin or destination reassigned to either I-5 in 
# Washington or I-15 in Montana

# trucks going between Alaska and CA, OR, WA, NV, AZ, ID, UT use I-5
i5_zones <- as.character(c(
  61:69, 411:419, 531:539, 321:329, 41:49, 160, 491:499
))

FAF <- FAF %>%
  mutate_if(
    dms_orig == "20", 
    origin = ifelse(dms_dest %in% i5_zones, "3004", "3310")
  ) %>%
  mutate_if(
    dms_dest == "20", 
    destination = ifelse(dms_orig %in% i5_zones, "3004", "3310")
  )


cat("Writing to file\n")
save(FAF, file = "./data/disaggregated_trucks.Rdata")

