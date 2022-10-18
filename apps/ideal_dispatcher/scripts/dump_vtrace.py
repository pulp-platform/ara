#!/usr/bin/env python3
# Copyright 2020 ETH Zurich and University of Bologna.
#
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

# Decode the vector instructions replacing the register names with their actual values

import sys

infile  = sys.argv[1]
outfile = sys.argv[2]

# 32 registers, with 4 registers per row
RegRows  = 8
# String width of a single register in the rf, "label: value"
RegWidth = 24

xrf = {
  'zero' : '0',
  'ra'   : '0',
  'sp'   : '0',
  'gp'   : '0',
  'tp'   : '0',
  't0'   : '0',
  't1'   : '0',
  't2'   : '0',
  's0'   : '0',
  's1'   : '0',
  'a0'   : '0',
  'a1'   : '0',
  'a2'   : '0',
  'a3'   : '0',
  'a4'   : '0',
  'a5'   : '0',
  'a6'   : '0',
  'a7'   : '0',
  's2'   : '0',
  's3'   : '0',
  's4'   : '0',
  's5'   : '0',
  's6'   : '0',
  's7'   : '0',
  's8'   : '0',
  's9'   : '0',
  's10'  : '0',
  's11'  : '0',
  't3'   : '0',
  't4'   : '0',
  't5'   : '0',
  't6'   : '0'
}

frf = {
  'ft0'  : '0',
  'ft1'  : '0',
  'ft2'  : '0',
  'ft3'  : '0',
  'ft4'  : '0',
  'ft5'  : '0',
  'ft6'  : '0',
  'ft7'  : '0',
  'fs0'  : '0',
  'fs1'  : '0',
  'fa0'  : '0',
  'fa1'  : '0',
  'fa2'  : '0',
  'fa3'  : '0',
  'fa4'  : '0',
  'fa5'  : '0',
  'fa6'  : '0',
  'fa7'  : '0',
  'fs2'  : '0',
  'fs3'  : '0',
  'fs4'  : '0',
  'fs5'  : '0',
  'fs6'  : '0',
  'fs7'  : '0',
  'fs8'  : '0',
  'fs9'  : '0',
  'fs10' : '0',
  'fs11' : '0',
  'ft8'  : '0',
  'ft9'  : '0',
  'ft10' : '0',
  'ft11' : '0'
}

insn_pattern = "core"

insn = {
  'asm'  : '',
  'name' : '',
  'regs' : '',
  'vals' : ''
}

def updateRf(regline, reg_width, rf):
  # Divide the four registers in list elements
  reg_list = [regline[idx : idx + reg_width] for idx in range(0, len(regline), reg_width)]
  # Divide each label from the reg value
  reg_list = [string.replace('0x', '').replace(':', '').split() for string in reg_list[:-1]]
  # Update the regstate and return
  for reg in reg_list:
    rf[reg[0]] = reg[1]
  return rf

# Some vector instructions require an rs2 value to be passed along
# vsetvl, strided mem ops (vtype, stride)
def addRs2(disasm, args):
  rs2 = ''
  if (disasm == 'vsetvl'):
    print('ERROR: vlse or vsse found, implement addRs2 function!')
  if ('vlse' in disasm or 'vsse' in disasm):
    for reg in xrf:
      if (reg == args[-1]):
        rs2 = "{}".format(xrf[reg])
  return rs2

# If an instruction needs a register value, fetch it from the next XRF/FRF state
with open(infile, "r") as fin, open(outfile, "w") as fout:
  # Read all the lines
  for line in fin:
    # Look for instructions
    if (insn_pattern in line):
      # Remove brackets
      insn['asm']  = line.split()[3][3:-1]
      insn['name'] = line.split()[4]
      insn['regs'] = [elm.replace(',', '').replace('(', '').replace(')', '') for elm in line.split()[5:]]
      # Update the internal state
      stateline = ''
      # Upadte xrf
      for row in range(RegRows):
        regline = fin.readline()
        xrf = updateRf(regline, RegWidth, xrf)
      # Update frf
      for row in range(RegRows):
        regline = fin.readline()
        frf = updateRf(regline, RegWidth, frf)
      # Check for Rs2 and delete its entry if present
      rs2 = addRs2(insn['name'], insn['regs'])
      if rs2 != '':
        del insn['regs'][-1]
      else:
        rs2 = '0000000000000000'
      # Fetch the rs1 value to be forwarded to Ara
      for reg in xrf:
        if (reg in insn['regs']):
          insn['vals'] = "{}".format(xrf[reg])
      for reg in frf:
        if (reg in insn['regs']):
          insn['vals'] = "{}".format(frf[reg])
    insn_out = ''
    fout.write(insn_out.join([insn['asm'], insn['vals'], rs2]) + '\n')
