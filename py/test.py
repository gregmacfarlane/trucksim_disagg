import pandas as pd
import numpy as np
import xml.etree.ElementTree as et



def get_start_day():
    """
    :return: a random day of the week. For now all days are the same,
    but we don't have to make it that way. We have a two-week simulation
    """
    return np.random.randint(1, 14)

def get_departure_time():
    """
    :return:
    """
    y0 = np.random.randn()
    y1 = np.random.randn()
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

    def __init__(self, id, origin, destination, sctg, type, full):
        self.id = id
        self.origin = origin
        self.destination = destination
        self.sctg = sctg
        self.type = type
        self.full = full
        self.time = None
        TruckPlan.truckCount += 1

        # get the departure time
        self.get_time()



    def display_count(self):
        print "Total number of trucks: ", TruckPlan.truckCount


    def display_plan(self):
        print "Origin: ", self.origin, "Destination", self.destination

    def display_cargo(self):
        print "Commodity: ", self.sctg, "Full? ", self.full, "Vehicle: ", self.type


    def get_origin(self):
        print "origin"

    def get_destination(self):
        print "destination"


    def get_time(self):
        "What time does the truck leave?"
        self.time = get_start_day() * 3600 + get_departure_time()


t1 = TruckPlan(1)
print(t1.time)

print "Truck plans created: ", TruckPlan.truckCount



