import pandas as pd


# trucks = pd.read_csv("./data/faf_trucks.csv")

class TruckPlan:
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