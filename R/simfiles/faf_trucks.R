# Flows to Trucks
# ==============================================================
# This script calculates the number of trucks shipping a given tonnage of frieght
# between two zones takes. This is based on chapter 3 of the FAF manual.
library(dplyr, warn.conflicts = FALSE)
library(tidyr)
library(feather)
library(readr)
suppressPackageStartupMessages(library(maptools, quietly = TRUE))
library(parallel)

# The user should requst the number of cores with the call.
args <-commandArgs(TRUE)
cores <- args[1]

if(is.na(cores)){
  stop("please submit the number of processes to use: rscript Flows2Trucks.R 4")
}
if(cores > detectCores()){
  stop("Requested processes exceeds available cores.")
}


# DEFINE TRUCK ALLOCATION FACTORS -------------------------------------------
# Read the truck allocation factors (Table 3-3) into memory, and reshape to make
# it more useful. 
truck_allocation_factors <- read_csv("./data_raw/trucks/truckallocation.csv") %>%
  gather(vehicle_type, allocation_factor, -distance, convert = TRUE)

# Read the truck equivalency factors found in Appendix A of the FAF3 Freight
# Traffic Analysis report, which we'll need to convert from wide to tall format.
truck_equivalency_factors <- read_csv("data_raw/trucks/truckequivalence.csv") %>%
  gather(body_type, equiv_factor, auto:other, convert = TRUE)

# Finally, read empty truck factors from Table 3-5 and define a helper function
# to grab the appropriate ones by body type and flow direction. Again, convert
# from the original wide to tall format on the fly.
empty_truck_factors <- read_csv("data_raw/trucks/emptytrucks.csv") %>%
  gather(vehicle_type, empty_factor, SU:TPT, convert = TRUE)

# It will be much more efficient to join all of the factors to the data at one
# time.
truck_factors <- left_join(
  truck_allocation_factors, truck_equivalency_factors, 
  by = "vehicle_type"
) %>%
  left_join(empty_truck_factors, ., by = c("body_type", "vehicle_type"))

# FUNCTION TO CALCULATE THE NECESSARY TRUCKS -----------------------------------
calcTruckloadEquivalencies <- function(flow_records, truck_factors){
  # Join the truck factors to the flow records table, `left_join` will expand
  # the LHS table as neccessary to match as many records as in needs to on the
  # RHS.
  expandedtable <- left_join(
    flow_records, truck_factors, by = c("sctg", "distance", "crossing_type")
    ) %>%
    group_by(id) %>%
    mutate(
      # We now multiply the factors through the data.frame to get number of
      # trucks in each body type and each vehicle type. But we need to group
      # by the id variable so the summed variables don't read across rows
      trucks = 1000 * tons * allocation_factor * equiv_factor,
      # As well as the number of empty trucks!
      empty_trucks = trucks * empty_factor
    ) %>%
    # We care about vehicle type, but not body type. So let's group on the `id`
    # field as well as the `vehicle_type`, and then collapse everything else.
    group_by(id, vehicle_type) %>%
    summarise(
      # we obviously want the sum of the trucks and the empty trucks.
      trucks = sum(trucks), empty_trucks = sum(empty_trucks), 
      # but we also want to keep the relevant fields from the original data.
      # Because these are constant, we'll just take the first record in each
      # group.
      dms_orig = dms_orig[1], dms_dest = dms_dest[1], sctg = sctg[1],
      fr_inmode = fr_inmode[1], fr_outmode = fr_outmode[1]
    ) %>%
    gather(type, trucks, trucks:empty_trucks) %>%
    mutate(
      type = ifelse(
        type == "empty_trucks",  
        paste(vehicle_type, "empty", sep = ":"), 
        vehicle_type
      )
    ) %>%
    select(-vehicle_type)
  
  return(expandedtable)
}



# TEST WITH THE PUBLISHED EXAMPLE =============================================
# See docs/trucks_calculation.Rmd

# DETERMINE DISTANCE AND ADJACENCY ============================================
# Which factor the flows get is determined first by the distance betweeen the
# FAF zones and second by whether the zones share a land border. If they do, then
# there are more empty trucks flowing between the zones. We can determine both
# sets of information from the FAF zones shapefile.
message("Calculating distance and adjacency\n")
WGS84 <- sp::CRS("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs +towgs84=0,0,0")
FAFzones <- maptools::readShapePoly(
  "data_raw/shapefiles/faf4zone.shp", proj4string = WGS84
)
F4Z <- FAFzones@data %>%
  transmute(F4Z = sprintf("%03s", as.character(F4Z))) %>%
  .$F4Z

# Calculate Great Circle distance between every zone, and reshape into a lookup
# table.
distmatrix <- sp::spDists(FAFzones, longlat = TRUE) %>%
  as.data.frame() %>%
  as_data_frame() %>%
  mutate(dms_orig = F4Z)

names(distmatrix) <- c(F4Z, "dms_orig")

distmatrix <- distmatrix %>%
  gather(dms_dest, distance, -dms_orig) %>%
  mutate(
    distance = cut(distance * 0.621371, # spDists returns km, factors in mi
                   breaks = c(0, 50, 100, 200, 500, Inf),
                   include.lowest = TRUE),
    dms_dest = as.character(dms_dest)
  )
  

# APPLY FACTORS TO FAF DATA ===================================================
message("Calculating trucks\n")
load("data/faf_data.Rdata")

FAF <- FAF %>%
  left_join(distmatrix, by = c("dms_dest", "dms_orig")) %>%
  
  # identify if the trucks cross a land border: 801 is Canada, 802 is Mexico
  mutate(
    dms_orig = dms_orig,
    dms_dest = dms_dest,
    crossing_type = ifelse(
      fr_orig %in% c(801, 802) | fr_dest %in% c(801, 802),
      "land_border", "domestic")
  )

FAF <- rbind_all(
  mclapply(split(FAF, FAF$sctg), mc.cores = cores,
  function(x)  calcTruckloadEquivalencies(x, truck_factors))
  ) %>%
  # if less than a quarter of a truck, don't count it.
  filter(trucks > 0.25) %>%
  # and then round up the rest
  mutate(trucks = ceiling(trucks))


write_feather(FAF, "data/simfiles/faf_trucks.feather")
