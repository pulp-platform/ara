# Copyright 2019 ETH Zurich and University of Bologna.
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

#!/usr/bin/env bash

i=1
max_attempts=10
while ! memora "$@"; do
  echo "Attempt $i/$max_attempts of 'memora $@' failed."
  if test $i -ge $max_attempts; then
    echo "'memora $@' keeps failing; aborting!"
    exit 1
  fi
  i=$(($i+1))
done
