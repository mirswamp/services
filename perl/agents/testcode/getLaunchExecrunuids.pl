#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2018 Software Assurance Marketplace

use strict;
use warnings;
use Log::Log4perl qw(:easy);
use DBI;
use Data::Dumper;

# use lib '/opt/swamp/perl5';
use lib '../lib';
use SWAMP::vmu_Support qw(
	database_connect 
	database_disconnect
);
use SWAMP::vmu_AssessmentSupport qw(
	getLaunchExecrunuids
);

Log::Log4perl->easy_init($ALL);
my $launch_counter_begin = $ARGV[0];
my $launch_counter_end = $ARGV[1];
my $execrunuids = getLaunchExecrunuids($launch_counter_begin, $launch_counter_end);
my $count = 0;
foreach my $execrunuid (@$execrunuids) {
	print $count++, ') ', $execrunuid, "\n";
}
print "Total: $count\n";
print "Hello World\n";
