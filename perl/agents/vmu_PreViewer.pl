#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

use strict;
use warnings;
use English '-no_match_vars';
use File::Copy;
use File::Remove qw(remove);
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
	listDirectoryContents
	getSwampDir 
	loadProperties 
	saveProperties
	getLoggingConfigString 
	systemcall 
	createQcow2Disks
	patchDeltaQcow2ForInit
	construct_vmhostname
	create_empty_file
	getSwampConfig
	$global_swamp_config
	timing_log_viewer_timepoint
	$HTCONDOR_JOB_INPUT_DIR
	$HTCONDOR_JOB_OUTPUT_DIR
	$HTCONDOR_JOB_IP_ADDRESS_PATH
	$HTCONDOR_JOB_EVENTS_PATH
);
$global_swamp_config = getSwampConfig();
use SWAMP::vmu_ViewerSupport qw(
	$VIEWER_STATE_LAUNCHING
	createvrunscript 
	copyvruninputs 
	copyuserdatabase
	getViewerVersion
	updateClassAdViewerStatus
	identifyViewer
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

sub populateInputDirectory { my ($bogref, $inputfolder) = @_ ;
	if (! $bogref->{'use_baked_viewer'}) {
		my $result = copyvruninputs($bogref, $inputfolder);
		if (! $result) {
			$log->error("populateInputDirectory - copyvruninputs failed with $inputfolder");
			return 0;
		}
	}
	my $result = copyuserdatabase($bogref, $inputfolder);
	if (! $result) {
		$log->error("populateInputDirectory - copyuserdatabase failed with $inputfolder");
	}
	$result = createvrunscript($bogref, $inputfolder);
	if (! $result) {
		$log->error("populateInputDirectory - createvrunscript failed with $inputfolder");
		return 0;
	}
	return 1;
}

sub extractBogFile { my ($execrunuid, $bogfile, $inputfolder) = @_ ;
	my $submitbundle = $execrunuid . '_submitbundle.tar.gz';
	my ($output, $status) = systemcall("tar xzf $submitbundle");
	if ($status) {
		$log->error("extractBogFile - $submitbundle tar failed: $output $status");
		return;
	}
	my %bog;
	loadProperties($bogfile, \%bog);
	return \%bog;
}

sub preserveBogFile { my ($bogfile, $bogref, $platform_image, $inputfolder) = @_ ;
	my $viewerversion = getViewerVersion($bogref);
	$bogref->{'viewerversion'} = $viewerversion;
	$bogref->{'viewerplatform'} = $platform_image;
	saveProperties($bogfile, $bogref);
	copy($bogfile, $inputfolder);
}

sub exit_prescript_with_error {
	if ($log) {
		$log->info("Exiting $PROGRAM_NAME ($PID) with error");
   		$log->info("Unlinking delta, input, and output disks for HTCondor");
	}
    unlink 'delta.qcow2' if (-e 'delta.qcow2');
    unlink 'inputdisk.qcow2' if (-e 'inputdisk.qcow2');
    unlink 'outputdisk.qcow2' if (-e 'outputdisk.qcow2');
    exit(1);
}

########
# Main #
########

# args: execrunuid owner uiddomain clusterid procid numjobstarts [debug]
# execrunuid is global because it is used in logfilename
my ($owner, $uiddomain, $clusterid, $procid, $numjobstarts, $debug) = getStandardParameters(\@ARGV, \$execrunuid);
if (! $execrunuid) {
	# we have no execrunuid for the log4perl log file name
	exit_prescript_with_error();
}
$logfilesuffix = $clusterid if (defined($clusterid));

# Initialize Log4perl
Log::Log4perl->init(getLoggingConfigString());

$log = Log::Log4perl->get_logger(q{});
$log->level($debug ? $TRACE : $INFO);
$log->info("PreViewer: $execrunuid Begin");
$tracelog = Log::Log4perl->get_logger('runtrace');
$tracelog->trace("$PROGRAM_NAME ($PID) called with args: @ARGV");
setHTCondorEnvironment();
identifyScript(\@ARGV);
listDirectoryContents();

my $vmhostname = construct_vmhostname($execrunuid, $clusterid, $procid);

my $inputfolder = $HTCONDOR_JOB_INPUT_DIR;
mkdir($inputfolder);
my $outputfolder = $HTCONDOR_JOB_OUTPUT_DIR;
mkdir($outputfolder);

my $error_message = 'Unable to Start VM';
my $bogfile = $execrunuid . '.bog';
my $bogref = extractBogFile($execrunuid, $bogfile, $inputfolder);
if (! $bogref) {
	$log->error("extractBogFile failed for: $bogfile");
	updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_LAUNCHING, $error_message, $bogref);
	exit_prescript_with_error();
}
$bogref->{'vmhostname'} = $vmhostname;
identifyViewer($bogref);

my $status = populateInputDirectory($bogref, $inputfolder);
if (! $status) {
	$log->error("populateInputDirectory failed for: $execrunuid");
	updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_LAUNCHING, $error_message, $bogref);
	exit_prescript_with_error();
}
my $platform_image = $bogref->{'platform_image'};
if (! $bogref->{'use_docker_universe'}) {
	if (! createQcow2Disks($platform_image, $inputfolder, $outputfolder)) {
		$log->error("createQcow2Disks failed for: $execrunuid $platform_image");
		updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_LAUNCHING, $error_message, $bogref);
		exit_prescript_with_error();
	}
	if (! $bogref->{'use_baked_viewer'}) {
		if (! patchDeltaQcow2ForInit($platform_image, $vmhostname)) {
			$log->error("patchDeltaQcow2ForInit failed for: $platform_image $vmhostname");
			updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_LAUNCHING, $error_message, $bogref);
			exit_prescript_with_error();
		}
	}
	create_empty_file($HTCONDOR_JOB_EVENTS_PATH);
	create_empty_file($HTCONDOR_JOB_IP_ADDRESS_PATH);
	$log->info("Starting virtual machine for: $execrunuid $platform_image $vmhostname");
	updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_LAUNCHING, "Starting VM", $bogref);
}
else {
	$log->info("Starting docker container for: $execrunuid $platform_image $vmhostname");
	updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_LAUNCHING, "Starting DC", $bogref);
}
preserveBogFile($bogfile, $bogref, $platform_image, $inputfolder);
listDirectoryContents();
$log->info("Starting vmu_MonitorViewer for: $execrunuid $platform_image $vmhostname");
if (my $pid = fork()) {
	# Parent
	$log->info("vmu_MonitorViewer $execrunuid pid: $pid");
}
else {
	# Child
	$debug ||= '';
	my $script = catfile(getSwampDir(), 'bin', 'vmu_MonitorViewer.pl');
	my $command = "source /etc/profile.d/swamp.sh; perl $script $execrunuid $owner $uiddomain $clusterid $procid $numjobstarts $debug";
	{exec($command)}; # use {} to prevent the warning about a statement following exec
	$log->error("PreViewer $execrunuid - exec command: $command failed");
}

$log->info("PreViewer: $execrunuid Exit");
exit(0);
