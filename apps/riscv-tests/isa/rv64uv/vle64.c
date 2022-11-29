// TODO uncomment TEST_CASE12 and TEST_CASE 14 after issue of vl=0 and
// non-zero vstart is resolved
// TODO uncomment TEST_CASE2 after issue of exception is resolved

#include "long_array.h"
#include "vector_macros.h"

#define AXI_DWIDTH 128
// Exception Handler for rtl

void mtvec_handler(void) {
  asm volatile("csrr t0, mcause"); // Read mcause

  // Read mepc
  asm volatile("csrr t1, mepc");

  // Increment return address by 4
  asm volatile("addi t1, t1, 4");
  asm volatile("csrw mepc, t1");

  // Filter with mcause and handle here

  asm volatile("mret");
}

// Exception Handler for spike
void handle_trap(void) {
  // Read mepc
  asm volatile("csrr t1, mepc");

  // Increment return address by 4
  asm volatile("addi t1, t1, 4");
  asm volatile("csrw mepc, t1");

  asm volatile("ld ra, 8(sp)");
  asm volatile("ld sp, 16(sp)");
  asm volatile("ld gp, 24(sp)");
  asm volatile("ld tp, 32(sp)");
  asm volatile("ld t0, 40(sp)");
  asm volatile("ld t0, 40(sp)");
  asm volatile("ld t1, 48(sp)");
  asm volatile("ld t2, 56(sp)");
  asm volatile("ld s0, 64(sp)");
  asm volatile("ld s1, 72(sp)");
  asm volatile("ld a0, 80(sp)");
  asm volatile("ld a1, 88(sp)");
  asm volatile("ld a2, 96(sp)");
  asm volatile("ld a3, 104(sp)");
  asm volatile("ld a4, 112(sp)");
  asm volatile("ld a5, 120(sp)");
  asm volatile("ld a6, 128(sp)");
  asm volatile("ld a7, 136(sp)");
  asm volatile("ld s2, 144(sp)");
  asm volatile("ld s3, 152(sp)");
  asm volatile("ld s4, 160(sp)");
  asm volatile("ld s5, 168(sp)");
  asm volatile("ld s6, 176(sp)");
  asm volatile("ld s7, 184(sp)");
  asm volatile("ld s8, 192(sp)");
  asm volatile("ld s9, 200(sp)");
  asm volatile("ld s10, 208(sp)");
  asm volatile("ld s11, 216(sp)");
  asm volatile("ld t3, 224(sp)");
  asm volatile("ld t4, 232(sp)");
  asm volatile("ld t5, 240(sp)");
  asm volatile("ld t6, 248(sp)");

  // Read mcause
  asm volatile("csrr t3, mcause");

  asm volatile("addi sp, sp, 272");

  // Filter with mcause and handle here

  asm volatile("mret");
}

static volatile uint64_t ALIGNED_I64[16]
    __attribute__((aligned(AXI_DWIDTH))) = {
        0x9fe419208f2e05e0, 0xf9aa71f0c394bbd3, 0xa11a9384a7163840,
        0x99991348a9f38cd1, 0x9fa831c7a11a9384, 0x3819759853987548,
        0x1893179501093489, 0x81937598aa819388, 0x1874754791888188,
        0x3eeeeeeee33111ae, 0x9013930148815808, 0xab8b914891484891,
        0x9031850931584902, 0x3189759837598759, 0x8319599991911111,
        0x8913984898951989};

//**********Checking functionality of vle64********//
void TEST_CASE1(void) {
  VSET(15, e64, m1);
  asm volatile("vle64.v v0, (%0)" ::"r"(&ALIGNED_I64[1]));
  VCMP_U64(1, v0, 0xf9aa71f0c394bbd3, 0xa11a9384a7163840, 0x99991348a9f38cd1,
           0x9fa831c7a11a9384, 0x3819759853987548, 0x1893179501093489,
           0x81937598aa819388, 0x1874754791888188, 0x3eeeeeeee33111ae,
           0x9013930148815808, 0xab8b914891484891, 0x9031850931584902,
           0x3189759837598759, 0x8319599991911111, 0x8913984898951989);
}

//******Checking functionality of  with illegal destination register
// specifier for EMUL********//
// In this test case EMUL=2 and register is v1 which will cause illegal
// instruction exception and set mcause = 2
void TEST_CASE2(void) {
  uint8_t mcause;
  VSET(15, e64, m2);
  asm volatile("vle64.v v1, (%0)" ::"r"(&ALIGNED_I64[1]));
  asm volatile("addi %[A], t3, 0" : [A] "=r"(mcause));
  XCMP(2, mcause, 2);
}

//*******Checking functionality of vle64 with different values of masking
// register******//
void TEST_CASE3(void) {
  VSET(16, e64, m1);
  VCLEAR(v3);
  VLOAD_8(v0, 0xFF, 0xFF);
  asm volatile("vle64.v v3, (%0), v0.t" ::"r"(&ALIGNED_I64[0]));
  VCMP_U64(3, v3, 0x9fe419208f2e05e0, 0xf9aa71f0c394bbd3, 0xa11a9384a7163840,
           0x99991348a9f38cd1, 0x9fa831c7a11a9384, 0x3819759853987548,
           0x1893179501093489, 0x81937598aa819388, 0x1874754791888188,
           0x3eeeeeeee33111ae, 0x9013930148815808, 0xab8b914891484891,
           0x9031850931584902, 0x3189759837598759, 0x8319599991911111,
           0x8913984898951989);
}

void TEST_CASE4(void) {
  VSET(16, e64, m1);
  VCLEAR(v3);
  VLOAD_8(v0, 0x00, 0x00);
  asm volatile("vle64.v v3, (%0), v0.t" ::"r"(&ALIGNED_I64[0]));
  VCMP_U64(4, v3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
}

void TEST_CASE5(void) {
  VSET(16, e64, m1);
  VCLEAR(v3);
  VLOAD_64(v3, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  VLOAD_8(v0, 0xAA, 0xAA);
  asm volatile("vle64.v v3, (%0), v0.t" ::"r"(&ALIGNED_I64[0]));
  VCMP_U64(5, v3, 1, 0xf9aa71f0c394bbd3, 3, 0x99991348a9f38cd1, 5,
           0x3819759853987548, 7, 0x81937598aa819388, 9, 0x3eeeeeeee33111ae, 11,
           0xab8b914891484891, 13, 0x3189759837598759, 15, 0x8913984898951989);
}

//******Checking functionality with different combinations of vta and vma*****//
// **** It uses undisturbed policy for tail agnostic and mask agnostic****//
void TEST_CASE6(void) {
  uint64_t avl;
  VSET(16, e64, m1);
  VLOAD_64(v4, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  VLOAD_8(v0, 0xAA, 0xAA);
  __asm__ volatile("vsetivli %[A], 12, e64, m1, ta, ma" : [A] "=r"(avl));
  asm volatile("vle64.v v4, (%0), v0.t" ::"r"(&ALIGNED_I64[0]));
  VSET(16, e64, m1);
  VCMP_U64(6, v4, 1, 0xf9aa71f0c394bbd3, 3, 0x99991348a9f38cd1, 5,
           0x3819759853987548, 7, 0x81937598aa819388, 9, 0x3eeeeeeee33111ae, 11,
           0xab8b914891484891, 13, 14, 15, 16);
}

void TEST_CASE7(void) {
  uint64_t avl;
  VSET(16, e64, m1);
  VLOAD_64(v4, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  VLOAD_8(v0, 0xAA, 0xAA);
  __asm__ volatile("vsetivli %[A], 12, e64, m1, ta, mu" : [A] "=r"(avl));
  asm volatile("vle64.v v4, (%0), v0.t" ::"r"(&ALIGNED_I64[0]));
  VSET(16, e64, m1);
  VCMP_U64(7, v4, 1, 0xf9aa71f0c394bbd3, 3, 0x99991348a9f38cd1, 5,
           0x3819759853987548, 7, 0x81937598aa819388, 9, 0x3eeeeeeee33111ae, 11,
           0xab8b914891484891, 13, 14, 15, 16);
}

void TEST_CASE8(void) {
  uint64_t avl;
  VSET(16, e64, m1);
  VLOAD_64(v4, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  VLOAD_8(v0, 0xAA, 0xAA);
  __asm__ volatile("vsetivli %[A], 12, e64, m1, tu, ma" : [A] "=r"(avl));
  asm volatile("vle64.v v4, (%0), v0.t" ::"r"(&ALIGNED_I64[0]));
  VSET(16, e64, m1);
  VCMP_U64(8, v4, 1, 0xf9aa71f0c394bbd3, 3, 0x99991348a9f38cd1, 5,
           0x3819759853987548, 7, 0x81937598aa819388, 9, 0x3eeeeeeee33111ae, 11,
           0xab8b914891484891, 13, 14, 15, 16);
}

void TEST_CASE9(void) {
  uint64_t avl;
  VSET(16, e64, m1);
  VLOAD_64(v4, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  VLOAD_8(v0, 0xAA, 0xAA);
  __asm__ volatile("vsetivli %[A], 12, e64, m1, tu, mu" : [A] "=r"(avl));
  asm volatile("vle64.v v4, (%0), v0.t" ::"r"(&ALIGNED_I64[0]));
  VSET(16, e64, m1);
  VCMP_U64(9, v4, 1, 0xf9aa71f0c394bbd3, 3, 0x99991348a9f38cd1, 5,
           0x3819759853987548, 7, 0x81937598aa819388, 9, 0x3eeeeeeee33111ae, 11,
           0xab8b914891484891, 13, 14, 15, 16);
}

//*******Checking functionality if encoded EEW is not supported for given SEW
// and LMUL values because EMUL become out of range*****//
// This test case cover upper bound of EMUL(8). If LMUL is changed to
// m2 it will give error because emul become greater than 8 (EMUL = 16)
void TEST_CASE10(void) {
  VSET(15, e8, m1);
  asm volatile("vle64.v v8, (%0)" ::"r"(&ALIGNED_I64[1]));
  VCMP_U64(10, v8, 0xf9aa71f0c394bbd3, 0xa11a9384a7163840, 0x99991348a9f38cd1,
           0x9fa831c7a11a9384, 0x3819759853987548, 0x1893179501093489,
           0x81937598aa819388, 0x1874754791888188, 0x3eeeeeeee33111ae,
           0x9013930148815808, 0xab8b914891484891, 0x9031850931584902,
           0x3189759837598759, 0x8319599991911111, 0x8913984898951989);
}

//******Checking functionality with different values of vl******//
void TEST_CASE11(void) {
  VSET(16, e64, m1);
  VLOAD_64(v6, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  VSET(16, e64, m1);
  asm volatile("vle64.v v6, (%0)" ::"r"(&ALIGNED_I64[0]));
  VSET(16, e64, m1);
  VCMP_U64(11, v6, 0x9fe419208f2e05e0, 0xf9aa71f0c394bbd3, 0xa11a9384a7163840,
           0x99991348a9f38cd1, 0x9fa831c7a11a9384, 0x3819759853987548,
           0x1893179501093489, 0x81937598aa819388, 0x1874754791888188,
           0x3eeeeeeee33111ae, 0x9013930148815808, 0xab8b914891484891,
           0x9031850931584902, 0x3189759837598759, 0x8319599991911111,
           0x8913984898951989);
}

void TEST_CASE12(void) {
  uint64_t avl;
  VSET(16, e64, m1);
  VLOAD_64(v6, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  __asm__ volatile("vsetivli %[A], 0, e64, m1, ta, ma" : [A] "=r"(avl));
  asm volatile("vle64.v v6, (%0)" ::"r"(&ALIGNED_I64[0]));
  VSET(16, e64, m1);
  VCMP_U64(12, v6, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
}

void TEST_CASE13(void) {
  VSET(16, e64, m1);
  VLOAD_64(v6, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  VSET(13, e64, m1);
  asm volatile("vle64.v v6, (%0)" ::"r"(&ALIGNED_I64[0]));
  VSET(16, e64, m1);
  VCMP_U64(13, v6, 0x9fe419208f2e05e0, 0xf9aa71f0c394bbd3, 0xa11a9384a7163840,
           0x99991348a9f38cd1, 0x9fa831c7a11a9384, 0x3819759853987548,
           0x1893179501093489, 0x81937598aa819388, 0x1874754791888188,
           0x3eeeeeeee33111ae, 0x9013930148815808, 0xab8b914891484891,
           0x9031850931584902, 14, 15, 16);
}

//******Checking functionality with different vstart value*****//
void TEST_CASE14(void) {
  VSET(16, e64, m1);
  VLOAD_64(v7, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  write_csr(vstart, 2);
  asm volatile("vle64.v v7, (%0)" ::"r"(&ALIGNED_I64[0]));
  VSET(16, e64, m1);
  VCMP_U64(14, v7, 1, 2, 0xa11a9384a7163840, 0x99991348a9f38cd1,
           0x9fa831c7a11a9384, 0x3819759853987548, 0x1893179501093489,
           0x81937598aa819388, 0x1874754791888188, 0x3eeeeeeee33111ae,
           0x9013930148815808, 0xab8b914891484891, 0x9031850931584902,
           0x3189759837598759, 0x8319599991911111, 0x8913984898951989);
}

//****Checking functionality with different values of EMUL and
// large number of elements *******//
void TEST_CASE15(void) {
  VSET(512, e64, m8);
  asm volatile("vle64.v v8, (%0)" ::"r"(&LONG_I64[0]));
  LVCMP_U64(15, v8, LONG_I64);
}

void TEST_CASE16(void) {
  VSET(256, e64, m4);
  asm volatile("vle64.v v12, (%0)" ::"r"(&LONG_I64[0]));
  LVCMP_U64(16, v12, LONG_I64);
}

void TEST_CASE17(void) {
  VSET(128, e64, m2);
  asm volatile("vle64.v v10, (%0)" ::"r"(&LONG_I64[0]));
  LVCMP_U64(17, v10, LONG_I64);
}

void TEST_CASE18(void) {
  VSET(100, e64, m2);
  asm volatile("vle64.v v14, (%0)" ::"r"(&LONG_I64[0]));
  LVCMP_U64(18, v14, LONG_I64);
}

int main(void) {
  INIT_CHECK();
  enable_vec();

  printf("*****Running tests for vle64.v*****\n");
  TEST_CASE1();
  // TEST_CASE2();
  TEST_CASE3();
  TEST_CASE4();
  TEST_CASE5();
  TEST_CASE6();
  TEST_CASE7();
  TEST_CASE8();
  TEST_CASE9();
  TEST_CASE10();
  TEST_CASE11();
  // TEST_CASE12();
  TEST_CASE13();
  // TEST_CASE14();
  TEST_CASE15();
  TEST_CASE16();
  TEST_CASE17();
  TEST_CASE18();

  EXIT_CHECK();
}
