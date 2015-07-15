#' Convert a zone-to-zone record of trucks into a trip table.
#' 
#' @param trucks A data frame of truck plans, from TAZ i to TAZ j. Also includes
#'   truck class.
#' @param taz A vector containing all i.
#' 
#' @return a data frame with i, j, and volume by class.
#' 
#' @import dplyr
#' @import tidyr
#' 
sum_to_taz <- function(trucks){
  
  trucks %>% 
    
    # determine if truck is MU or SU
    mutate(
      class = ifelse(grepl("SU", type), "SU", "MU")
    ) %>%
    
    # Add up to i, j, by class
    group_by(origin, destination, class) %>%
    
    summarise(n = n()) %>%
    
    # spread across types
    spread(class, n, fill = 0)
  
}

# main code
library(dplyr)
library(tidyr)
library(readr)

trucks <- read_csv("population.csv")

truck_table <- sum_to_taz(trucks)

write_csv(truck_table, "trip_table.csv")
