__author__ = 'Greg'

import truckplans as tp
import pandas as pd
import lxml.etree as et
import gzip
import numpy as np
def pick_ienode(dict_table, mode, zone):
    """
    :param dict_table: the dictionary table of import and export nodes.
    :param mode: the import or export mode, indicating what facility (port,
      airport, seaport) should be chosen.
    :param zone: the FAF zone on the import or export end.
    :return: the airport, seaport, or highway crossing
    """
    ienode = np.random.choice(
        dict_table[zone][mode].keys(),
        p=dict_table[zone][mode].values())
    return ienode


        # get the origin points ----
        if self.inmode in ['1', '3', '4']:  # imported?
            try:
                # If a valid import node exists, use it
                self.origin = pick_ienode(EXIM_DICT, self.inmode, self.origin)
            except KeyError:
                # If it doesn't, just assign like normal
                self.get_origin()
        else:
            self.get_origin()

        # get the destination points ----
        if self.outmode in ['1', '3', '4']:  # imported?
            try:
                # If a valid import node exists, use it
                self.destination = pick_ienode(EXIM_DICT,  self.outmode,
                                               self.destination)
            except KeyError:
                # If it doesn't, just assign like normal
                self.get_destination()
        else:
            self.get_destination()

        self.write_plan()

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
EXIM_DICT = recur_dictify(pd.read_csv(
    "./data/ienodes.csv",
    dtype={'F3Z': np.str, 'mode': np.str, 'name': np.str}
))


# Create the element tree container
population = et.Element("population")
pop_file = et.ElementTree(population)

# read in the split trucks file with numbers of trucks going from i to j.
faf_trucks = pd.read_csv("./data/faf_trucks.csv",
                         dtype={'dms_orig': np.str, 'dms_dest': np.str,
                                'sctg': np.str, 'trucks': np.int,
                                'fr_inmode': np.str, 'fr_outmode': np.str})
faf_trucks = faf_trucks[faf_trucks['fr_inmode'] == '1'][:5]

# create the appropriate numbers of trucks for each row.
for index, row in faf_trucks.iterrows():
    [TruckPlan(row['dms_orig'], row['dms_dest'], row['sctg'],
                  row['fr_inmode'], row['fr_outmode']),
     for _ in range(row['trucks'])]

with gzip.open('population.xml.gz', 'w', compresslevel=0) as f:
    f.write("""<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE population SYSTEM "http://www.matsim.org/files/dtd/population_v5.dtd">
""")
    pop_file.write(f, pretty_print=True)