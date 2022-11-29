// TODO uncomment TEST_CASE13 and TEST_CASE 15 after issue of vl=0 and
// non-zero vstart is resolved
// TODO uncomment TEST_CASE2 after issue of exception is resolved
#include "long_array.h"
#include "vector_macros.h"
#define AXI_DWIDTH 128
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

void reset_vec32(volatile uint32_t *vec) {
  for (uint64_t i = 0; i < 1024; ++i)
    vec[i] = 0;
}

static volatile uint32_t ALIGNED_I32[1024] __attribute__((aligned(AXI_DWIDTH)));

//**********Checking functionality of vse32********//
void TEST_CASE1(void) {
  VSET(16, e32, m1);
  VLOAD_32(v0, 0x9fe41920, 0xf9aa71f0, 0xa11a9384, 0x99991348, 0x9fa831c7,
           0x38197598, 0x18931795, 0x81937598, 0x18747547, 0x3eeeeeee,
           0x90139301, 0xab8b9148, 0x90318509, 0x31897598, 0x83195999,
           0x89139848);
  asm volatile("vse32.v v0, (%0)" ::"r"(ALIGNED_I32));
  VVCMP_U32(1, ALIGNED_I32, 0x9fe41920, 0xf9aa71f0, 0xa11a9384, 0x99991348,
            0x9fa831c7, 0x38197598, 0x18931795, 0x81937598, 0x18747547,
            0x3eeeeeee, 0x90139301, 0xab8b9148, 0x90318509, 0x31897598,
            0x83195999, 0x89139848);
}

//******Checking functionality of  with illegal destination register
// specifier for EMUL********//
// In this test case EMUL=2 and register is v1 which will cause illegal
// instruction exception and set mcause = 2
void TEST_CASE2(void) {
  uint8_t mcause;
  reset_vec32(ALIGNED_I32);
  VSET(16, e32, m1);
  VLOAD_32(v1, 0x9fe41920, 0xf9aa71f0, 0xa11a9384, 0x99991348, 0x9fa831c7,
           0x38197598, 0x18931795, 0x81937598, 0x18747547, 0x3eeeeeee,
           0x90139301, 0xab8b9148, 0x90318509, 0x31897598, 0x83195999,
           0x89139848);
  VSET(16, e64, m4);
  asm volatile("vse32.v v1, (%0)" ::"r"(ALIGNED_I32));
  asm volatile("addi %[A], t3, 0" : [A] "=r"(mcause));
  XCMP(2, mcause, 2);
}

//*******Checking functionality of vse16 with different values of masking
// register******//
void TEST_CASE3(void) {
  reset_vec32(ALIGNED_I32);
  VSET(16, e32, m1);
  VLOAD_32(v3, 0x9fe41920, 0xf9aa71f0, 0xa11a9384, 0x99991348, 0x9fa831c7,
           0x38197598, 0x18931795, 0x81937598, 0x18747547, 0x3eeeeeee,
           0x90139301, 0xab8b9148, 0x90318509, 0x31897598, 0x83195999,
           0x89139848);
  VLOAD_8(v0, 0xFF, 0xFF);
  asm volatile("vse32.v v3, (%0), v0.t" ::"r"(ALIGNED_I32));
  VCLEAR(v3);
  VVCMP_U32(3, ALIGNED_I32, 0x9fe41920, 0xf9aa71f0, 0xa11a9384, 0x99991348,
            0x9fa831c7, 0x38197598, 0x18931795, 0x81937598, 0x18747547,
            0x3eeeeeee, 0x90139301, 0xab8b9148, 0x90318509, 0x31897598,
            0x83195999, 0x89139848);
}

void TEST_CASE4(void) {
  VSET(16, e32, m1);
  VLOAD_32(v3, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  asm volatile("vse32.v v3, (%0)" ::"r"(ALIGNED_I32));
  VCLEAR(v3);
  VLOAD_32(v3, 0x9fe41920, 0xf9aa71f0, 0xa11a9384, 0x99991348, 0x9fa831c7,
           0x38197598, 0x18931795, 0x81937598, 0x18747547, 0x3eeeeeee,
           0x90139301, 0xab8b9148, 0x90318509, 0x31897598, 0x83195999,
           0x89139848);
  VLOAD_8(v0, 0x00, 0x00);
  asm volatile("vse32.v v3, (%0), v0.t" ::"r"(ALIGNED_I32));
  VCLEAR(v3);
  VVCMP_U32(4, ALIGNED_I32, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
            16);
}

void TEST_CASE5(void) {
  VSET(16, e32, m1);
  VLOAD_32(v3, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  asm volatile("vse32.v v3, (%0)" ::"r"(ALIGNED_I32));
  VCLEAR(v3);
  VLOAD_32(v3, 0x9fe41920, 0xf9aa71f0, 0xa11a9384, 0x99991348, 0x9fa831c7,
           0x38197598, 0x18931795, 0x81937598, 0x18747547, 0x3eeeeeee,
           0x90139301, 0xab8b9148, 0x90318509, 0x31897598, 0x83195999,
           0x89139848);
  VLOAD_8(v0, 0xAA, 0xAA);
  asm volatile("vse32.v v3, (%0), v0.t" ::"r"(ALIGNED_I32));
  VCLEAR(v3);
  VVCMP_U32(5, ALIGNED_I32, 1, 0xf9aa71f0, 3, 0x99991348, 5, 0x38197598, 7,
            0x81937598, 9, 0x3eeeeeee, 11, 0xab8b9148, 13, 0x31897598, 15,
            0x89139848);
}

//******Checking functionality with different combinations of vta and vma*****//
// **** It uses undisturbed policy for tail agnostic and mask agnostic****//
void TEST_CASE6(void) {
  reset_vec32(ALIGNED_I32);
  uint64_t avl;
  VSET(16, e32, m1);
  VLOAD_32(v4, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  asm volatile("vse32.v v4, (%0)" ::"r"(ALIGNED_I32));
  VCLEAR(v4);
  VLOAD_8(v0, 0xAA, 0xAA);
  VLOAD_32(v4, 0x9fe41920, 0xf9aa71f0, 0xa11a9384, 0x99991348, 0x9fa831c7,
           0x38197598, 0x18931795, 0x81937598, 0x18747547, 0x3eeeeeee,
           0x90139301, 0xab8b9148, 0x90318509, 0x31897598, 0x83195999,
           0x89139848);
  __asm__ volatile("vsetivli %[A], 12, e32, m1, ta, ma" : [A] "=r"(avl));
  asm volatile("vse32.v v4, (%0),v0.t" ::"r"(ALIGNED_I32));
  VCLEAR(v4);
  VVCMP_U32(6, ALIGNED_I32, 1, 0xf9aa71f0, 3, 0x99991348, 5, 0x38197598, 7,
            0x81937598, 9, 0x3eeeeeee, 11, 0xab8b9148, 13, 14, 15, 16);
}

void TEST_CASE7(void) {
  reset_vec32(ALIGNED_I32);
  uint64_t avl;
  VSET(16, e32, m1);
  VLOAD_32(v4, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  asm volatile("vse32.v v4, (%0)" ::"r"(ALIGNED_I32));
  VCLEAR(v4);
  VLOAD_8(v0, 0xAA, 0xAA);
  VLOAD_32(v4, 0x9fe41920, 0xf9aa71f0, 0xa11a9384, 0x99991348, 0x9fa831c7,
           0x38197598, 0x18931795, 0x81937598, 0x18747547, 0x3eeeeeee,
           0x90139301, 0xab8b9148, 0x90318509, 0x31897598, 0x83195999,
           0x89139848);
  __asm__ volatile("vsetivli %[A], 12, e32, m1, ta, mu" : [A] "=r"(avl));
  asm volatile("vse32.v v4, (%0), v0.t" ::"r"(ALIGNED_I32));
  VCLEAR(v4);
  VVCMP_U32(7, ALIGNED_I32, 1, 0xf9aa71f0, 3, 0x99991348, 5, 0x38197598, 7,
            0x81937598, 9, 0x3eeeeeee, 11, 0xab8b9148, 13, 14, 15, 16);
}

void TEST_CASE8(void) {
  reset_vec32(ALIGNED_I32);
  uint64_t avl;
  VSET(16, e32, m1);
  VLOAD_32(v4, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  asm volatile("vse32.v v4, (%0)" ::"r"(ALIGNED_I32));
  VCLEAR(v4);
  VLOAD_8(v0, 0xAA, 0xAA);
  VLOAD_32(v4, 0x9fe41920, 0xf9aa71f0, 0xa11a9384, 0x99991348, 0x9fa831c7,
           0x38197598, 0x18931795, 0x81937598, 0x18747547, 0x3eeeeeee,
           0x90139301, 0xab8b9148, 0x90318509, 0x31897598, 0x83195999,
           0x89139848);
  __asm__ volatile("vsetivli %[A], 12, e32, m1, tu, ma" : [A] "=r"(avl));
  asm volatile("vse32.v v4, (%0), v0.t" ::"r"(ALIGNED_I32));
  VCLEAR(v4);
  VVCMP_U32(8, ALIGNED_I32, 1, 0xf9aa71f0, 3, 0x99991348, 5, 0x38197598, 7,
            0x81937598, 9, 0x3eeeeeee, 11, 0xab8b9148, 13, 14, 15, 16);
}

void TEST_CASE9(void) {
  reset_vec32(ALIGNED_I32);
  uint64_t avl;
  VSET(16, e32, m1);
  VLOAD_32(v4, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  asm volatile("vse32.v v4, (%0)" ::"r"(ALIGNED_I32));
  VCLEAR(v4);
  VLOAD_8(v0, 0xAA, 0xAA);
  VLOAD_32(v4, 0x9fe41920, 0xf9aa71f0, 0xa11a9384, 0x99991348, 0x9fa831c7,
           0x38197598, 0x18931795, 0x81937598, 0x18747547, 0x3eeeeeee,
           0x90139301, 0xab8b9148, 0x90318509, 0x31897598, 0x83195999,
           0x89139848);
  __asm__ volatile("vsetivli %[A], 12, e16, m1, tu, mu" : [A] "=r"(avl));
  asm volatile("vse32.v v4, (%0), v0.t" ::"r"(ALIGNED_I32));
  VCLEAR(v4);
  VVCMP_U32(9, ALIGNED_I32, 1, 0xf9aa71f0, 3, 0x99991348, 5, 0x38197598, 7,
            0x81937598, 9, 0x3eeeeeee, 11, 0xab8b9148, 13, 14, 15, 16);
}

//*******Checking functionality if encoded EEW is not supported for given SEW
// and LMUL values because EMUL become out of range*****//
// This test case cover corner case for EEW = 32.If LMUL is changed to
// mf8 and SEW is changed to e64 it will give error because emul become less
// than 1/8 (EMUL = 1/16) But it does not support this configuration because
// SEW/LMUL > ELEN
void TEST_CASE10(void) {
  reset_vec32(ALIGNED_I32);
  VSET(16, e32, m1);
  VLOAD_32(v5, 0x9fe41920, 0xf9aa71f0, 0xa11a9384, 0x99991348, 0x9fa831c7,
           0x38197598, 0x18931795, 0x81937598, 0x18747547, 0x3eeeeeee,
           0x90139301, 0xab8b9148, 0x90318509, 0x31897598, 0x83195999,
           0x89139848);
  VSET(16, e32, mf2);
  asm volatile("vse32.v v5, (%0)" ::"r"(ALIGNED_I32));
  VCLEAR(v5);
  VVCMP_U32(10, ALIGNED_I32, 0x9fe41920, 0xf9aa71f0, 0xa11a9384, 0x99991348,
            0x9fa831c7, 0x38197598, 0x18931795, 0x81937598, 0x18747547,
            0x3eeeeeee, 0x90139301, 0xab8b9148, 0x90318509, 0x31897598,
            0x83195999, 0x89139848);
}

// This test case execute upper bound case of EMUL (8)
// If LMUL is changed to m8 it will give error because emul become greater than
// 8 (EMUL = 16)
void TEST_CASE11(void) {
  reset_vec32(ALIGNED_I32);
  VSET(16, e32, m1);
  VLOAD_32(v8, 0x9fe41920, 0xf9aa71f0, 0xa11a9384, 0x99991348, 0x9fa831c7,
           0x38197598, 0x18931795, 0x81937598, 0x18747547, 0x3eeeeeee,
           0x90139301, 0xab8b9148, 0x90318509, 0x31897598, 0x83195999,
           0x89139848);
  VSET(16, e8, m2);
  asm volatile("vse32.v v8, (%0)" ::"r"(ALIGNED_I32));
  VCLEAR(v8);
  VVCMP_U32(11, ALIGNED_I32, 0x9fe41920, 0xf9aa71f0, 0xa11a9384, 0x99991348,
            0x9fa831c7, 0x38197598, 0x18931795, 0x81937598, 0x18747547,
            0x3eeeeeee, 0x90139301, 0xab8b9148, 0x90318509, 0x31897598,
            0x83195999, 0x89139848);
}

//******Checking functionality with different values of vl******//
void TEST_CASE12(void) {
  reset_vec32(ALIGNED_I32);
  VSET(16, e32, m1);
  VLOAD_32(v6, 0x9fe41920, 0xf9aa71f0, 0xa11a9384, 0x99991348, 0x9fa831c7,
           0x38197598, 0x18931795, 0x81937598, 0x18747547, 0x3eeeeeee,
           0x90139301, 0xab8b9148, 0x90318509, 0x31897598, 0x83195999,
           0x89139848);
  asm volatile("vse32.v v6, (%0)" ::"r"(ALIGNED_I32));
  VCLEAR(v6);
  VVCMP_U32(12, ALIGNED_I32, 0x9fe41920, 0xf9aa71f0, 0xa11a9384, 0x99991348,
            0x9fa831c7, 0x38197598, 0x18931795, 0x81937598, 0x18747547,
            0x3eeeeeee, 0x90139301, 0xab8b9148, 0x90318509, 0x31897598,
            0x83195999, 0x89139848);
}

void TEST_CASE13(void) {
  uint64_t avl;
  VSET(16, e32, m1);
  VLOAD_32(v6, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  asm volatile("vse32.v v6, (%0)" ::"r"(ALIGNED_I32));
  VCLEAR(v6);
  VLOAD_32(v6, 0x9fe41920, 0xf9aa71f0, 0xa11a9384, 0x99991348, 0x9fa831c7,
           0x38197598, 0x18931795, 0x81937598, 0x18747547, 0x3eeeeeee,
           0x90139301, 0xab8b9148, 0x90318509, 0x31897598, 0x83195999,
           0x89139848);
  __asm__ volatile("vsetivli %[A], 0, e32, m1, tu, ma" : [A] "=r"(avl));
  asm volatile("vse32.v v6, (%0)" ::"r"(ALIGNED_I32));
  VSET(16, e32, m1);
  VVCMP_U32(13, ALIGNED_I32, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
            16);
}

void TEST_CASE14(void) {
  VSET(16, e32, m1);
  VLOAD_32(v6, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  asm volatile("vse32.v v6, (%0)" ::"r"(ALIGNED_I32));
  VCLEAR(v6);
  VLOAD_32(v6, 0x9fe41920, 0xf9aa71f0, 0xa11a9384, 0x99991348, 0x9fa831c7,
           0x38197598, 0x18931795, 0x81937598, 0x18747547, 0x3eeeeeee,
           0x90139301, 0xab8b9148, 0x90318509, 0x31897598, 0x83195999,
           0x89139848);
  VSET(13, e32, m1);
  asm volatile("vse32.v v6, (%0)" ::"r"(ALIGNED_I32));
  VSET(16, e32, m1);
  VVCMP_U32(14, ALIGNED_I32, 0x9fe41920, 0xf9aa71f0, 0xa11a9384, 0x99991348,
            0x9fa831c7, 0x38197598, 0x18931795, 0x81937598, 0x18747547,
            0x3eeeeeee, 0x90139301, 0xab8b9148, 0x90318509, 14, 15, 16);
}

//******Checking functionality with different vstart value*****//
void TEST_CASE15(void) {
  reset_vec32(ALIGNED_I32);
  VSET(16, e32, m1);
  VLOAD_32(v7, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  asm volatile("vse32.v v7, (%0)" ::"r"(ALIGNED_I32));
  VCLEAR(v7);
  VLOAD_32(v7, 0x9fe41920, 0xf9aa71f0, 0xa11a9384, 0x99991348, 0x9fa831c7,
           0x38197598, 0x18931795, 0x81937598, 0x18747547, 0x3eeeeeee,
           0x90139301, 0xab8b9148, 0x90318509, 0x31897598, 0x83195999,
           0x89139848);
  VSET(13, e32, m1);
  write_csr(vstart, 2);
  asm volatile("vse32.v v7, (%0)" ::"r"(ALIGNED_I32));
  VVCMP_U32(15, ALIGNED_I32, 1, 2, 0xa11a9384, 0x99991348, 0x9fa831c7,
            0x38197598, 0x18931795, 0x81937598, 0x18747547, 0x3eeeeeee,
            0x90139301, 0xab8b9148, 0x90318509, 14, 15, 16);
}

//****Checking functionality with different values of EMUL and
// large number of elements *******//
void TEST_CASE16(void) {
  reset_vec32(ALIGNED_I32);
  VSET(1024, e32, m8);
  asm volatile("vle32.v v8, (%0)" ::"r"(&LONG_I32[0]));
  asm volatile("vse32.v v8, (%0)" ::"r"(ALIGNED_I32));
  LVVCMP_U32(16, ALIGNED_I32, LONG_I32);
}

void TEST_CASE17(void) {
  reset_vec32(ALIGNED_I32);
  VSET(512, e32, m4);
  asm volatile("vle32.v v12, (%0)" ::"r"(&LONG_I32[0]));
  asm volatile("vse32.v v12, (%0)" ::"r"(ALIGNED_I32));
  LVVCMP_U32(17, ALIGNED_I32, LONG_I32);
}

void TEST_CASE18(void) {
  reset_vec32(ALIGNED_I32);
  VSET(256, e32, m2);
  asm volatile("vle32.v v10, (%0)" ::"r"(&LONG_I32[0]));
  asm volatile("vse32.v v10, (%0)" ::"r"(ALIGNED_I32));
  LVVCMP_U32(18, ALIGNED_I32, LONG_I32);
}

void TEST_CASE19(void) {
  reset_vec32(ALIGNED_I32);
  VSET(200, e32, m2);
  asm volatile("vle32.v v8, (%0)" ::"r"(&LONG_I32[0]));
  asm volatile("vse32.v v8, (%0)" ::"r"(ALIGNED_I32));
  LVVCMP_U32(19, ALIGNED_I32, LONG_I32);
}

int main(void) {
  INIT_CHECK();
  enable_vec();

  printf("*****Running tests for vse32.v*****\n");
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
  TEST_CASE12();
  // TEST_CASE13();
  TEST_CASE14();
  // TEST_CASE15();
  TEST_CASE16();
  TEST_CASE17();
  TEST_CASE18();
  TEST_CASE19();

  EXIT_CHECK();
}
