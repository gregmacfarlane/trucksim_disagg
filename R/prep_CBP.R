# CBP DATA -----
library(dplyr, warn.conflicts = FALSE)
library(reshape2)
library(readr)

# Read in the data from the CBP file, impute missing variables, and save as
# binary format
cat("Cleaning CBP data\n")
CBP <- read_csv("data_raw/cbp12co.txt") %>%
  mutate(GEOID = paste0(fipstate, fipscty))

ranges <- read.csv("data_raw/cbp_missingcodes.csv", sep="&",
                   colClasses = c("character", "character", "numeric"))
CBP <- CBP %>% left_join(., ranges, by = "empflag") %>%
  mutate(emp = ifelse(is.na(empimp), emp, empimp)) %>%
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

save(CBP, file = "data/cbp_data.Rdata")
