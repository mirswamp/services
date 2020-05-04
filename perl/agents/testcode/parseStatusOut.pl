#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

use strict;
use warnings;
use Log::Log4perl qw(:easy);
use lib "../lib";
use SWAMP::AssessmentTools qw(parseStatusOut);
use SWAMP::SWAMPUtils qw(systemcall);

my $statusout = 'status.out';
$statusout = $ARGV[0] if (defined($ARGV[0]));
my ($output, $status) = systemcall("cat $statusout");
my ($runOK, $why, $weaknesses) = parseStatusOut($output, 0);

print 'runOK: <', $runOK, ">\n" if (defined($runOK));
print 'why: <', $why, ">\n" if (defined($why));
print 'weaknesses: <', $weaknesses, ">\n" if (defined($weaknesses));

print "Hello World!\n";
