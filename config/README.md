# Configuration file for Ara

This file is included by all *Makefiles* in the Ara project to have a common
source for all configurations. Please only edit this file to change some
parameters such as the number of lanes in the design. This will automatically
generate the correct software runtime and the correct hardware.

Ara currently has four configurations, which differ on the amount of lanes:
- `2_lanes.mk`
- `4_lanes.mk`
- `8_lanes.mk`
- `16_lanes.mk`
We also provide a `default.mk` configuration, which links to the `4_lanes` one.

When running Ara's Makefiles, prepend `config=configuration_without_mk` to choose
a configuration. Alternatively, export the `ARA_CONFIG` variable. Please note that
the configuration chosen via the `config=` command line has priority over the
configuration set globally through the `ARA_CONFIG` variable.

If no configuration is explicitly chosen, Ara will use the `default` one. Please run
`make clean` after changing configurations.

To avoid constantly having a dirty git environment when working with a
configuration that differs from the default one, you can ignore changes to the
configuration file with the following command:

```bash
git update-index --assume-unchanged config/default.mk
```

In case you want to change the default and commit your changes to `default.mk`,
you can use the following command to make git pick up tracking the file again:

```bash
git update-index --no-assume-unchanged config/default.mk
```
