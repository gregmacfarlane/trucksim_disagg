# How many cores are available on your computer?
CORES = 24

# What year to simulate?
SIMYEAR = 2007

# Do you want to do a small disaggregation? This will only model FAF flows that
# go to or from FAF Zone 373: Raleigh North Carolina.
SMALL = TRUE


# This is the final simulation file.
MASTER = population.xml.gz

all: $(MASTER)


$(MASTER): simfiles py/disaggregate_trucks.py
	@echo Simulating truck O and D
	@python -m cProfile -o complete_run.prof py/disaggregate_trucks.py	

# Create simulation files
simfiles: data/cbp_data.Rdata data/faf_trucks.csv R/size_terms.R
	@echo creating lookup tables for simulation
	@Rscript R/size_terms.R

# Split flows into trucks
data/faf_trucks.csv: data/faf_data.Rdata R/flows_to_trucks.R
	@echo Converting FAF flows into trucks.
	@Rscript R/flows_to_trucks.R $(CORES)

# Read cleaned source data into R.
sourcedata: data/faf_data.Rdata data/cbp_data.Rdata


data/faf_data.Rdata: data_raw/faf35_data.csv R/prep_FAF.R
	@Rscript R/prep_FAF.R $(SIMYEAR) $(SMALL)

data/cbp_data.Rdata: data_raw/Cbp07co.txt R/prep_CBP.R
	@Rscript R/prep_CBP.R

# Download and unzip source data from FHWA and Census
data_raw/Cbp07co.txt: data_raw/cbp07co.zip
	@echo extracting County Business Patterns source data
	@unzip $< -d $(@D) 
	@touch $@

data_raw/cbp07co.zip:
	@echo Downloading County Business Patterns source data 
	@wget -O $@ ftp://ftp.census.gov/econ2007/CBP_CSV/cbp07co.zip

data_raw/faf35_data.csv: data_raw/faf3_5.zip
	@echo extracting FAF 3.5 region-to-region database
	@unzip $< -d $(@D)
	@touch $@

data_raw/faf3_5.zip:
	@echo Downloading FAF 3.5 region-to-region database
	@wget -O $@ http://www.ops.fhwa.dot.gov/freight/freight_analysis/faf/faf3/faf3_5.zip


menu:
	@ echo + ==============================
	@ echo + .......GNU Make menu..........
	@ echo + all: .... build population.xml
	@ echo + sourcedata: .. download source
	@ echo + simfiles: .... prepare for sim
	@ echo + clean: ...... delete aux files
	@ echo + realclean: . delete all output
	@ echo + ==============================
	
