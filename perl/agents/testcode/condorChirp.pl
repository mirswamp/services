#!/usr/bin/env perl
use strict;
use warnings;
use lib "../lib";
use SWAMP::SWAMPUtils;

my $key = "start";
my $value = time();
my ($output, $status) = SWAMP::SWAMPUtils::condor_chirp($key,$value);
print "Hello World!\n";
