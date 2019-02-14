#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2019 Software Assurance Marketplace

use strict;
use warnings;
use Log::Log4perl qw(:easy);

use lib '../lib';
use SWAMP::vmu_Support qw(getSwampConfig);
use SWAMP::ToolLicense qw(getVMIPAddr);

my $vmname = $ARGV[0];
if (! $vmname) {
	print "Error - no vmname\n";
	exit;
}
Log::Log4perl->easy_init($ALL);

my $config = getSwampConfig();
my $vmip = getVMIPAddr($config, $vmname);
print "vmname: $vmname vmip: <$vmip> ";
if ($vmip =~ m/^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/) {                                                                
	print "proper ip address";
}
print "\n";

print "Hello World!\n";
