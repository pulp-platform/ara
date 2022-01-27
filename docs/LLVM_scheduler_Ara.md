# LLVM Scheduler for Ara

Thanks to Michael Platzer (https://github.com/michael-platzer, https://github.com/vproc/vicuna) for the precious information.

An LLVM instruction scheduler crafted on Ara can help in generating
performant code when using intrinsics, without the need for coding
in assembly.
This is a work in progress.

Getting familiar with the topic:
https://llvm.org/devmtg/2014-10/Slides/Estes-MISchedulerTutorial.pdf
https://llvm.org/devmtg/2016-09/slides/Absar-SchedulingInOrder.pdf

LLVM scheduling definitions for RVV instructions:
https://github.com/llvm/llvm-project/blob/main/llvm/lib/Target/RISCV/RISCVScheduleV.td

Example with Rocket:
https://github.com/llvm/llvm-project/blob/main/llvm/lib/Target/RISCV/RISCVSchedRocket.td
