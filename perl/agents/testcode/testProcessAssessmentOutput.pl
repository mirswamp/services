#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

use strict;
use warnings;
use English '-no_match_vars';
use File::Basename qw(basename);
use File::Copy qw(copy);
use File::Spec::Functions;
use Log::Log4perl qw(:easy);
use Time::localtime;

use lib '/opt/swamp/perl5';
use FindBin;
use lib "$FindBin::Bin/../lib";

use SWAMP::vmu_AssessmentSupport qw(
	$OUTPUT_FILES_CONF_FILE_NAME
	locate_output_files
	parse_statusOut
);
use SWAMP::FrameworkUtils qw(
	generateStatusOutJson
);

my $log;

Log::Log4perl->easy_init($ALL);
$log = Log::Log4perl->get_logger(q{});
my $outputfolder = 'out';

my $output_files = locate_output_files($outputfolder, $OUTPUT_FILES_CONF_FILE_NAME);
if (defined($output_files->{'statusOut'})) {
	my $statusOut_file = catfile($outputfolder, $output_files->{'statusOut'});
	my $statusOut = parse_statusOut($statusOut_file);
	if ($ARGV[0]) {
		$statusOut->{'meta'}->{'all_pass'} = 0;
		$statusOut->{'meta'}->{'first_failure'} = $ARGV[0];
	}
	my $report = generateStatusOutJson($outputfolder, $output_files, $statusOut);
	$DB::single = 1;
}

print "Hello World!\n";
