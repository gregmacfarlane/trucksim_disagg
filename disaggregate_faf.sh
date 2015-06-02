#!/bin/bash

echo "Building plans from source data"
echo "======================================"
# This script builds the MATSim plan set from the FAF regional flows and other
# input files. All steps take about a day and a half to run on my computer using
# 24 cores. You can adjust the number of cores by setting the variable below.
CORES=24
# I believe that these scripts will run on Windows, but not in parallel.
# Additionally, there may be an error in the scripts on the `library(parallel)`
# call, because this library is not available on Windows.

# 1 ---------------------------
echo 
echo "1/3 Reading FAF source data into binary file"
echo "--------------------------------------"
# This calls an R script that reads the FAF csv file and turns it into a binary
# RData file.

# @param year the year for which the faf should be disaggregated.
# @param small boolean indicating if the faf should only disaggregate trucks
# bound for Raleigh, NC (for debugging with minimal sample)

Rscript R/data_prep.R 2011 TRUE

# 2 ---------------------------
echo 
echo "2/3 Splitting freight flows into trucks"
echo "--------------------------------------"
# This calls an R script that converts the region-to-region flows into a
# discrete number of trucks, including their vehicle type and whether they are
# full or empty.

# @param cores the number of processing cores available to R.
Rscript R/flows_to_trucks.R $CORES

# 3 ---------------------------
echo 
echo "3/3 Allocating trucks to counties"
echo "--------------------------------------"
# This R script converts BEA IO files and NTAD Import/Export information into
# size terms for counties and ports.
Rscript R/size_terms.R

# This python script directs the individual trucks to counties or ports based on
# county-level economic data and economy-wide IO tables.
python py/truck_plans.py

