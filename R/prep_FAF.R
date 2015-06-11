# Data Preparation
# ==============================================================


# FAF Data -----
# This script creates an R binary file from the FAF source data 
# in the year specified by the user. Requires the `dplyr` package.
library(dplyr, warn.conflicts = FALSE)
library(reshape2)

# The user should enter the year with the call; the year must be a valid year
# either observed of forecasted values.
args <-commandArgs(TRUE)
year <- args[1]
small <- args[2]
if(is.na(year)){
  cat("Using default year 2007\n")
  year <- 2007
}

if(is.na(small)){
	cat("creating small FAF dataset (only Raleigh)")
	small <- TRUE
}

years <- c(2007, 2011, 2015, 2020, 2025, 2030, 2035, 2040)
if(!(year %in% years)){ stop("Please select a valid year") }

# Read in the data from the original csv, remove unneeded years and fields,
# and save as an R binary file.
cat("Reading original FAF data for ", year, ":\n")
FAF <- read.csv("data_raw/faf35_data.csv")

# Create a simulation from just RDU for testing
if(small){
  print(  "Using smaller data frame")
  FAF <- FAF %>%
    filter(dms_orig == "373" | dms_dest == "373")
}

FAF <- FAF %>% 
  mutate(value_2011 = (value_2007 + value_2015)/2,
         tons_2011  = (tons_2007  + tons_2015)/2,
         tmiles_2011  = (tmiles_2007  + tmiles_2015)/2)
FAF <- reshape(FAF, dir = "long", varying = 10:ncol(FAF), 
               sep = "_") %>%
  mutate(sctg = sprintf("%02d", sctg2),
         id = as.character(id),
         dms_orig = as.character(dms_orig),
         dms_dest = as.character(dms_dest)) %>%
  #filter out trucks exclusively in Hawaii or Alaska Alaska is zone 20, and 
  # Hawaii is in two zones, 151 and 159.
  filter(!(dms_orig == "20" & dms_dest == "20")) %>% 
  filter(!(dms_orig %in% c("151", "159") & dms_dest %in% c("151", "159"))) %>% 
  
  filter(time == year, dms_mode == 1) %>% # chosen year and trucks only.
  select(-sctg2, -tmiles) 


# TODO: Impute missing flows
cat("Saving to R binary format\n")
save(FAF, file = "data/faf_data.Rdata")


