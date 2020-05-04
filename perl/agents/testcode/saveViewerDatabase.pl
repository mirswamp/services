#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

use strict;
use warnings;
use Log::Log4perl qw(:easy);
use lib '../lib';
use SWAMP::vmu_ViewerSupport qw(
	saveViewerDatabase
);

my $viewer_uuid = $ARGV[0];
if (! $viewer_uuid) {
	print "Error - no viewer instance uuid - exiting ...\n";
	exit(0);
}
my $bogref = {
	'viewer'		=> 'CodeDX',
	'resultsfolder'	=> 'resultsfolder',
	'viewer_uuid'	=> $viewer_uuid,
};
my $vmhostname = 'vmhostname';
my $outputfolder = 'outputfolder';
my $saverunname = '';
Log::Log4perl->easy_init($ALL);
my $result = saveViewerDatabase($bogref, $vmhostname, $outputfolder, $saverunname);
print "Hello World!\n";
