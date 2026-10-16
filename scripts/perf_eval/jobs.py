#!/usr/bin/env python3
# Copyright 2026 ETH Zurich and University of Bologna.
# SPDX-License-Identifier: Apache-2.0
#
# Author: Hong Pang <hopang@iis.ee.ethz.ch>
#
# Job tables of the timing sweep (perf) and the verification sweep (check),
# and the config parsing shared by the other perf_eval scripts.
#
#   jobs.py list [--mode perf|check] [--smoke] [--only k:P,k,...]
#     one "name kernel prec args" line per job
#   jobs.py check-sets --config <cfg> [--set k=v ...]
#     exit with an error on an unknown config or --set key

import argparse
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

# kernel, prec, full args, smoke args; job name <kernel>_<prec>, short jobs first
_PERF = [
  ('fdotproduct', 'FP64', '131072',       '64'),
  ('fdotproduct', 'FP32', '262144',       '64'),
  ('fdotproduct', 'FP16', '524288',       '64'),
  ('faxpy',       'FP64', '131072',       '64'),
  ('faxpy',       'FP32', '262144',       '64'),
  ('faxpy',       'FP16', '524288',       '64'),
  ('cos',         'FP64', '16384',        '64'),
  ('cos',         'FP32', '32768',        '64'),
  ('log',         'FP64', '16384',        '64'),
  ('log',         'FP32', '32768',        '64'),
  ('exp',         'FP64', '16384',        '64'),
  ('exp',         'FP32', '32768',        '64'),
  ('softmax',     'FP32', '8 32768',      '8 64'),
  ('gemv',        'FP64', '120 2048',     '8 64'),
  ('gemv',        'FP32', '120 4096',     '8 64'),
  ('gemv',        'FP16', '120 8192',     '8 64'),
  ('fconv2d',     'FP64', '124 1024 7',    '8 64 7'),
  ('fconv2d',     'FP32', '124 2048 7',   '8 64 7'),
  ('fconv2d',     'FP16', '124 4096 7',   '8 64 7'),
  ('fmatmul',     'FP64', '128 128 1024',  '8 8 64'),
  ('fmatmul',     'FP32', '128 128 2048', '8 8 64'),
  ('fmatmul',     'FP16', '128 128 4096', '8 8 64'),
]


# name, kernel, prec, check args, smoke args. Sizes keep each job under ~1 h,
# yet cross VLMAX (and fconv2d/fmatmul multi-row paths) in >= 1 precision
_CHECK = [
  ('fdotproduct_FP64', 'fdotproduct', 'FP64', '4096',       '64'),
  ('fdotproduct_FP32', 'fdotproduct', 'FP32', '8192',       '64'),
  ('fdotproduct_FP16', 'fdotproduct', 'FP16', '16384',      '64'),
  ('faxpy_FP64',       'faxpy',       'FP64', '4096',       '64'),
  ('faxpy_FP32',       'faxpy',       'FP32', '8192',       '64'),
  ('faxpy_FP16',       'faxpy',       'FP16', '16384',      '64'),
  ('cos_FP64',         'cos',         'FP64', '1024',       '64'),
  ('cos_FP32',         'cos',         'FP32', '2048',       '64'),
  ('log_FP64',         'log',         'FP64', '1024',       '64'),
  ('log_FP32',         'log',         'FP32', '2048',       '64'),
  ('exp_FP64',         'exp',         'FP64', '1024',       '64'),
  ('exp_FP32',         'exp',         'FP32', '2048',       '64'),
  ('softmax_FP32',     'softmax',     'FP32', '4 1024',     '8 64'),
  ('gemv_FP64',        'gemv',        'FP64', '120 1024',   '8 64'),
  ('gemv_FP32',        'gemv',        'FP32', '120 2048',   '8 64'),
  ('gemv_FP16',        'gemv',        'FP16', '120 4096',   '8 64'),
  ('fconv2d7x7_FP64',  'fconv2d',     'FP64', '16 512 7',   '8 64 7'),
  ('fconv2d7x7_FP32',  'fconv2d',     'FP32', '16 512 7',   '8 64 7'),
  ('fconv2d7x7_FP16',  'fconv2d',     'FP16', '16 512 7',   '8 64 7'),
  ('fconv2d3x3_FP64',  'fconv2d',     'FP64', '8 512 3',    '8 64 3'),
  ('fconv2d3x3_FP32',  'fconv2d',     'FP32', '8 1024 3',   '8 64 3'),
  ('fconv2d3x3_FP16',  'fconv2d',     'FP16', '8 2048 3',   '8 64 3'),
  ('fmatmul_FP64',     'fmatmul',     'FP64', '8 64 1024',  '8 8 64'),
  ('fmatmul_FP32',     'fmatmul',     'FP32', '4 64 2048',  '8 8 64'),
  ('fmatmul_FP16',     'fmatmul',     'FP16', '4 64 4096',  '8 8 64'),
]


def jobs(smoke=False, only=None, mode='perf'):
  """Selected jobs as (name, kernel, prec, [int args]).
  `only` items are 'kernel', 'name' or either of them with ':PREC'."""
  table = _CHECK if mode == 'check' else [(f'{k}_{p}', k, p, f, s) for k, p, f, s in _PERF]
  sel = []
  for n, k, p, full, small in table:
    stem = n.rsplit('_', 1)[0]
    if only and not {k, stem, f'{k}:{p}', f'{stem}:{p}'} & only:
      continue
    sel.append((n, k, p, [int(x) for x in (small if smoke else full).split()]))
  return sel


# Config variables that --set may override
SETTABLE = ('nr_lanes', 'vlen')


def read_config(cfg, sets=()):
  """Variables of config/<cfg>.mk, with `k=v` overrides applied on top."""
  path = os.path.join(ROOT, 'config', f'{cfg}.mk')
  if not os.path.isfile(path):
    sys.exit(f'error: no such config {path}')
  var = {}
  for line in open(path):
    m = re.match(r'\s*(\w+)\s*\??=\s*(\S+)', line)
    if m:
      var[m.group(1)] = m.group(2)
  for kv in sets:
    k, v = kv.split('=', 1)
    if k not in SETTABLE:
      sys.exit(f'error: --set {k}: only {", ".join(SETTABLE)} can be set')
    var[k] = v
  return var


def parse_only(s):
  return set(x.strip() for x in s.split(',') if x.strip()) if s else None


if __name__ == '__main__':
  ap = argparse.ArgumentParser()
  ap.add_argument('cmd', choices=['list', 'check-sets'])
  ap.add_argument('--config', default='')
  ap.add_argument('--set', action='append', default=[])
  ap.add_argument('--mode', choices=['perf', 'check'], default='perf')
  ap.add_argument('--smoke', action='store_true')
  ap.add_argument('--only', default='')
  o = ap.parse_args()
  if o.cmd == 'check-sets':
    read_config(o.config, o.set)
    sys.exit(0)
  sel = jobs(o.smoke, parse_only(o.only), o.mode)
  if not sel:
    sys.exit('error: --only selected no jobs')
  for n, k, p, a in sel:
    print(n, k, p, *a)
