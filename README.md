# trucksim_disagg
A disaggregation of the FAF3 freight flows based on economic data.

This project contains scripts to disaggregate the Freight Analysis Framework from aggregate flows between FAF regions to discrete numbers of trucks traveling between specific geographic points. The output of this code is a **plans** file that MATSim can read in a simulation.

A user can run all steps sequentially sequentially with the root directory shell script,

    bash disaggregate_faf.sh


#### Data Preparation
`R/data_prep.R` reads the source Freight Analysis Framework (FAF) and County Business Patterns (CPB) data, and saves cleaned versions as `.Rdata` binary files. The script takes two additional command line arguments: the desired simulation year, and whether to make a `small` simulation for debugging. For instance, to build a 2007 simulation with the complete FAF, run

    Rscript R/data_prep.R 2007 FALSE

Changing the year will read from a different column of the FAF source data, but underlying economic patterns (make and use coefficients, industry distribution) are fixed to 2007 CBP and Commodity Flow Survey data. The smaller dataset created if `TRUE` contains all trucks with an origin or destination in FAF zone `373`, or Raleigh North Carolina.

*Prior to running this script, the user should unzip `data_raw/faf3_5.zip` to get the FAF source data as a `csv` file.*

#### Discrete Trucks	
`R/flows_to_trucks.R` converts the FAF commodity flows to a number of individual trucks, including empty trucks, using the methodology and factors supplied in Chapter 3 of the FAF documentation. To make this step run faster, we use the `parallel` library for R; the user should supply the number of available cores with this call,

    Rscript R/flows_to_trucks.R 4

As a note, the `parallel` library is not available for Windows. We have not tested if setting cores to `1` will allow the code to execute on a Windows computer.

#### Disaggregate Truck ODs
The trucks in the simulation choose a random point within their origin or destination zone. `R/size_terms.R` generates the probability tables for this process. The probability of choosing a county from within an origin FAF Zone, for example, is based on economic information from the CBP (which shows where different industries are located) and the CFS (which shows which industries create commodities. Destination counties are based on  and these tables in addition to Bureau of Labor Statistics input-output tables (which show which industries ship to which other industries); goods destined for consumers are based on county-level employment.

Imports and exports are also assigned to port, airport, or border crossing nodes as appropriate. As before, the number of desired cores should be supplied.
		
    Rscript R/size_terms.R

Once the probability tables are available, `py/disaggregate_trucks.py` selects the random origins and destinations and writes the plans file. As called from the `disaggregate_faf.sh`, this will write a `cProfile` metrics file.

    python -m cProfile -o complete_run.prof py/disaggregate_trucks.py

This can be used in [Snakeviz]() or other software to examine the simulation performance.


### Use
This software is distributed without license or claim. We request that applications and derivative work cite this as:

> Macfarlane, G. and Donnelly, R. (2014). A national simulation of freight truck flows.

Contributions, improvements, and suggestions are welcome. You may use the `issues` features of BitBucket or submit your own pull requests.
