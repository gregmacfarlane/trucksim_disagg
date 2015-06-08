library(dplyr, warn.conflicts = FALSE)
suppressMessages(require(maptools))

# Imports and Exports ----------------------------------------------------------
cat("   Determining import and export nodes\n")
# For imports and exports,  we are told the initial or final FAF zone in the 
# United States. Because there are a limited number of border crossings, airports,
# or ports, we can determine the probability that a truck uses each port as a 
# function of the departure mode and the volume of freight we observe passing 
# through the port. 

# First, we load the shapefiles for ports, airports, and border crossings and
# determine which FAF zone they are located in.
WGS84 <- CRS("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs +towgs84=0,0,0")
FAFzones <- readShapePoly("./data_raw/shapefiles/faf3zone.shp", 
                          proj4string = WGS84)

# Seaports
seaports <- readShapePoints("./data_raw/shapefiles/ntad/ports_major.shp",
                            proj4string = WGS84)

seaports <- seaports@data %>% 
  mutate(
    name = PORT, 
    mode = 3,
    freight = EXPORTS + IMPORTS,
    F3Z = over(seaports, FAFzones)$F3Z
  )  %>%
  
  # FAF zone probability
  group_by(F3Z) %>% 
  mutate(prob = freight/sum(freight)) %>% 
  ungroup(.) %>%
  
  # don't bother keeping stuff we don't need
  filter(prob > 0) %>%  # empty ports
  select(name, prob, mode, F3Z) 

# Airports
airports <- readShapePoints("./data_raw/shapefiles/ntad/airports.shp",
                            proj4string = WGS84)

# air freight statistics
airfreight <- read.csv("./data_raw/shapefiles/ntad/2006-2010AirFreight.txt", 
                       sep = "#",  stringsAsFactors = FALSE) %>%
  mutate(Year = substr(Date, 0, 4), name = substr(Origin, 0,3)) %>%
  filter(Year == "2007") %>%  group_by(name) %>% 
  summarise(freight = sum(Total))


airports <- airports@data %>%
  mutate(
    name = as.character(LOCID), 
    mode = 4, 
    F3Z = over(airports, FAFzones)$F3Z
  ) %>%
  select(name, F3Z, mode) %>% 
  
  # calculate probability of airport by FAF zone
  inner_join(., airfreight, by = "name")  %>%
  group_by(F3Z) %>%  
  mutate(prob = freight/sum(freight)) %>% ungroup(.) %>%
  
  # keep only what we need
  select(name, prob, mode, F3Z)


# Border crossings
crossings <- readShapePoints("./data_raw/shapefiles/ntad/border_x.shp",
                             proj4string = WGS84)

crossings <- crossings@data %>% 
  mutate(
    name = PortCode, mode = 1,
    F3Z = over(crossings, FAFzones)$F3Z
    )  %>%
  filter(Trucks > 0) %>% 
  
  group_by(F3Z) %>%
  mutate(prob = Trucks / sum(Trucks)) %>% ungroup(.) %>%
  select(name, prob, mode, F3Z)

# Bind the three crossing types into a single lookup table. 
ienodes <- rbind_list(seaports, airports, crossings) %>%
  mutate(F3Z = as.character(F3Z)) %>%
  select(F3Z, mode, name, prob) %>%
  arrange(F3Z, mode)

write.csv(ienodes, "./data/simfiles/ie_nodes.csv", row.names = FALSE)

