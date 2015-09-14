# Flows to Trucks
# ==============================================================
# This script calculates the number of trucks shipping a given tonnage of frieght
# between two zones takes. This is based on chapter 3 of the FAF manual.

suppressPackageStartupMessages(require(dplyr))
suppressPackageStartupMessages(require(reshape2))
suppressPackageStartupMessages(require(maptools))
suppressPackageStartupMessages(require(spdep))
suppressPackageStartupMessages(require(parallel))
suppressPackageStartupMessages(require(readr))

# The user should requst the number of cores with the call.
args <-commandArgs(TRUE)
cores <- args[1]

if(is.na(cores)){stop("please submit the number of processes to use:
rscript Flows2Trucks.R 4")}
if(cores > detectCores()){stop("Requested processes exceeds available cores.") }


# DEFINE TRUCK ALLOCATION FACTORS -------------------------------------------
# Read the truck allocation factors (Table 3-3) into memory, and reshape to make
# it more useful. Also account for R's extremely annoying habit of converting 
# everything it can into a factor
truck_allocation_factors <- read.csv("data_raw/trucks/truckallocation.csv") %>%
  melt( ., id.vars = "distance",
       variable.name = 'vehicle_type', value.name = "allocation_factor") %>%
  mutate(vehicle_type = as.character(vehicle_type))

# Read the truck equivalency factors found in Appendix A of the FAF3 Freight
# Traffic Analysis report, which we'll need to convert from wide to tall format.
# The factors are used for converting kilotons into truckload equivalents. Since
# we are dealing with tons we need to scale the factors to account for the
# differences. *UPDATE* You seem to want to convert the units on the tons and values
# instead.
truck_equivalency_factors <- read.csv("data_raw/trucks/truckequivalence.csv") %>%
  melt( ., id.vars = c("vehicle_type", "sctg"), 
       variable.name = 'body_type', value.name = 'equiv_factor') %>%
  mutate(vehicle_type = as.character(vehicle_type),
         body_type = as.character(body_type),
         sctg = sprintf("%02d", sctg))

# Finally, read empty truck factors from Table 3-5 and define a helper function
# to grab the appropriate ones by body type and flow direction. Again, convert
# from the original wide to tall format on the fly.
empty_truck_factors <- read.csv("data_raw/trucks/emptytrucks.csv") %>%
  melt(., id.vars = c("crossing_type", "body_type"),
       variable.name = "vehicle_type", value.name = "empty_factor") %>%
  mutate(vehicle_type = as.character(vehicle_type),
         crossing_type = as.character(crossing_type),
         body_type = as.character(body_type))

# It will be much more efficient to join all of the factors to the data at one
# time. 
truck_factors <- left_join(truck_allocation_factors, truck_equivalency_factors,
                           by = "vehicle_type") %>%
  left_join(empty_truck_factors, ., by = c("body_type", "vehicle_type"))

# FUNCTION TO CALCULATE THE NECESSARY TRUCKS -----------------------------------
calcTruckloadEquivalencies <- function(flow_records, truck_factors){
  # Join the truck factors to the flow records table, `left_join` will expand
  # the LHS table as neccessary to match as many records as in needs to on the 
  # RHS.
  expandedtable <- left_join(flow_records, truck_factors, 
                             by = c("sctg", "distance", "crossing_type")) %>%
    # We also need to cut out all of the records where the distance is 
    # outside of the appropriate range.
    #filter(distance > min_distance & distance <= max_distance) %>%
    # We now multiply the factors through the data.frame to get number of
    # trucks in each body type and each vehicle type. But we need to group
    # by the id variable so the summed variables don't read across rows
    group_by(id) %>%
    mutate(trucks = 1000 * tons * allocation_factor * equiv_factor, 
           # As well as the number of empty trucks!
           empty_trucks = trucks * empty_factor, 
           # Also, calculate an approximate tons and values in each group as 
           # the percentage of trucks 
           tons = tons * trucks/sum(trucks), 
           value = value * trucks/sum(trucks) )  %>%
    # We care about vehicle type, but not body type. So let's group on the `id`
    # field as well as the `vehicle_type`, and then collapse everything else.
    group_by(id, vehicle_type) %>%
    # we obviously want the sum of the trucks and the empty trucks.
    summarise(trucks = sum(trucks), empty_trucks = sum(empty_trucks),
              # tons = sum(tons), value = sum(value),
    # but we also want to keep the relevant fields from the original data.
    # Because these are constant, we'll just take the first record in each group.
              dms_orig = dms_orig[1], dms_dest = dms_dest[1], sctg = sctg[1],
              fr_inmode = fr_inmode[1], fr_outmode = fr_outmode[1]) %>%
    melt(., value.name = "trucks",  variable.name = "empty",
         measure.vars = c("trucks", "empty_trucks"))  %>%
    mutate(type = ifelse(empty == "empty_trucks", 
                         paste(vehicle_type, "empty", sep = ":"),
                         vehicle_type)) %>%
    select(-empty, -vehicle_type)
  return(expandedtable)
}

# SIMPLER FUNCTION THAT JUST RETURNS TRUCK NUMBERS ============================
simpleTruckloadEquivalencies <- function(flow_records, truck_factors){
  # Join the truck factors to the flow records table, `left_join` will expand
  # the LHS table as neccessary to match as many records as in needs to on the 
  # RHS.
  expandedtable <- left_join(flow_records, truck_factors, 
                             by = c("sctg", "distance", "crossing_type")) %>%
    # We also need to cut out all of the records where the distance is 
    # outside of the appropriate range.
    #filter(distance > min_distance & distance <= max_distance) %>%
    # We now multiply the factors through the data.frame to get number of
    # trucks in each body type and each vehicle type. But we need to group
    # by the id variable so the summed variables don't read across rows
    group_by(id) %>%
    mutate(trucks = 1000 * tons * allocation_factor * equiv_factor * 
             (1 + empty_factor)) %>%
    # We care about vehicle type, but not body type. So let's group on the `id`
    # field as well as the `vehicle_type`, and then collapse everything else.
    group_by(id) %>%
    # we obviously want the sum of the trucks and the empty trucks.
    summarise(trucks = sum(trucks),
    # but we also want to keep the relevant fields from the original data.
    # Because these are constant, we'll just take the first record in each group.
              dms_orig = dms_orig[1], dms_dest = dms_dest[1], sctg = sctg[1],
              fr_inmode = fr_inmode[1], fr_outmode = fr_outmode[1])
  return(expandedtable)
}


# TEST WITH THE PUBLISHED EXAMPLE =============================================
# Recreate the conversion laid out in Table 3-6 of the FAF3 Freight Traffic
# Analyis report. I added the term `crossing_type` because I think the crossing
# type is determined by adjacency and not purely by import/export, despite the 
# horrendous terminology.
# table36 <- data.frame(dms_orig=49, dms_dest=41, sctg="03", tons=1519.150,
#                      value=1373.96, distance="(100,200]", 
#                      crossing_type = "land_border",
#                      id = 1, stringsAsFactors = FALSE)
#calcTruckloadEquivalencies(table36, truck_factors)
#truckcount(table36, truck_factors)

# DETERMINE DISTANCE AND ADJACENCY ============================================
# Which factor the flows get is determined first by the distance betweeen the 
# FAF zones and second by whether the zones share a land border. If they do, then
# there are more empty trucks flowing between the zones. We can determine both 
# sets of information from the FAF zones shapefile.
cat("Calculating distance and adjacency\n")
WGS84 <- CRS("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs +towgs84=0,0,0")
FAFzones <- readShapePoly("data_raw/shapefiles/faf3zone.shp", proj4string = WGS84)
FAFzones@data <- FAFzones@data %>% select(F3Z)

# Calculate Great Circle distance between every zone, and reshape into a lookup
# table.
distmatrix <- spDists(FAFzones, longlat = TRUE)
colnames(distmatrix) <- rownames(distmatrix) <- sprintf("%03d", FAFzones$F3Z)
distmatrix <- melt(distmatrix, value.name = "distance", as.is = TRUE) %>%
  mutate(dms_orig = as.character(Var1), dms_dest = as.character(Var2),
         distance = cut(distance * 0.621371, # spDists returns kilometers
                        breaks = c(0, 50, 100, 200, 500, Inf),
                        include.lowest = TRUE)) %>%
  select(dms_orig, dms_dest, distance)
  

# APPLY FACTORS TO FAF DATA ===================================================
cat("Calculating trucks\n")
load("data/faf_data.Rdata")

FAF <- FAF %>%
  left_join(distmatrix, by = c("dms_dest", "dms_orig")) %>%
  
  # identify if the trucks cross a land border: 801 is Canada, 802 is Mexico
  mutate(
    crossing_type = ifelse(
      fr_orig %in% c(801, 802) | fr_dest %in% c(801, 802), 
      "land_border", "domestic")
  ) 

FAF <- rbind_all(mclapply(split(FAF, FAF$sctg), mc.cores = cores,
  function(x)  calcTruckloadEquivalencies(x, truck_factors))) %>%
  # if less than a quarter of a truck, don't count it.
  filter(trucks > 0.25) %>%
  # and then round up the rest
  mutate(trucks = ceiling(trucks))


write.csv(FAF, file = "data/simfiles/faf_trucks.csv", row.names = FALSE)

