## SoCDAML Exercise - 20/04/2021

This exercise goes through the basics of vector processing.

## Structure of the exercise

- `README.md`:
   This file.
- `main.c`
   Main file of the exercise. The execution starts at the main() function.
- `intrinsics.h`:
   Vector intrinsics. This file contains a series of small functions that help you write vector code without resorting to pure assembly code.
- `sew.h`:
   Standard element width and type of a vector element.

### Compiling the exercise

Run `make compile` in the current folder to compile the exercise.
If the compilation is succesful, the compiled binary can be found in `../bin/ara_training`, and the accompanying dump file is located at `../bin/ara_training.dump`.

You can define a series of variables to tweak the execution of the exercise.
- `SEW`: The width of a vector element. Can be one of `8`, `16`, `32`, or `64`. By default, `SEW = 64`.
- `SIZE`: The size of the vectors/matrices used throughout the exercise. The three statically allocated matrices, `a`, `b`, and `c`, have `SIZE` rows and `SIZE` columns. When `a`, `b`, and `c` are used as vectors, they have `SIZE` elements (basically, you will use the first row of the matrix). By default, `SIZE = 64`.
- `EX1`, `EX2`, `EX3`, `EX4`: Define each variable to `1` to run the corresponding exercise. By default, all exercises are deactivated.

For example, to run `EX2` and `EX3` with elements of `32` bits and a matrix of size `64`, you can run `EX2=1 EX3=1 SEW=32 SIZE=64 make compile`.

### Running the exercise

After compiling the code without errors, run `make run` to execute the exercise on Ara, using Verilator as a simulator.

## Exercise 1

In this exercise, we will learn about the `vsetvl` instructions, which is the base of vector processors, being present since the first CRAY vector machines. You will be asked to determine the MAXVL of Ara, for several element widths, using the `__vsetvl` function we defined in `intrinsics.h`. Check `ex1/ex1.c` for more details.

## Exercise 2

In this exercise, we will add two very long vectors together. We will need to write a stripmining loop. We will not need to write any assembly, though, since we will make use of vector intrinsics, small functions that get inlined by the compiler at compile-time. We will also measure the performance of this vector-vector add kernel, and compare with the ideal runtime. Check `ex2/ex2.c` for more details.

## Exercise 3

In this exercise, we will vectorize Dropout, an algorithm using during NN training. Check `ex3/ex3.c` for more details.

## Exercise 4 (optional)

In this exercise, we will implement the matrix multiplication of two matrices. Check `ex4/ex4.c` for more details.
