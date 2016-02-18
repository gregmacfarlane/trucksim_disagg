# County to TAZ disaggregation
library(readr)
library(dplyr)
library(tidyr)
library(maptools)
library(rgdal)
library(foreign)
# This script creates a county -> taz lookup table for disaggregating the county
# flows down another level.

ie_nodes <- read_csv("data/simfiles/ie_nodes.csv")
counties <- read.dbf("data_raw/shapefiles/cnty2faf.dbf")

faf_coords <- read_csv("data/simfiles/facility_coords.csv", col_types = "cnnc")

county_coords <- filter(faf_coords, name %in% counties$ANSI_ST_CO)
ie_coords <- filter(faf_coords, name %in% ie_nodes$name)
  
  
# Read TAZ shapefile with se data
taz_shp <- readShapePoly(
  "data_raw/shapefiles/NCSTM_TAZ_SE.shp",
  proj4string = CRS("+init=epsg:2264")
) %>%
  spTransform(., CRS("+init=epsg:2818"))
  

se <- taz_shp@data %>%
  tbl_df() %>%
  transmute(
    taz = MODEL_TAZ,
    region = REGION,  # regions, including outside the halo
    county = ifelse(is.na(COUNTYFIPS), NA,
                    paste(STATEFIPS, sprintf("%03d", COUNTYFIPS), sep = "")),
    ind = IND_11,
    hi_ind = HI_IND_11,
    ret = RET_11,
    hi_ret = HI_RET_11,
    off = OFF_11,
    serv = SERV_11,
    gov = GOV_11,
    edu = EDU_11,
    hosp = HOSP_11
  ) %>%
  gather(industry, count, ind:hosp)

# Import/Export Nodes
# Trucks destined for an airport or seaport should be directed to the
# TAZ that includes the port directly.
ie_coords$taz <- over(
  SpatialPoints(cbind(ie_coords$x, ie_coords$y),
                proj4string = CRS("+init=epsg:2818")),
  taz_shp
)$MODEL_TAZ

ie <- ie_coords %>%
  filter(!is.na(taz)) %>%
  select(name, taz)


# Zones outside the Halo ===========
# Zones inside of North Carolina and the Halo are generally smaller than a
# single county, and will need a split. Zones outside of the halo will instead
# get a p = 1 assigning them to the larger zone that contains one or more counties.

# which zone do the points fall in?
county_coords$taz <- over(
  SpatialPoints(cbind(county_coords$x, county_coords$y),
                proj4string = CRS("+init=epsg:2818")),
  taz_shp[taz_shp$REGION == 5, ]  # only need this outside Halo.
)$MODEL_TAZ

outside_counties <- county_coords %>%
  select(name, taz)

# Zones inside the Halo ==========
# there are two types of points inside the halo:
#  - standard counties that need to be disaggregated with se data
#  - import/export nodes that need to be assigned to an existing TAZ

se_halo <- se %>%
  filter(region != 5)
  
# Make term --------
make_coefs <- read_csv("data_raw/io/make_local.csv") %>%
  
  # clean up table
  gather(sctg, value, -Industry) %>%
  mutate(
    industry = tolower(Industry),
    sctg = substr(sctg, 5, 6)
  ) %>%
  select(industry, sctg, value) %>%

  # join se data and multiply coefficients
  left_join(se_halo) %>%
  mutate(value = value * count) %>%
  
  # sum all industries in taz
  group_by(county, taz, sctg) %>%
  summarise(value = sum(value)) %>%
  
  # calculate within-county probability
  group_by(county, sctg) %>%
  mutate(p = value / sum(value))

# Use term -------
use_coefs <- read_csv("data_raw/io/use_local.csv") %>%
  # clean up table
  gather(sctg, value, -Industry) %>%
  mutate(
    industry = tolower(Industry),
    sctg = substr(sctg, 5, 6)
  ) %>%
  select(industry, sctg, value) %>%

  # join se data and multiply coefficients
  left_join(se_halo) %>%
  mutate(value = value * count) %>%
  
  # sum all industries in taz
  group_by(county, taz, sctg) %>%
  summarise(value = sum(value)) %>%
  
  # calculate within-county probability
  group_by(county, sctg) %>%
  mutate(p = value / sum(value))


# output =======
write_csv(make_coefs, "data/simfiles/make_local.csv")
write_csv(use_coefs,  "data/simfiles/use_local.csv")
write_csv(rbind(outside_counties, ie), "data/simfiles/county_to_taz.csv")
