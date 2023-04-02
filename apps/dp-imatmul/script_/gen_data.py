#!/usr/bin/env python3
# Copyright 2022 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Author: Tim Fischer <fischeti@iis.ee.ethz.ch>

import numpy as np
import torch
import torch.nn as nn
import argparse
import pathlib
import hjson

np.random.seed(42)
torch.manual_seed(42)

global verbose


def array_to_cstr(a, fmt=float):
    out = '{'
    if isinstance(a, np.ndarray):
        a = a.flat
    if isinstance(a, torch.Tensor):
        a = a.numpy().flat
    for el in a:
        out += '{}, '.format(hex(int(el) & ((1 << fmt) - 1)))
    out = out[:-2] + '}'
    return out


def emit_header_file(layer_type: str, **kwargs):

    file_path = pathlib.Path(__file__).parent.parent / 'data'
    emit_str = "// Copyright 2022 ETH Zurich and University of Bologna.\n" + \
               "// Licensed under the Apache License, Version 2.0, see LICENSE for details.\n" + \
               "// SPDX-License-Identifier: Apache-2.0\n\n"

    if layer_type == 'GEMM':
        file = file_path / 'data_gemm.h'
        emit_str += emit_GEMM_layer(**kwargs)
    with file.open('w') as f:
        f.write(emit_str)

def emit_GEMM_layer(name='gemm', **kwargs):
    mat_A = kwargs['A']
    mat_B = kwargs['B']
    mat_C = kwargs['C']
    result = kwargs['result']

    m = kwargs['M']
    n = kwargs['N']
    k = kwargs['K']

    layer_str = ''
    layer_str += '#include "layer.h"\n\n'
    layer_str += f'const gemm_layer {name}_l = {{\n'
    layer_str += f'\t.M = {m},\n'
    layer_str += f'\t.N = {n},\n'
    layer_str += f'\t.K = {k},\n'
    layer_str += f'\t.TA = {int(kwargs["ta"])},\n'
    layer_str += f'\t.TB = {int(kwargs["tb"])},\n'
    layer_str += f'\t.ALPHA = {kwargs["alpha"]},\n'
    layer_str += f'\t.expand = {kwargs["expand"]}\n'
    layer_str += '};\n\n\n'

    ctypes = {
        '64': 'int64_t',
        '32': 'int32_t',
        '16': 'int16_t',
        '8':  'int8_t'
    }
    dtype = ctypes[str(kwargs['prec'])]

    layer_str += f'static {dtype} {name}_A_dram [{m}*{k}] __attribute__((aligned(32 * NR_LANES), section(".l2"))) = ' + array_to_cstr(kwargs['A'], kwargs['prec']) + ';\n\n\n'
    layer_str += f'static {dtype} {name}_B_dram [{k}*{n}] __attribute__((aligned(32 * NR_LANES), section(".l2"))) = ' + array_to_cstr(kwargs['B'], kwargs['prec']) + ';\n\n\n'
    layer_str += f'static {dtype} {name}_C_dram [{m}*{n}] __attribute__((aligned(32 * NR_LANES), section(".l2"))) = ' + array_to_cstr(kwargs['C'], kwargs['prec']) + ';\n\n\n'
    layer_str += f'static {dtype} {name}_checksum[{m}]    = ' + array_to_cstr(torch.sum(result, dim=-1), kwargs['prec']) + ';\n\n\n'
    return layer_str

def rand_data_generator(shape, prec, alt=False):
    if prec == 64:
        return torch.randint(low=-2**63, high=2**63-1, size=shape, requires_grad=False, dtype=torch.int64), {}
    elif prec == 32:
        return torch.randint(low=-2**31, high=2**31-1, size=shape, requires_grad=False, dtype=torch.int32), {}
    elif prec == 16:
        return torch.randint(low=-2**15, high=2**15-1, size=shape, requires_grad=False, dtype=torch.int16), {}
    elif prec == 8:
        return torch.randint(low=-2**7, high=2**7-1, size=shape, requires_grad=False, dtype=torch.int8), {}

def main():

    parser = argparse.ArgumentParser(description='Generate data for kernels')
    parser.add_argument(
        "-c",
        "--cfg",
        type=pathlib.Path,
        required=True,
        help='Select param config file kernel'
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action='store_true',
        help='Set verbose'
    )

    args = parser.parse_args()

    global verbose
    verbose = args.verbose

    with args.cfg.open() as f:
        param = hjson.loads(f.read())

    if param['prec'] == 64:
        dtype = torch.int64
    elif param['prec'] == 16:
        dtype = torch.int16
    elif param['prec'] == 8:
        dtype = torch.int8
    else:
        dtype = torch.int32

    if param['kernel'] == 'GEMM':
        mat_A, bits_A = rand_data_generator((param['M'], param['K']), param['prec'])
        mat_B, bits_B = rand_data_generator((param['K'], param['N']), param['prec'])
        mat_C, bits_C = rand_data_generator((param['M'], param['N']), param['prec'])

        result = param['alpha'] * mat_C + torch.matmul(mat_A, mat_B)

        if param['transpose_A']:
            mat_A = mat_A.T
        if param['transpose_B']:
            mat_B = mat_B.T

        kwargs = {
            'A': mat_A,
            'B': mat_B,
            'C': mat_C,
            'result': result,
            'M': param['M'],
            'N': param['N'],
            'K': param['K'],
            'ta': param['transpose_A'],
            'tb': param['transpose_B'],
            'alpha': param['alpha'],
            'prec': param['prec'],
            'expand': param['expand'],
            'bits_A': bits_A,
            'bits_B': bits_B,
            'bits_C': bits_C
        }

        emit_header_file('GEMM', **kwargs)

    else:
        print("No valid kernel selected")


if __name__ == '__main__':
    main()
