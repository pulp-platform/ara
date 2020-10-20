# AXI to APB bridge

This is an implementation of an AXI to APB bridge with configurable number of
APB master ports.
There are two versions of the bridge:

- One is for 64 bit (AXI 4) to 32 bit (APB) data width, e.g.: the bridge performs down conversion. This bridge also **supports fixed length burst transfers**.
- One is for n bit to n bit (data and address), e.g.: the bridge performs **no** down conversion. Also this bridge **does not** support any kind of **burst transfers**.

It was written for the use in the [PULP platform](http://pulp.ethz.ch/).
