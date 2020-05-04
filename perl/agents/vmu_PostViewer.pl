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

# returns:
# -1 - extraction failed
# -2 - viewerdb bundle not found
#  1 - viewerdb bundle skipped
#  0 - success
sub extract_outputdisk { my ($outputfolder) = @_ ;
	my ($output, $status) = systemcall(qq{/usr/bin/guestfish --ro -a outputdisk.qcow2 run : mount /dev/sda / : glob copy-out '/*' $outputfolder});    
    if ($status) {
        $log->error("extract_outputdisk - output extraction failed: $output $status");
        return -1;
    }
	if (-r "$outputfolder/skippedbundle") {
        $log->warn("extract_outputdisk - output extraction viewerdb bundle skipped");
		return 1;
	}
	if (! -r "$outputfolder/codedx_viewerdb.tar.gz") {
        $log->error("extract_outputdisk - output extraction viewerdb bundle not found");
		return -2;
	}
    return 0;
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

my $viewer_status = get_final_viewer_status('JobVMEvents.log');
if (! $viewer_status || (($viewer_status =~ m/SHUTDOWN/) && ($viewer_status ne 'TIMERSHUTDOWN'))) {
	$viewer_status = 'no JobVMEvents.log' if (! $viewer_status);
	updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_SHUTDOWN, "Viewer did not start - status: $viewer_status", {});
	exit(1);
}

my $outputfolder = q{output};

my %bog;
my $bogfile = $execrunuid . '.bog';
loadProperties($bogfile, \%bog);
$bog{'vmhostname'} = $vmhostname;

$log->info("Viewer is starting shutdown");
updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_STOPPING, 'Viewer is starting shutdown', \%bog);

# returns:
# -1 - extraction failed
# -2 - viewerdb bundle not found
#  1 - viewerdb bundle skipped
#  0 - success
my $status = extract_outputdisk($outputfolder);
if ($status == -1) {
	$log->error("Failed to extract viewer results for: $vmhostname");
}
elsif ($status == -2) {
	$log->error("Failed to find viewer bundle for: $vmhostname");
}
elsif ($status == 1) {
	$log->warn("Viewer bundling skipped for: $vmhostname");
}

my $exitCode = 0;
if ($status == 0) {
	$status = saveViewerDatabase(\%bog, $vmhostname, $outputfolder);
	if (! $status) {
		$log->error("Failed to save viewer results for: $vmhostname");
		$exitCode = 1;
	}
}
else {
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
