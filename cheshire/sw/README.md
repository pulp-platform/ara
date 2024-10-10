# Build software for Cheshire Ara

## Compile the vector code for Cheshire

Compile the source files with the vector extension support enable:

```bash
make chs-sw-all
```

This command will also copy the necessary dependencies to `sw/tests` and enable the vector extension at compile time.

## (OPTIONAL) Build an RVV-ready Linux Image

1. **Run the Makefile Target**:
```
make linux_img
```

If the version of the default host compiler is too low, the build can fail.
gcc and g++ version 11.2.0 work.

For IIS builds:
```
make linux_img TOOLCHAIN_SUFFIX=-11.2.0
```
