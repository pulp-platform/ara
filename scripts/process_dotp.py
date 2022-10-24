#!/usr/bin/env python3
#
# Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>
#
# Build a database of the benchmark results and create useful plots
#

import sys
import copy
import matplotlib.pyplot as plt
import numpy as np

# Update the database
def update_db(fpath, db, template):
  with open(fpath, 'r') as fid:
    for line in fid:
      append_entry(db, template)
      elm = line.split()
      # [token]: lanes vsize sew cycles
      assert len(elm) == 5
      db[-1] = {
        'kernel' : elm[0][1:-2],
        'lanes'  : int(elm[1]),
        'vsize'  : int(elm[2]),
        'sew'    : int(elm[3]),
        'cycles' : int(elm[4]),
      }

# Append a new entry to the main database
def append_entry(lst, template):
  lst.append(copy.deepcopy(template))

# Create a hierarchical bar plot with 2 variables on the X axis
# On the y axis, we plot the cycle count (lower is better)
# len(set(x0)) groups of len(set(x1)) bars each
# With plotlib, we plot len(set(x0)) bars for len(set(x1)) times
def plot_2vars_2const(db, vars_x, unit_x, const_x, const_val, fname, swap=False):
  if swap:
    vars_x.reverse()
    unit_x.reverse()
  # Sort ascending on key `(x0, x1)`
  db.sort(key=lambda e: (e[vars_x[0]], e[vars_x[1]]))
  # Get the different values of the x0 and x1 variables (x-axis)
  x0 = sorted(list(set([e[vars_x[0]] for e in db])))
  x1 = sorted(list(set([e[vars_x[1]] for e in db])))
  # Bar width so that the different sub plots are spaced
  BAR_WIDTH = 1 / (len(x1) + 1)
  # x_base is the collection of offset to be used for plotting cycles at constant vsize
  x_offset = [np.arange(len(x0))]
  # Each y1 element is a list of y values corresponding
  # to different x0, to be plot for a specific x1
  y1 = list()
  for y in x1:
    x_offset.append([off + BAR_WIDTH for off in x_offset[-1]])
    # Each new list contains the different x0s at constant x1
    y1.append([e['cycles'] for e in db if e[const_x[0]] == const_val[0] and
                                          e[const_x[1]] == const_val[1] and
                                          e[vars_x[1]] == y])
  # Last element is useless
  del x_offset[-1]
  # Create the plot
  for x, y, label in zip(x_offset, y1, x1):
    plt.bar(x, y, width=BAR_WIDTH, label= vars_x[1] + ': ' + str(label) + unit_x[1])
  # Print x-axis vsize labels
  x_tick_idx = int(np.ceil(len(x_offset) / 2)) - 1
  plt.xticks(x_offset[x_tick_idx], x0)
  # Print x-axis sew legend
  plt.title(const_x[0] + ': ' + str(const_val[0]) + ', ' + const_x[1] + ': ' + str(const_val[1]) +
            '\n' + ' cycle count @different ' + vars_x[0] + ' and ' + vars_x[1])
  plt.xlabel(vars_x[0] + ' [' + unit_x[0] + ']')
  plt.ylabel('Cycle count')
  plt.grid(visible=True, which='both')
  plt.legend()
  # Save the plot
  outfile = '{}_{}_{}_{}{}_{}{}.png'.format(fname, vars_x[0], vars_x[1], const_x[0],
                                  const_val[0], const_x[1], const_val[1])
  plt.savefig(outfile)
  plt.close()

def main():
  # kernel
  kernel    = sys.argv[1]
  # Input file path
  IN_FPATH  = sys.argv[2]
  # Output file name
  OUT_FNAME = sys.argv[3]

  # Main database (DB)
  db = list()

  # DB entry template
  template = {
    'kernel'     : '',
    'lanes'      : 0,
    'vsize'      : 0,
    'sew'        : 0,
    'cycles'     : 0,
  }

  # Update the database with the information from the input file
  update_db(IN_FPATH, db, template)

  # Plot @constant #Lanes
  for lanes in set([e['lanes'] for e in db]):
    plot_2vars_2const(db, ['vsize', 'sew'], ['Byte', 'Byte'],
                      ['kernel', 'lanes'], [kernel, lanes], OUT_FNAME, swap=False)
  for lanes in set([e['lanes'] for e in db]):
    plot_2vars_2const(db, ['vsize', 'sew'], ['Byte', 'Byte'],
                      ['kernel', 'lanes'], [kernel, lanes], OUT_FNAME, swap=True)

  # Plot @constant sew
  for sew in set([e['sew'] for e in db]):
    plot_2vars_2const(db, ['lanes', 'vsize'], ['Lanes', 'Byte'],
                      ['kernel', 'sew'], [kernel, sew], OUT_FNAME, swap=False)
  for sew in set([e['sew'] for e in db]):
    plot_2vars_2const(db, ['lanes', 'vsize'], ['Lanes', 'Byte'],
                      ['kernel', 'sew'], [kernel, sew], OUT_FNAME, swap=True)

  # Plot @constant vsize
  for vsize in set([e['vsize'] for e in db]):
    plot_2vars_2const(db, ['sew', 'lanes'], ['Byte', 'Lanes'],
                      ['kernel', 'vsize'], [kernel, vsize], OUT_FNAME, swap=False)
  for vsize in set([e['vsize'] for e in db]):
    plot_2vars_2const(db, ['sew', 'lanes'], ['Byte', 'Lanes'],
                      ['kernel', 'vsize'], [kernel, vsize], OUT_FNAME, swap=True)

if __name__ == '__main__':
  main()
