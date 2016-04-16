# In an extraordinarily annoying twist, NUMAs are not clipped to shorelines
# in the way that counties are. This makes some of them show up over water.
# Additionally, Virginia's weird habit of calling cities counties means that
# not every NUMA centroid lines up with its correct county. 

# Even less excusable is the riduculous choice to put an incorrect GEOID on 
# the NUMA file.

# This is an attempt to resolve these issues by brute-forcing the lookuptable

library(readr)
library(dplyr, warn.conflicts = FALSE)
library(tidyr)
suppressPackageStartupMessages(library(maptools))
suppressPackageStartupMessages(library(rgdal))
library(feather)
suppressPackageStartupMessages(library(rgeos))
library(foreign)

wgs84 <- CRS("+init=epsg:4326")
lcc <- CRS("+init=epsg:2818")

# read numa shapefile
numa_shp <- readShapePoly(
  "data_raw/shapefiles/numa.shp",
  proj4string = wgs84
) %>%
  spTransform(., lcc)

counties_shp <- readShapeSpatial(
  "data_raw/shapefiles/cnty2faf.shp", proj4string = wgs84
) %>%
  spTransform(., lcc)

# Read NUMA shapefile with se data
numa_coords <- gCentroid(numa_shp, byid = TRUE)
numa_coords$numa <- as.character(numa_shp$ID)
numa_coords$county <- as.character(over( numa_coords, counties_shp )$ANSI_ST_CO)

counties_missing_numa <- data_frame(
  numa = c(
    "3350",  "2211",  "3118",  "2212",  "3064",  "4364",  "2764",
    "4383",  "3151",  "1434",  "825",   "830",   "3853",  "1507", 
    "3545",  "306",   "4259",  "1931",  "1959",  "1972",  "1718",
    "1956",  "1971",  "1712",  "2481",  "1945",  "2499",  "1970", 
    "2718",  "2742",  "2489",  "2485",  "2512",  "2457",  "2763", 
    "2458",  "2755",  "2476",  "2459",  "2454",  "1988",  "3070", 
    "1440",  "2475",  "1582",  "3865"
  ),
  county = c(
    "15005", "36117", "22045", "36073", "39043", "39085", "39123", 
    "25007", "51161", "51685", "51600", "51610", "51089", "29093", 
    "51735", "08119", "27031", "55101", "55003", "55089", "55059", 
    "55029", "55071", "55061", "26003", "55091", "26007", "55117", 
    "26097", "26121", "26083", "26095", "26127", "26019", "26101", 
    "26069", "26105", "26131", "26001", "26141", "02122", "12087", 
    "02016", "26005", "02105", "51199"
  )
  
)

numa_lookup <- bind_rows(numa_coords@data, counties_missing_numa)

saveRDS(numa_lookup, "data/numa_lookup.rds")
