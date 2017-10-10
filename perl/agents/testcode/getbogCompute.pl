#!/usr/bin/env perl
use strict;
use warnings;
use DBI;
use Data::Dumper;

use lib '../lib';
# use lib '/opt/swamp/perl5';
use SWAMP::vmu_AssessmentSupport;

my $execrunuid = $ARGV[0];
if ($execrunuid) {
	my $result = SWAMP::vmu_AssessmentSupport::_computeBOG($execrunuid);
	print 'result: ', Dumper($result);
}

print "Hello World\n";
