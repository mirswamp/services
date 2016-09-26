#/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

use strict;
use warnings;

use Test::More tests => 2;
use VMPrimitives qw(isValidVmID);

BEGIN { use_ok('VMPrimitives'); }

is(isValidVmID("xyz"), 0, "Checking bogus VmID");
