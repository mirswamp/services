#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

use strict;
use warnings;
use Log::Log4perl qw(:easy);
use lib '../lib';
use SWAMP::vmu_AssessmentSupport qw(
	updateClassAdAssessmentStatus
);

Log::Log4perl->easy_init($ALL);

my $execrunuid = 'tjab-execrunuid';
my $vmhostname = 'tjab-vmhostname';
my $user_uuid = 'tjab-user_uuid';
my $projectid = 'tjab-projectid';
my $status = 'tjab-status';
updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $status);
print "Hello World!\n";
