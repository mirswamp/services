#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2018 Software Assurance Marketplace

use strict;
use warnings;
use lib '/opt/swamp/perl5';
use lib '../lib';
use SWAMP::vmu_AssessmentSupport qw(updateExecutionResults);

my $execrun_uuid = '65b92ae7-082b-11e7-a029-0025b51000fd';
my $newrecord = {
	'status'	=> 'This is the new final status',
	'cpu_utilization'	=> 50.7,
	'execute_node_architecture_id' => 'tardis',
	'vm_ip_address'	=> '123.456.789.012',
};
my $finalStatus = 1;

updateExecutionResults($execrun_uuid, $newrecord, $finalStatus);

print "Hello World!\n";
