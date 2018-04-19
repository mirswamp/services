#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2018 Software Assurance Marketplace

use strict;
use warnings;
use DBI;
use Data::Dumper;
use Log::Log4perl qw(:easy);

use lib '../lib';
# use lib '/opt/swamp/perl5';
use SWAMP::vmu_AssessmentSupport;

my $execrunuid = $ARGV[0];
if ($execrunuid) {
	Log::Log4perl->easy_init($DEBUG);
	my $bogref = SWAMP::vmu_AssessmentSupport::_computeBOG($execrunuid);
	print 'bog: ', Dumper($bogref);
	if ($bogref) {
		my $result = SWAMP::vmu_AssessmentSupport::_createUserConf($bogref, '.');
		print 'user_cnf result: ', Dumper($result);
	}
}

print "Hello World\n";
