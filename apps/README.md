# Tests and Benchmarks for Ara

## conv2d benchmark
`conv2d` currently supports filter sizes from this set: {3, 5, 7}. To run all the applications, execute:
`make v_benchmarks_spike FILTER_SIZE=${F}`
Where ${F} is the chosen filter size.
