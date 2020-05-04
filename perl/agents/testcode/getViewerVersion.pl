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
	getViewerVersion
);

my $bogref = {
	'viewer'		=> 'CodeDX',
};
Log::Log4perl->easy_init($ALL);
my $viewerversion = getViewerVersion($bogref);
print "viewerversion: $viewerversion\n";
print "Hello World!\n";
