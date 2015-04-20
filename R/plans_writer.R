# Write Truck OD to file
# ==============================================================
# This script takes the trucks that we assigned origins and destinations to
# and creates a planset that MATSIM can read.
suppressPackageStartupMessages(require(dplyr))
suppressPackageStartupMessages(require(parallel))
suppressPackageStartupMessages(require(methods))

set.seed(5)
# The user should request the number of cores with the call.
args <-commandArgs(TRUE)
cores <- args[1]
if(is.na(cores)){stop("please submit the number of processes to use:
rscript PlanWriter.R 4")}
if(cores > detectCores()){stop("Requested processes exceeds available cores.") }



# FUNCTION TO DETERMINE DEPARTURE DATE -----------------------------------------
# MATSim requires a start or end time for activities, so we need to determine a
# day that the truck leaves. On top of this, we have a two-week simulation, 
# but the flow data is annual; we only want to keep records with a departure date
# in the first three days. Day 1 is to load the network, Day 2 is to give 
# long-distance trucks into position, and Day 3 is for analysis.
getDepartureDay <- function(df){
  splittable <- df %>% ungroup() %>%
    group_by(id)  %>%
    do( data.frame(olat = rep(.$olat, .$trucks), olong = rep(.$olong, .$trucks),
                   dlat = rep(.$dlat, .$trucks), dlong = rep(.$dlong, .$trucks),
                   sctg = rep(.$sctg, .$trucks), type = rep(.$type, .$trucks), 
                   origin = rep(.$origin, .$trucks), 
                   destination = rep(.$destination, .$trucks),
                   day = sample(0:364, .$trucks, replace = TRUE))) %>%
    filter(day <= 3)
  return(splittable)
}

# FUNCTION TO DETERMINE DEPARTURE TIME -----------------------------------------
# We assume that trucks, for the most part, depart during business hours. We
# therefore use a bimodal normal distribution with peaks early and late in the
# the work day, a bit of a lag in the middle of the day, and less at night time.
# if the distribution assigns a time outside of 24 hours, we resample it using
# a uniform distribution. These parameters are just guesses, but in a later 
# version we could estimate them from real data.
getDepartureTime <- function(n, cpct, mu1, mu2, sig1, sig2){
  y0 <- rnorm(n, mean = mu1, sd = sig1)
  y1 <- rnorm(n, mean = mu2, sd = sig2)
  
  flag <- rbinom(n, size = 1, prob = cpct)
  y <- y0*(1-flag) + y1*flag
  y <- ifelse(y < 0, runif(n, 0,6), y)
  y <- ifelse(y >24, runif(n, 18, 24), y)
  y
}

# FUNCTION TO CREATE A NEW XML NODE --------------------------------------------
# Every truck in the data will be handled like a "person" in our MATSim simulation,
# so they get a person node. This function returns a node
addPersonXMLString <- function(dfrow){
  personplan <- paste(
'  <person id="', dfrow$id, '">\n',
'      <plan selected="yes">\n',
'        <act type="dummy" x="', dfrow$olong, '" y="', dfrow$olat, 
              '" end_time="', dfrow$departure, '" />\n',
'        <leg mode="car"/>\n',
'        <act type="dummy" x="', dfrow$dlong, '" y="', dfrow$dlat, '" />\n',
'      </plan>\n',
'   </person>\n', sep="")
 return(personplan)
}

# MAIN PROGRAM =================================================================
cat("Reading distributed truck flows\n")
load("./data/disaggregated_trucks.Rdata")
FAF <- FAF %>% mutate(id = seq(1:nrow(FAF))) %>% 
  arrange(id) %>% filter(trucks > 0) 

# Get individual trucks with days of departure, trimmed to trucks that depart 
# in the first three days. This is smaller than we originally wanted to have,
# but probably still reasonable to get the effect of long-distance trucks 
# crossing the country. We'll need to come back to this when we build the whole
# thing.

FAF <- rbind_all(mclapply(split(FAF, FAF$sctg), mc.cores = cores,
                                           function(x) getDepartureDay(x)))
FAF <- FAF %>%
  mutate(departure = round((getDepartureTime(nrow(FAF), 0.5, 9, 16, 2.5, 2.5) + 
                           24 * FAF$day) * 3600, 0),
         id = seq(1:nrow(FAF))) %>%
  sample_frac(0.03) # sample 3% of the records

save(FAF, file = "./data/truck_plans.Rdata")
cat("Writing to XML\n")
# Create xml representation of truck plans
suppressMessages(plans <- unlist(mclapply(split(FAF, FAF$sctg), mc.cores = cores,
                                     function(x) addPersonXMLString(x))))

header <- paste(
'<?xml version="1.0" encoding="utf-8"?>',
'<!DOCTYPE population SYSTEM "http://www.matsim.org/files/dtd/population_v5.dtd">\n',
'<population>\n', sep = "\n")

tail <- "</population>"

cat(header, plans, tail, file = "./plans.xml")

