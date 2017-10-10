#!/usr/bin/env perl
use strict;
use warnings;
use lib "../lib";
use SWAMP::vmu_Support qw(
	getHTCondorJobId
);

my $execrunuid = $ARGV[0];
my $jobid = getHTCondorJobId($execrunuid);
print "execrunuid: ", $execrunuid || '', " jobid: ", $jobid || '', "\n";
print "Hello World!\n";
