#!/usr/bin/env python3
# Copyright 2026 ETH Zurich and University of Bologna.
# SPDX-License-Identifier: Apache-2.0
#
# Author: Hong Pang <hopang@iis.ee.ethz.ch>
#
# Convert the [SWEEP] lines of a run.log to CSV, and write status.txt and
# summary.csv of a run directory.
#
#   parse_log.py sweep   <run.log> <sweep.csv>
#   parse_log.py status  <cfg_dir>
#   parse_log.py summary <cfg_dir>

import csv
import glob
import os
import re
import subprocess
import sys

COLS = ['kernel', 'prec', 'lanes', 'size', 'elems_per_lane', 'bytes_per_lane',
        'cycles', 'flop_cycle', 'util_pct', 'warmup']

SWEEP_RE = re.compile(r'\[SWEEP\]((?: \w+=\S+)+)')


def sweep_rows(log):
  rows = []
  if not os.path.isfile(log):
    return rows
  for line in open(log, errors='replace'):
    m = SWEEP_RE.search(line)
    if not m:
      continue
    f = dict(kv.split('=', 1) for kv in m.group(1).split())
    sew, lanes, size = int(f['sew']), int(f['lanes']), int(f['size'])
    rows.append({
      'kernel': f['kernel'], 'prec': f'FP{sew}', 'lanes': lanes, 'size': size,
      'elems_per_lane': size / lanes, 'bytes_per_lane': size * sew / 8 / lanes,
      'cycles': int(f['cycles']), 'flop_cycle': float(f['flop_cycle']),
      'util_pct': float(f['util']),
      # First point only warms the I-cache
      'warmup': int(not rows),
    })
  return rows


def write_csv(path, rows, cols, header=()):
  with open(path, 'w', newline='') as fh:
    for h in header:
      fh.write(f'# {h}\n')
    w = csv.DictWriter(fh, fieldnames=cols, extrasaction='ignore')
    w.writeheader()
    w.writerows(rows)


def job_dirs(cfg_dir):
  return sorted(d for d in glob.glob(os.path.join(cfg_dir, '*')) if os.path.isfile(os.path.join(d, 'state')))


def state(d):
  return open(os.path.join(d, 'state')).read().strip()


def verdict(d):
  """PASS/FAIL for a checked (verification) job, '-' for a timing job."""
  f = os.path.join(d, 'check')
  if not os.path.isfile(f) or open(f).read().strip() != '1':
    return '-'
  st = state(d)
  return 'PASS' if st == 'done' else 'FAIL' if st.startswith('FAILED') else st


def status(cfg_dir):
  lines = []
  for d in job_dirs(cfg_dir):
    rows = sweep_rows(os.path.join(d, 'run.log'))
    last = (f'size={rows[-1]["size"]:<8} util={rows[-1]["util_pct"]:6.2f}%  '
            f'({len(rows)} points)') if rows else ''
    v = verdict(d)
    lines.append(f'{os.path.basename(d):<18} {state(d):<40} {"" if v == "-" else v + "  "}{last}')
  tmp = os.path.join(cfg_dir, '.status.txt')
  with open(tmp, 'w') as fh:
    fh.write('\n'.join(lines) + '\n')
  os.replace(tmp, os.path.join(cfg_dir, 'status.txt'))


def git(*a):
  return subprocess.run(['git', '-C', os.path.dirname(os.path.abspath(__file__)), *a],
                        capture_output=True, text=True).stdout.strip()


def summary(cfg_dir):
  rows, fails, checked = [], [], []
  for d in job_dirs(cfg_dir):
    st, v = state(d), verdict(d)
    if st != 'done':
      fails.append(f'{os.path.basename(d)}: {st}')
    if v != '-':
      checked.append(v)
    for r in sweep_rows(os.path.join(d, 'run.log')):
      rows.append(dict(r, job=os.path.basename(d), state=st, check=v))
  dirty = git('status', '--porcelain', '--untracked-files=no').replace('\n', '; ')
  header = [f'git {git("rev-parse", "HEAD")}', f'dirty: {dirty or "none"}']
  if checked:
    header.append(f'verification: {checked.count("PASS")}/{len(checked)} PASS')
  header += [f'NOT DONE {f}' for f in fails]
  write_csv(os.path.join(cfg_dir, 'summary.csv'), rows, ['job', 'state', 'check'] + COLS, header)
  return fails


if __name__ == '__main__':
  cmd = sys.argv[1] if len(sys.argv) > 1 else ''
  if cmd == 'sweep' and len(sys.argv) == 4:
    write_csv(sys.argv[3], sweep_rows(sys.argv[2]), COLS)
  elif cmd == 'status' and len(sys.argv) == 3:
    status(sys.argv[2])
  elif cmd == 'summary' and len(sys.argv) == 3:
    sys.exit(1 if summary(sys.argv[2]) else 0)
  else:
    sys.exit(__doc__ or 'usage: parse_log.py sweep|status|summary ...')
