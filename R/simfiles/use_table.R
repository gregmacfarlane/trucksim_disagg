# Truck Attractions ------------------------------------------------------------
library(dplyr, warn.conflicts = FALSE)
library(tidyr)
library(httr)
library(readr)
library(XML)
library(foreign)
message("   Calculating truck attractions coefficients\n")
# In this section we determine the destination locations of our trucks based on
# national county business patterns (where industries are located),  and
# national IO tables (which industries buy stuff from other industries).
load("./data/cbp_data.Rdata")

# Read io use table ======
# query data from BEA API
year <- 2012
api_key <- "871EEC7A-11CB-4841-B062-3A66E6829522"

uri <- paste(
  "http://www.bea.gov/api/data/?&UserID=", api_key,
  "&method=GetData&DataSetName=InputOutput&Year=", year, 
  "&tableID=", 46, "&ResultFormat=xml", sep = "")
response <- httr::content(httr::GET(uri), type = "text/xml")

# collect into parse into a useable dataframe
use_data_xmllist <- getNodeSet(xmlParse(response), "//Results/Data")
use_data_list <- lapply(use_data_xmllist, function(x){
  data.frame(as.list(xmlAttrs(x)), stringsAsFactors = FALSE)
})

usetable <- rbind_all(use_data_list) %>%
  tbl_df() %>%
  select(make_naics = rowCode, use_naics = colcode, trade = DataValue) %>%
  mutate(trade = ifelse(as.numeric(trade) < 0, 0, as.numeric(trade))) %>%

  # The table contains the dollar value of goods sold to other industries,
  # Government, and to final users of different types. We only consider other
  # industries and consumers, which we 
  # will proxy by the total employment in a county (blank CBP NAICS code). Of
  # course, we do not want to double-count final use cases, so we filter them
  # out.
  mutate_each(funs(ifelse(. == "F010", "", .)), make_naics:use_naics) %>%
  filter(!(make_naics %in% c(
    "GFE" , "GSLE", "GSLG", "HS" , "ORE" , "Other" , "TOTII" , "TOTINDOUT" , 
    "TOTVA", "Used" , "V001" , "V002" , "V003")
  )) %>%
  filter(use_naics %in% c(make_naics, "")) %>%
  
  # many of the naics codes have notes identifying them for particular
  # sub-industries, such as `4A0` for "other retail." These details are 
  # not particularly important in this application, because trucks carrying
  # each commodity are distributed independently (counting employment in `441`
  # does not mean we can't distribute goods to `44` employees)
  mutate_each(funs(ifelse(. == "4A0", "44", .)), make_naics:use_naics) %>%
  mutate_each(funs(gsub("[^0-9]", "", .)), make_naics:use_naics)
  
  
  
# need to get proportion of commodities made by each industry from make table.
maketable <- readRDS("data/io/makecoefs.rds") %>%
  group_by(naics) %>%
  mutate(makecoef = value / sum(value)) %>%
  rename(make_naics = naics, production = value)
  
usetable <- usetable %>%
  # join information about commodity production by NAICS
  inner_join(maketable, by = "make_naics") %>%
  group_by(sctg, use_naics) %>%
  summarise(trade = sum(trade * makecoef)) %>%
  mutate(usecoef = trade / sum(trade)) %>%
  rename(naics = use_naics)

# save usetable for report
saveRDS(usetable, "data/io/usecoefs.rds")

# County-to-FAF lookup table =====
cnty2faf <- read.dbf("./data_raw/shapefiles/cnty2faf.dbf") %>%
  transmute(
    GEOID = as.character(ANSI_ST_CO),
    F4Z = as.character(F4Z)
  )
  

CountyDemand <- inner_join(CBP, usetable, by = "naics") %>%
  
  # employment in industry-commodity pair
  mutate(emp = emp * usecoef) %>%
  
  # employment using commodity, summed across industries within county
  group_by(GEOID, sctg) %>%
  summarise(emp = sum(emp)) %>% ungroup(.)  %>%
  
  # which FAF zone is the county in?
  left_join(., cnty2faf, by = "GEOID") %>%
  mutate(F4Z = as.character(F4Z)) %>%
  group_by(F4Z, sctg) %>%
  
  mutate(
    prob = emp/sum(emp),
    name = GEOID
  ) %>% ungroup(.) %>%
  
  # cleanup
  select(F4Z, sctg, name, prob) %>%
  arrange(F4Z, sctg) %>% tbl_df()

write.csv(CountyDemand, "./data/simfiles/use_table.csv", row.names = FALSE)
