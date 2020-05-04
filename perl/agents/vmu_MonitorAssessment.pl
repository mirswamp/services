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
my $events_file = 'JobVMEvents.log';
my $vmip_file = 'vmip.txt';
my $MAX_OPEN_ATTEMPTS = 5;
my $RESET_WAIT_DURATION = 60 * 15; # seconds
my $RESET_MAX_ATTEMPTS = 1;
my $done_int = 0;
my $done_term = 0;

my %status_seen = ();
my $INITIAL_STATUS	= 'RUNSHSTART';
my $FINAL_STATUS	= 'ENDASSESSMENT';

my %status_messages = (
	$INITIAL_STATUS		=> 'Starting assessment run script',
	'BEGINASSESSMENT'	=> 'Performing assessment',
	'CONNECTEDUSERS'	=> 'Checking for connected users',
	$FINAL_STATUS		=> 'Shutting down the VM',
);

# logfilesuffix is the HTCondor clusterid 
my $logfilesuffix = ''; 
sub logfilename {
	my $name = catfile(getSwampDir(), 'log', $execrunuid . '_' . $logfilesuffix . '.log');
	return $name;
}

sub send_command_to_vm { my ($execrunuid, $vmhostname, $user_uuid, $projectid, $vmdomainname, $command) = @_ ;
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
sub get_next_status { my ($file, $final_status_seen) = @_ ;
	my $fh;
	if (! open($fh, '<', $file)) {
		$open_attempts += 1;
		if (! $final_status_seen) {
			$log->warn("Failed to open events file: $file $open_attempts");
		}
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

sub monitor { my ($execrunuid, $vmhostname, $user_uuid, $projectid, $vmdomainname, $job_status_message_suffix) = @_ ;
	my $time_start = time();
	my $sleep_time = 5; # seconds
	my $update_interval = 60 * 10; # seconds
	my $any_status_seen = 0;
	my $final_status_seen = 0;
	my $last_status;
	my $poll_count = 0;
	my $reset_attempts = 0;
	my $shutdown_sent = 0;
    while (! $done_term) {
		my ($open_attempts, $mstatus) = get_next_status($events_file, $final_status_seen);
		# check for termination
		if ($open_attempts > $MAX_OPEN_ATTEMPTS) {
			$log->info("$events_file max open attempts exceeded: $open_attempts $MAX_OPEN_ATTEMPTS");
			# void the vm_password field in the database to turn off ssh access button
			updateExecutionResults($execrunuid, {'vm_password' => ''});
			return 1 if ($final_status_seen);
			return -1 if ($any_status_seen);
			return 0;
		}
		# any current status
		if ($mstatus && exists($status_messages{$mstatus})) {
			my $job_status_message = $status_messages{$mstatus} . $job_status_message_suffix;
			updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $job_status_message);
			if ($mstatus eq $FINAL_STATUS) {
				$final_status_seen = 1;
				# void the vm_password field in the database to turn off ssh access button
				updateExecutionResults($execrunuid, {'vm_password' => ''});
				return 1;
			}
			$any_status_seen = 1;
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
			# caught INT signal - attempt to shutdown vm and continue monitor
			if ($done_int) {
				send_command_to_vm($execrunuid, $vmhostname, $user_uuid, $projectid, $vmdomainname, 'shutdown');
				$shutdown_sent = 1;
				next;
			}
			# check polling interval for sparse updating of ClassAd
			if ($poll_count >= ($update_interval / $sleep_time)) {
				my $time_now = time();
				my $seconds = $time_now - $time_start;
				my $date_now = strftime("%Y-%m-%d %H:%M:%S", localtime($time_now));
				my $date_start = strftime("%Y-%m-%d %H:%M:%S", localtime($time_start));
				my $job_status_message = "VM Failed - ";
				if ($any_status_seen) {
					$job_status_message = "VM Started and Failed - ";
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
						my $success = send_command_to_vm($execrunuid, $vmhostname, $user_uuid, $projectid, $vmdomainname, 'reset');
						if (! $success) {
							# on failure of reset -- shutdown
							$log->error("vm: $vmdomainname reset failed - shutdown sent");
							send_command_to_vm($execrunuid, $vmhostname, $user_uuid, $projectid, $vmdomainname, 'shutdown');
							$shutdown_sent = 1;
							# now just monitor for HTCondor to terminate the controlling job
						}
						$reset_attempts += 1;
					}
					else {
						$log->error("vm: $vmdomainname has been reset $reset_attempts times - shutdown sent");
						send_command_to_vm($execrunuid, $vmhostname, $user_uuid, $projectid, $vmdomainname, 'shutdown');
						$shutdown_sent = 1;
						# now just monitor for HTCondor to terminate the controlling job
					}
				}
			}
		}
		sleep $sleep_time;
		$poll_count += 1;
	}
	# caught TERM signal - attempt to shutdown vm
	if ($vmdomainname) {
		$log->info("MonitorAssessment: $execrunuid caught signal - shutdown $vmdomainname");
		send_command_to_vm($execrunuid, $vmhostname, $user_uuid, $projectid, $vmdomainname, 'shutdown');
	}
	# void the vm_password field in the database to turn off ssh access button
	updateExecutionResults($execrunuid, {'vm_password' => ''});
}

sub obtain_vmip { my ($execrunuid, $bogref, $vmhostname, $user_uuid, $projectid, $job_status_message_suffix) = @_ ;
	my $vmip_lookup_assessment_delay = $global_swamp_config->get('vmip_lookup_assessment_delay') || 600;
	# open vmip file and read vm ip address
	my $mstatus;
	for (my $i = 0; $i < $vmip_lookup_assessment_delay; $i++) {
		return if ($done_term);
		(my $open_attempts, $mstatus) = get_next_status($events_file, 0);
		# check for termination
		if ($open_attempts > $MAX_OPEN_ATTEMPTS) {
			$log->error("$events_file max open attempts exceeded: $open_attempts $MAX_OPEN_ATTEMPTS");
			return;
		}
		last if ($mstatus eq $INITIAL_STATUS);
		sleep 1;
	}
	if ($mstatus ne $INITIAL_STATUS) {
		$log->error("$events_file initial status not found");
		return;
	}
	# open Floodlight flow rule for licensed tools
	my $message = 'Obtaining VM IP Address' . $job_status_message_suffix;
	updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $message);
	my $vmip = getVMIPAddress($vmhostname);
	(my $license_result, $vmip) = openFloodlightAccess($global_swamp_config, $bogref, $vmhostname, $vmip);
	if ($vmip =~ m/^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/) {
		$log->info("Obtained vmip: $vmip" . $job_status_message_suffix);
	}
	else {
		$log->error("Failed to obtain vmip: $vmip" . $job_status_message_suffix);
	}
	updateExecutionResults($execrunuid, {'vm_ip_address' => "$vmip"});
	return $license_result;
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

# look for INITIAL_STATUS and then obtain vm ip address and open floodlight flow rule
timing_log_assessment_timepoint($execrunuid, 'obtain vmip - begin');
my $license_result = obtain_vmip($execrunuid, \%bog, $vmhostname, $user_uuid, $projectid, $job_status_message_suffix);
timing_log_assessment_timepoint($execrunuid, 'obtain vmip - end');

# -1 vm returns status but not final
#  0 vm returns no status
#  1 vm returns final status
my $status = monitor($execrunuid, $vmhostname, $user_uuid, $projectid, $vmdomainname, $job_status_message_suffix);
$log->info("MonitorAssessment: loop returns status: $status");

# close Floodlight flow rule for licensed tools
closeFloodlightAccess($global_swamp_config, \%bog, $license_result);

$log->info("MonitorAssessment: $execrunuid Exit");
timing_log_assessment_timepoint($execrunuid, 'monitor assessment - exit');
exit(0);
