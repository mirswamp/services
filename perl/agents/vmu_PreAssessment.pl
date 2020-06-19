#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

use strict;
use warnings;
use English '-no_match_vars';
use Sys::Hostname;
use File::Copy;
use File::Remove qw(remove);
use File::Basename;
use File::Spec::Functions;
use Log::Log4perl::Level;
use Log::Log4perl;
use POSIX qw(strftime);

use FindBin qw($Bin);
use lib ("$FindBin::Bin/../perl5", "$FindBin::Bin/lib");

use SWAMP::vmu_Support qw(
	getStandardParameters
	setHTCondorEnvironment
	identifyScript
	listDirectoryContents
	computeDirectorySizeInBytes
	getSwampDir
	loadProperties
	getLoggingConfigString
	systemcall
	createQcow2Disks
	patchDeltaQcow2ForInit
	construct_vmhostname
	create_empty_file
	getSwampConfig
	$global_swamp_config
	timing_log_assessment_timepoint
	$HTCONDOR_JOB_INPUT_DIR
	$HTCONDOR_JOB_OUTPUT_DIR
	$HTCONDOR_JOB_IP_ADDRESS_PATH
	$HTCONDOR_JOB_EVENTS_PATH
);
$global_swamp_config ||= getSwampConfig();
use SWAMP::vmu_AssessmentSupport qw(
	identifyAssessment
	copyAssessmentInputs
	createAssessmentConfigs
	builderUser
	builderPassword
	updateExecutionResults
	updateClassAdAssessmentStatus
);

my $log;
my $tracelog;
my $execrunuid;
my $builderUser;
my $builderPassword;
my $hostname = hostname();

# logfilesuffix is the HTCondor clusterid
my $logfilesuffix = ''; 
sub logfilename {
	my $name = catfile(getSwampDir(), 'log', $execrunuid . '_' . $logfilesuffix . '.log');
	return $name;
}

sub populateInputDirectory { my ($bogref, $inputfolder) = @_ ;
	$builderUser = builderUser();
	$builderPassword = builderPassword();
	my $retval = 1;
	my $result = copyAssessmentInputs($bogref, $inputfolder);
	if (! $result) {
		$log->error("populateInputDirectory - copyInputs failed with $inputfolder");
		$retval = 0;
	}
	$result = createAssessmentConfigs($bogref, $inputfolder, $builderUser, $builderPassword);
	if (! $result) {
		$log->error("populateInputDirectory - createAssessmentConfigs failed with $inputfolder");
		$retval = 0;
	}
	chmod 0755, catfile($inputfolder, 'run.sh'); 
	listDirectoryContents($inputfolder);
	return $retval;
}

sub extractBogFile { my ($execrunuid, $outputfolder) = @_ ;
	my $submitbundle = $execrunuid . '_submitbundle.tar.gz';
	my ($output, $status) = systemcall("tar xzf $submitbundle");
	if ($status) {
		$log->error("extractBogFile - $submitbundle tar failed: $output $status");
		return;
	}
	my %bog;
	my $bogfile = $execrunuid . '.bog';
	loadProperties($bogfile, \%bog);

	# copy bogfile and submitfile to outputfolder
    my $submitfile = $execrunuid . '.sub';
	copy($bogfile, $outputfolder);
	copy($submitfile, $outputfolder);

	return \%bog;
}

sub exit_prescript_with_error {
	if ($log) {
		$log->info("Exiting $PROGRAM_NAME ($PID) with error");
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

timing_log_assessment_timepoint($execrunuid, 'prescript - start');
$log = Log::Log4perl->get_logger(q{});
$log->level($debug ? $TRACE : $INFO);
$log->info("PreAssessment: $execrunuid Begin");
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

my $job_status_message_suffix = '';
if ($numjobstarts > 0) {
	my $htcondor_assessment_max_retries = $global_swamp_config->get('htcondor_assessment_max_retries') || 3;
	$job_status_message_suffix = " retry($numjobstarts/$htcondor_assessment_max_retries)";
}

my $job_status_message = 'Unable to Start ' . $job_status_message_suffix;
my $bogref = extractBogFile($execrunuid, $outputfolder);
if (! $bogref) {
	$log->error("extractBogFile failed for: $execrunuid");
	updateClassAdAssessmentStatus($execrunuid, $vmhostname, 'null', 'null', $job_status_message);
	exit_prescript_with_error();
}
identifyAssessment($bogref);

my $user_uuid = $bogref->{'userid'} || 'null';
my $projectid = $bogref->{'projectid'} || 'null';

my $status = populateInputDirectory($bogref, $inputfolder);
if (! $status) {
	$log->error("populateInputDirectory failed for: $execrunuid");
	updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $job_status_message);
	exit_prescript_with_error();
}

my $platform_image = $bogref->{'platform_image'};
if (! $bogref->{'use_docker_universe'}) {
	if (! createQcow2Disks($platform_image, $inputfolder, $outputfolder)) {
		$log->error("createQcow2Disks failed for: $execrunuid $platform_image");
		updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $job_status_message);
		exit_prescript_with_error();
	}
	if (! patchDeltaQcow2ForInit($platform_image, $vmhostname)) {
		$log->error("patchDeltaQcow2ForInit failed for: $execrunuid $platform_image $vmhostname");
		updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $job_status_message);
		exit_prescript_with_error();
	}

	create_empty_file($HTCONDOR_JOB_EVENTS_PATH);
	create_empty_file($HTCONDOR_JOB_IP_ADDRESS_PATH);
	$log->info("Starting virtual machine for: $execrunuid $platform_image $vmhostname");
	$job_status_message = 'Starting virtual machine' . $job_status_message_suffix;
}
else {
	$log->info("Starting docker container for: $execrunuid $platform_image $vmhostname");
	$job_status_message = 'Starting docker container' . $job_status_message_suffix;
}

updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $job_status_message);
updateExecutionResults($execrunuid, {
	'status'						=> $job_status_message,
	'execute_node_architecture_id'	=> $hostname,
	'vm_hostname'					=> $vmhostname,
	'vm_username'					=> $builderUser,
	'vm_password'					=> $builderPassword,
	'vm_image'						=> $platform_image,
	'tool_filename'					=> $bogref->{'toolpath'},
	'run_date'						=> strftime("%Y-%m-%d %H:%M:%S", gmtime(time())),
});

listDirectoryContents();

$log->info("Starting vmu_MonitorAssessment for: $execrunuid $platform_image $vmhostname");
if (my $pid = fork()) {
	# Parent
	$log->info("vmu_MonitorAssessment $execrunuid pid: $pid");
}
else {
	# Child
	$debug ||= '';
	my $script = catfile(getSwampDir(), 'bin', 'vmu_MonitorAssessment.pl');
	my $command = "source /etc/profile.d/swamp.sh; perl $script $execrunuid $owner $uiddomain $clusterid $procid $numjobstarts $debug";
	{exec($command)}; # use {} to prevent the warning about a statement following exec
	$log->error("PreAssessment $execrunuid - exec command: $command failed");
}

my $slot_size_start = computeDirectorySizeInBytes();
updateExecutionResults($execrunuid, {'slot_size_start' => $slot_size_start});

$log->info("PreAssessment: $execrunuid Exit");
timing_log_assessment_timepoint($execrunuid, 'prescript - exit');
exit(0);
