#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2019 Software Assurance Marketplace

use 5.014;
use utf8;
use warnings;
use strict;
use English '-no_match_vars';
use Getopt::Long qw(GetOptions);
use File::Basename qw(basename);
use File::Spec::Functions;
use Log::Log4perl::Level;
use Log::Log4perl;

use FindBin qw($Bin);
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );

use SWAMP::vmu_Support qw(
	runScriptDetached
	setHTCondorEnvironment
	identifyScript
	getLoggingConfigString 
	getSwampDir 
	launchPadKill
	$LAUNCHPAD_SUCCESS
	getHTCondorJobId
	HTCondorJobStatus
	getSwampConfig
	$global_swamp_config
);

use SWAMP::vmu_AssessmentSupport qw(
	updateExecutionResults
	updateClassAdAssessmentStatus
	updateRunStatus
);

use SWAMP::vmu_ViewerSupport qw(
	$VIEWER_STATE_TERMINATING
	$VIEWER_STATE_TERMINATED
	$VIEWER_STATE_TERMINATE_FAILED
	updateClassAdViewerStatus
);

my $debug = 0;
my $asdetached = 1;
my $log;
my $tracelog;
my $execrunuid;
my $hard_kill;
my $configfile;
my $kill_sleep_time = 5; 	# seconds
my $kill_wait_time = 180;	# seconds

sub logfilename {
    my $name = basename($PROGRAM_NAME, ('.pl'));
    chomp $name;
    return catfile(getSwampDir(), 'log', $name . '.log');
}

my @PRESERVEARGV = @ARGV;
GetOptions(
	'debug'						=> \$debug,
	'execution_record_uuid=s'	=> \$execrunuid,
	'hard=s'					=> \$hard_kill,
	'detached!'					=> \$asdetached,
	'config=s'					=> \$configfile,
);
# viewer jobs provide hard kill and graceful shutdown
# all other jobs provide only hard kill
# the default for viewer jobs is graceful shutdown
my $graceful_shutdown = 0;

Log::Log4perl->init(getLoggingConfigString());
$log = Log::Log4perl->get_logger(q{});
$log->level($TRACE);
$tracelog = Log::Log4perl->get_logger('runtrace');
$tracelog->trace("$PROGRAM_NAME ($PID) called with args: @PRESERVEARGV");
setHTCondorEnvironment();
identifyScript(\@PRESERVEARGV);

if ($execrunuid) {
	runScriptDetached() if ($asdetached);
	my ($jobid, $type, $returned_execrunuid, $viewer_instanceuid) = getHTCondorJobId($execrunuid);
	if ($jobid && ($jobid =~ m/^\d+\.\d+$/)) {
		my $viewerbog = {};
		if ($type eq 'vrun') {
			my $viewer_name = '';
			$viewer_name = (split '_', $returned_execrunuid)[2] if ($returned_execrunuid);
			$viewerbog->{'projectid'} = $execrunuid;
			$viewerbog->{'viewer'} = $viewer_name;
			$viewerbog->{'viewer_uuid'} = $viewer_instanceuid;
			# the default for viewer jobs is graceful shutdown
			$graceful_shutdown = 1 if (! defined($hard_kill) || ($hard_kill =~ m/false/i));
		}
    	my $retval = launchPadKill($returned_execrunuid, $jobid, $type, $graceful_shutdown);
		if ($retval != $LAUNCHPAD_SUCCESS) {
			my $job_status_message = 'Terminate Failed';
			$tracelog->trace("$PROGRAM_NAME launchPadKill returned failure for $returned_execrunuid $jobid: $retval $job_status_message");
			# these status page entries will be overwritten by the entries from the monitor 
			if ($type eq 'arun' || $type eq 'mrun') {
				updateClassAdAssessmentStatus($returned_execrunuid, '', '', '', $job_status_message);
				updateRunStatus($returned_execrunuid, $job_status_message, 1);
			}
			elsif ($type eq 'vrun') {
				updateClassAdViewerStatus($returned_execrunuid, $VIEWER_STATE_TERMINATE_FAILED, $job_status_message, $viewerbog);
			}
		}
		else {
			# query condor job queue for jobid
			# stop when jobid not found in queue
			# or time limit expires

			my $job_status_message = 'Terminating';
			$tracelog->trace("$PROGRAM_NAME launchPadKill returned success for $returned_execrunuid $jobid: $retval $job_status_message");
			my $total_sleep_time = 0;
			my $job_found = HTCondorJobStatus($jobid);
			my $timeout = 0;
			while ($job_found && ! $timeout) {
				if ($type eq 'arun' || $type eq 'mrun') {
					updateClassAdAssessmentStatus($returned_execrunuid, '', '', '', $job_status_message);
				}
				elsif ($type eq 'vrun') {
					updateClassAdViewerStatus($returned_execrunuid, $VIEWER_STATE_TERMINATING, $job_status_message, $viewerbog);
				}
				$job_found = HTCondorJobStatus($jobid);
				if ($job_found) {
					sleep $kill_sleep_time;
					$total_sleep_time += $kill_sleep_time;
					$timeout = ($total_sleep_time >= $kill_wait_time);
				}
			}

			# now rewrite status to collector and database
			$job_status_message = 'Terminated';
			$job_status_message = 'Terminate Status Unknown' if ($job_found);
			if ($type eq 'arun' || $type eq 'mrun') {
				updateClassAdAssessmentStatus($returned_execrunuid, '', '', '', $job_status_message);
				updateExecutionResults($returned_execrunuid, {'vm_password' => ''});
				updateRunStatus($returned_execrunuid, $job_status_message, 1);
			}
			elsif ($type eq 'vrun') {
				updateClassAdViewerStatus($returned_execrunuid, $VIEWER_STATE_TERMINATED, $job_status_message, $viewerbog);
			}
		}
	}
	else {
		$tracelog->error("$PROGRAM_NAME - no HTCondor jobid to kill for: $execrunuid");
		# do not modify any status on this condition
	}
}
else {
	$tracelog->error("$PROGRAM_NAME - no execrunuid to kill");
	# do not modify any status on this condition
}
