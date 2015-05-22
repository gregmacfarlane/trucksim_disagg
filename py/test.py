import pandas as pd


# trucks = pd.read_csv("./data/faf_trucks.csv")

class TruckPlan:

    'Critical information for the truck plan'
    truckCount = 0

    def __init__(self, id, origin, destination, sctg, type, full):
        self.id = id
        self.origin = origin
        self.destination = destination
        self.sctg = sctg
        self.type = type
        self.full = full
        TruckPlan.truckCount += 1

    def display_count(self):
        print "Total number of trucks: %d" % TruckPlan.truckCount

    def display_plan(self):
        print "Origin: ", self.origin, "Destination", self.destination

    def display_cargo(self):
        print "Commodity: ", self.sctg, "Full? ", self.full, "Vehicle: ", self.type



def get_ods(trucks_table, i):

    """
    Given a number of trucks between two different FAF zones,
    create a plan for each
    """

t1 = TruckPlan(1, 20, 21, "a", "v", False)
t2 = TruckPlan(2, 20, 21, "a", "v", False)


t1.display_count()