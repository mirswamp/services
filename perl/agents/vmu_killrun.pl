#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2017 Software Assurance Marketplace

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
	identifyScript
	getLoggingConfigString 
	getSwampConfig
	getSwampDir 
	isSwampInABox
	buildExecRunAppenderLogFileName
	launchPadKill
	$LAUNCHPAD_SUCCESS
	getHTCondorJobId
	HTCondorJobStatus
	isAssessmentRun
	isViewerRun
	isMetricRun
	runType
	$RUNTYPE_ARUN
	$RUNTYPE_VRUN
	$RUNTYPE_MRUN
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
my $log;
my $tracelog;
my $execrunuid;
my $kill_sleep_time = 5; 	# seconds
my $kill_wait_time = 180;	# seconds
my $kill_rewrite_status_count = 5;
my $config = getSwampConfig();

sub logfilename {
	if ($execrunuid) {
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
	'debug'	=> \$debug,
	'execution_record_uuid=s'	=> \$execrunuid,
);

Log::Log4perl->init(getLoggingConfigString());
$log = Log::Log4perl->get_logger(q{});
$log->level($debug ? $TRACE : $INFO);
$tracelog = Log::Log4perl->get_logger('runtrace');
$tracelog->trace("$PROGRAM_NAME ($PID) called with args: @PRESERVEARGV");
identifyScript(\@PRESERVEARGV);

if ($execrunuid) {
	my $jobid = getHTCondorJobId($execrunuid);
	if ($jobid && ($jobid =~ m/^\d+\.\d+$/)) {
		my $viewerbog = {};
		if (isViewerRun($execrunuid)) {
			($viewerbog->{'projectid'}, $viewerbog->{'viewer'}) = (split '_', $execrunuid)[1,2];
		}
    	my $retval = launchPadKill($execrunuid, $jobid);
		if ($retval != $LAUNCHPAD_SUCCESS) {
			my $status_message = 'Terminate Failed';
			$tracelog->trace("$PROGRAM_NAME launchPadKill returned failure for $execrunuid $jobid: $retval $status_message");
			if (isAssessmentRun($execrunuid)) {
				updateClassAdAssessmentStatus($execrunuid, '', '', '', $status_message);
				updateRunStatus($execrunuid, $status_message, 1);
			}
			elsif (isViewerRun($execrunuid)) {
				updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_TERMINATE_FAILED, $status_message, $viewerbog);
			}
		}
		else {
			my $status_message = 'Terminating';
			$tracelog->trace("$PROGRAM_NAME launchPadKill returned success for $execrunuid $jobid: $retval $status_message");
			my $done = 0;
			my $total_sleep_time = 0;
			while (! $done) {
				if (isAssessmentRun($execrunuid)) {
					updateClassAdAssessmentStatus($execrunuid, '', '', '', $status_message);
				}
				elsif (isViewerRun($execrunuid)) {
					updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_TERMINATING, $status_message, $viewerbog);
				}
				my $retval = HTCondorJobStatus($jobid);
				last if (! $retval);
				$done = ($total_sleep_time >= $kill_wait_time);
				sleep $kill_sleep_time;
				$total_sleep_time += $kill_sleep_time;
			}
			$status_message = 'Terminated';
			if (isAssessmentRun($execrunuid)) {
				updateExecutionResults($execrunuid, {'vm_password' => ''});
				updateRunStatus($execrunuid, $status_message, 1);
			}
			for (my $i = 0; $i < $kill_rewrite_status_count; $i++) {
				if (isAssessmentRun($execrunuid)) {
					updateClassAdAssessmentStatus($execrunuid, '', '', '', $status_message);
				}
				elsif (isViewerRun($execrunuid)) {
					updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_TERMINATED, $status_message, $viewerbog);
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
