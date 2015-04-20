# trucksim_disagg
A disaggregation of the FAF3 freight flows based on economic data.


FAF Disaggregation
-------------------------------------------------

This project contains scripts to disaggregate the Freight Analysis Framework from aggregate flows between FAF regions to discrete numbers of trucks traveling between specific geographic points. 

The output of this code is a  **plans** file that MATSim can read in a simulation.

There are four primary steps in this process, all of which are stored in the `Disaggregation` folder. All steps can be run sequentially with the `1_Dissagregator.sh` bash script in the root folder. This script is hard-coded to run a 2007 simulation on 24 cores. To simulate a different year or use a different number of cores, edit either the root script or call the individual R scripts manually.

All steps here take about 18 hours to run on my computer.

#### Data Preparation
`DataPrep.R` reads the source Freight Analysis Framework (FAF) and County Business Patterns (CPB) data, and saves cleaned versions as `.Rdata` binary files. The script takes an additional command line argument, which is the desired simulation year. For instance, to build a 2007 simulation, enter

    Rscript Disaggregation/DataPrep.R 2007

Changing the year will read from a different column of the FAF source data, but underlying economic patterns (make and use coefficients, industry distribution) are fixed to 2007 CBP and Commodity Flow Survey data. *Prior to running this script, the user should unzip `faf3_5.zip` to get the FAF source data as a `csv` file.*

#### Discrete Trucks	
`Flows2Trucks` converts the FAF commodity flows to a number of necessary trucks, including empty trucks, using the methodology and factors supplied in Chapter 3 of the FAF documentation. The number of desired cores should be supplied with this call,

    Rscript Disaggregation/Flows2Trucks.R 4

#### Split Trucks
`SplitTrucks.R` assigns the individual trucks to origin and destination points based on economic information from the CBP (which shows where different industries are located), the CFS (which shows which industries create commodities) and Bureau of Labor Statistics input-output tables (which show which industries ship to which other industries). 

Imports and exports are also assigned to port, airport, or border crossing nodes as appropriate. As before, the number of desired cores should be supplied.
		
    Rscript Disaggregation/SplitTrucks.R 4

#### Plan Writer
`PlanWriter.R` takes the trucks that have been assigned to origins and destinations and writes a MATSim plan set XML file.

    Rscript Disaggregation/PlanWriter.R 4

To compress this data for quick use with MATSim, run

    gzip Simulation/inputs/plans.xml



### Use
This software is distributed without license or claim. We request that applications and derivative work cite this as:

> Macfarlane, G. and Donnelly, R. (2014). A national simulation of freight truck flows.

Contributions, improvements, and suggestions are welcome. You may use the `issues` features of BitBucket or submit your own pull requests.
