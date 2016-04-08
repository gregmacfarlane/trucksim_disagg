library(dplyr, warn.conflicts = FALSE)
library(feather)
suppressMessages(library(maptools))
suppressMessages(library(rgdal))
suppressMessages(library(rgeos))
# Activity Coordinates ------
# This script creates a table with the geographic coordinates for all the points
# that trucks in the simulation can use.

message("Making table of facility coordinates.\n")
WGS84 <- CRS("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs +towgs84=0,0,0")
LCC <- CRS("+init=epsg:2818")

numas_poly <- readShapePoly("data_raw/shapefiles/numa.shp",
                          proj4string = WGS84) %>%
  spTransform(LCC)

numas <- numas_poly@data %>%
  transmute(
    name = as.character(ID),
    x = coordinates(numas_poly)[, 1],
    y = coordinates(numas_poly)[, 2]
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
    name = paste("x", as.character(PortCode), sep = "_"),
    x = coordinates(crossings)[, 1],
    y = coordinates(crossings)[, 2],
    trucks = Trucks
  ) %>%
  filter(trucks > 0) %>% select(-trucks)

points <- rbind_list(numas, airports, seaports, crossings)

points$numa <- over(
  SpatialPoints(coords = cbind(points$x, points$y), proj4string = LCC),
  numas_poly
) %>%
  mutate(numa = as.character(ID)) %>%
  .$numa

write_feather(points, "data/simfiles/facility_coords.feather")
