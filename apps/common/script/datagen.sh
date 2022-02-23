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
#
# Author: Matteo Perotti
#
# Run the datagen script. Each program has its own.

# Extract the name of the application
app=$1

if [[ $1 == *"conv"* ]]
then
  # Convolutions need args to be passed along
  args="${@:2}"
  # Use default values if args is not set
  [ -z "$args" ] && args="112 7"
else
  # Other program datagens do not need any arguments
  args=
fi

# Generate the data
python3 script/gen_data.py $args > data.S
