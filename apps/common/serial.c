#include <stdint.h>

extern char fake_uart;

void _putchar(char character) {
  // send char to console
  fake_uart = character;
}