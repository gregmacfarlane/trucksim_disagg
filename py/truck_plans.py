import pandas as pd
import numpy as np
import lxml.etree as et


# Read in the lookup tables for the origins and the destinations.
MAKE_TABLE = pd.read_csv(
    "./data/make_table.csv",
    dtype={'sctg': np.str, 'F3Z': np.str, 'name': np.str}
)

USE_TABLE = pd.read_csv(
    "./data/use_table.csv",
    dtype={'sctg': np.str, 'F3Z': np.str, 'name': np.str}
)


def pick_county(zone, sctg, df):
    """
    :param zone: the original FAF Zone O or D for the truck
    :param sctg: the commodity code for the truck's cargo
    :param df: the appropriate lookup table
    :return: the O or D county FIPS code
    """
    # get the relevant county lookup table
    df = df[df['F3Z'] == zone]
    df = df[df['sctg'] == sctg]
    county = np.random.choice(df['name'], p=df['prob'])
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
    truckCount = 0

    def __init__(self, truck_id, origin, destination, sctg):
        TruckPlan.truckCount += 1
        self.id = truck_id
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
        self.origin = pick_county(self.origin, self.sctg, MAKE_TABLE)

    def get_destination(self):
        self.destination = pick_county(self.destination, self.sctg, USE_TABLE)

    def get_time(self):
        self.time = get_start_day() * 3600 + get_departure_time()

    def write_plan(self):
        person = et.SubElement(population, "person",
                               attrib={'id': str(self.id)})
        plan = et.SubElement(person, "plan", attrib={'selected': "yes"})
        act = et.SubElement(plan, "act",
                            attrib={'type': "dummy",
                                    'facility': str(self.origin),
                                    'end_time': str(self.time)
                                    })
        leg = et.SubElement(plan, "leg", attrib={'mode': "car"})
        act = et.SubElement(plan, "act",
                            attrib={'type': "dummy",
                                    'facility': str(self.destination)})


population = et.Element("population")
pop_file = et.ElementTree(population)

t1 = TruckPlan(1, "19", "371", "01")

with open('population.xml', 'w') as f:
    f.write("""<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE population SYSTEM "http://www.matsim.org/files/dtd/population_v5.dtd">
""")
    pop_file.write(f, pretty_print=True)
