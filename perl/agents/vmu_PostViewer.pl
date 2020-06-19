#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

use strict;
use warnings;
use English '-no_match_vars';
use File::Copy;
use File::Basename;
use File::Spec::Functions;
use Log::Log4perl::Level;
use Log::Log4perl;

use FindBin qw($Bin);
use lib ("$FindBin::Bin/../perl5", "$FindBin::Bin/lib");

use SWAMP::vmu_Support qw(
	getStandardParameters
	setHTCondorEnvironment
	identifyScript
	isSwampInABox
	getSwampDir 
	getLoggingConfigString 
	getSwampConfig
	$global_swamp_config
	systemcall 
	loadProperties
	construct_vmhostname
	getSwampConfig
	$global_swamp_config
	$HTCONDOR_JOB_OUTPUT_DIR
	$HTCONDOR_JOB_EVENTS_PATH
);
$global_swamp_config = getSwampConfig();
use SWAMP::vmu_ViewerSupport qw(
	$VIEWER_STATE_STOPPING
	$VIEWER_STATE_SHUTDOWN
	saveViewerDatabase
	updateClassAdViewerStatus
);

$global_swamp_config ||= getSwampConfig();
my $log;
my $tracelog;
my $execrunuid;

# logfilesuffix is the HTCondor clusterid and is used to distinguish viewer log files
# since the execrunuid for viewers is the viewer projectid and is not distinct across
# viewer executions
my $logfilesuffix = '';
sub logfilename {
	my $projectid = $execrunuid;
	$projectid =~ s/^vrun_//;
	$projectid =~ s/_CodeDX$//;
	my $name = catfile(getSwampDir(), 'log', $projectid . '_' . $logfilesuffix . '.log');
	return $name;
}

sub extract_outputdisk { my ($bogref, $outputfolder) = @_ ;
	return 1 if ($bogref->{'use_docker_universe'});
	my ($output, $status) = systemcall(qq{LIBGUESTFS_BACKEND=direct /usr/bin/guestfish --ro -a outputdisk.qcow2 run : mount /dev/sda / : glob copy-out '/*' $outputfolder});    
    if ($status) {
        $log->error("extract_outputdisk - output extraction failed: $output $status");
        return 0;
    }
	return 1;
}

sub get_final_viewer_status { my ($file) = @_ ;
	my $fh;
	if (! open($fh, '<', $file)) {
		return ''; 
	}
	my @lines = <$fh>;
	close($fh);
	my $viewer_status = $lines[-1];
	$viewer_status =~ s/[^[:print:]]+//g;
	return $viewer_status;
}

########
# Main #
########

# args: execrunuid owner uiddomain clusterid procid numjobstarts [debug]
# execrunuid is global because it is used in logfilename
my ($owner, $uiddomain, $clusterid, $procid, $numjobstarts, $debug) = getStandardParameters(\@ARGV, \$execrunuid);
if (! $execrunuid) {
	# we have no execrunuid for the log4perl log file name
	exit(1);
}
$logfilesuffix = $clusterid if (defined($clusterid));

my $vmhostname = construct_vmhostname($execrunuid, $clusterid, $procid);

# Initialize Log4perl
Log::Log4perl->init(getLoggingConfigString());

$log = Log::Log4perl->get_logger(q{});
$log->level($debug ? $TRACE : $INFO);
$log->info("PostViewer: $execrunuid Begin");
$tracelog = Log::Log4perl->get_logger('runtrace');
$tracelog->trace("$PROGRAM_NAME ($PID) called with args: @ARGV");
setHTCondorEnvironment();
identifyScript(\@ARGV);

my $viewer_status = get_final_viewer_status($HTCONDOR_JOB_EVENTS_PATH);
if (! $viewer_status || (($viewer_status =~ m/SHUTDOWN/) && ($viewer_status ne 'TIMERSHUTDOWN'))) {
	$viewer_status = "no $HTCONDOR_JOB_EVENTS_PATH" if (! $viewer_status);
	updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_SHUTDOWN, "Viewer did not start - status: $viewer_status", {});
	exit(1);
}

my $outputfolder = $HTCONDOR_JOB_OUTPUT_DIR;

my %bog;
my $bogfile = $execrunuid . '.bog';
loadProperties($bogfile, \%bog);
$bog{'vmhostname'} = $vmhostname;

$log->info("Viewer is starting shutdown");
updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_STOPPING, 'Viewer is starting shutdown', \%bog);

my $exitCode = 0;
my $status = extract_outputdisk(\%bog, $outputfolder);
if ($status) {
	if (-r "$outputfolder/skippedbundle") {
        $log->warn("output extraction viewerdb bundle skipped");
	}
	if (! -r "$outputfolder/codedx_viewerdb.tar.gz") {
        $log->error("output extraction viewerdb bundle not found");
	}
	else {
		$log->info("output extraction succeeded - preserving codedx_viewerdb.tar.gz");
		$status = saveViewerDatabase(\%bog, $vmhostname, $outputfolder);
		if (! $status) {
			$log->error("Failed to save viewer results for: $vmhostname");
			$exitCode = 1;
		}
	}
}
else {
	$log->error("Failed to extract viewer results for: $vmhostname");
	$exitCode = 1;
}

$log->info("Viewer shutdown completed");
updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_SHUTDOWN, 'Viewer shutdown completed', \%bog);

$log->info("PostViewer: $execrunuid Exit $exitCode");
if (! isSwampInABox($global_swamp_config)) {
	my $logfile = logfilename();
	my $central_log_dir = '/swamp/working/logs';
	if (! -d $central_log_dir) {
		if (! use_make_path($central_log_dir)) {
			$log->error("PostAssessment: $execrunuid - unable to create dir: $central_log_dir");
		}
	}
	if (-d $central_log_dir && -r $logfile) {
		copy($logfile, $central_log_dir);
	}
}
exit($exitCode);
