# County to TAZ disaggregation
library(readr)
library(dplyr, warn.conflicts = FALSE)
library(tidyr)
suppressPackageStartupMessages(library(maptools))
suppressPackageStartupMessages(library(rgdal))
library(feather)
suppressPackageStartupMessages(library(rgeos))
library(foreign)
# This script creates a county -> numa lookup table for disaggregating the county
# flows down another level.
wgs84 <- CRS("+init=epsg:4326")
lcc <- CRS("+init=epsg:2818")


# read numa shapefile
numa_shp <- readShapePoly(
  "data_raw/shapefiles/numa.shp",
  proj4string = wgs84
) %>% 
  spTransform(., lcc)

# Import/Export Nodes =================
# Trucks destined for an airport or seaport should be directed to the
# NUMA that includes the port directly. In this section we find the 
# NUMA of the port based on its coordinates.
faf_coords <- read_feather("data/simfiles/facility_coords.feather")
ie_nodes <- read_feather("data/simfiles/ie_nodes.feather")
ie_coords <- filter(faf_coords, name %in% ie_nodes$name)

ie_coords$numa <- as.character(over(
  SpatialPoints(cbind(ie_coords$x, ie_coords$y), proj4string = lcc),
  numa_shp
)$ID)

ie <- ie_coords %>%
  filter(!is.na(numa)) %>%
  select(name, numa, x, y)


# NUMA Productions/ Attractions ============
# NUMAs are all contained within a single county, but some county flows
# will need to be divided to the several numas that exist within that county.
# In this section we find the county that each numa lies in and develop size
# terms on the make and use side that we use to disaggregate 
counties_shp <- readShapeSpatial(
  "data_raw/shapefiles/cnty2faf.shp", proj4string = wgs84
  ) %>%
  spTransform(., lcc)

# Read NUMA shapefile with se data

numa_coords <- gCentroid(numa_shp, byid = TRUE)
numa_coords$numa <- as.character(numa_shp$ID)
numa_coords$county <- over( numa_coords, counties_shp )$ANSI_ST_CO

se <- numa_shp@data %>%
  tbl_df() %>%
  transmute(
    numa = as.character(ID),
    hh = TOTALHH,
    retail = RETAILEMP,
    nonretail = NONRETAILE
  ) %>%
  left_join(numa_coords@data, by = "numa") %>%
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
  inner_join(se) %>%
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

# Use term -------
use_coefs <- 
  read_csv("data_raw/io/use_local.csv") %>%
  # combine fields to numa variables
  transmute(
    sctg = substr(Industry, 5, 6),
    retail = (RET + HI_RET)/2,
    nonretail = (IND + HI_IND + OFF + SERV + GOV + EDU + HOSP)/7
  ) %>%
  gather(industry, value, -sctg) %>%
  
  # join se data and multiply coefficients
  inner_join(se) %>%
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
write_feather(use_coefs,  "data/simfiles/use_local.feather")
