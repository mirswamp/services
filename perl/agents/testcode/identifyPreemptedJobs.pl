#!/usr/bin/env perl
use strict;
use warnings;
use Log::Log4perl qw(:easy);

use FindBin qw($Bin);
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/../perl5");
use SWAMP::vmu_Support qw(
	identifyPreemptedJobs
);

Log::Log4perl->easy_init($ALL);
my $jobs = identifyPreemptedJobs();
print 'Preempted jobs: ', (join ', ', @$jobs), "\n";
print "Hello World!\n";
