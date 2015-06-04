#' Retrieve data from the Census API
#' 
#' Returns Census data for the 2008-2013 5-year ACS aggregation for requested
#' variables at requested geographies.
#'
#' @param variables_to_get the variable name for the Census API call, 
#' defined at \url{http://api.census.gov/}
#' 
#' @param geoids a vector of FIPS codes; must be at least to the county (5-digit)
#' level, and can accept down to block groups (12-digit).
#'
#' @return a data_frame with each requested variable at each requested geography.
#' 
#' @export 
#' @import dplyr
#' @import httr
call_census_api <- function(variables_to_get, geoids) {
  
  # parse geoid
  split_geo <- function(geoid) {
    list(st = substr(geoid,1,2), 
         co = substr(geoid,3,5),
         tr = substr(geoid,6,9),
         bg = substr(geoid,10,12))
  } 
  
  call_api_once <- function(variables_to_get, geoid) {
    newgeo <- split_geo(geoid)
    st <- newgeo$st; co <- newgeo$co; tr <- newgeo$tr; bg <- newgeo$bg;
    
    # if using block groups
    if(bg != ""){
      url <- paste(
        "http://api.census.gov/data/2013/acs5?get=",
        paste(variables_to_get, collapse = ","),
        "&for=block+group:", bg,
        "&in=state:", st,
        "+county:", co,
        "+tract:", tr,
        "&key=1209214b319264ae3163b6d262dda4106e5c77f0",
        sep = ""
      )
    # if using tracts
    } else if(tr != ""){
      url <- paste(
        "http://api.census.gov/data/2013/acs5?get=",
        paste(variables_to_get, collapse = ","),
        "&for=tract:", tr,
        "&in=state:", st,
        "+county:", co,
        "&key=1209214b319264ae3163b6d262dda4106e5c77f0",
        sep = ""
      )
    # if using counties
    } else {
      url <- paste(
        "http://api.census.gov/data/2013/acs5?get=",
        paste(variables_to_get, collapse = ","),
        "&for=county:", co,
        "&in=state:", st,
        "&key=1209214b319264ae3163b6d262dda4106e5c77f0",
        sep = ""
      )
    }
    
    
    # Gives back a list of lists; first list has the headers
    response <- httr::content(httr::GET(url))
    header <- response[[1]]
    
    # Build data frame
    values <- do.call(rbind, response)
    nicified_response <- dplyr::data_frame(
       variable = as.numeric(values[, 1])[-1],
       geoid =  paste(newgeo$st, newgeo$co, 
                      values[-1, 4], sep = "")
    )
    
    names(nicified_response)[1] <- header[1]
    return(nicified_response)
  }
  
  # Call hit_api_once for each geoid to get
  all_vars <- dplyr::rbind_all(
    suppressWarnings(
    lapply(geoids, function(geoid) call_api_once(variables_to_get, geoid)) 
    )
  )
  
  # Keep geoid and variable columns (throw out others)
  col_indexes <- match(variables_to_get, names(all_vars))
  all_vars <- dplyr::select(all_vars, geoid, col_indexes)
  
  dplyr::tbl_df(all_vars)
}
