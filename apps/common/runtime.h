#ifndef _RUNTIME_H_
#define _RUNTIME_H_

#include <stdint.h>

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
