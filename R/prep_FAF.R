# Data Preparation
# ==============================================================


# FAF Data -----
# This script creates an R binary file from the FAF source data
# in the year specified by the user. Requires the `dplyr` package.
library(dplyr, warn.conflicts = FALSE)
library(lazyeval)
library(readr)

# The user should enter the year with the call; the year must be a valid year
# either observed of forecasted values.
args <-commandArgs(TRUE)
year <- args[1]
small <- args[2]
if(is.na(year)){
  message("Using default year 2012\n")
  year <- 2012
}

if(is.na(small)){
	small <- TRUE
}

if(small){
	message("creating small FAF dataset (only Raleigh)")
}

years <- c(2012)
if(!(year %in% years)){ stop("Please select a valid year") }

# Read in the data from the original csv, remove unneeded years and fields,
# and save as an R binary file.
message("Reading original FAF data for ", year, ":\n")
FAF <- read_csv(
  "data_raw/faf4_data.csv", 
  col_types = list(
    fr_orig = col_character(),
    dms_orig = col_character(),
    dms_dest = col_character(),
    fr_dest = col_character(),
    fr_inmode = col_character(),
    fr_outmode = col_character(),
    sctg2 = col_numeric(),
    trade_type = col_numeric()
  )
) 

# Create a simulation from just RDU for testing
if(small){
  message("Using smaller data frame for RDU")
  FAF <- FAF %>%
    filter(dms_orig == "373" | dms_dest == "373")
}


# cleanup
FAF <- FAF %>%
  mutate(
    sctg = sprintf("%02d", sctg2),
    id = as.character(rownames(.))
  ) %>%
  # Filter out trucks exclusively in Hawaii or Alaska
  #   Alaska is zone 20, and
  #   Hawaii is in two zones, 151 and 159.
  filter(!(dms_orig == "20" & dms_dest == "20")) %>%
  filter(!(dms_orig %in% c("151", "159") & dms_dest %in% c("151", "159"))) %>%

  filter(dms_mode == "1") %>%   # trucks only.
  select(-sctg2)

# matrix core variables
keep_vars <- c(
  'id', 'sctg',
  'fr_orig', 'dms_orig', 'dms_dest', 'fr_dest', 'fr_inmode', 'fr_outmode',
  'trade_type'
)

if(year == 2012){
  
  # use 2012 data
  faf_vars <- paste(c('value', 'tons'), "2012", sep = "_")

  FAF <- FAF %>%
    select_(.dots = c(keep_vars, faf_vars)) %>%
    rename(
      value = value_2012,
      tons = tons_2012
    )

} else {  # other years unavailable
  
  stop("Only 2012 is available from FAF 4.0")
  
}

# TODO: Impute missing flows
message("Saving to R binary format\n")
save(FAF, file = "data/faf_data.Rdata")
