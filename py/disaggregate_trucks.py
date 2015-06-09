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
    but we don't have to make it that way. We have a two-week simulation
    """
    return np.random.randint(0, 364)


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
    return str(FAC_COORDS[dim][name])

class TruckPlan:
    """Critical information for the truck plan"""
    id_iter = itertools.count(1)

    def __init__(self, origin, destination, sctg, inmode, outmode):
        # get the departure time ---
        self.time = 1
        self.id = self.id_iter.next()

        # only write the plan if the truck runs in the first week
        # and only if in a 10% sample
        if self.time == 1:
            """
            :rtype : a truck plan with origin, destination, etc.
            """
            self.origin = origin
            self.destination = destination
            self.sctg = sctg
            self.inmode = inmode
            self.outmode = outmode

            self.write_plan()

    def display_plan(self):
        print "Id: ", self.id
        print "Origin: ", self.origin, "Destination", self.destination

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
        self.time = day * 3600 * 24 + get_departure_time()

    def write_plan(self):
        person = et.SubElement(population, "person",
                               attrib={'id': str(self.id)})
        plan = et.SubElement(person, "plan", attrib={'selected': "yes"})

        # write elements of plan
        et.SubElement(plan, "act",
                      attrib={'type': "dummy",
                              'origin': self.origin})
        et.SubElement(plan, "leg", attrib={'mode': "car"})
        et.SubElement(plan, "act",
                      attrib={'type': "dummy",
                              'destination': self.destination})


if __name__ == "__main__":


    # Create the element tree container
    population = et.Element("population")
    pop_file = et.ElementTree(population)

    # read in the split trucks file with numbers of trucks going from i to j.


    print "  Creating truck plans"

    pool = mp.Pool(processes=4)
    m = mp.Manager()
    q = m.Queue()

    pool.apply_async(
        [TruckPlan('orig', 'dest', 'sctg', 'fr_inmode', 'fr_outmode')
        for _ in range(int(1e4))]
    )


    with gzip.open('parallel.xml.gz', 'w', compresslevel=4) as f:
        f.write("""<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE population SYSTEM "http://www.matsim.org/files/dtd/population_v5.dtd">
""")
        pop_file.write(f, pretty_print=True)
