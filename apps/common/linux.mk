IS_LINUX_EXTENSION := .linux

CVA6_SDK ?= /usr/scratch/fenga3/vmaisto/cva6-sdk_fork_backup
ROOTFS_DEST ?= $(CVA6_SDK)/rootfs/ara/apps/bin
cp_to_rootfs: 
	mkdir -p $(ROOTFS_DEST)
	@echo "[Copying binaries to rootfs directory $(ROOTFS_DEST)]"
	cp -v bin/*.linux $(ROOTFS_DEST)

# Set the runtime variables to empty, the Linux libs will takcare of that 
LD_FLAGS     := 
RUNTIME_GCC   ?= common/util-gcc.c.o
RUNTIME_LLVM  ?= common/util-llvm.c.o


# Override
INSTALL_DIR             ?= $(ARA_DIR)/install
GCC_INSTALL_DIR         ?= $(CVA6_SDK)/buildroot/output/host/
LLVM_INSTALL_DIR        ?= $(INSTALL_DIR)/riscv-llvm

RISCV_XLEN    ?= 64
RISCV_ARCH    ?= rv$(RISCV_XLEN)gcv
RISCV_ABI     ?= lp64d
RISCV_TARGET  ?= riscv$(RISCV_XLEN)-buildroot-linux-gnu-

# Don't use LLVM
RISCV_PREFIX  ?= $(GCC_INSTALL_DIR)/bin/$(RISCV_TARGET)
RISCV_CC      ?= $(RISCV_PREFIX)gcc
RISCV_CXX     ?= $(RISCV_PREFIX)g++
RISCV_OBJDUMP ?= $(RISCV_PREFIX)objdump
RISCV_OBJCOPY ?= $(RISCV_PREFIX)objcopy
RISCV_AS      ?= $(RISCV_PREFIX)as
RISCV_AR      ?= $(RISCV_PREFIX)ar
RISCV_LD      ?= $(RISCV_PREFIX)ld
RISCV_STRIP   ?= $(RISCV_PREFIX)strip

# Override flags
# LLVM_FLAGS     ?= -march=rv64gcv_zfh_zvfh0p1 -mabi=$(RISCV_ABI) -mno-relax -fuse-ld=lld
LLVM_FLAGS     ?= -march=rv64gcv -mabi=$(RISCV_ABI)
LLVM_V_FLAGS   ?= #+no-optimized-zero-stride-load
# RISCV_FLAGS    ?= $(LLVM_FLAGS) $(LLVM_V_FLAGS) -mcmodel=medany -I$(CURDIR)/common -std=gnu99 -O3 -ffast-math -fno-common -fno-builtin-printf $(DEFINES) $(RISCV_WARNINGS)
RISCV_FLAGS    ?= -g $(LLVM_FLAGS) $(LLVM_V_FLAGS) -I$(CURDIR)/common -std=gnu99 -O0 $(DEFINES) $(RISCV_WARNINGS)
RISCV_CCFLAGS  ?= $(RISCV_FLAGS) #-ffunction-sections -fdata-sections
RISCV_CXXFLAGS ?= $(RISCV_FLAGS) -ffunction-sections -fdata-sections
RISCV_LDFLAGS  ?= #-static -nostartfiles -lm -Wl,--gc-sections

RISCV_OBJDUMP_FLAGS ?= -S
