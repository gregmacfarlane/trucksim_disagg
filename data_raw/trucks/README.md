# FAF Payload Equivalency Factors
This folder contains three tables distributed with the FAF version 3 traffic analysis [methodology](http://faf.ornl.gov/fafweb/Data/Freight_Traffic_Analysis/chap3.htm), and edited for use in computer programs.
- `truckallocation.csv` The proportion of truck configuration by distance, Table 3.3
- `emptytrucks.csv` The percent of empty trucks based on truck type and configuration, Table 3.5
- `truckequivalence.csv` The volume of goods in each commodity class carried by different truck types and configurations, [Appendix A](http://faf.ornl.gov/fafweb/Data/Freight_Traffic_Analysis/appendixa.htm).

The documentation contains an example of how to apply these factors to convert FAF commodity flows to truck volumes; `R/faf_trucks.R` contains an implementation of this methodology.
