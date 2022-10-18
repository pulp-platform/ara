---
name: Issue filing for tests by YL
about: This issue template is specifically for the issue reporting of one particular
  set of tests generated from YL's script for RVV1.0 vector tests.
title: Test failures in `` instruction in multiple configurations of `LMUL/SEW`
labels: bug
assignees: ''

---

### Test failures in `` instruction in multiple configurations of `LMUL/SEW`

#### Failing combinations to be debugged:
```
```

*see `ara/apps/riscv-tests/isa/rv64uv/Makefrag` for all tested combinations, and see folder `ara/hardware/report/` for viewing logs of `stdout` and `stderr`. For more, see `ara/hardware/build/*.trace` files.

**Verification branch**:  [main_verif_](https://github.com/10x-Engineers/ara/tree/main_verif_) extended from  [main_verif](https://github.com/10x-Engineers/ara/tree/main_verif).

#### Steps to recreate this issue:

1. In root folder, `git checkout main_verif_`
2. `cd apps`
3. `make riscv_tests` (only mentioned tests should process, since they are the only one listed in `Makefrag`)
4. `cd ../hardware`
5. `make simulate` or `make simv app="name of individual ELF"` or `make riscv_tests_simv -j4` to run regression
6. View `ara/hardware/build/*.trace` file(s) to view the test case that failed during simulation on ARA, in `(tohost=***)`
