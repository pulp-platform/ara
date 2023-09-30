#!/usr/bin/perl -w

# Copyright (c) 2015, Technische Universität Kaiserslautern
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
# TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER
# OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# Authors: 
#    Matthias Jung
#    Eder F. Zulian
#    Lukas Steiner

use warnings;
use strict;

# Assuming this address mapping:
# {
#     "CONGEN": {
#         "BYTE_BIT": [
#             0,
#             1,
#             2,
#             3
#         ],
#         "BANK_BIT": [
#             4,
#             5
#         ],
#         "COLUMN_BIT": [
#             6,
#             7,
#             8,
#             9,
#             10,
#             11,
#             12
#         ],
#         "ROW_BIT": [
#             13,
#             14,
#             15,
#             16,
#             17,
#             18,
#             19,
#             20,
#             21,
#             22,
#             23,
#             24
#         ],
#         "CHANNEL_BIT": [
#             25,
#             26
#         ]
#     }
# }

# This is how it should look like later:
# 31:     write   0x0     0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff

my $numberOfChannels = 4;
my $numberOfRows = 4096;
my $numberOfColumns = 128;
my $bytesPerColumn = 16;
my $burstLength = 4; # burst length of 4 columns --> 4 columns written or read per access
my $dataLength = $bytesPerColumn * $burstLength;

my $channelOffset = 0x2000000;
my $rowOffset = 0x2000;
my $columnOffset = 0x40;

# Generate Data Pattern:
my $dataPatternByte = "ff";

my $dataPattern = "0x";
for(my $i = 0; $i < $dataLength; $i++)
{
    $dataPattern .= $dataPatternByte;
}

my $clkCounter = 0;
my $addr = 0;

# Generate Trace file (writes):
for(my $cha = 0; $cha < ($numberOfChannels * $channelOffset); $cha = $cha + $channelOffset)
{
    for(my $row = 0; $row < ($numberOfRows * $rowOffset); $row = $row + $rowOffset)
    {
        for(my $col = 0; $col < ($numberOfColumns * $columnOffset); $col = $col + ($columnOffset * $burstLength))
        {
            my $addrHex = sprintf("0x%x", $addr);
            print "$clkCounter:\twrite\t$addrHex\t$dataPattern\n";
            $clkCounter++;
            $addr += $columnOffset * $burstLength;
        }
    }
}

$clkCounter = 50000000;
$addr = 0;

# Generate Trace file (reads):
for(my $cha = 0; $cha < ($numberOfChannels * $channelOffset); $cha = $cha + $channelOffset)
{
    for(my $row = 0; $row < ($numberOfRows * $rowOffset); $row = $row + $rowOffset)
    {
        for(my $col = 0; $col < ($numberOfColumns * $columnOffset); $col = $col + ($columnOffset * $burstLength))
        {
            my $addrHex = sprintf("0x%x", $addr);
            print "$clkCounter:\tread\t$addrHex\n";
            $clkCounter++;
            $addr += $columnOffset * $burstLength;
        }
    }
}