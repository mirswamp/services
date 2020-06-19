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

use SWAMP::vmu_Support qw(
	systemcall
);
use SWAMP::vmu_AssessmentSupport qw(
	$OUTPUT_FILES_CONF_FILE_NAME
	locate_output_files
);

my $log;
Log::Log4perl->easy_init($ALL);
$log = Log::Log4perl->get_logger(q{});
my $outputdisk = q{outputdisk.tar.gz};
my $outputfolder = q{out};
my $dir = $ARGV[0];
if ($dir) {
	$outputfolder = catdir($dir, $outputfolder);
}
if (! -x $outputfolder || ! -d $outputfolder) {
	if (-r -f catfile($dir, $outputdisk)) {
		my $command = qq{cd $dir; tar xf $outputdisk};
		my ($status, $output, $error_output) = systemcall($command);
		if ($status) {
			print "Error - $command failed - $status $output $error_output $OS_ERROR", "\n";		
		}
	}
}
if (-x -d $outputfolder) {
	my $output_files = locate_output_files($outputfolder, $OUTPUT_FILES_CONF_FILE_NAME);
	$DB::single = 1;
	my $bogus = $output_files;
}
print "Hello World!\n";
