#ifndef _RUNTIME_H_
#define _RUNTIME_H_

#include <stdint.h>

extern int64_t timer;

// Return the current value of the cycle counter
inline int64_t get_cycle_count() {
  int64_t cycle_count;
  asm volatile("csrr %[cycle_count], cycle" : [cycle_count] "=r"(cycle_count));
  return cycle_count;
};

// Start and stop the counter
inline void start_timer() { timer = -get_cycle_count(); }
inline void stop_timer() { timer += get_cycle_count(); }

// Get the value of the timer
inline int64_t get_timer() { return timer; }

#endif // _RUNTIME_H_
