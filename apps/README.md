# Apps

This folder contains the benchmarks, programs, and tests ready to be run on Ara.

Run the following command to build an application. E.g., `hello_world`:

```bash
cd apps
make bin/hello_world
```

### Convolutions

Convolutions allow to specify the output matrix size and the size of the filter, with the variables `OUT_MTX_SIZE` up to 112 and `F_SIZE` within {3, 5, 7}. Currently, not all the configurations are supported for all the convolutions. For more information, check the `main.c` file for the convolution of interest.
Example:

```bash
cd apps
make bin/fconv2d OUT_MTX_SIZE=112 F_SIZE=7
```
