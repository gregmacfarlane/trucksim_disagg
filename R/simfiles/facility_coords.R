library(dplyr, warn.conflicts = FALSE)
suppressMessages(library(maptools))
suppressMessages(library(rgdal))
suppressMessages(library(rgeos))
# Activity Coordinates ------
# This script creates a table with the geographic coordinates for all the points
# that trucks in the simulation can use.

message("Making table of facility coordinates.\n")
WGS84 <- CRS("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs +towgs84=0,0,0")
LCC <- CRS("+init=epsg:2818")

counties <- readShapePoly("data_raw/shapefiles/cnty2faf.shp",
                          proj4string = WGS84) %>%
  spTransform(LCC) 

county_points%
  gCentroid(., byid = TRUE)

counties <- counties@data %>%
  transmute(
    name = as.character(GEOID), 
    x = coordinates(counties)[, 1],
    y = coordinates(counties)[, 2]
  )

seaports <- readShapePoints("./data_raw/shapefiles/ntad/ports_major.shp",
                            proj4string = WGS84) %>%
  spTransform(LCC)
seaports <- seaports@data %>%
  transmute(
    name = as.character(PORT), 
    x = coordinates(seaports)[, 1],
    y = coordinates(seaports)[, 2]
  )
  

airports <- readShapePoints("./data_raw/shapefiles/ntad/airports.shp",
                            proj4string = WGS84) %>%
  spTransform(LCC)
airports <- airports@data %>%
  transmute(
    name = as.character(LOCID), 
    x = coordinates(airports)[, 1],
    y = coordinates(airports)[, 2]
  )


crossings <- readShapePoints("./data_raw/shapefiles/ntad/border_x.shp",
                             proj4string = WGS84) %>%
  spTransform(LCC)
crossings <- crossings@data %>%
  transmute(
    name = as.character(PortCode), 
    x = coordinates(crossings)[, 1],
    y = coordinates(crossings)[, 2]
  )

points <- rbind_list(counties, airports, seaports, crossings)

write.csv(points, file = "data/simfiles/facility_coords.csv", row.names = FALSE)