// Author: Yanghao Hua <huayanghao@gmail.com>

#include <stdint.h>
#include <string.h>
#include "runtime.h"

#include "printf.h"

extern int test_hang(int n, int m);

int main() {
  printf("test start ...\n");
  int r = test_hang(256, 1);
  printf("test done: %d\n", r);
  return 0;
}
