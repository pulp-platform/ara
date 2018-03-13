#include "benchmarks.h"

void main() {
    __sync_synchronize();
    TEST_START(in_dim);
    dgemm(in_dim, in_dim, in_dim, in_alpha, in_A, in_B, in_beta, in_C);
    TEST_END(in_dim);
    __sync_synchronize();
}
