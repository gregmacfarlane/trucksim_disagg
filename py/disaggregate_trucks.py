import numpy as np
import feather
import itertools
import multiprocessing as mp
import xml.etree.ElementTree as ET
import cPickle as pickle
import gzip
import csv
import sys
import getopt
import os.path

__author__ = 'Greg'


def main(argv):
    """ Handle input arguments from command line

    Args:
        argv: A series of command line arguments. Expects up to four:
          s - A sampling rate for the proportion of total trucks in the
          simulation (defaults to 1, or a full sample)
          o - An output file path (either csv or xml)
          d - The number of days in the simulation (default to 1)
          r - The region simulated (either counties or numas; defaults to numas)

    Returns:
        Global variables for each of the four command line inputs, or default
        values if arguments are not given

    """
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
    
    try:
        opts, args = getopt.getopt(
            argv, "hs:o:d:r:",
            ["samplerate=", "ofile=", "numberdays=", "region="]
        )
    except getopt.GetoptError:
        print 'disaggregate_trucks.py -s <samplerate> -o <outputfile> ' \
              '-d <numberdays> -r <region>'
        sys.exit(2)
        
    for opt, arg in opts:
        if opt == '-h':
            print 'disaggregate_trucks.py -s <samplerate> -o <outputfile> ' \
                  '-d <numberdays> -r <region>'
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


def pick_ienode(dict_table, mode, zone):
    """Pick import or export facility in a FAF region

    If the FAF trucks are listed as carrying imported or exported goods,
    then the selection isn't based on the production or consumption
    employment, but rather on the freight moved through airports, seaports,
    and highway border crossings in the FAF zone

     Args:
        dict_table: An import/export node dictionary containing keys for
            'F4Z', 'sctg', and a value representing the probability
            of picking a facility 'name'.
        mode: The import or export mode, which determines the type of
            facility the trucks can choose. If mode = 1, for example, the
            trucks will choose only highway border crossings.
        zone: The FAF zone/region code on the origin or destination end

    Returns:
        A character string with the id of the airport, seaport, or highway
        border crossing.
    """
    ienode = np.random.choice(
        dict_table[zone][mode].keys(),
        p=dict_table[zone][mode].values())
    return ienode


def pick_county(dict_table, sctg, zone):
    """Pick county from a set of counties in a FAF region

    This function works on origin or destination counties by passing
    either a make or use table, respectively.

    Args:
        dict_table: Either a make or use dictionary containing keys for
            'F4Z', 'sctg', and a value representing the probability
            of picking county 'name'.
        sctg: The commodity code for the truck's cargo
        zone: The FAF zone/region code on the origin or destination end

    Returns:
        A character string with the GEOID of the selected county

    Raises:
        KeyError: The zone-sctg pair isn't found in the dictionary
    """
    try:
        dict_table[zone][sctg]
    except KeyError:
        print "Key not found for zone ", zone, " and commodity ", sctg
        county = 'NA'
    else:
        county = np.random.choice(
            dict_table[zone][sctg].keys(),
            p=dict_table[zone][sctg].values())

    return county


def pick_numa(county_dict, sctg, county):
    """Pick numa from a set of numas in a county

    This function works on origin or destination counties by passing
    either a local make or a local use table, respectively.

    Args:
        county_dict: Either a make or use table containing keys for
            `county`, `sctg`, and a value representing the probability of
            picking numa 'numa'.
        sctg: The commodity code for the truck's cargo
        county: The county to which the simulation has assigned the shipment
            (using pick_county())

    Returns:
        If the global variable for `region` is set to counties, then the
        function simply returns the `county` input. Otherwise, a character
        string with the numa of the origin or destination.

    Raises:
        ValueError: Numpy rejects the probability vector, for example if it
            sums to less than one or contains missing values
        KeyError: Could not find the county or sctg combo in the dictionary

    """
    if region == "counties":
        return county
    else:
        try:
            probs = county_dict[county][sctg].values()
            probs /= sum(probs)   # renormalize probability vector
            try:
                numa = np.random.choice(
                    county_dict[county][sctg].keys(),
                    p=probs
                )
            except ValueError:
                print "  Inappropriate probability values for county", county, \
                    ", probs ", probs
                numa = "NA"
        except KeyError:
            print "  Local key not defined for county ", county, \
                ", sctg ", sctg
            numa = "NA"
        return numa


def get_start_day():
    """Get the day on which the truck starts its trip

    Returns:
       A random day between zero and global variable NUMBER_DAYS - 1

    """
    if NUMBER_DAYS == 1:
        return 0
    else:
        # TODO: allow this to vary by day of week
        return np.random.randint(0, NUMBER_DAYS - 1)


def get_departure_time():
    """Get the time at which the truck will depart

    Selects a random departure time day based on a bimodal probability
    distribution (departures are less common in the middle of the night, for
    example).

    Returns:
       A number of seconds between 00:00:00 and 23:59:59 indicating
       a random departure time.

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

    depart_time = get_start_day() * 3600 * 24 + int(y)
    return depart_time


def get_coord(name, dim):
    """Get the coordinates of a facility

    For simulations where we want to write out the coordinates on the origin
    and destination ends (instead of simply knowing the name of the facility),
    this function recovers the requested coordinates.

    In cases where we are writing to an origin-destination NUMA file, this
    function also locates the import/export facilities in their containing
    NUMA. For example, get_coord("SLC", "numa") will return "808", the NUMA in
    which the Salt Lake City International Airport is located.

    Args:
        name: The name of the facility that we need to get the coordinate for.
        dim: Which value to return
            x: The x-coordinate
            y: The y-coordinate
            numa: The numa containing the facility

    Returns:
        A string with the desired coordinate of the facility.

    """
    return str(FAC_COORDS[dim][name])


def make_plans(df):
    """Make plans for trucks in the FAF data frame

    Args:
        df: A data frame containing records of faf trucks with the information
            necessary to initialize a TruckPlans object.

    Returns:
        A list of TruckPlans objects, of length defined by the total
        number of trucks represented in df, as well as the SAMPLE_RATE and
        NUMBER_DAYS global variables.
    """
    truck_list = []
    for index, row in df.iterrows():

        # sample down the number of trucks to the simulation period
        # the `trucks` variable contains the number of trucks in a year;
        # this samples down based on the simulation sampling rate as well
        # the number of days in the simulation
        trucks = np.random.binomial(
            row['trucks'],
            min(NUMBER_DAYS / 365.25 * 1.02159 * SAMPLE_RATE, 1)
        )
        truck_list += [TruckPlan(row) for _ in range(trucks)]
    return truck_list


def write_output(truck_list, outfile, type):
    """Write truck plans to file

    Depending on the needs of the project, this function can write either an
    origin-destination node with details of the truck to a CSV,
    or it can write a MATSim plan set. This is controlled with the
    --outfile command line argument, and writes to matsim by default.

    Args:
        truck_list: a list of objects of class TruckPlan
        outfile: a path to the output file
        type: which type of output to produce

    Returns:
        Writes to a file. If type = `csv` then the result is a csv with the
        origin, destination, number of trucks by sctg code. Otherwise, writes to
        a MATSim plans file.
     """

    if type == "csv":
        with open(outfile, 'w') as f:
            columns = ['id', 'origin', 'destination', 'config', 'sctg']
            writer = csv.DictWriter(f, columns)
            writer.writeheader()
            for truck_plan in truck_list:
                writer.writerow(truck_plan.write_detailed_plan())
    else:
        # Create the element tree container
        population = ET.Element("population")
        pop_file = ET.ElementTree(population)

        for truck_plan in truck_list:
            truck_plan.write_plan(population)

        with gzip.open(outfile, 'w', compresslevel=4) as f:
            f.write("""<?xml version="1.0" encoding="utf-8"?>\n \
            <!DOCTYPE population SYSTEM \
            "http://www.matsim.org/files/dtd/population_v5.dtd">""")
            pop_file.write(f, pretty_print=True)


class TruckPlan(object):
    """Critical information for the truck plan

    Attributes:
        id: A numeric string indicating the truck id. This cannot be set on
            initialization because the classes will be initialized in parallel,
            and we cannot have duplicate id
        origin: The origin point of the truck. On init will be a FAF region,
            but will be sampled to origin and destination numa or import node.
        destination:
        origin: The destination point of the truck. On init will be a FAF
            region, but will be sampled to origin and destination numa or export
            node.
        sctg: The commodity the truck is carrying
        inmode: The import mode (if imported)
        outmode: The export mode (if exported)
        time: The departure time of the truck
        config: The truck configuration (CS, DBL, etc.)
    """
    __slots__ = ['id', 'origin', 'destination', 'sctg', 'inmode', 'outmode',
                 'time', 'config']

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
        self.time = get_departure_time()
        self.config = row['type']

        # get the origin points ----
        if self.inmode in ['1', '3', '4']:  # imported?
            try:
                # If a valid import node exists, use it
                self.origin = pick_ienode(EXIM_DICT, self.inmode, self.origin)
                if output_type == "csv":
                    # if xml then the coordinate is already known. If csv, need
                    # to grab NUMA
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
                    # if xml then the coordinate is already known. If csv, need
                    # to join to NUMA
                    self.destination = get_coord("numa", self.destination)
            except KeyError:
                # If it doesn't, just assign like normal
                self.get_destination()
        else:
            self.get_destination()

    def display_plan(self):
        print "Id: ", self.id
        print "    Origin: ", self.origin, "Destination", self.destination

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
                self.destination = pick_numa(USE_LOCAL, self.sctg, "x_3004")
            else:
                # I-15 at the Montana/Alberta border
                self.destination = pick_numa(USE_LOCAL, self.sctg, "x_3310")
        else:
            self.destination = pick_numa(
              USE_LOCAL, self.sctg,
              pick_county(USE_DICT, self.sctg, self.destination)
            )

    def write_plan(self, population):
        """Write truck's plan as XML object

        This writes what MATSim requires for its input plans.xml file
        Each truck is a 'person' within the xml 'population' node.
        Each truck has a starting activity at the origin that "ends" at the
        Sampled simulation time, and then the truck proceeds by "car" to
        its second activity, at the destination.

        Args:
            population: An XML parent node defining all the individuals
                in the population

        Returns:
            Adds the current truck's plan to the population XML node
        """

        person = ET.SubElement(population, "person",
                               attrib={'id': str(self.id)})

        plan = ET.SubElement(person, "plan", attrib={'selected': "yes"})

        # starting/origin activity
        ET.SubElement(plan, "act",
                      attrib={'type': "dummy",
                              'x': get_coord(self.origin, 'x'),
                              'y': get_coord(self.origin, 'y'),
                              'end_time': str(self.time)})

        # Travel leg
        # TODO: write mode as configuration. Currently only uses car mode
        ET.SubElement(plan, "leg", attrib={'mode': "car"})

        # ending/destination activity
        ET.SubElement(plan, "act",
                      attrib={'type': "dummy",
                              'x': get_coord(self.destination, 'x'),
                              'y': get_coord(self.destination, 'y')})

    def write_detailed_plan(self):
        """Give truck's plan as a dictionary

        Returns:
            A dictionary describing the trucks origin, destination,
            configuration, and cargo, for writing to a csv or internal
            debugging.
        """
        row = {'id': self.id,
               'origin': self.origin,
               'destination': self.destination,
               'config': self.config,
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

    # read in the split trucks file with numbers of trucks going from i to j.
    faf_trucks = feather.read_dataframe(simdir + "faf_trucks.feather")

    print "  Maximum of", sum(faf_trucks['trucks']), "trucks."

    # The faf_trucks data frame is almost 2 million lines long (for 2007 data).
    # But this is an embarrassingly parallel process for the most part (more on
    # ids below). The most efficient way to handle this is to split the data
    # into n_cores equal parts and do the origin and destination assignment off
    # on all the child cores. When we return all of the TruckPlans objects, we
    # can create their xml nodes and give them new ids.
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
