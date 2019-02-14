#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2019 Software Assurance Marketplace

use strict;
use warnings;
use lib "../lib";
use SWAMP::vmu_Support qw(
	getHTCondorJobId
	HTCondorJobStatus
);

my $arg = $ARGV[0];
if (! $arg) {
	print "No execrunuid and no jobid - exiting\n";
	exit;
}
if (($arg =~ m/^\d+\.\d+$/) || ($arg =~ m/^\d+$/)) {
	my $jobstatus = HTCondorJobStatus($arg);
	print 'jobid: ', $arg || '', ' jobstatus: ', $jobstatus || '', "\n";
}
else {
	my ($jobid, $type, $returned_execrunuid)  = getHTCondorJobId($arg);
	print 'execrunuid: ', $arg || '', ' jobid: ', $jobid || '', ' type: ', $type || '', ' returned_execrunuid: ', $returned_execrunuid || '', "\n";
}
print "Hello World!\n";
