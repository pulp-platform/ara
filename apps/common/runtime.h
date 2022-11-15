#ifndef _RUNTIME_H_
#define _RUNTIME_H_

#include <stdint.h>

#define FOREVER   1000000000
#define LONG_TIME 2000

#ifndef NR_CORES
#define NR_CORES 4
#define LOG_NR_CORES 2
#endif

uint8_t global_sync_idx[NR_CORES];
volatile uint64_t sync_reg_wait;
volatile uint64_t sync_reg_go;

#define ENABLE_VEC                                                             \
  asm volatile(                                                                \
      "csrs mstatus, %[bits];" ::[bits] "r"(0x00000600 & (0x00000600 >> 1)))

extern int64_t event_trigger;
extern int64_t timer;
// SoC-level CSR
extern uint64_t hw_cnt_en_reg;

// Return the current value of the cycle counter
inline int64_t get_cycle_count() {
  int64_t cycle_count;
  // The fence is needed to be sure that Ara is idle, and it is not performing
  // the last vector stores when we read mcycle with stop_timer()
  asm volatile("fence; csrr %[cycle_count], cycle"
               : [cycle_count] "=r"(cycle_count));
  return cycle_count;
};

/// Obtain the ID of the current core.
static inline uint64_t get_core_id() {
  uint64_t r;
  asm volatile("csrr %0, mhartid" : "=r"(r));
  return r;
}

static inline void wait_forever() {
  for (uint64_t i = 0; i < FOREVER; ++i) asm volatile ("nop");
}

static inline void wait_long_time() {
  for (uint64_t i = 0; i < LONG_TIME; ++i) asm volatile ("nop");
}

// The maximum sync in a program depends on the width
// of the sync_reg_go
static inline void primitive_synch(int core_id) {
  volatile uint8_t volatile *sync_reg_wait_byte_ptr = &sync_reg_wait;
  int go = 0;
  // Current sync idx
  uint8_t idx = global_sync_idx[core_id];

  // Write the sync wait register at the correct index
  // This means that this core has arrived to the sync point
  sync_reg_wait_byte_ptr[core_id] = 1;

  if (!core_id) {
    // Poll until all the cores have reached the sync point
    while (!go) {
      go = 1;
      for (uint64_t i; i < NR_CORES; ++i) {
        go &= sync_reg_wait_byte_ptr[i];
      }
    }
    // All the cores are at the sync point!
    // Clear the sync wait reg flags
    *(&sync_reg_wait) = 0;
    // Write the go flag
    *(&sync_reg_go) = 1 << idx;
  } else {
    // Just wait until all the cores reach the sync point
    while (!go) {
      go = (sync_reg_go >> idx) && 0x1;
    }
  }

  // Throw away the previous "go flag"
  // Increment the private sync ID
  global_sync_idx[core_id]++;
}

#ifndef SPIKE
// Enable and disable the hw-counter
// Until the HW counter is not enabled, it will not start
// counting even if a vector instruction is dispatched
// Enabling the HW counter does NOT mean that the hardware
// will start counting, but simply that it will be able to start.
#define HW_CNT_READY hw_cnt_en_reg = 1;
#define HW_CNT_NOT_READY hw_cnt_en_reg = 0;
// Start and stop the counter
inline void start_timer() { timer = -get_cycle_count(); }
inline void stop_timer() { timer += get_cycle_count(); }

// Get the value of the timer
inline int64_t get_timer() { return timer; }
#else
#define HW_CNT_READY ;
#define HW_CNT_NOT_READY ;
// Start and stop the counter
inline void start_timer() {
  while (0)
    ;
}
inline void stop_timer() {
  while (0)
    ;
}

// Get the value of the timer
inline int64_t get_timer() { return 0; }
#endif

#endif // _RUNTIME_H_
