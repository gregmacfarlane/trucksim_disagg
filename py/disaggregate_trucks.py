__author__ = 'Greg'

import pandas as pd
import gzip
import numpy as np
import lxml.etree as et
import itertools
import multiprocessing as mp


def recur_dictify(frame):
    """
    h/t: http://stackoverflow.com/a/19900276/843419
    :param frame: a pandas data frame
    :return: a nested dictionary with the columns as the keys and the final one
    as the value. Best if the keys are arranged and sorted and there are no
    duplicates.
    """
    if len(frame.columns) == 1:
        if frame.values.size == 1:
            return frame.values[0][0]
        return frame.values.squeeze()
    grouped = frame.groupby(frame.columns[0])
    d = {k: recur_dictify(g.ix[:, 1:]) for k, g in grouped}
    return d


def pick_county(dict_table, sctg, zone):
    """
    :param sctg: the commodity code for the truck's cargo
    :param dict_table: the appropriate lookup table
    :return: the O or D county FIPS code
    """
    # get the relevant county lookup table
    try:
        a = dict_table[zone][sctg]
    except KeyError:
        print "Key not found for zone ", zone, " and commodity ", sctg
        sys.exit()
    else:
        county = np.random.choice(
            dict_table[zone][sctg].keys(),
            p=dict_table[zone][sctg].values())
        return county


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


def get_start_day():
    """
    :return: a random day of the week. For now all days are the same,
    but we don't have to make it that way. We have a one-week simulation
    """
    return np.random.randint(0, 6)


def get_departure_time():
    """
    :return: a random time in the day, bimodally distributed.
    """
    flag = np.random.binomial(1, 0.5)
    y = np.random.normal(9, 2.5) * (1 - flag) + \
        np.random.normal(16, 2.5) * flag
    if y < 0:
        # time cannot be less than midnight
        y = np.random.randint(0, 6 * 3600)
    elif y > 24 * 3600:
        # or greater than midnight
        y = np.random.randint(18 * 3600, 24 * 3600)
    else:
        y *= 3600
    return int(y)


def get_coord(name, dim):
    """Get the coordinates of a facility.
    Args:
        name: The name of the facility that we need to get the coordinate for.
        dim: x or y coordinate?

    Returns:
        A string with the desired coordinate of the facility.
    """
    return str(FAC_COORDS[dim][name])


def make_plans(df):
    l = []
    for index, row in df.iterrows():
        # sample down the number of trucks to the simulation period
        trucks = np.random.binomial(row['trucks'],
          3 / 365.25 * 1.02159 * SAMPLE_RATE)
        l += [TruckPlan(row) for _ in range(trucks)]
    return l


class TruckPlan(object):
    """Critical information for the truck plan

    Attributes:
        id: A numeric string indicating the truck id. This has to be set later
        because the different processes won't talk to each other.
        origin:
        destination:
        sctg:
        inmode:
        outmode:
    """
    __slots__ = ['id', 'origin', 'destination', 'sctg', 'inmode', 'outmode',
     'time', 'type']

    def __init__(self, row):
        """
        :rtype : a truck plan with origin, destination, etc.
        """
        self.id = None
        self.origin = row['dms_orig']
        self.destination = row['dms_dest']
        self.sctg = row['sctg']
        self.inmode = row['fr_inmode']
        self.outmode = row['fr_outmode']
        self.time = self.get_time()
        self.type = row['type']

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
                self.destination = pick_ienode(EXIM_DICT, self.outmode,
                                               self.destination)
            except KeyError:
                # If it doesn't, just assign like normal
                self.get_destination()
        else:
            self.get_destination()

    def display_plan(self):
        print "Id: ", self.id
        print "Origin: ", self.origin, "Destination", self.destination

    def set_id(self, x):
        self.id = x

    def get_origin(self):
        # Is the truck coming from Alaska?
        if self.origin == '20':
            # Is it going to states on the west coast?
            if self.destination in west_coast_f3z:
                # I-5 at the Washington/British Columbia border
                self.origin = '3004'
            else:
                # I-15 at the Montana/Alberta border
                self.origin = '3310'
        else:
            self.origin = pick_county(MAKE_DICT, self.sctg, self.origin)

    def get_destination(self):
        # Is the truck going to Alaska?
        if self.destination == '20':
            # is it coming from states on the west coast?
            # FAF zones have three-digit codes, the first two of which are
            # the state
            if self.origin[:2] in west_coast_states:
                # I-5 at the Washington/British Columbia border
                self.destination = '3004'
            else:
                # I-15 at the Montana/Alberta border
                self.destination = '3310'
        else:
            self.destination = pick_county(USE_DICT, self.sctg,
                                           self.destination)

    def get_time(self):
        day = get_start_day()
        return day * 3600 * 24 + get_departure_time()

    def write_plan(self, population):
        person = et.SubElement(population, "person",
                               attrib={'id': str(self.id)})
        plan = et.SubElement(person, "plan", attrib={'selected': "yes"})

        # write elements of plan
        et.SubElement(plan, "act",
                      attrib={'type': "dummy",
                              'x': get_coord(self.origin, 'x'),
                              'y': get_coord(self.origin, 'y'),
                              'end_time': str(self.time)})
        et.SubElement(plan, "leg", attrib={'mode': "car"})
        et.SubElement(plan, "act",
                      attrib={'type': "dummy",
                              'x': get_coord(self.destination, 'x'),
                              'y': get_coord(self.destination, 'y')})


if __name__ == "__main__":
    # sampling rate to use in the simulation
    SAMPLE_RATE = 0.03

    # Read in the I/O tables and convert them to dictionaries.
    print "  Reading input tables"
    MAKE_DICT = recur_dictify(pd.read_csv(
        "./data/simfiles/make_table.csv",
        dtype={'sctg': np.str, 'F4Z': np.str, 'name': np.str}
    ))

    USE_DICT = recur_dictify(pd.read_csv(
        "./data/simfiles/use_table.csv",
        dtype={'sctg': np.str, 'F4Z': np.str, 'name': np.str}
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
        "./data/simfiles/ie_nodes.csv",
        dtype={'F4Z': np.str, 'mode': np.str, 'name': np.str}
    ))

    # Geographical points for the activity locations
    FAC_COORDS = pd.read_csv(
        "./data/simfiles/facility_coords.csv",
        dtype={'name': np.str}
    ).set_index('name').to_dict()

    # read in the split trucks file with numbers of trucks going from i to j.
    faf_trucks = pd.read_csv(
        "./data/simfiles/faf_trucks.csv",
        dtype={'dms_orig': np.str, 'dms_dest': np.str, 'sctg': np.str,
               'trucks': np.int, 'fr_inmode': np.str, 'fr_outmode': np.str}
    )

    print "  Maximum of", sum(faf_trucks['trucks']), "trucks."

    # The faf_trucks data frame is almost 2 million lines long (for 2007 data).
    # But this is an embarrassingly parallel process for the most part (more on
    # ids below). The most efficient way to handle this is to split the data into
    # n_cores equal parts and do the origin and destination assignment off on
    # all the child cores. When we return all of the TruckPlans objects, we can
    # create their xml nodes and give them new ids.
    n_cores = mp.cpu_count() - 1  # leave yourself one core
    print "  Creating truck plans with ", n_cores, " separate processes"
    p = mp.Pool(processes=n_cores)
    split_dfs = np.array_split(faf_trucks, n_cores)
    pool_results = p.map(make_plans, split_dfs)   # apply f() to each chunk
    p.close()  # close child processes
    p.join()
    l = [a for L in pool_results for a in L]   # put all TPlans in same list
    print "  Created plans for", len(l), "trucks."

    # Create the element tree container
    population = et.Element("population")
    pop_file = et.ElementTree(population)

    # make new ids and write each truck's plan into the population tree
    for i, truck in itertools.izip(range(len(l)), l):
        truck.set_id(i)

    for truck in l:
        truck.write_plan(population)

    with gzip.open('population.xml.gz', 'w', compresslevel=4) as f:
        f.write("""<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE population SYSTEM "http://www.matsim.org/files/dtd/population_v5.dtd">
""")
        pop_file.write(f, pretty_print=True)
