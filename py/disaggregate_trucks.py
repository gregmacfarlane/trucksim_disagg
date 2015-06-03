__author__ = 'Greg'

import truckplans as tp
import pandas as pd
import lxml.etree as et
import gzip
import numpy as np


# Read in the I/O tables and convert them to dictionaries.
MAKE_DICT = tp.recur_dictify(pd.read_csv(
    "./data/make_table.csv",
    dtype={'sctg': np.str, 'F3Z': np.str, 'name': np.str}
))

USE_DICT = tp.recur_dictify(pd.read_csv(
    "./data/use_table.csv",
    dtype={'sctg': np.str, 'F3Z': np.str, 'name': np.str}
))

# To handle Alaska shipments appropriately, we need to have a list of
# states/faf zones where the trucks will either drive down the coast to
# Washington or in front of the Rockies to Montana
# western states (Washington route): [CA, OR, WA, NV, AZ, ID, UT]
west_coast_states = ['06', '41', '53', '32', '04', '16', '49']
west_coast_f3z = range(61, 69) + range(411, 419) + range(531, 539) + \
                 range(321, 329) + range(41, 49) + [160] + range(491, 499)

# Exports/Imports are directed to airports, seaports, or highway border
# crossings in the FAF zone.
#EXIM_DICT =


# Create the element tree container
population = et.Element("population")
pop_file = et.ElementTree(population)

# read in the split trucks file with numbers of trucks going from i to j.
faf_trucks = pd.read_csv("./data/faf_trucks.csv",
                         dtype={'dms_orig': np.str, 'dms_dest': np.str,
                                'sctg': np.str, 'trucks': np.int})
faf_trucks = faf_trucks.head(5)

# create the appropriate numbers of trucks for each row.
for index, row in faf_trucks.iterrows():
    [tp.TruckPlan(row['dms_orig'], row['dms_dest'], row['sctg'])
     for _ in range(row['trucks'])]

with gzip.open('population.xml.gz', 'w', compresslevel=0) as f:
    f.write("""<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE population SYSTEM "http://www.matsim.org/files/dtd/population_v5.dtd">
""")
    pop_file.write(f, pretty_print=True)