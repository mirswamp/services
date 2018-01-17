#!/usr/bin/env perl
use strict;
use warnings;
use lib "../lib";
use SWAMP::vmu_Support qw(
	getHTCondorJobId
);

my $execrunuid = $ARGV[0];
my ($jobid, $type, $returned_execrunuid)  = getHTCondorJobId($execrunuid);
print 'execrunuid: ', $execrunuid || '', ' jobid: ', $jobid || '', ' type: ', $type || '', ' returned_execrunuid: ', $returned_execrunuid || '', "\n";
print "Hello World!\n";
