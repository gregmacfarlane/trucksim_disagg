__author__ = 'Greg'

import numpy as np
import feather
import itertools
import multiprocessing as mp
import csv

import sys, getopt
import os.path

def main(argv):
    """
    Handle input arguments from command line
    """
    # program defaults
    global SAMPLE_RATE
    SAMPLE_RATE = 1
    global NUMBER_DAYS
    NUMBER_DAYS = 1
    global output_file
    output_file = 'sim_output.csv'
    global output_type
    output_type = 'csv'
    global region
    region = "numas"
    
    # try to get the arguments
    try:
        opts, args = getopt.getopt(argv,"hs:o:d:r:",["samplerate=","ofile=","numberdays=","region="])
    except getopt.GetoptError:
        print 'disaggregate_trucks.py -s <samplerate> -o <outputfile> -d <numberdays> -r <region>'
        sys.exit(2)
        
    for opt, arg in opts:
        if opt == '-h':
            print 'disaggregate_trucks.py -s <samplerate> -o <outputfile> -d <numberdays> -r <region>'
            sys.exit()
        elif opt in ("-s", "--samplerate"):
            try:
                SAMPLE_RATE = float(arg)
            except ValueError:
                print 'samplerate must be numeric'
                sys.exit(2)
        elif opt in ("-d", "--days"):
            try:
                NUMBER_DAYS = int(arg)
            except ValueError:
                print 'days must be integer'
                sys.exit(2)
        elif opt in ("-o", "--outputfile"):
            output_file = arg
            output_type = os.path.splitext(output_file)[1][1:]
            if output_type != 'xml' and output_type != 'csv':
                print 'output must be either xml or csv'
                sys.exit(2)
        elif opt in ("-r", "--region"):
            region = arg
            if region != 'numas' and region != 'counties':
                print 'region must be either numas or counties'
                sys.exit(2)
                



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

def pick_numa(county_dict, sctg, point) :
    """
    :param county_dict: a dictionary of the simulation points inside the halo that need to be disaggregated to the TAZ level. This has by-commodity fields with make and use coefficients.
    :param point: The point (either a county or an import/export node) to which the simulation has assigned the shipment.
    :return: the TAZ to which the truck is destined
    """
    # If the global variable is set to counties only, then just return the original
    # input
    if region == "counties":
        return(point)
    else:
        try:
            probs = county_dict[point][sctg].values()
            probs /= sum(probs)   # renormalize probability vector
            try:
                taz = np.random.choice(
                    county_dict[point][sctg].keys(),
                    p=probs
                )
            except ValueError:
                taz = "NA"
        except KeyError:
            # if it doesn't exist in either dictionary, return NA
            taz = "NA"
    return taz

def get_start_day():
    """
    :return: a random day of the week. For now all days are the same,
    but we don't have to make it that way. We have a one-week simulation
    """
    if NUMBER_DAYS == 1:
        return 0
    else:
        return np.random.randint(0, NUMBER_DAYS - 1)


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
          min(NUMBER_DAYS / 365.25 * 1.02159 * SAMPLE_RATE,
              1))
        l += [TruckPlan(row) for _ in range(trucks)]
    return l

def write_output(list, file, type):
    """Write truck plans to file
    
    Depending on the needs of the project, this function can write either an
    origin-destination node with details of the truck to a CSV,
    or it can write a MATSim plan set. This is controlled with the
    -t argument, and writes to matsim by default.
    
    Args:
        list: a list of objects of class TruckPlan
        file: a path to the output file
        type: which type of output to produce
        
    Returns:
        Writes to a file. If type = `csv` then the result is a csv with the
        origin, destination, number of trucks by sctg code. Otherwise, writes to
        a MATSim plans file.
     """
     
    if type == "csv":
        with open(file, 'w') as f:
            columns = ['id', 'origin', 'destination', 'config', 'sctg']
            writer = csv.DictWriter(f, columns)
            writer.writeheader()
            for truck in list:
                writer.writerow(truck.write_detailed_plan())
    else:
        # Create the element tree container
        population = et.Element("population")
        pop_file = et.ElementTree(population)
        
        for truck in list:
            truck.write_plan(population)

        with gzip.open(file, 'w', compresslevel=4) as f:
            f.write("""<?xml version="1.0" encoding="utf-8"?>\n<!DOCTYPE population SYSTEM "http://www.matsim.org/files/dtd/population_v5.dtd">""")
            pop_file.write(f, pretty_print=True)

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
                if output_type == "csv":
                    #if xml then the coordinate is already known. If csv, need
                    #to grab NUMA
                    self.origin = get_coord("numa", self.origin)
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
                if output_type == "csv":
                    #if xml then the coordinate is already known. If csv, need
                    #to join to NUMA
                    self.destination = get_coord("numa", self.destination)
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
                self.origin = pick_numa(MAKE_LOCAL, self.sctg, '3004')
            else:
                # I-15 at the Montana/Alberta border
                self.origin = pick_numa(MAKE_LOCAL, self.sctg, '3310')
        else:
            self.origin = pick_numa(
              MAKE_LOCAL, self.sctg,
              pick_county(MAKE_DICT, self.sctg, self.origin)
            )

    def get_destination(self):
        # Is the truck going to Alaska?
        if self.destination == '20':
            # is it coming from states on the west coast?
            # FAF zones have three-digit codes, the first two of which are
            # the state
            if self.origin[:2] in west_coast_states:
                # I-5 at the Washington/British Columbia border
                self.destination = pick_numa(USE_LOCAL, self.sctg, "3004")
            else:
                # I-15 at the Montana/Alberta border
                self.destination = pick_numa(USE_LOCAL, self.sctg, "3310")
        else:
            self.destination = pick_numa(
              USE_LOCAL, self.sctg,
              pick_county(USE_DICT, self.sctg, self.destination)
            )

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
                              
    def write_detailed_plan(self):
        row = {'id': self.id,
               'origin': self.origin,
               'destination': self.destination,
               'config': self.type,
               'sctg': self.sctg}
        return row

if __name__ == "__main__":
    # handle arguments
    main(sys.argv[1:])
    print 'Sampling Rate of ', SAMPLE_RATE
    print 'Days in simulation: ', NUMBER_DAYS
    print 'Output file is ', output_file
    print 'Type is ', output_type
    print 'Disaggregating to ', region
    simdir = "data/simfiles/"

    # Read in the I/O tables and convert them to dictionaries.
    # These tables are for FAF zone to county disaggregation
    print "  Reading county make and use tables"
    MAKE_DICT = pickle.load(open(simdir + "make_table.pickle", "rb"))
    USE_DICT = pickle.load(open(simdir + "use_table.pickle", "rb"))

    # These tables are for county-to-numa disaggregation
    print "  Reading NUMA make and use tables"
    MAKE_LOCAL = pickle.load(open(simdir + "make_local.pickle", "rb"))
    USE_LOCAL = pickle.load(open(simdir + "use_local.pickle", "rb"))

    # Exports/Imports are directed to airports, seaports, or highway border
    # crossings in the FAF zone.
    EXIM_DICT = pickle.load(open(simdir + "ie_nodes.pickle", "rb"))

    # Geographical points for the activity locations
    # also contains name-numa lookup for import export nodes
    FAC_COORDS = pickle.load(open(simdir + "facility_coords.feather", "rb"))

    # To handle Alaska shipments appropriately, we need to have a list of
    # states/faf zones where the trucks will either drive down the coast to
    # Washington or in front of the Rockies to Montana
    # western states (Washington route): [CA, OR, WA, NV, AZ, ID, UT]
    west_coast_states = ['06', '41', '53', '32', '04', '16', '49']
    west_coast_f3z = range(61, 69) + range(411, 419) + range(531, 539) + \
                     range(321, 329) + range(41, 49) + [160] + range(491, 499)


    # Geographical points for the activity locations
    # also contains name-numa lookup for import export nodes
    FAC_COORDS = feather.read_dataframe(
        "./data/simfiles/facility_coords.feather",
    ).set_index('name').to_dict()

    # read in the split trucks file with numbers of trucks going from i to j.
    faf_trucks = feather.read_dataframe("./data/simfiles/faf_trucks.feather")

    print "  Maximum of", sum(faf_trucks['trucks']), "trucks."

    # The faf_trucks data frame is almost 2 million lines long (for 2007 data).
    # But this is an embarrassingly parallel process for the most part (more on
    # ids below). The most efficient way to handle this is to split the data into
    # n_cores equal parts and do the origin and destination assignment off on
    # all the child cores. When we return all of the TruckPlans objects, we can
    # create their xml nodes and give them new ids.
    n_cores = mp.cpu_count()
    print "  Creating truck plans with ", n_cores, " separate processes"
    p = mp.Pool(processes=n_cores)
    split_dfs = np.array_split(faf_trucks, n_cores)
    pool_results = p.map(make_plans, split_dfs)   # apply f() to each chunk
    p.close()  # close child processes
    p.join()
    l = [a for L in pool_results for a in L]   # put all TPlans in same list
    print "  Created plans for", len(l), "trucks."

    # make new ids and write each truck's plan to a CSV
    for i, truck in itertools.izip(range(len(l)), l):
        truck.set_id(i)

    write_output(l, output_file, output_type)
