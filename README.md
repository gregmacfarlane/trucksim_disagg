# trucksim_disagg
A disaggregation of the FAF3 freight flows based on economic data.

This project contains scripts to disaggregate the Freight Analysis Framework from aggregate flows between FAF regions to discrete numbers of trucks traveling between specific geographic points. The output of this code is a **plans** file that MATSim can read in a simulation.

This simulation is operated by a `makefile`. A user can execute the disaggregation process by calling 

    make all

On a command line. If you are on Windows computer, you may need to install `GNU Make` manually. 

#### Data Preparation
`make sourcedata` will if necessary, download the FAF 3.5 data and the CBP data directly from the FHWA/Census Bureau servers, extract the compressed data tables, and clean them for further analysis.

There are two variables in the `makefile` that the user should set:

  - `SIMYEAR` the FAF data or forecast year that the software will disaggregate.
  - `SMALL` boolean; `TRUE` will only disaggregate trucks going to or coming from Raleigh, North Carolina. `FALSE` will disaggregate the entire FAF dataset.


#### Discrete Trucks	
`R/simdata/faf_trucks.R` converts the FAF commodity flows to a number of individual trucks, including empty trucks, flowing between FAF regions using the methodology and factors supplied in Chapter 3 of the FAF documentation. To make this step run faster, we use the `parallel` library for R; the user should set the `CORES` variable to the number of cores they have available.

As a note, the `parallel` library is not available for Windows. We have not tested if setting cores to `1` will allow the code to execute on a Windows computer.

#### Disaggregate Truck ODs
The trucks in the simulation choose a random point within their origin or destination zone. `make simdata` generates the probability tables for this process. The probability of choosing a county from within an origin FAF Zone, for example, is based on economic information from the CBP (which shows where different industries are located) and the CFS (which shows which industries create commodities. Destination counties are based on  and these tables in addition to Bureau of Labor Statistics input-output tables (which show which industries ship to which other industries); goods destined for consumers are based on county-level employment.

Imports and exports are also assigned to port, airport, or border crossing nodes as appropriate.

Once the probability tables are available, `py/disaggregate_trucks.py` selects the random origins and destinations and writes the plans file. The simulation draws a random departure time for each truck, but only writes plans for trucks that depart in the first week of the simulation.

### Use
This software is distributed without license or claim. We request that applications and derivative work cite this as:

> Macfarlane, G. and Donnelly, R. (2014). A national simulation of freight truck flows.

Contributions, improvements, and suggestions are welcome. You may use the `issues` features of GitHub or submit your own pull requests.
