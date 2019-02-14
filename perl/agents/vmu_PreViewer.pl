#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2019 Software Assurance Marketplace

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
	timetrace_event
	timetrace_elapsed
);
$global_swamp_config = getSwampConfig();
use SWAMP::vmu_ViewerSupport qw(
	$VIEWER_STATE_LAUNCHING
	createrunscript 
	copyvruninputs 
	getViewerVersion
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

sub populateInputDirectory { my ($bogref, $inputfolder) = @_ ;
	my $result = copyvruninputs($bogref, $inputfolder);
	if (! $result) {
		$log->error("populateInputDirectory - copyvruninputs failed with $inputfolder");
		return 0;
	}
	$result = createrunscript($bogref, $inputfolder);
	if (! $result) {
		$log->error("populateInputDirectory - createrunscript failed with $inputfolder");
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

sub preserveBogFile { my ($bogfile, $bogref, $imagename, $inputfolder) = @_ ;
	my $viewerversion = getViewerVersion($bogref);
	$bogref->{'viewerversion'} = $viewerversion;
	$bogref->{'viewerplatform'} = $imagename;
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
my $event_start = timetrace_event($execrunuid, 'viewer', 'prescript start');

my $inputfolder = q{input};
mkdir($inputfolder);
my $outputfolder = q{output};
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

my $status = populateInputDirectory($bogref, $inputfolder);
if (! $status) {
	$log->error("populateInputDirectory failed for: $execrunuid");
	updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_LAUNCHING, $error_message, $bogref);
	exit_prescript_with_error();
}
my $imagename = createQcow2Disks($bogref, $inputfolder, $outputfolder);
if (! $imagename) {
	$log->error("createQcow2Disks failed for: $execrunuid");
	updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_LAUNCHING, $error_message, $bogref);
	exit_prescript_with_error();
}
if (! patchDeltaQcow2ForInit($imagename, $vmhostname)) {
	$log->error("patchDeltaQcow2ForInit failed for: $imagename $vmhostname");
	updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_LAUNCHING, $error_message, $bogref);
	exit_prescript_with_error();
}
preserveBogFile($bogfile, $bogref, $imagename, $inputfolder);

create_empty_file('JobVMEvents.log');
create_empty_file('vmip.txt');
$log->info("Starting virtual machine for: $execrunuid $imagename $vmhostname");
updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_LAUNCHING, "Starting VM", $bogref);

listDirectoryContents();
$log->info("Starting vmu_MonitorViewer for: $execrunuid $imagename $vmhostname");
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
timetrace_elapsed($execrunuid, 'viewer', 'prescript', $event_start);
exit(0);
