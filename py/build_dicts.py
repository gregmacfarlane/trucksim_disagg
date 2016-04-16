__author__ = 'Greg'

import sys, getopt
import cPickle as pickle
import feather


def recur_dictify(frame):
    """Transform a dataframe into an indexed dictionary

    Returns a multi-level dictionary from a pandas dataframe by looping
    over the columns recursively. The top-level dictionary should be in the
    left-most column, the next level in the second-to-left, and so on.
    h/t: http://stackoverflow.com/a/19900276/843419

    Args:
        frame: A pandas data frame

    Returns:
        A nested dictionary with the columns as the keys and the final column
        as the value.

    """
    if len(frame.columns) == 1:
        if frame.values.size == 1:
            return frame.values[0][0]
        return frame.values.squeeze()
    grouped = frame.groupby(frame.columns[0])
    d = {k: recur_dictify(g.ix[:, 1:]) for k, g in grouped}
    return d

def main(argv):
    """Process command line arguments

    Args:
        argv: A series of command line arguments. Expects two: a path to an
        input feather file and a path to an output pickle file.

    Returns:
        Two variables into the global environment, character string paths
        to the arguments defined in Args.

    """
    # try to get the arguments
    try:
        opts, args = getopt.getopt(argv, "hi:o:",["infeather=","outpickle="])
    except getopt.GetoptError:
        print 'build_dicts.py -i <infeather> -o <outpickle>'
        sys.exit(2)

    for opt, arg in opts:
        if opt == '-h':
            print 'build_dicts.py -i <infeather> -o <outpickle>'
            sys.exit()
        elif opt in ("-i", "--infeather"):
            global infeather
            infeather = arg
        elif opt in ("-o", "--outpickle"):
            global outpickle
            outpickle = arg


if __name__ == "__main__":
    # get input and output file from command line
    main(sys.argv[1:])

    # get feather table written from R
    d = feather.read_dataframe(infeather)

    # reorder columns depending on what file is read in
    if "x" in d and "y" in d:
        # This is the facility coordinates dictionary,
        # which gets handled differently because it is a three column dictionary
        # instead of a multi-level dictionary like the others that this
        # script handles
        d = d.set_index('name').to_dict()
    elif "dms_orig" in d:
        # This is the trucks dictionary, which does not need to be put into a
        # a dictionary
        d = d
    else:
        if "F4Z" in d:
            if "sctg" in d:
                # FAF region to county name: make_table use_table.feather
                d = d[['F4Z', 'sctg', 'name', 'prob']]
            elif "mode" in d:
                # FAF region to import/export facility: ie_nodes.feather
                d = d[['F4Z', 'mode', 'name', 'prob']]
            else:
                print "Cannot determine input table type"
                sys.exit()
        elif "county" in d:
            # county to numa lookup probability dictionary:
            # make_local and use_local.feather
            d = d[['county', 'sctg', 'numa', 'p']]
        else:
            print "Cannot determine input table type"
            sys.exit()

        d = recur_dictify(d)

    # write out to pickle
    pickle.dump(d, open(outpickle, "wb"))

