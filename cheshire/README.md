## Introduction

Support for FPGA synthesis was added to Ara by integrating it into Cheshire. Since we don't want to directly add our custom compile flow into Cheshire, we use a technique called back-referencing. This method allows us to utilize Cheshire's compile flow from outside the repository. Our entry point is to generate a custom `add_sources.vcu128.tcl` file with specific Ara targets, copy this file into the Cheshire directory, and then use the default Cheshire compile flow, which will use our provided TCL file.

## How to Use

### Generate Bitstream

1.  **Navigate to the Root Directory**
    Ensure you are in the root directory where the Makefile is located.
    
2.  **Set up environment**
    Set the `BACKREF_CHS_ROOT` variable to root directory of the Cheshire repository where you want to build the bitstream.

3.  **Run the Makefile Target**:
```
make ara-chs-xilinx-all
```
This command will:
-   Generate a custom `add_sources.vcu128.tcl` file with Ara-specific targets.
-   Copy this TCL file into the Cheshire directory.
-   Start the Cheshire compile flow using the copied TCL file.

## Back-Referencing Explained

Here's how we use back-referencing in our setup:

1.  **Generate Custom TCL File**:
    
    -   We generate a custom `add_sources.vcu128.tcl` file using the `bender script vivado` command with our specific targets (`-t fpga -t cv64a6_imafdcv_sv39 -t cva6 -t vcu128 --define ARA`).
    -   This custom TCL file includes all the necessary sources and configurations required for the FPGA synthesis with Cheshire + Ara.

2.  **Copy Custom TCL File**:
    
    -   The generated custom TCL file is then copied into the Cheshire directory (`$(BACKREF_CHS_XIL_SCRIPTS)/add_sources.vcu128.tcl`).

3.  **Invoke Cheshire Compile Flow**:
    
    -   With the custom TCL file in place, we invoke the Cheshire compile flow by running `make -C $(BACKREF_CHS_ROOT) chs-xilinx-all`.
    -   The Cheshire compile flow target depends on the `add_sources.vcu128.tcl` file, and since we have provided our custom version, it will use ours for the synthesis process.

This method ensures that we can extend and customize the compile flow for our specific needs without modifying the Cheshire repository directly.
