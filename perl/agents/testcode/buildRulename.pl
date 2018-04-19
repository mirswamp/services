#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2018 Software Assurance Marketplace

use strict;
use warnings;
use lib "../lib";
use SWAMP::ToolLicense;

my $rulename = SWAMP::ToolLicense::build_rulename('parasoft', time(), 'swamp24680', '10.129.65.61', 1);
print 'rulename: <', $rulename, ">\n";
print "Hello World!\n";
