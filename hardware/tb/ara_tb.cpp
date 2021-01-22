#include <stdlib.h>
#include <Vara_testharness.h>
#include <verilated.h>

int main(int argc, char **argv) {
  // Initialize Verilator variables
  Verilated::commandArgs(argc, argv);

  // Create an instance of the DUT
  Vara_testharness *dut = new Vara_testharness;

  // Reset the design
  dut->clk_i  = 0;
  dut->rst_ni = 0;

  for (int cycle = 0; cycle < 5; cycle++) {
    dut->clk_i = 1;
    dut->clk_i = 0;
  }

  dut->rst_ni = 1;

  // Tick the clock until we are done
	while((dut->exit_o & 0x1) == 0) {
		dut->clk_i = 1;
		dut->eval();
		dut->clk_i = 0;
		dut->eval();
	}

  if (dut->exit_o >> 1) {
    printf("Core Test *** FAILED *** (tohost = %0d)", dut->exit_o >> 1);
  } else {
    printf("Core Test *** SUCCESS *** (tohost = %0d)", dut->exit_o >> 1);
  }

  // Finish execution
  return dut->exit_o >> 1;
}
