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

void reset_vec16(volatile uint16_t *vec) {
  for (uint64_t i = 0; i < 1024; ++i)
    vec[i] = 0;
}

static volatile uint16_t ALIGNED_I16[1024] __attribute__((aligned(AXI_DWIDTH)));

//**********Checking functionality of vse16 ********//
void TEST_CASE1(void) {
  VSET(16, e16, m1);
  VLOAD_16(v0, 0x05e0, 0xbbd3, 0x3840, 0x8cd1, 0x9384, 0x7548, 0x3489, 0x9388,
           0x8188, 0x11ae, 0x5808, 0x4891, 0x4902, 0x8759, 0x1111, 0x1989);
  asm volatile("vse16.v v0, (%0)" ::"r"(ALIGNED_I16));
  VVCMP_U16(1, ALIGNED_I16, 0x05e0, 0xbbd3, 0x3840, 0x8cd1, 0x9384, 0x7548,
            0x3489, 0x9388, 0x8188, 0x11ae, 0x5808, 0x4891, 0x4902, 0x8759,
            0x1111, 0x1989);
}

//******Checking functionality of  with illegal destination register
// specifier for EMUL********//
// In this test case EMUL=2 and register is v1 which will cause illegal
// instruction exception and set mcause = 2
void TEST_CASE2(void) {
  uint8_t mcause;
  reset_vec16(ALIGNED_I16);
  VSET(16, e16, m2);
  VLOAD_16(v1, 0x05e0, 0xbbd3, 0x3840, 0x8cd1, 0x9384, 0x7548, 0x3489, 0x9388,
           0x8188, 0x11ae, 0x5808, 0x4891, 0x4902, 0x8759, 0x1111, 0x1989);
  VSET(16, e16, m2);
  asm volatile("vse16.v v1, (%0)" ::"r"(ALIGNED_I16));
  asm volatile("addi %[A], t3, 0" : [A] "=r"(mcause));
  XCMP(2, mcause, 2);
}

//*******Checking functionality of vse16 with different values of masking
// register******//
void TEST_CASE3(void) {
  reset_vec16(ALIGNED_I16);
  VSET(16, e16, m1);
  VLOAD_16(v3, 0x05e0, 0xbbd3, 0x3840, 0x8cd1, 0x9384, 0x7548, 0x3489, 0x9388,
           0x8188, 0x11ae, 0x5808, 0x4891, 0x4902, 0x8759, 0x1111, 0x1989);
  VLOAD_8(v0, 0xFF, 0xFF);
  asm volatile("vse16.v v3, (%0), v0.t" ::"r"(ALIGNED_I16));
  VCLEAR(v3);
  VVCMP_U16(3, ALIGNED_I16, 0x05e0, 0xbbd3, 0x3840, 0x8cd1, 0x9384, 0x7548,
            0x3489, 0x9388, 0x8188, 0x11ae, 0x5808, 0x4891, 0x4902, 0x8759,
            0x1111, 0x1989);
}

void TEST_CASE4(void) {
  VSET(16, e16, m1);
  VLOAD_16(v3, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  asm volatile("vse16.v v3, (%0)" ::"r"(ALIGNED_I16));
  VCLEAR(v3);
  VLOAD_16(v3, 0x05e0, 0xbbd3, 0x3840, 0x8cd1, 0x9384, 0x7548, 0x3489, 0x9388,
           0x8188, 0x11ae, 0x5808, 0x4891, 0x4902, 0x8759, 0x1111, 0x1989);
  VLOAD_8(v0, 0x00, 0x00);
  asm volatile("vse16.v v3, (%0), v0.t" ::"r"(ALIGNED_I16));
  VCLEAR(v3);
  VVCMP_U16(4, ALIGNED_I16, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
            16);
}

void TEST_CASE5(void) {
  VSET(16, e16, m1);
  VLOAD_16(v3, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  asm volatile("vse16.v v3, (%0)" ::"r"(ALIGNED_I16));
  VCLEAR(v3);
  VLOAD_16(v3, 0x05e0, 0xbbd3, 0x3840, 0x8cd1, 0x9384, 0x7548, 0x3489, 0x9388,
           0x8188, 0x11ae, 0x5808, 0x4891, 0x4902, 0x8759, 0x1111, 0x1989);
  VLOAD_8(v0, 0xAA, 0xAA);
  asm volatile("vse16.v v3, (%0), v0.t" ::"r"(ALIGNED_I16));
  VCLEAR(v3);
  VVCMP_U16(5, ALIGNED_I16, 1, 0xbbd3, 3, 0x8cd1, 5, 0x7548, 7, 0x9388, 9,
            0x11ae, 11, 0x4891, 13, 0x8759, 15, 0x1989);
}

//******Checking functionality with different combinations of vta and vma*****//
// **** It uses undisturbed policy for tail agnostic and mask agnostic****//
void TEST_CASE6(void) {
  uint64_t avl;
  VSET(16, e16, m1);
  VLOAD_16(v4, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  asm volatile("vse16.v v4, (%0)" ::"r"(ALIGNED_I16));
  VCLEAR(v4);
  VLOAD_8(v0, 0xAA, 0xAA);
  VLOAD_16(v4, 0x05e0, 0xbbd3, 0x3840, 0x8cd1, 0x9384, 0x7548, 0x3489, 0x9388,
           0x8188, 0x11ae, 0x5808, 0x4891, 0x4902, 0x8759, 0x1111, 0x1989);
  __asm__ volatile("vsetivli %[A], 12, e16, m1, ta, ma" : [A] "=r"(avl));
  asm volatile("vse16.v v4, (%0),v0.t" ::"r"(ALIGNED_I16));
  VCLEAR(v4);
  VVCMP_U16(6, ALIGNED_I16, 1, 0xbbd3, 3, 0x8cd1, 5, 0x7548, 7, 0x9388, 9,
            0x11ae, 11, 0x4891, 13, 14, 15, 16);
}

void TEST_CASE7(void) {
  reset_vec16(ALIGNED_I16);
  uint64_t avl;
  VSET(16, e16, m1);
  VLOAD_16(v4, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  asm volatile("vse16.v v4, (%0)" ::"r"(ALIGNED_I16));
  VCLEAR(v4);
  VLOAD_8(v0, 0xAA, 0xAA);
  VLOAD_16(v4, 0x05e0, 0xbbd3, 0x3840, 0x8cd1, 0x9384, 0x7548, 0x3489, 0x9388,
           0x8188, 0x11ae, 0x5808, 0x4891, 0x4902, 0x8759, 0x1111, 0x1989);
  __asm__ volatile("vsetivli %[A], 12, e16, m1, ta, mu" : [A] "=r"(avl));
  asm volatile("vse16.v v4, (%0), v0.t" ::"r"(ALIGNED_I16));
  VCLEAR(v4);
  VVCMP_U16(7, ALIGNED_I16, 1, 0xbbd3, 3, 0x8cd1, 5, 0x7548, 7, 0x9388, 9,
            0x11ae, 11, 0x4891, 13, 14, 15, 16);
}

void TEST_CASE8(void) {
  reset_vec16(ALIGNED_I16);
  uint64_t avl;
  VSET(16, e8, m1);
  VLOAD_16(v4, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  asm volatile("vse16.v v4, (%0)" ::"r"(ALIGNED_I16));
  VCLEAR(v4);
  VLOAD_8(v0, 0xAA, 0xAA);
  VLOAD_16(v4, 0x05e0, 0xbbd3, 0x3840, 0x8cd1, 0x9384, 0x7548, 0x3489, 0x9388,
           0x8188, 0x11ae, 0x5808, 0x4891, 0x4902, 0x8759, 0x1111, 0x1989);
  __asm__ volatile("vsetivli %[A], 12, e16, m1, tu, ma" : [A] "=r"(avl));
  asm volatile("vse16.v v4, (%0), v0.t" ::"r"(ALIGNED_I16));
  VCLEAR(v4);
  VVCMP_U16(8, ALIGNED_I16, 1, 0xbbd3, 3, 0x8cd1, 5, 0x7548, 7, 0x9388, 9,
            0x11ae, 11, 0x4891, 13, 14, 15, 16);
}

void TEST_CASE9(void) {
  uint64_t avl;
  VSET(16, e8, m1);
  VLOAD_16(v4, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  asm volatile("vse16.v v4, (%0)" ::"r"(ALIGNED_I16));
  VCLEAR(v4);
  VLOAD_8(v0, 0xAA, 0xAA);
  VLOAD_16(v4, 0x05e0, 0xbbd3, 0x3840, 0x8cd1, 0x9384, 0x7548, 0x3489, 0x9388,
           0x8188, 0x11ae, 0x5808, 0x4891, 0x4902, 0x8759, 0x1111, 0x1989);
  __asm__ volatile("vsetivli %[A], 12, e16, m1, tu, mu" : [A] "=r"(avl));
  asm volatile("vse16.v v4, (%0), v0.t" ::"r"(ALIGNED_I16));
  VCLEAR(v4);
  VVCMP_U16(9, ALIGNED_I16, 1, 0xbbd3, 3, 0x8cd1, 5, 0x7548, 7, 0x9388, 9,
            0x11ae, 11, 0x4891, 13, 14, 15, 16);
}

//*******Checking functionality if encoded EEW is not supported for given SEW
// and LMUL values because EMUL become out of range*****//
// This test case cover corner case for EEW = 16.If LMUL is changed to
// mf8 it will give error because emul become less than 1/8 (EMUL = 1/16)
// But it does not support this configuration because SEW/LMUL > ELEN
void TEST_CASE10(void) {
  VSET(16, e16, m1);
  VLOAD_16(v5, 0x05e0, 0xbbd3, 0x3840, 0x8cd1, 0x9384, 0x7548, 0x3489, 0x9388,
           0x8188, 0x11ae, 0x5808, 0x4891, 0x4902, 0x8759, 0x1111, 0x1989);
  VSET(16, e32, mf2);
  asm volatile("vse16.v v5, (%0)" ::"r"(ALIGNED_I16));
  VCLEAR(v5);
  VVCMP_U16(10, ALIGNED_I16, 0x05e0, 0xbbd3, 0x3840, 0x8cd1, 0x9384, 0x7548,
            0x3489, 0x9388, 0x8188, 0x11ae, 0x5808, 0x4891, 0x4902, 0x8759,
            0x1111, 0x1989);
}

// This test case execute upper bound case of EMUL (8)
// If LMUL is changed to m8 it will give error because emul become greater than
// 8 (EMUL = 16)
void TEST_CASE11(void) {
  reset_vec16(ALIGNED_I16);
  VSET(16, e16, m1);
  VLOAD_16(v8, 0x05e0, 0xbbd3, 0x3840, 0x8cd1, 0x9384, 0x7548, 0x3489, 0x9388,
           0x8188, 0x11ae, 0x5808, 0x4891, 0x4902, 0x8759, 0x1111, 0x1989);
  VSET(16, e8, m4);
  asm volatile("vse16.v v8, (%0)" ::"r"(ALIGNED_I16));
  VCLEAR(v8);
  VVCMP_U16(11, ALIGNED_I16, 0x05e0, 0xbbd3, 0x3840, 0x8cd1, 0x9384, 0x7548,
            0x3489, 0x9388, 0x8188, 0x11ae, 0x5808, 0x4891, 0x4902, 0x8759,
            0x1111, 0x1989);
}

//******Checking functionality with different values of vl******//
void TEST_CASE12(void) {
  reset_vec16(ALIGNED_I16);
  VSET(16, e16, m1);
  VLOAD_16(v6, 0x05e0, 0xbbd3, 0x3840, 0x8cd1, 0x9384, 0x7548, 0x3489, 0x9388,
           0x8188, 0x11ae, 0x5808, 0x4891, 0x4902, 0x8759, 0x1111, 0x1989);
  asm volatile("vse16.v v6, (%0)" ::"r"(ALIGNED_I16));
  VCLEAR(v6);
  VVCMP_U16(12, ALIGNED_I16, 0x05e0, 0xbbd3, 0x3840, 0x8cd1, 0x9384, 0x7548,
            0x3489, 0x9388, 0x8188, 0x11ae, 0x5808, 0x4891, 0x4902, 0x8759,
            0x1111, 0x1989);
}

void TEST_CASE13(void) {
  uint64_t avl;
  VSET(16, e8, m1);
  VLOAD_16(v6, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  asm volatile("vse16.v v6, (%0)" ::"r"(ALIGNED_I16));
  VCLEAR(v6);
  VLOAD_16(v6, 0xe0, 0xd3, 0x40, 0xd1, 0x84, 0x48, 0x89, 0x88, 0x88, 0xae, 0x08,
           0x91, 0x02, 0x59, 0x11, 0x89);
  __asm__ volatile("vsetivli %[A], 0, e8, m1, tu, ma" : [A] "=r"(avl));
  asm volatile("vse16.v v6, (%0)" ::"r"(ALIGNED_I16));
  VSET(16, e16, m1);
  VVCMP_U16(13, ALIGNED_I16, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
            16);
}

void TEST_CASE14(void) {
  VSET(16, e16, m1);
  VLOAD_16(v6, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  asm volatile("vse16.v v6, (%0)" ::"r"(ALIGNED_I16));
  VCLEAR(v6);
  VLOAD_16(v6, 0x05e0, 0xbbd3, 0x3840, 0x8cd1, 0x9384, 0x7548, 0x3489, 0x9388,
           0x8188, 0x11ae, 0x5808, 0x4891, 0x4902, 0x8759, 0x1111, 0x1989);
  VSET(13, e8, m1);
  asm volatile("vse16.v v6, (%0)" ::"r"(ALIGNED_I16));
  VVCMP_U16(14, ALIGNED_I16, 0x05e0, 0xbbd3, 0x3840, 0x8cd1, 0x9384, 0x7548,
            0x3489, 0x9388, 0x8188, 0x11ae, 0x5808, 0x4891, 0x4902, 14, 15, 16);
}

//******Checking functionality with different vstart value*****//
void TEST_CASE15(void) {
  VSET(16, e16, m1);
  VLOAD_16(v7, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
  asm volatile("vse16.v v7, (%0)" ::"r"(ALIGNED_I16));
  VCLEAR(v7);
  VLOAD_16(v7, 0x05e0, 0xbbd3, 0x3840, 0x8cd1, 0x9384, 0x7548, 0x3489, 0x9388,
           0x8188, 0x11ae, 0x5808, 0x4891, 0x4902, 0x8759, 0x1111, 0x1989);
  VSET(13, e16, m1);
  write_csr(vstart, 2);
  asm volatile("vse16.v v7, (%0)" ::"r"(ALIGNED_I16));
  VVCMP_U16(15, ALIGNED_I16, 1, 2, 0x3840, 0x8cd1, 0x9384, 0x7548, 0x3489,
            0x9388, 0x8188, 0x11ae, 0x5808, 0x4891, 0x4902, 14, 15, 16);
}

//****Checking functionality with different values of EMUL and
// large number of elements *******//
void TEST_CASE16(void) {
  reset_vec16(ALIGNED_I16);
  VSET(1024, e16, m4);
  asm volatile("vle16.v v8, (%0)" ::"r"(&LONG_I16[0]));
  asm volatile("vse16.v v8, (%0)" ::"r"(ALIGNED_I16));
  LVVCMP_U16(16, ALIGNED_I16, LONG_I16);
}

void TEST_CASE17(void) {
  reset_vec16(ALIGNED_I16);
  VSET(512, e16, m2);
  asm volatile("vle16.v v10, (%0)" ::"r"(&LONG_I16[0]));
  asm volatile("vse16.v v10, (%0)" ::"r"(ALIGNED_I16));
  LVVCMP_U16(17, ALIGNED_I16, LONG_I16);
}

void TEST_CASE18(void) {
  reset_vec16(ALIGNED_I16);
  VSET(300, e16, m2);
  asm volatile("vle16.v v10, (%0)" ::"r"(&LONG_I16[0]));
  asm volatile("vse16.v v10, (%0)" ::"r"(ALIGNED_I16));
  LVVCMP_U16(18, ALIGNED_I16, LONG_I16);
}

int main(void) {
  INIT_CHECK();
  enable_vec();

  printf("*****Running tests for vse16.v*****\n");
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

  EXIT_CHECK();
}
