#!/usr/bin/env bash
# Copyright 2020 ETH Zurich and University of Bologna.
#
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Author: Matteo Perotti <mperotti@iis.ee.ethz.ch>

# Check if the SPIKE log contains only expected strings
check_log() {
  # Super simple check. It can give false negatives
  if grep -v "0x" $1 >/dev/null; then echo "The SPIKE log was not clean."; fi
}

# Filter out scalar instructions and simple trash from SPIKE log with intermixed scalar and vector instructions
filter_vec() {
  grep "0x" $1 | grep -v ";" | grep -v "core\s\+0.*) [^v]" > $2
}

# Main function
main() {
  # Check if the log is clean
  check_log $1
  # Filter out scalar instructions
  filter_vec $1 $2
}

# Call main
main $1 $2
