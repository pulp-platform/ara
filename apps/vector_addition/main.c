#include <stdint.h>
#include <string.h>

#ifndef SPIKE
#include "printf.h"
#else
#include "util.h"
#include <stdio.h>
#endif

uint64_t x[10] = {1,2,3,4,5,6,7,8,9,10};
uint64_t y[10] = {10,9,8,7,6,5,4,3,2,1};
uint64_t z[10];

int main() {
  printf("Ariane says Hello!\n");

  /*
  * Example of Using Vector Instruction -- Vector Addition Z = Y + X
  */

  //step1 -- configure the vector length
  uint64_t VL = 10; 
  asm volatile("vsetvli zero, %0, e64, m4, ta, ma" ::"r"(VL));

  //step2 -- load x to vector register 0 (v0)
  asm volatile("vle64.v v0, (%0);" ::"r"(x));

  //step3 -- load y to vector register 4 (v4)
  asm volatile("vle64.v v4, (%0);" ::"r"(y));

  //step4 -- v0 + v4 -> v8
  asm volatile("vadd.vv v8, v4, v0;");

  //step5 -- store v8 to z array
  asm volatile("vse64.v v8, (%0);" ::"r"(z));


  // Check the results (CVA6)
  for (int i = 0; i < 10; ++i)
  {
    printf("%d\n", z[i]);
  }

  return 0;
}
