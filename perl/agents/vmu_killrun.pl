#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2018 Software Assurance Marketplace

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
	identifyScript
	deleteJobDir
	getLoggingConfigString 
	getSwampConfig
	getSwampDir 
	isSwampInABox
	buildExecRunAppenderLogFileName
	launchPadKill
	$LAUNCHPAD_SUCCESS
	getHTCondorJobId
	HTCondorJobStatus
);

use SWAMP::vmu_AssessmentSupport qw(
	updateExecutionResults
	updateClassAdAssessmentStatus
	updateRunStatus
);

use SWAMP::vmu_ViewerSupport qw(
	$VIEWER_STATE_NO_RECORD
	$VIEWER_STATE_LAUNCHING
	$VIEWER_STATE_READY
	$VIEWER_STATE_STOPPING
	$VIEWER_STATE_JOBDIR_FAILED
	$VIEWER_STATE_SHUTDOWN
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
my $kill_sleep_time = 5; 	# seconds
my $kill_wait_time = 180;	# seconds
my $kill_rewrite_status_count = 10;

sub logfilename {
	if ($execrunuid) {
		my $config = getSwampConfig();
    	if (isSwampInABox($config)) {
        	my $name = buildExecRunAppenderLogFileName($execrunuid);
        	return $name;
    	}   
	}
    my $name = basename($PROGRAM_NAME, ('.pl'));
    chomp $name;
    return catfile(getSwampDir(), 'log', $name . '.log');
}

my @PRESERVEARGV = @ARGV;
GetOptions(
	'debug'						=> \$debug,
	'execution_record_uuid=s'	=> \$execrunuid,
	'detached!'					=> \$asdetached,
);

Log::Log4perl->init(getLoggingConfigString());
$log = Log::Log4perl->get_logger(q{});
$log->level($debug ? $TRACE : $INFO);
$tracelog = Log::Log4perl->get_logger('runtrace');
$tracelog->trace("$PROGRAM_NAME ($PID) called with args: @PRESERVEARGV");
identifyScript(\@PRESERVEARGV);

if ($execrunuid) {
	runScriptDetached() if ($asdetached);
	my ($jobid, $type, $returned_execrunuid) = getHTCondorJobId($execrunuid);
	if ($jobid && ($jobid =~ m/^\d+\.\d+$/)) {
		my $viewerbog = {};
		if ($type eq 'vrun') {
			my $viewer_name = (split, '_', $returned_execrunuid)[2];
			$viewerbog->{'projectid'} = $execrunuid;
			$viewerbog->{'viewer'} = $viewer_name;
		}
    	my $retval = launchPadKill($returned_execrunuid, $jobid);
		if ($retval != $LAUNCHPAD_SUCCESS) {
			my $status_message = 'Terminate Failed';
			$tracelog->trace("$PROGRAM_NAME launchPadKill returned failure for $returned_execrunuid $jobid: $retval $status_message");
			if ($type eq 'arun' || $type eq 'mrun') {
				updateClassAdAssessmentStatus($returned_execrunuid, '', '', '', $status_message);
				updateRunStatus($returned_execrunuid, $status_message, 1);
			}
			elsif ($type eq 'vrun') {
				updateClassAdViewerStatus($returned_execrunuid, $VIEWER_STATE_TERMINATE_FAILED, $status_message, $viewerbog);
			}
		}
		else {
			my $status_message = 'Terminating';
			$tracelog->trace("$PROGRAM_NAME launchPadKill returned success for $returned_execrunuid $jobid: $retval $status_message");
			my $done = 0;
			my $total_sleep_time = 0;
			while (! $done) {
				if ($type eq 'arun' || $type eq 'mrun') {
					updateClassAdAssessmentStatus($returned_execrunuid, '', '', '', $status_message);
				}
				elsif ($type eq 'vrun') {
					updateClassAdViewerStatus($returned_execrunuid, $VIEWER_STATE_TERMINATING, $status_message, $viewerbog);
				}
				my $retval = HTCondorJobStatus($jobid);
				last if (! $retval);
				$done = ($total_sleep_time >= $kill_wait_time);
				sleep $kill_sleep_time;
				$total_sleep_time += $kill_sleep_time;
			}
			my $status = deleteJobDir($returned_execrunuid);
			if ($status) {
				$tracelog->info("$PROGRAM_NAME - job directory for: $returned_execrunuid successfully deleted");
			}
			else {
				$tracelog->info("$PROGRAM_NAME - job directory for: $returned_execrunuid deletion failed");
			}
			$status_message = 'Terminated';
			if ($type eq 'arun' || $type eq 'mrun') {
				updateExecutionResults($returned_execrunuid, {'vm_password' => ''});
				updateRunStatus($returned_execrunuid, $status_message, 1);
			}
			# rewrite status until the exec node job monitor has exited
			for (my $i = 0; $i < $kill_rewrite_status_count; $i++) {
				if ($type eq 'arun' || $type eq 'mrun') {
					updateClassAdAssessmentStatus($returned_execrunuid, '', '', '', $status_message);
				}
				elsif ($type eq 'vrun') {
					updateClassAdViewerStatus($returned_execrunuid, $VIEWER_STATE_TERMINATED, $status_message, $viewerbog);
				}
				sleep $kill_sleep_time;
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
