#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

use strict;
use warnings;
use English '-no_match_vars';
use File::Basename;
use File::Spec::Functions;
use Time::Local;
use POSIX qw(strftime);
use Log::Log4perl::Level;
use Log::Log4perl;

use FindBin qw($Bin);
use lib ("$FindBin::Bin/../perl5", "$FindBin::Bin/lib");

use SWAMP::vmu_Support qw(
	getStandardParameters
	setHTCondorEnvironment
	runScriptDetached
	identifyScript
	getSwampDir
	getLoggingConfigString
	systemcall
	loadProperties
	construct_vmhostname
	construct_vmdomainname
	getSwampConfig
	$global_swamp_config
	getVMIPAddress
	timing_log_assessment_timepoint
	$HTCONDOR_JOB_EVENTS_FILE
	$HTCONDOR_JOB_EVENTS_PATH
);
$global_swamp_config = getSwampConfig();
use SWAMP::vmu_AssessmentSupport qw(
	updateExecutionResults
	updateClassAdAssessmentStatus
);
use SWAMP::FloodlightAccess qw(
	openFloodlightAccess
	closeFloodlightAccess
);

$global_swamp_config ||= getSwampConfig();
my $log;
my $tracelog;
my $execrunuid;
my $events_file = $HTCONDOR_JOB_EVENTS_FILE;
my $events_path = $HTCONDOR_JOB_EVENTS_PATH;
my $MAX_MONITOR_FIRST_OPEN_ATTEMPTS = 50;
my $MAX_MONITOR_OPEN_ATTEMPTS = 5;
my $RESET_WAIT_DURATION = 60 * 15; # seconds
my $RESET_MAX_ATTEMPTS = 1;
my $done_int = 0;
my $done_term = 0;

my %status_seen = ();
my $INITIAL_STATUS	= 'RUNSHSTART';
my $FINAL_STATUS	= 'ENDASSESSMENT';
my $IPADDR_STATUS	= 'WROTEIPADDR';

my %status_messages = (
	$INITIAL_STATUS		=> 'Starting assessment run script',
	$IPADDR_STATUS		=> 'Wrote ip address',
	'BEGINASSESSMENT'	=> 'Performing assessment',
	'CONNECTEDUSERS'	=> 'Checking for connected users',
	$FINAL_STATUS		=> 'Shutting down the assessment machine',
);

# logfilesuffix is the HTCondor clusterid 
my $logfilesuffix = ''; 
sub logfilename {
	my $name = catfile(getSwampDir(), 'log', $execrunuid . '_' . $logfilesuffix . '.log');
	return $name;
}

sub send_command_to_assessment_machine { my ($execrunuid, $bogref, $vmhostname, $user_uuid, $projectid, $vmdomainname, $command) = @_ ;
	# FIXME update this routine to properly operate on docker containers
	return 0 if ($bogref->{'use_docker_universe'});
	my ($output, $status) = systemcall("sudo virsh $command $vmdomainname");
	my $success_regex = 'Domain.*is being shutdown';
	$success_regex = 'Domain.*was reset' if ($command eq 'reset');
	if ($status || ($output && ($output !~ m/$success_regex/))) {
		$log->error("virsh $command to: $vmdomainname failed: <$output>");
		updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, "vm $command failed");
		return 0;
	}
	$log->info("virsh $command to: $vmdomainname succeeded");
	updateClassAdAssessmentStatus($execrunuid, $user_uuid, $projectid, $vmhostname, "vm $command");
	return 1;
}

my $open_attempts = 0;
sub get_next_status { my ($file) = @_ ;
	my $fh;
	if (! open($fh, '<', $file)) {
		$open_attempts += 1;
		return ($open_attempts, '');
	}
	$open_attempts = 0;
	my @lines = <$fh>;
	close($fh);
	foreach my $line (@lines) {
		$line =~ s/[^[:alnum:]]//g;
		next if (exists($status_seen{$line}));
		$status_seen{$line} = 1;
		return ($open_attempts, $line);
	}
	return ($open_attempts, '');
}

sub obtain_viewerip { my ($execrunuid, $bogref, $vmhostname, $user_uuid, $projectid, $job_status_message_suffix) = @_ ;
	# open Floodlight flow rule for licensed tools
	my $message = 'Obtaining Assessment Machine IP Address' . $job_status_message_suffix;
	updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $message);
	my $viewerip = getVMIPAddress($vmhostname);
	(my $license_result, $viewerip) = openFloodlightAccess($global_swamp_config, $bogref, $vmhostname, $viewerip);
	if ($viewerip =~ m/^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/) {
		$log->info("Obtained viewer ip address: $viewerip" . $job_status_message_suffix);
	}
	else {
		$log->error("Failed to obtain viewer ip address: $viewerip" . $job_status_message_suffix);
	}
	updateExecutionResults($execrunuid, {'vm_ip_address' => "$viewerip"});
	return $license_result;
}

sub monitor { my ($execrunuid, $bogref, $vmhostname, $user_uuid, $projectid, $vmdomainname, $job_status_message_suffix) = @_ ;
	my $time_start = time();
	my $sleep_time = 5; # seconds
	my $update_interval = 60 * 10; # seconds
	my $any_status_seen = 0;
	my $last_status;
	my $poll_count = 0;
	my $reset_attempts = 0;
	my $shutdown_sent = 0;
	my $license_result;
	# before first open, wait for an extended period of time
	my $max_open_attempts = $MAX_MONITOR_FIRST_OPEN_ATTEMPTS;
    while (! $done_term) {
		my ($open_attempts, $mstatus) = get_next_status($events_path);
		# check for termination
		if ($open_attempts > $max_open_attempts) {
			$log->info("$events_file max open attempts exceeded: $open_attempts $max_open_attempts");
			# void the vm_password field in the database to turn off ssh access button
			updateExecutionResults($execrunuid, {'vm_password' => ''});
			# close Floodlight flow rule for licensed tools
			closeFloodlightAccess($global_swamp_config, $bogref, $license_result);
			my $retval = 0;
			$retval = -1 if ($any_status_seen);
			$log->info("MonitorAssessment: max open attempts exceeded - monitor loop returning status: $retval");
			return $retval;
		}
		# any current status
		if ($mstatus && exists($status_messages{$mstatus})) {
			my $job_status_message = $status_messages{$mstatus} . $job_status_message_suffix;
			updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $job_status_message);
			if ($mstatus eq $FINAL_STATUS) {
				# void the vm_password field in the database to turn off ssh access button
				updateExecutionResults($execrunuid, {'vm_password' => ''});
				# close Floodlight flow rule for licensed tools
				closeFloodlightAccess($global_swamp_config, $bogref, $license_result);
				my $retval = 1;
				$log->info("MonitorAssessment: found status - $mstatus - monitor loop returning status: $retval");
				return $retval;
			}
			elsif ($mstatus eq $IPADDR_STATUS) {
				# obtain machine ip address and open floodlight flow rule
				$license_result = obtain_viewerip($execrunuid, $bogref, $vmhostname, $user_uuid, $projectid, $job_status_message_suffix);

			}
			$any_status_seen = 1;
			# now that we have seen a status, wait less long for subsequent opens
			$max_open_attempts = $MAX_MONITOR_OPEN_ATTEMPTS;
			$poll_count = 0;
			$last_status = $mstatus;
		}
		# no current status - have prior status
		elsif ($last_status) {
			if ($poll_count >= ($update_interval / $sleep_time)) {
				my $job_status_message = $status_messages{$last_status} . $job_status_message_suffix;
				updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $job_status_message);
				$poll_count = 0;
			}
		}
		# no current status - no prior status - shutdown not yet sent
		elsif (! $shutdown_sent) {
			# caught INT signal - attempt to shutdown machine and continue monitor
			if ($done_int) {
				send_command_to_assessment_machine($execrunuid, $bogref, $vmhostname, $user_uuid, $projectid, $vmdomainname, 'shutdown');
				$shutdown_sent = 1;
				next;
			}
			# check polling interval for sparse updating of ClassAd
			if ($poll_count >= ($update_interval / $sleep_time)) {
				my $time_now = time();
				my $seconds = $time_now - $time_start;
				my $date_now = strftime("%Y-%m-%d %H:%M:%S", localtime($time_now));
				my $date_start = strftime("%Y-%m-%d %H:%M:%S", localtime($time_start));
				my $job_status_message = "Viewer Machine Failed - ";
				if ($any_status_seen) {
					$job_status_message = "Viewer Machine Started and Failed - ";
				}
				$job_status_message .= "$date_start $date_now ($seconds)" . $job_status_message_suffix;
				updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $job_status_message);
				$poll_count = 0;
			}
			# check for reset condition and attempt to reset
			# time calculation is independent of poll interval
			if (! $any_status_seen && $vmdomainname) {
				my $time_now = time();
				# wait for at least RESET_WAIT_DURATION between each reset
				if (($time_now - $time_start) > ($RESET_WAIT_DURATION * ($reset_attempts + 1))) {
					# attempt to reset for RESET_MAX_ATTEMPTS
					if ($reset_attempts < $RESET_MAX_ATTEMPTS) {
						my $success = send_command_to_assessment_machine($execrunuid, $bogref, $vmhostname, $user_uuid, $projectid, $vmdomainname, 'reset');
						if (! $success) {
							# on failure of reset -- shutdown
							$log->error("vm: $vmdomainname reset failed - shutdown sent");
							send_command_to_assessment_machine($execrunuid, $bogref, $vmhostname, $user_uuid, $projectid, $vmdomainname, 'shutdown');
							$shutdown_sent = 1;
							# now just monitor for HTCondor to terminate the controlling job
						}
						$reset_attempts += 1;
					}
					else {
						$log->error("vm: $vmdomainname has been reset $reset_attempts times - shutdown sent");
						send_command_to_assessment_machine($execrunuid, $bogref, $vmhostname, $user_uuid, $projectid, $vmdomainname, 'shutdown');
						$shutdown_sent = 1;
						# now just monitor for HTCondor to terminate the controlling job
					}
				}
			}
		}
		sleep $sleep_time;
		$poll_count += 1;
	}
	# caught TERM signal - attempt to shutdown assessment machine
	if ($vmdomainname) {
		$log->info("MonitorAssessment: $execrunuid caught signal - shutdown $vmdomainname");
		send_command_to_assessment_machine($execrunuid, $bogref, $vmhostname, $user_uuid, $projectid, $vmdomainname, 'shutdown');
	}
	# void the vm_password field in the database to turn off ssh access button
	updateExecutionResults($execrunuid, {'vm_password' => ''});
	my $retval = -15;
	$log->info("MonitorAssessment: caught TERM signal - monitor loop returning status: $retval");
	return $retval;
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

if (open(my $fh, '>', "vmu_MonitorAssessment_${clusterid}.pid")) {
	print $fh "$$\n";
	close($fh);
}

sub signal_handler { my ($signal_name) = @_ ;
	$log->info("MonitorAssessment for: $execrunuid signal: $signal_name caught");
	if ($signal_name eq 'TERM') {
		$done_term = 1;
	}
	elsif ($signal_name eq 'INT') {
		$done_int = 1;
	}
}
$SIG{INT} = \&signal_handler;
$SIG{TERM} = \&signal_handler;

my $vmhostname = construct_vmhostname($execrunuid, $clusterid, $procid);
my $vmdomainname = construct_vmdomainname($owner, $uiddomain, $clusterid, $procid);

# Initialize Log4perl
Log::Log4perl->init(getLoggingConfigString());

timing_log_assessment_timepoint($execrunuid, 'monitor assessment - start');
$log = Log::Log4perl->get_logger(q{});
$log->level($debug ? $TRACE : $INFO);
$log->info("MonitorAssessment: $execrunuid Begin");
$tracelog = Log::Log4perl->get_logger('runtrace');
$tracelog->trace("$PROGRAM_NAME ($PID) called with args: @ARGV");
setHTCondorEnvironment();
identifyScript(\@ARGV);
# my $startupdir = runScriptDetached();
# chdir($startupdir);

my %bog;
my $bogfile = $execrunuid . '.bog';
loadProperties($bogfile, \%bog);
my $user_uuid = $bog{'userid'} || 'null';
my $projectid = $bog{'projectid'} || 'null';

my $job_status_message_suffix = '';
if ($numjobstarts > 0) {
	my $htcondor_assessment_max_retries = $global_swamp_config->get('htcondor_assessment_max_retries') || 3;
	$job_status_message_suffix = " retry($numjobstarts/$htcondor_assessment_max_retries)";
}

# -15 monitor receives TERM signal
# -1  machine returns status but not final
#  0  machine returns no status
#  1  machine returns final status
$log->info("MonitorAssessment: starting monitor loop");
my $status = monitor($execrunuid, \%bog, $vmhostname, $user_uuid, $projectid, $vmdomainname, $job_status_message_suffix);
$log->info("MonitorAssessment: monitor loop returned status: $status");

timing_log_assessment_timepoint($execrunuid, 'monitor assessment - exit');
$log->info("MonitorAssessment: $execrunuid Exit");
exit(0);
