import pandas as pd
import numpy as np
import lxml.etree as et
import gzip
import itertools


def recur_dictify(frame):
    """
    h/t: http://stackoverflow.com/a/19900276/843419
    :param frame: a pandas data frame
    :return: a nested dictionary with the columns as the keys and the final one
    as the value. Best if the keys are arranged and sorted and there are no duplicates.
    """
    if len(frame.columns) == 1:
        if frame.values.size == 1: return frame.values[0][0]
        return frame.values.squeeze()
    grouped = frame.groupby(frame.columns[0])
    d = {k: recur_dictify(g.ix[:,1:]) for k,g in grouped}
    return d



def pick_county(dict, sctg, zone):
    """
    :param sctg: the commodity code for the truck's cargo
    :param dict: the appropriate lookup table
    :return: the O or D county FIPS code
    """
    # get the relevant county lookup table
    county = np.random.choice(
        dict[zone][sctg].keys(),
        p=dict[zone][sctg].values())
    return county


def get_start_day():
    """
    :return: a random day of the week. For now all days are the same,
    but we don't have to make it that way. We have a two-week simulation
    """
    return np.random.randint(1, 14)


def get_departure_time():
    """
    :return: a random time in the day, bimodally distributed.
    """
    y0 = np.random.normal(9, 2.5)
    y1 = np.random.normal(16, 2.5)
    flag = np.random.binomial(1, 0.5)
    y = y0 * (1 - flag) + y1 * flag
    if y < 0:
        # time cannot be less than midnight
        y = np.random.randint(0, 6 * 3600)
    elif y > 24 * 3600:
        # or greater than midnight
        y = np.random.randint(18 * 3600, 24 * 3600)
    else:
        y *= 3600
    return int(y)


class TruckPlan:
    """Critical information for the truck plan"""
    id_iter = itertools.count(1)

    def __init__(self, origin, destination, sctg):
        """

        :rtype : a truck plan
        """
        self.id = self.id_iter.next()
        self.origin = origin
        self.destination = destination
        self.sctg = sctg
        self.time = None

        # get the departure time
        self.get_time()

        # get the origin and destination counties
        self.get_origin()
        self.get_destination()

        self.write_plan()

    def display_plan(self):
        print "Origin: ", self.origin, "Destination", self.destination

    def get_origin(self):
        self.origin = pick_county(MAKE_DICT, self.sctg, self.origin)

    def get_destination(self):
        self.destination = pick_county(USE_DICT, self.sctg, self.destination)

    def get_time(self):
        self.time = get_start_day() * 3600 + get_departure_time()

    def write_plan(self):
        person = et.SubElement(population, "person",
                               attrib={'id': str(self.id)})
        plan = et.SubElement(person, "plan", attrib={'selected': "yes"})

        # write elements of plan
        et.SubElement(plan, "act", attrib={'type': "dummy",
                                           'facility': str(self.origin),
                                           'end_time': str(self.time)})
        et.SubElement(plan, "leg", attrib={'mode': "car"})
        et.SubElement(plan, "act", attrib={'type': "dummy",
                                           'facility': str(self.destination)})


# Read in the I/O tables and convert them to dictionaries.
MAKE_DICT = recur_dictify(pd.read_csv(
    "./data/make_table.csv",
    dtype={'sctg': np.str, 'F3Z': np.str, 'name': np.str}
))

USE_DICT = recur_dictify(pd.read_csv(
    "./data/use_table.csv",
    dtype={'sctg': np.str, 'F3Z': np.str, 'name': np.str}
))

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
    [TruckPlan(row['dms_orig'], row['dms_dest'], row['sctg'])
     for _ in range(row['trucks'])]


with gzip.open('population.xml.gz', 'w', compresslevel=0) as f:
    f.write("""<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE population SYSTEM "http://www.matsim.org/files/dtd/population_v5.dtd">
""")
    pop_file.write(f, pretty_print=True)
