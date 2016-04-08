library(dplyr, warn.conflicts = FALSE)
library(feather)
suppressMessages(require(maptools))

# Imports and Exports ----------------------------------------------------------
options(stringsAsFactors = FALSE)
cat("   Determining import and export nodes\n")
# For imports and exports,  we are told the initial or final FAF zone in the 
# United States. Because there are a limited number of border crossings, airports,
# or ports, we can determine the probability that a truck uses each port as a 
# function of the departure mode and the volume of freight we observe passing 
# through the port. 

# First, we load the shapefiles for ports, airports, and border crossings and
# determine which FAF zone they are located in.
WGS84 <- CRS("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs +towgs84=0,0,0")
FAFzones <- readShapePoly("./data_raw/shapefiles/faf4zone.shp", 
                          proj4string = WGS84)

# Seaports
seaports <- readShapePoints("./data_raw/shapefiles/ntad/ports_major.shp",
                            proj4string = WGS84)

seaports_f4z <- over(seaports, FAFzones)$F4Z

seaports <- seaports@data %>% 
  tbl_df() %>%
  transmute(
    name = as.character(PORT),
    mode = 3,
    freight = EXPORTS + IMPORTS,
    F4Z = seaports_f4z
  ) %>%
 
  # FAF zone probability
  group_by(F4Z) %>% 
  mutate(prob = freight/sum(freight)) %>% 
  ungroup() %>%
  
  # don't bother keeping stuff we don't need
  filter(prob > 0) %>%  # empty ports
  select(name, prob, mode, F4Z) 

# Airports
airports <- readShapePoints("./data_raw/shapefiles/ntad/airports.shp",
                            proj4string = WGS84)

# air freight statistics
airfreight <- read.csv("./data_raw/shapefiles/ntad/2006-2010AirFreight.txt", 
                       sep = "#",  stringsAsFactors = FALSE) %>%
  mutate(Year = substr(Date, 0, 4), name = substr(Origin, 0,3)) %>%
  filter(Year == "2007") %>%  group_by(name) %>% 
  summarise(freight = sum(Total))

airports_f4z <- over(airports, FAFzones)$F4Z

airports <- airports@data %>%
  mutate(
    name = as.character(LOCID), 
    mode = 4, 
    F4Z = airports_f4z
  ) %>%
  select(name, F4Z, mode) %>% 
  
  # calculate probability of airport by FAF zone
  inner_join(., airfreight, by = "name")  %>%
  group_by(F4Z) %>%  
  mutate(prob = freight/sum(freight)) %>% ungroup(.) %>%
  
  # keep only what we need
  select(name, prob, mode, F4Z)


# Border crossings
crossings <- readShapePoints("./data_raw/shapefiles/ntad/border_x.shp",
                             proj4string = WGS84)

crossings_f4z <- over(crossings, FAFzones)$F4Z

crossings <- crossings@data %>% 
  mutate(
    name = paste("x", as.character(PortCode), sep = "_"),
    mode = 1,
    F4Z = crossings_f4z
    )  %>%
  filter(Trucks > 0) %>% 
  
  group_by(F4Z) %>%
  mutate(prob = Trucks / sum(Trucks)) %>% ungroup(.) %>%
  select(name, prob, mode, F4Z)

# Bind the three crossing types into a single lookup table. 
ienodes <- rbind_list(seaports, airports, crossings) %>%
  mutate(F4Z = as.character(F4Z)) %>%
  select(F4Z, mode, name, prob) %>%
  arrange(F4Z, mode)

write_feather(ienodes, "./data/simfiles/ie_nodes.feather")

