#!/usr/bin/env perl
use strict;
use warnings;
use lib "../lib";
use SWAMP::vmu_Support qw(
	identifyPreemptedJobs
);

my $jobs = identifyPreemptedJobs();

print "Hello World!\n";
