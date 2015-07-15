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
  cat("Using default year 2007\n")
  year <- 2007
}

if(is.na(small)){
	small <- TRUE
}

if(small){
	cat("creating small FAF dataset (only Raleigh)")
}

years <- c(2006:2013, 2015, 2020, 2025, 2030, 2035, 2040)
if(!(year %in% years)){ stop("Please select a valid year") }

# Read in the data from the original csv, remove unneeded years and fields,
# and save as an R binary file.
cat("Reading original FAF data for ", year, ":\n")
FAF <- read_csv(
  "data_raw/faf35_data.csv", 
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
  print(  "Using smaller data frame")
  FAF <- FAF %>%
    filter(dms_orig == "373" | dms_dest == "373")
}


# cleanup
FAF <- FAF %>%
  mutate(
    sctg = sprintf("%02d", sctg2),
    id = as.character(rownames(.)),
    dms_orig = as.character(dms_orig),
    dms_dest = as.character(dms_dest)
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

# If historical data for the simulation year is available, then use that to
# grow 2007 data to the appropriate year. All commodities use the GDP Gross
# output total, except for oil and gas industries. These draw from the
# industry-level gross output for "Oil and Gas", hopefully accounting for
# some of the growth in shale gas extraction between 2007 and 2015.
if(year < 2014){

  # read in historical gdp data
  gdp <- readRDS("data/gdp_output.rds") %>%
    filter(data_year == year)

  # gdp figures are indexed to 2007, so keep these columns
  faf_vars <- paste(c('value', 'tons'), "2007", sep = "_")

  FAF <- FAF %>%
    select_(.dots = c(keep_vars, faf_vars)) %>%
    left_join(gdp) %>%

    # scale value and tons by gdp factor
    mutate(
      value = value_2007 * gdp,
      tons = tons_2007 * gdp
    ) %>%
    select(-value_2007, -tons_2007, -data_year, -industry, -gdp)

} else {  # for future years, just use the FAF forecasts.

  faf_vars <- paste(c('value', 'tons'), year, sep = "_")
  FAF <- FAF %>%
    select_(.dots = c(keep_vars, faf_vars)) %>%
    # give generic name
    rename_(
      "value" = faf_vars[1],
      "tons"  = faf_vars[2]
    )
}

# TODO: Impute missing flows
cat("Saving to R binary format\n")
save(FAF, file = "data/faf_data.Rdata")
