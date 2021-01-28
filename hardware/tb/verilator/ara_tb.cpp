#include <fstream>
#include <iostream>

#include "verilated_toplevel.h"
#include "verilator_memutil.h"
#include "verilator_sim_ctrl.h"

int main(int argc, char **argv) {
  // Create an instance of the DUT
  ara_testharness *dut = new ara_testharness;

  // Initialize lowRISC's verilator utilities
  VerilatorMemUtil memutil;
  VerilatorSimCtrl &simctrl = VerilatorSimCtrl::GetInstance();
  simctrl.SetTop(dut, &dut->clk_i, &dut->rst_ni,
                 VerilatorSimCtrlFlags::ResetPolarityNegative);

  // Initialize the DRAM
  MemAreaLoc l2_mem = {.base=0x80000000, .size=0x00080000};
  memutil.RegisterMemoryArea(
                             "ram", "TOP.ara_testharness.i_dram", 64*NR_LANES/2, &l2_mem);
  simctrl.RegisterExtension(&memutil);

  bool exit_app = false;
  int ret_code = simctrl.ParseCommandArgs(argc, argv, exit_app);
  if (exit_app) {
    return ret_code;
  }

  std::cout << "Simulation of Ara" << std::endl
            << "=================" << std::endl
            << std::endl;

  simctrl.RunSimulation();

  if (!simctrl.WasSimulationSuccessful()) {
    return 1;
  }

  return 0;
}
