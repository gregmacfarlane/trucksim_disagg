# How many cores are available on your computer?
CORES = 24

# What year to simulate? Options: 2006:2013, 2015, 2020, 2025, 2030, 2035, 2040
SIMYEAR = 2012

# Do you want to do a small disaggregation? This will only model FAF flows that
# go to or from FAF Zone 373: Raleigh North Carolina.
SMALL = FALSE

# This is the final simulation file.
MASTER = population.xml.gz

SCRIPTDIR = R/simfiles
SIMULFDIR = data/simfiles

SCRIPTS  := $(wildcard $(SCRIPTDIR)/*.R)
SIMFILES := $(SCRIPTS:$(SCRIPTDIR)/%.R=$(SIMULFDIR)/%.csv)

all: $(MASTER)


$(MASTER): py/disaggregate_trucks.py
	@echo Simulating truck O and D
	@python $<

$(MASTER): $(SIMFILES)

# Each simulation table gets created by an R script with the same name in
# R/simfiles
$(SIMFILES): $(SIMULFDIR)/%.csv: $(SCRIPTDIR)/%.R
	@mkdir -p data/simfiles
	@echo making $@ from $<
	@Rscript $< $(CORES)

$(SIMULFDIR)/faf_trucks.csv: data/faf_data.Rdata

$(SIMULFDIR)/use_table.csv: $(SIMULFDIR)/make_table.csv

$(SIMULFDIR)/make_table.csv: data/cbp_data.Rdata

$(SIMULFDIR)/make_table.csv: data_raw/cfs_pums.csv

# Read cleaned source data into R.
data/faf_data.Rdata: data_raw/faf4_data.csv R/prep_FAF.R
	@echo Reading FAF data into R
	@Rscript R/prep_FAF.R $(SIMYEAR) $(SMALL)

data/cbp_data.Rdata: data_raw/cbp12co.txt R/prep_CBP.R
	@echo Reading CBP data into R
	@Rscript R/prep_CBP.R

data/gdp_output.rds: R/prep_BEA.R data_raw/gdp_output.csv
	@echo Reading BEA data into R
	@Rscript R/prep_BEA.R

R/prep_FAF.R: data/gdp_output.rds

# Download and unzip source data from FHWA and Census
data_raw/cbp12co.txt: data_raw/cbp12co.zip
	@echo extracting County Business Patterns source data
	@unzip $< -d data_raw
	@touch $@

data_raw/cbp12co.zip:
	@echo Downloading County Business Patterns employment data
	@wget -O $@ ftp://ftp.census.gov/econ2012/CBP_CSV/cbp12co.zip

data_raw/faf4_data.csv:
	@echo downloading FAF 4.0 data table
	@wget -O $@ http://www.rita.dot.gov/bts/sites/rita.dot.gov.bts/files/AdditionalAttachmentFiles/FAF4_0%20data.csv
	@touch $@

data_raw/cfs_pums.csv: data_raw/cfs_pums.zip
	@echo extracting CFS PUMS file
	@unzip $< -d data_raw
	@mv data_raw/cfs_2012_pumf_csv.txt $@
	@touch $@

data_raw/cfs_pums.zip:
	@echo downloading CSF PUMS file
	@wget -O $@ http://www.census.gov/econ/cfs/2012/cfs_2012_pumf_csv.zip


# Helper calls
menu:
	@ echo + ==============================
	@ echo + .......GNU Make menu..........
	@ echo + all: .... build population.xml
	@ echo + sourcedata: .. download source
	@ echo + simfiles: .... prepare for sim
	@ echo + newsim: .. prep for new disagg
	@ echo + clean: ....... delete simfiles
	@ echo + realclean: .... delete sim+src
	@ echo + ==============================

clean:
	@rm -rf data/simfiles/*

realclean: clean
	@rm -f data/cbp_data.Rdata
	@rm -f data/faf_data.Rdata

newsim:
	@rm -f data/simfiles/faf_trucks.csv
	@rm -f data/faf_data.Rdata
	@echo Ready to disaggregate FAF
