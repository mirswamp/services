#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2019 Software Assurance Marketplace

use strict;
use warnings;
use Log::Log4perl qw(:easy);

use lib '/opt/swamp/perl5';
use SWAMP::vmu_AssessmentSupport qw(saveResult);

Log::Log4perl->easy_init($ALL);

my $execrunuid = $ARGV[0];
my $pathname = 'pathname';
my $sha512sum = 100;
my $sourcepathname = 'sourcepathname';
my $source512sum = 200;
my $logpathname = 'logpathname';
my $log512sum = 300;
my $weaknesses = 400;
my $locSum = 500;
my $status_out = 'status_out';
my $options = {
	'execrunid' 		=> $execrunuid,
	'pathname'			=> $pathname,
	'sha512sum'			=> $sha512sum,
	'sourcepathname'	=> $sourcepathname,
	'source512sum'		=> $source512sum,
	'logpathname'		=> $logpathname,
	'log512sum'			=> $log512sum,
	'weaknesses'		=> $weaknesses,
	'locSum'			=> $locSum,
	'status_out'		=> $status_out,
};
my $result = saveResult($options);
print "result: <$result>\n";

print "Hello World\n";
