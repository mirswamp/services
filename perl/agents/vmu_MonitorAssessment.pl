#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2018 Software Assurance Marketplace

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
	identifyScript
	getSwampDir
	getSwampConfig
	isSwampInABox
	buildExecRunAppenderLogFileName
	getLoggingConfigString
	systemcall
	loadProperties
	construct_vmhostname
	construct_vmdomainname
	deleteJobDir
);
use SWAMP::vmu_AssessmentSupport qw(
	updateExecutionResults
	updateClassAdAssessmentStatus
);
use SWAMP::Libvirt qw(getVMIPAddress);
use SWAMP::FloodlightAccess qw(
	openFloodlightAccess
	closeFloodlightAccess
);

my $log;
my $tracelog;
my $config = getSwampConfig();
my $execrunuid;
my $clusterid;
my $events_file = catfile('events', 'JobVMEvents.log');
my $MAX_OPEN_ATTEMPTS = 5;
my $RESET_WAIT_DURATION = 60 * 15; # seconds
my $RESET_MAX_ATTEMPTS = 1;
my $done_int = 0;
my $done_term = 0;

my %status_seen = ();
my $FINAL_STATUS	= 'ENDASSESSMENT';

my %status_messages = (
	'RUNSHSTART'		=> 'Starting assessment run script',
	'BEGINASSESSMENT'	=> 'Performing assessment',
	$FINAL_STATUS		=> 'Shutting down the VM',
);

sub logfilename {
	if (isSwampInABox($config)) {
		my $name = buildExecRunAppenderLogFileName($execrunuid);
		return $name;
	}
    my $name = basename($0, ('.pl'));
    chomp $name;
	$name =~ s/Monitor//sxm;
    $name .= '_' . $clusterid;
    return catfile(getSwampDir(), 'log', $name . '.log');
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

sub dump_vm_xml { my ($vmdomainname) = @_ ;
	my $vmxml = $vmdomainname . '_dump.xml';
	$log->info("virsh dumpxml $vmdomainname > $vmxml");
	my ($output, $status) = systemcall("sudo virsh dumpxml $vmdomainname > $vmxml");
	if ($status) {
		$log->error("virsh dumpxml $vmdomainname failed: <$output>");
	}
}
			
sub monitor { my ($execrunuid, $vmhostname, $user_uuid, $projectid, $vmdomainname) = @_ ;
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
			updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $status_messages{$mstatus});
			if ($mstatus eq $FINAL_STATUS) {
				$final_status_seen = 1;
				# void the vm_password field in the database to turn off ssh access button
				updateExecutionResults($execrunuid, {'vm_password' => ''});
			}
			# dump vmdomainname xml on first status
			if (! $any_status_seen) {
				dump_vm_xml($vmdomainname);
			}
			$any_status_seen = 1;
			$poll_count = 0;
			$last_status = $mstatus;
		}
		# no current status - have prior status
		elsif ($last_status) {
			if ($poll_count >= ($update_interval / $sleep_time)) {
				updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $status_messages{$last_status});
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
				my $message = "VM Failed - ";
				if ($any_status_seen) {
					$message = "VM Started and Failed - ";
				}
				$message .= "$date_start $date_now ($seconds)";
				updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $message);
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

########
# Main #
########

# args: execrunuid owner uiddomain clusterid procid [debug]
# execrunuid is global because it is used in logfilename
# clusterid is global because it is used in logfilename
my ($owner, $uiddomain, $procid, $debug) = getStandardParameters(\@ARGV, \$execrunuid, \$clusterid);
if (! $execrunuid || ! $clusterid) {
	# we have no execrunuid or clusterid for the log4perl log file name
	exit(1);
}

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

Log::Log4perl->init(getLoggingConfigString());
$log = Log::Log4perl->get_logger(q{});
$log->level($debug ? $TRACE : $INFO);
$log->info("MonitorAssessment: $execrunuid Begin");
$tracelog = Log::Log4perl->get_logger('runtrace');
$tracelog->trace("$PROGRAM_NAME ($PID) called with args: @ARGV");
identifyScript(\@ARGV);

my %bog;
my $bogfile = $execrunuid . '.bog';
loadProperties($bogfile, \%bog);
my $user_uuid = $bog{'userid'} || 'null';
my $projectid = $bog{'projectid'} || 'null';

# open Floodlight flow rule for licensed tools
my $message = 'Obtaining VM IP Address';
updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $message);
my $vmip_lookup_delay = $config->get('vmip_lookup_delay') || 10;
sleep $vmip_lookup_delay;
my $vmip = getVMIPAddress($config, $vmhostname);
(my $license_result, $vmip) = openFloodlightAccess($config, \%bog, $vmhostname, $vmip);
if ($vmip =~ m/^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/) {
	$message = 'Obtained vmip';
	$log->info($message . ": $vmip");
}
else {
	$message = 'Failed to obtain vmip';
	$log->error($message . ": $vmip");
}
updateExecutionResults($execrunuid, {'status' => $message, 'vm_ip_address' => "$vmip"});

# -1 vm returns status but not final
#  0 vm returns no status
#  1 vm returns final status
my $status = monitor($execrunuid, $vmhostname, $user_uuid, $projectid, $vmdomainname);
$log->info("MonitorAssessment: loop returns status: $status");

# close Floodlight flow rule for licensed tools
closeFloodlightAccess($config, \%bog, $license_result);

# signal delete jobdir on sumbit node iff some status returned from vm
if ($status) {
	$status = deleteJobDir($execrunuid);
	if ($status) {
		$log->info("MonitorAssessment: - job directory for: $execrunuid successfully deleted");
	}
	else {
		$log->error("MonitorAssessment - job directory for: $execrunuid deletion failed");
	}
}
else {
	$log->info("MonitorAssessment: - job directory for: $execrunuid deletion skipped");
}

$log->info("MonitorAssessment: $execrunuid Exit");
exit(0);
