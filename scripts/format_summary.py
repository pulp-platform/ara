# Ara's plotting library

import numpy as np
import copy
import seaborn as sns
import pandas as pd
import matplotlib.pylab as plt
import argparse

# Instantiate the parser
parser = argparse.ArgumentParser(description=
'''
Format the database.
''')

# Switch
parser.add_argument('-f', '--infile', action='store',
                    help=
'''
Specify a file that contains all the kernel files with results.
''')

parser.add_argument('-m', '--metric', action='store',
                    help=
'''
Select which metric to display [perf|dstall|istall|sbfull].
''')

args = parser.parse_args()

# Roofline plot

# 2 vars - 1 const 1d histogram

# 2d heatmap - vars on x/y-axes - hm() value on z-axis
# arg1: label vector(y-axis + z-axis)
# arg2: label vector (x-axis)
def heatmap(db):
  titlefont = {'fontname' : 'Garamond'};
  axisfont  = {'fontname' : 'Garamond'};
  sns.heatmap(db, cmap="Greens", annot=True)
  plt.title('Relative kernel performance on maximum achievable', **titlefont)
  plt.xlabel('Vector Length [elements]', **axisfont)
  plt.ylabel('Kernel', **axisfont)
  plt.show()

# Append a new entry to the main database
def append_entry(lst, template):
  lst.append(copy.deepcopy(template))

# Update the database
def update_db(fpath, db, template):
  with open(fpath, 'r') as fid:
    for line in fid:
      append_entry(db, template)
      elm = line.split()
      # [token]: lanes vsize sew cycles
      assert len(elm) == 10
      db[-1] = {
        'kernel'     : elm[0],
        'lanes'      : int(elm[1]),
        'vsize'      : int(elm[2]),
        'sew'        : int(elm[3]),
        'perf'       : float(elm[4]),
        'max_perf'   : float(elm[5]),
        'ideal_disp' : int(elm[6]),
        'dstall'     : int(elm[7]),
        'istall'     : int(elm[8]),
        'sb_full'    : int(elm[9]),
      }

def kernel_list_gen(db):
  return list(set([d['kernel'] for d in db]))

def vsize_list_gen(db, kernel_list):
  return sorted(list(set([d0['vsize'] for d0 in db if
    (len([d1 for d1 in db if d1['vsize'] == d0['vsize']]) == len(kernel_list))])))

def create_db(db, r_label, c_label):
  pd.DataFrame([[{l : [d['cycles']/d['max_cycles'] for d in db if (d['kernel'], d['size']) == (r, l)]} for l in c_label] for r in r_label])

def main():
  # Main database (DB)
  db = list()

  # DB entry template
  template = {
    'kernel'     : '',
    'lanes'      : 0,
    'vsize'      : 0,
    'sew'        : 0,
    'perf'       : 0,
    'max_perf'   : 0,
    'ideal_disp' : 0,
    'dstall'     : 0,
    'istall'     : 0,
    'sb_full'    : 0,
  }

  # Update the database with the information from the input file
  update_db(args.infile, db, template)

  # Build list of available kernels and common vsizes
  kernel_list = kernel_list_gen(db)
  vsize_list  = vsize_list_gen(db, kernel_list)

  # Build relative performance(kernel, vsize) db
  buf_perf = [{vs : [(entry['perf'] / entry['max_perf']) for k in kernel_list for entry in db if (entry['kernel'], entry['vsize']) == (k, vs)]} for vs in vsize_list];
  buf_dstall = [{vs : [(entry['dstall']) for k in kernel_list for entry in db if (entry['kernel'], entry['vsize']) == (k, vs)]} for vs in vsize_list];
  buf_istall = [{vs : [(entry['istall']) for k in kernel_list for entry in db if (entry['kernel'], entry['vsize']) == (k, vs)]} for vs in vsize_list];
  buf_sbfull = [{vs : [(entry['sb_full']) for k in kernel_list for entry in db if (entry['kernel'], entry['vsize']) == (k, vs)]} for vs in vsize_list];

  if   (args.metric == 'perf'):
    buf = buf_perf
  elif (args.metric == 'dstall'):
    buf = buf_dstall
  elif (args.metric == 'istall'):
    buf = buf_istall
  elif (args.metric == 'sbfull'):
    buf = buf_sbfull

  pkv_db = dict()
  for d in buf:
    pkv_db.update(d)
  pkv_db = pd.DataFrame(pkv_db);
  pkv_db.index = kernel_list;
  pkv_db.sort_index(axis=0, inplace=True)

  print(pkv_db)

if __name__ == '__main__':
  main()
