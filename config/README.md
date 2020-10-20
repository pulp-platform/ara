# Configuration file for Ara

This file is included by all *Makefiles* in the Ara project to have a common
source for all configurations. Please only edit this file to change some
parameters such as the number of cores in the design. This will automatically
generate the correct software runtime and the correct hardware.

To avoid constantly having a dirty git environment when working with a
configuration that differs from the default one, you can ignore changes to the
configuration file with the following command:

```bash
git update-index --assume-unchanged config/config.mk
```

In case you want to change the default and commit your changes to `config.mk`,
you can use the following command to make git pick up tracking the file again:

```bash
git update-index --no-assume-unchanged config/config.mk
```
