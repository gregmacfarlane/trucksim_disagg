# Prep the bureau of economic analysis gdp data by commodity
library(dplyr)
library(readr)
library(tidyr)

gdp <- read_csv(
  "data_raw/gdp_output.csv",
  skip = 4
  ) %>%
  
  # fix imported names
  mutate(
    Line = as.numeric(Line),
    industry = `[EMPTY]`
  ) %>%
  
  # only keep all industries and oil/gas for now.
  filter(Line %in% c(1, 7)) %>%
  mutate(industry = c("other", "oil")) %>%
  gather(data_year, gdp, `2006`:`2013`, convert = TRUE) %>%
  select(industry, data_year, gdp) %>%
  
  # remove oil from other industries
  spread(industry, gdp) %>%
  mutate(other = other - oil) %>%
  gather(industry, gdp, oil:other)
 
gdp <- gdp %>%
  # calculate percent change from 2007
  group_by(industry) %>%
  arrange(data_year) %>%
  mutate(
    gdp = as.numeric(gdp),
    gdp = gdp / gdp[2]
  )

# join sctg codes
sctg <- data_frame(
  sctg = sprintf("%02d", c(1:41, 43, 99)),
  industry = ifelse(sctg %in% c("16", "17", "18", "19"), "oil", "other")
)

gdp <- gdp %>% 
  inner_join(sctg)

saveRDS(gdp, file = "data/gdp_output.rds")
