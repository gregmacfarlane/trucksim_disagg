# Allocate Trucks to Facilities
# ==============================================================
# This script assigns the trucks flowing between two FAF regions to counties
# based on county business patterns and macroeconomic IO tables.
library(methods)
suppressPackageStartupMessages(require(dplyr))
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

load("./data/CBPData.Rdata")
load("./data/io/MakeTable.Rdata")
WGS84 <- CRS("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs +towgs84=0,0,0")
LCC <- CRS("+proj=lcc +lat_1=49 +lat_2=45 +lat_0=44.25 +lon_0=-109.5 +x_0=600000 +y_0=0 +ellps=GRS80 +units=m +no_defs")

cnty2faf <- readShapePoints("./data/shapefiles/cnty2faf.shp",
                            proj4string = WGS84)
cnty2faf <- spTransform(cnty2faf, LCC)

cnty2faf <- cnty2faf@data %>%
  mutate(long = cnty2faf@coords[,1], lat = cnty2faf@coords[,2]) %>%
  select(long, lat, GEOID, F3Z)
  
# Lookup table with the number of employees in every county making a commodity
# as a percent of the total employees making that commodity in the FAF zone.
CountyLabor <- inner_join(CBP, maketable, by = "naics") %>%
  # employment in industry-commodity pair
  mutate(emp = emp * makecoef) %>% group_by(GEOID, sctg)    %>%
  # employment making commodity, summed across industries within county
  summarise(emp = sum(emp)) %>% ungroup(.) %>%
  # join county-FAF crosswalk
  left_join(., cnty2faf, by = "GEOID") %>%
  mutate(F3Z = as.character(F3Z)) %>%
  group_by(F3Z, sctg) %>% 
  mutate(prob = emp/sum(emp), name = GEOID, mode = 0) %>% ungroup() %>%
  select(lat, long, sctg, name, prob, mode, F3Z)




# Truck Attractions ------------------------------------------------------------
cat("Calculating truck attractions coefficients\n")
# In this section we determine the destination locations of our trucks based on 
# national county business patterns (where industries are located), Table 7
# of the commodity flow survey (which industries create commodities), and national
# IO tables (which industries buy stuff from other industries). 
load("./data/io/UseTable.Rdata")

CountyDemand <- inner_join(CBP, usetable, by = "naics") %>%
  # employment in industry-commodity pair
  mutate(emp = emp * usecoef) %>%
  # employment using commodity, summed across industries within county
  group_by(GEOID, sctg) %>% summarise(emp = sum(emp)) %>% ungroup(.)  %>%
  # join county-FAF crosswalk
  left_join(., cnty2faf, by = "GEOID") %>% 
  mutate(F3Z = as.character(F3Z)) %>%
  group_by(F3Z, sctg) %>% 
  mutate(prob = emp/sum(emp), name = GEOID, mode = 0) %>% ungroup(.) %>%
  select(lat, long, sctg, name, prob, mode, F3Z)

# Imports and Exports ----------------------------------------------------------
cat("Determining import and export nodes\n")
# For imports and exports,  we are told the initial or final FAF zone in the 
# United States. Because there are a limited number of border crossings, airports,
# or ports, we can determine the probability that a truck uses each port as a 
# function of the departure mode and the volume of freight we observe passing 
# through the port. 

# First, we load the shapefiles for ports, airports, and border crossings and
# determine which FAF zone they are located in.
FAFzones <- readShapePoly("./data/shapefiles/faf3zone.shp", proj4string = WGS84)
FAFzones <- spTransform(FAFzones, LCC)

# Seaports
seaports <- readShapePoints("./data/shapefiles/NTAD/ports_major.shp",
                            proj4string = WGS84)
seaports <- spTransform(seaports, LCC)
seaports$F3Z <- over(seaports, FAFzones)$F3Z
seaports <- seaports@data %>% 
  mutate(name = PORT, mode = 2,
         long = seaports@coords[,1], lat = seaports@coords[,2],
         freight = EXPORTS + IMPORTS)  %>%
  group_by(F3Z) %>% mutate(prob = freight/sum(freight)) %>% ungroup(.) %>%
  filter(prob > 0) %>% select(lat, long, name, prob, mode, F3Z) 

# Airports
airports <- readShapePoints("./data/shapefiles/NTAD/airports.shp",
                            proj4string = WGS84)
airports <- spTransform(airports, LCC)
airports$F3Z <- over(airports, FAFzones)$F3Z
airfreight <- read.csv("./data/2006-2010AirFreight.txt", sep = "#", 
                       stringsAsFactors = FALSE) %>%
  mutate(Year = substr(Date, 0, 4), name = substr(Origin, 0,3)) %>%
  filter(Year == "2007") %>%  group_by(name) %>% 
  summarise(freight = sum(Total))
airports <- airports@data %>%
  mutate(name = LOCID, mode = 3,
         long = coordinates(airports)[,1], lat = coordinates(airports)[,2]) %>%
  select(long, lat, name, F3Z, mode) %>% inner_join(., airfreight, by = "name")  %>%
  group_by(F3Z) %>%  mutate(prob = freight/sum(freight)) %>% ungroup(.) %>%
  select(lat, long, name, prob, mode, F3Z)


# Border crossings
crossings <- readShapePoints("./data/shapefiles/NTAD/border_x.shp",
                             proj4string = WGS84)
crossings <- spTransform(crossings, LCC)
crossings$F3Z <- over(crossings, FAFzones)$F3Z
crossings <- crossings@data %>% 
  mutate(long = coordinates(crossings)[,1], lat = coordinates(crossings)[,2], 
         name = PortCode, mode = 1)  %>%
  filter(Trucks > 0) %>% group_by(F3Z) %>%
  mutate(prob = Trucks / sum(Trucks)) %>% ungroup(.) %>%
  select(lat, long, name, prob, mode, F3Z)

# Bind the three crossing types into a single lookup table. We haven't considered
# sctg codes to this point, but we need to retain them in the join. This means
# we need to expand across all sctg codes.
suppressWarnings(ienodes <- rbind_list(seaports, airports, crossings) %>%
  left_join(., expand.grid(mode = c(1:3), 
                           sctg = sprintf("%02d", c(1:41, 43, 99))), by = "mode") %>%
  mutate(F3Z = as.character(F3Z), sctg = as.character(sctg)) %>%
  .[, c("mode", "lat", "long", "name", "prob", "F3Z", "sctg")]
  )

# Split FAF into production counties -------------------------------------------
cat("Allocating trucks to origins\n")
# Based on the point probability we calculated above, distribute the trucks to
# each point. To limit the amount of data splitting and recombining, we want 
# to split origins at once; this requires that we consolidate import and domestic
# mode information into a single variable
load("./data/processedfafdata.Rdata")
FAF <- FAF %>% ungroup() %>%
  mutate(id = 1:nrow(FAF),
         inmode = ifelse(is.na(fr_inmode), 0, fr_inmode),
         outmode= ifelse(is.na(fr_outmode), 0, fr_outmode)) %>% 
  select(-fr_inmode, -fr_outmode)

# join the origin node information together and to the FAF data
originnodes <- rbind_list(ienodes, CountyLabor)
names(originnodes) <- c("inmode", "olat", "olong", "origin", "prob", 
                        "dms_orig", "sctg")
FAF <- inner_join(FAF, originnodes, by = c("dms_orig", "sctg", "inmode"))

# split 
FAF$trucks <- unlist(mclapply(split(FAF, FAF$sctg),  mc.cores = cores,
                              function (x) splitorigin(x)),
                     use.names = FALSE)

# filter out zeros to limit unnecessary memory use.
FAF <- FAF %>% filter(trucks > 0)

# Split FAF into attraction counties -------------------------------------------
cat("Allocating trucks to destinations\n")
# Based on the point probability we calculated above, distribute the trucks to
# each point. To limit the amount of data splitting and recombining, we want 
# to split destinations at once. One important step will be to reassign each row
# a new id.
destinnodes <- rbind_list(ienodes, CountyDemand)
names(destinnodes) <- c("outmode", "dlat", "dlong", "destination", "prob", 
                        "dms_dest", "sctg")

FAF <- FAF %>% mutate(id = seq(1:nrow(FAF))) %>%  
  select(-prob, -inmode) %>%
  inner_join(., destinnodes, by = c("dms_dest", "sctg", "outmode"))

# split 
FAF$trucks <- unlist(mclapply(split(FAF, FAF$sctg),   mc.cores = cores, 
                                function (x) splitdest(x)), 
                       use.names = FALSE)
FAF <- FAF %>% filter(trucks > 0) %>% select(-outmode, -prob)

# Dealing with Alaska ---------------------------------------------------------
# We are only interested (at this point) in trucks that travel within the 48 
# contiguous United States. So trucks that travel between Alaska and the lower
# 48 need to have their origin or destination reassigned to the point where I-15
# crosses from Montana into Canada (this is the only border crossing that can
# be used by trucks in the FAF network). 
Sweetgrass <- crossings %>% filter(name == 3310)

FAF <- FAF %>%
  # filter out trucks exclusively in Hawaii or Alaska (as I think about it, 
  # this would be more efficient earlier in the scripts). Alaska is zone 20, and
  # Hawaii is in two zones, 151 and 159.
  filter(!(dms_orig == "20" & dms_dest == "20")) %>% 
  filter(!(dms_orig %in% c("151", "159") & dms_dest %in% c("151", "159"))) %>% 
  # If one end of the trip is in Alaska, reassign that end to I-15 in Montana
  mutate(olat  = ifelse(dms_orig == "20", Sweetgrass$lat,  olat ),
         olong = ifelse(dms_orig == "20", Sweetgrass$long, olong),
         dlat  = ifelse(dms_dest == "20", Sweetgrass$lat,  dlat ),
         dlong = ifelse(dms_dest == "20", Sweetgrass$long, dlong))



cat("Writing to file\n")
save(FAF, file = "data/dividedtrucks.Rdata")

