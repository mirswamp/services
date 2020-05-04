#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

use strict;
use warnings;
use lib '../lib';
use SWAMP::SWAMPUtils;

my $oldname = '/home/tbricker/Downloads/python/swamp_python_151015/mock-1.3.0/mock-1.3.0-py2.py3-none-any.whl';
my $newname;
if (-r $oldname) {
	$newname = SWAMP::SWAMPUtils::makezip($oldname);
}
print "Hello World!\n";
