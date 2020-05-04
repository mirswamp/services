#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

use strict;
use warnings;

my $done_term = 0;
my $done_int = 0;

sub signal_handler { my ($signal_name) = @_ ;
	print "signal: $signal_name caught\n";
	if ($signal_name eq 'TERM') {
		$done_term = 1;
	}
	elsif ($signal_name eq 'INT') {
		$done_int = 1;
	}
}
$SIG{INT} = \&signal_handler;
$SIG{TERM} = \&signal_handler;

while (1) {
	if ($done_term) {
		print "TERM caught - exiting\n";
		exit;
	}
	if ($done_int) {
		print "INT caught - continuing\n";
	}
	print "$$ Sleeping\n";
	sleep 5;
}
