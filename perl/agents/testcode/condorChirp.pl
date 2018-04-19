#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2018 Software Assurance Marketplace

use strict;
use warnings;
use lib "../lib";
use SWAMP::SWAMPUtils;

my $key = "start";
my $value = time();
my ($output, $status) = SWAMP::SWAMPUtils::condor_chirp($key,$value);
print "Hello World!\n";
