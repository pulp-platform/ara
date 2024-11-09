#!/usr/bin/env python

import random
import sys

def generate_bit_vector(size):
    # Generate a random bit vector I of size 'size'
    I = [random.randint(0, 1) for _ in range(size)]

    # Initialize the accumulator and the output vector O
    accumulator = 0
    O = []

    # Compute each element of O based on I and the accumulator
    for bit in I:
        O.append(accumulator)
        accumulator += bit

    return I, O

def format_I_vector_as_binary(I, size):
    # Format the I vector in chunks of 8 bits in reverse order
    bin_chunks = [
        "0b" + "".join(str(bit) for bit in I[i:i+8][::-1])
        for i in range(0, size, 8)
    ]
    return ", ".join(bin_chunks)

def format_O_vector(O):
    # Format the O vector as individual elements
    return ", ".join(f"{val}" for val in O)

def generate_test_case(size):
    # Generate I and O vectors
    I, O = generate_bit_vector(size)

    # Format I as binary strings in chunks of 8 bits and O as individual elements
    I_formatted = format_I_vector_as_binary(I, size)
    O_formatted = format_O_vector(O)

    # Prepare the test case template
    test_case = f"""
void TEST_CASE1() {{
  VSET({int(size/8)}, e8, m1);
  VLOAD_8(v1, {I_formatted});
  VSET({size}, e8, m1);
  asm volatile("viota.m v2, v1");
  VCMP_U8(1, v2, {O_formatted});
}}
"""

    return test_case

# Example of using the function
if __name__ == "__main__":
    size = int(sys.argv[1])
    print(generate_test_case(size))
