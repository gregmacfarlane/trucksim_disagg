# Data Preparation
# ==============================================================


# FAF Data -----
# This script creates an R binary file from the FAF source data 
# in the year specified by the user. Requires the `dplyr` package.
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(reshape2))

# The user should enter the year with the call; the year must be a valid year
# either observed of forecasted values.
args <-commandArgs(TRUE)
year <- args[1]
small <- args[2]
if(is.na(year)){
  cat("Using default year 2007\n")
  year <- 2007
}

years <- c(2007, 2011, 2015, 2020, 2025, 2030, 2035, 2040)
if(!(year %in% years)){ stop("Please select a valid year") }

# Read in the data from the original csv, remove unneeded years and fields,
# and save as an R binary file.
cat("Reading original FAF data for ", year, ":\n")
FAF <- read.csv("../data_raw/faf35_data.csv")
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
  filter(time == year, dms_mode == 1) %>% # chosen year and trucks only.
  select(-sctg2, -tmiles) 

# Create a simulation from just RDU for testing
if(small == "True"){
  test <- FAF %>%
    filter(dms_orig == "373" | dms_dest == "373")
}

# TODO: Impute missing flows
cat("Saving to R binary format\n")
save(FAF, file = "../data/faf_data.Rdata")

# CBP DATA -----
# Read in the data from the CBP file, impute missing variables, and save as
# binary format
cat("Cleaning CBP data\n")
CBP <- read.csv("../data_raw/Cbp07co.txt", stringsAsFactors = FALSE)
ranges <- read.csv("../data_raw/cbp_missingcodes.csv", sep="&", 
                   colClasses = c("character", "character", "numeric"))
CBP <- CBP %>% left_join(., ranges, by = "empflag") %>%
  mutate(emp = ifelse(is.na(empimp), emp, empimp),
         GEOID = paste(sprintf("%02d", fipstate), # sprintf to pad leading zeros
                       sprintf("%03d", fipscty), sep="")) %>%
  filter(fipscty != "999") %>%
  mutate(naics = gsub("[[:punct:]]", "", naics)) %>%
  select(naics, emp, GEOID)

# There are some naics codes that don't map very nearly into other categories
problemnaics <- c("44", "441", "445")
breakouts <- CBP %>% filter(naics %in% problemnaics) %>%
  mutate(naics = paste("x", naics, sep = "")) %>%
  dcast(., formula = GEOID ~ naics, value.var = "emp", fill = 0) %>%
  mutate(naics = "44",  emp = x44 - x441 - x445, 
         emp = ifelse(emp < 0, 0, emp)) %>% select(GEOID, naics, emp)  

CBP <- rbind_list(CBP %>% filter(naics != "44"), breakouts)

save(CBP, file = "../data/cbp_data.Rdata")

