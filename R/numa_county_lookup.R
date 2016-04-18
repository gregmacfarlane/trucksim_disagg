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

# Read NUMA shapefile and pair each numa with its county
numa_coords <- gCentroid(numa_shp, byid = TRUE)
numa_coords$numa <- as.character(numa_shp$FID_1)
numa_coords$county <- as.character(over( numa_coords, counties_shp )$ANSI_ST_CO)

counties_missing_numa <- data_frame(
  numa = c(
    "3348", "2209", "3116", "2210", "3062", "4362", "2762", "4381", 
    "3149", "1432", "823",  "828",  "3851", "1505", "3543", "304", 
    "4257", "1929", "1957", "1970", "1716", "1954", "1969", "1710", 
    "2479", "1943", "2497", "1968", "2716", "2740", "2487", "2483", 
    "2510", "2455", "2761", "2456", "2753", "2474", "2457", "2452", 
    "1986", "3068", "1438", "2473", "1580", "3863"),
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
