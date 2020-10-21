# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## Unreleased

## 0.2.1 - 2020-06-23
### Added
-`Bender:` Add `rtl/tc_sram` to target `rtl`, to prevent overwriting of target specific implementations.

### Fixed
- `tc_sram`: Drop string literal from parameter `SimInit` definition as synopsys throws an elaboration error.
- `tc_clk:tc_clk_delay`: Add Verilator and synthesis guards.

## 0.2.0 - 2020-03-18
### Added
- Add `tc_sram` and `tc_sram_xilinx`, with testbench for verifying technology specific implementations.

## 0.1.6 - 2019-11-18
### Added
- Add Readme
- Add Contribution Guide

### Changed
- Move modules of similar topic to a single file. This makes it easier to add new modules.
- Move separation between `cluster` and `pulp` to `deprecated` folder. There should be a single solution to a tech-cell.

## 0.1.1 - 2018-09-12
### Changed
- Polish release
- Keep Changelog
- Move to sources subfolder

## 0.1.0 - 2018-09-12
### Added
- Initial commit.
