# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

- Move to flip-flop-based registers to store the vector descriptions (addresses and lengths)
- Restrict Ara's FPU type support to RVD, RVF and Xf16
- Data-movement instructions (vslide, vins, vext) are executed in a dedicated VSLIDE unit
- Add support to full-duplex AXI operation
- Add dedicated reduction hardware in VALU and VFPU
- Remove VSLIDE unit

## [0.1.0] - 2018-05-30

### Added
- Initial development
- Support to RV64 "V" 0.3-DRAFT
