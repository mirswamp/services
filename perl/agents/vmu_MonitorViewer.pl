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
	getVMIPAddress
	getSwampDir
	getLoggingConfigString
	loadProperties
	construct_vmhostname
	getSwampConfig
	$global_swamp_config
	timing_log_viewer_timepoint
);
$global_swamp_config ||= getSwampConfig();
use SWAMP::vmu_ViewerSupport qw(
	$VIEWER_STATE_ERROR
	$VIEWER_STATE_LAUNCHING
	$VIEWER_STATE_READY
	$VIEWER_STATE_STOPPING
	$VIEWER_STATE_SHUTDOWN
	updateClassAdViewerStatus
);

$global_swamp_config ||= getSwampConfig();
my $log;
my $tracelog;
my $execrunuid;
my $events_file = 'JobVMEvents.log';
my $vmip_file = 'vmip.txt';
my $MAX_OPEN_ATTEMPTS = 5;
my $done = 0;

my %status_seen = ();
my $INITIAL_STATUS		= 'RUNSHSTART';
my $FINAL_UP_STATUS		= 'VIEWERUP';
my $FINAL_DOWN_STATUS	= 'VIEWERDOWN';
my $status_messages = {
	$INITIAL_STATUS			=> ['Starting viewer vm run script', 				$VIEWER_STATE_LAUNCHING	],
	'NOIP'					=> ['Viewer vm has no ip address', 					$VIEWER_STATE_STOPPING	],
	'NOIPSHUTDOWN'			=> ['Shutting down viewer vm for no ip address', 	$VIEWER_STATE_STOPPING	],
	'MYSQLSTART'			=> ['Starting mysql service', 						$VIEWER_STATE_LAUNCHING	],
	'MYSQLFAIL'				=> ['Service mysql failed to start', 				$VIEWER_STATE_STOPPING	],
	'MYSQLSHUTDOWN'			=> ['Shutting down viewer vm for no mysql', 		$VIEWER_STATE_STOPPING	],
	'MYSQLRUN'				=> ['Service mysql running', 						$VIEWER_STATE_LAUNCHING	],
	'MYSQLEMPTY'			=> ['Restoring empty mysql database', 				$VIEWER_STATE_LAUNCHING	],
	'MYSQLGRANT'			=> ['Granting privileges for viewer database', 		$VIEWER_STATE_LAUNCHING	],
	'MYSQLDROP'				=> ['Dropping viewer database', 					$VIEWER_STATE_LAUNCHING	],
	'USERDB'				=> ['Restoring user database', 						$VIEWER_STATE_LAUNCHING	],
	'EMPTYDB'				=> ['Restoring empty viewer database', 				$VIEWER_STATE_LAUNCHING	],
	'CREATEPROXY'			=> ['Creating proxy directory', 					$VIEWER_STATE_LAUNCHING	],
	'CONFIG'				=> ['Restoring viewer configuration', 				$VIEWER_STATE_LAUNCHING	],
	'EMPTYCONFIG'			=> ['Initializing viewer configuration', 			$VIEWER_STATE_LAUNCHING	],
	'PROPERTIES'			=> ['Copying viewer properties', 					$VIEWER_STATE_LAUNCHING	],
	'APIKEY'				=> ['Inserting APIKEY', 							$VIEWER_STATE_LAUNCHING	],
	'BASEURL'				=> ['Inserting DefaultConfiguration', 				$VIEWER_STATE_LAUNCHING	],
	'WARFILE'				=> ['Restoring viewer war file', 					$VIEWER_STATE_LAUNCHING	],
	'TOMCATSTART'			=> ['Starting tomcat service', 						$VIEWER_STATE_LAUNCHING	],
	'TOMCATFAIL'			=> ['Service tomcat failed to start', 				$VIEWER_STATE_STOPPING	],
	'CONNECTEDUSERS'		=> ['Checking for connected users', 				$VIEWER_STATE_STOPPING	],
	'TOMCATSHUTDOWN'		=> ['Shutting down viewer vm for no tomcat', 		$VIEWER_STATE_STOPPING	],
	'TOMCATRUN'				=> ['Service tomcat running', 						$VIEWER_STATE_LAUNCHING	],
	'TIMERSTART'			=> ['Starting viewer checktimeout', 				$VIEWER_STATE_LAUNCHING	],
	'TIMERSHUTDOWN'			=> ['Shutting down viewer after timeout', 			$VIEWER_STATE_STOPPING	],
	'VIEWERDBBACKUP'		=> ['Starting viewer database backup', 				$VIEWER_STATE_STOPPING	],
	'VIEWERDBDUMPFAIL'		=> ['Viewer database dump failed', 					$VIEWER_STATE_STOPPING	],
	'VIEWERDBDUMPSUCCESS'	=> ['Viewer database dump succeeded', 				$VIEWER_STATE_STOPPING	],
	'VIEWERDBCONFIGFAIL'	=> ['Viewer configuration tar failed', 				$VIEWER_STATE_STOPPING	],
	'VIEWERDBCONFIGSUCCESS'	=> ['Viewer configuration tar succeeded', 			$VIEWER_STATE_STOPPING	],
	'VIEWERDBBUNDLESKIP'	=> ['Viewer user data bundling skipped', 			$VIEWER_STATE_STOPPING	],
	'VIEWERDBNOBUNDLE'		=> ['Viewer no user data to bundle', 				$VIEWER_STATE_STOPPING	],
	'VIEWERDBBUNDLEFAIL'	=> ['Viewer user data bundling failed', 			$VIEWER_STATE_STOPPING	],
	'VIEWERDBBUNDLESUCCESS'	=> ['Viewer user data bundling succeeded', 			$VIEWER_STATE_STOPPING	],
	$FINAL_UP_STATUS		=> ['Viewer is up', 								$VIEWER_STATE_READY		],
	$FINAL_DOWN_STATUS		=> ['Viewer is shutdown', 							$VIEWER_STATE_SHUTDOWN  ],
};

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

sub monitor { my ($execrunuid, $bogref) = @_ ;
	my $time_start = time();
	my $sleep_time = 5; # seconds
	my $update_interval = 60 * 10; # seconds
	my $any_status_seen = 0;
	my $final_status_seen = 0;
	my $last_status;
	my $poll_count = 0;
    while (! $done) {
		my ($open_attempts, $mstatus) = get_next_status($events_file, $final_status_seen);
		if ($open_attempts > $MAX_OPEN_ATTEMPTS) {
			$log->info("$events_file max open attempts exceeded: $open_attempts $MAX_OPEN_ATTEMPTS");
			return;
		}
		if ($mstatus && ($mstatus eq $FINAL_DOWN_STATUS)) {
			$log->info("MonitorViewer $mstatus - leaving monitor loop");
			return;
		}
		if ($mstatus && exists($status_messages->{$mstatus})) {
			my ($message, $state) = @{$status_messages->{$mstatus}};
			$log->info("Status: $mstatus state: $state message: $message");
			# this is where VIEWER_STATE_READY is set
			if ($mstatus eq $FINAL_UP_STATUS) {
				$log->info("MonitorViewer entering collector beacon mode");
				$final_status_seen = 1;
			}
			$any_status_seen = 1;
			updateClassAdViewerStatus($execrunuid, $state, $message, $bogref);
			$poll_count = 0;
			$last_status = $mstatus;
		}
		elsif ($last_status) {
			if ($poll_count >= ($update_interval / $sleep_time)) {
				my ($message, $state) = @{$status_messages->{$last_status}};
				updateClassAdViewerStatus($execrunuid, $state, $message, $bogref);
				$poll_count = 0;
			}
			# if status file has gone away this job should exit
			if ($open_attempts > 0) {
				$log->info("MonitorViewer entering exit mode") if ($open_attempts == 1);
			}
		}
		else {
			if ($poll_count >= ($update_interval / $sleep_time)) {
				my $time_now = time();
				my $seconds = $time_now - $time_start;
                my $date_now = strftime("%Y-%m-%d %H:%M:%S", localtime($time_now));
				my $date_start = strftime("%Y-%m-%d %H:%M:%S", localtime($time_start));
				my $message = "VM Failed - ";
				if ($any_status_seen) {
					$message = "VM Started and Failed - currently unknown - ";
				}   
				$message .= "$date_start $date_now ($seconds)";
				updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_ERROR, $message, $bogref);
				$poll_count = 0;
			}
		}
		sleep $sleep_time;
		$poll_count += 1;
	}
}

sub obtain_vmip { my ($execrunuid, $bogref, $vmhostname) = @_ ;
	my $vmip_lookup_viewer_delay = $global_swamp_config->get('vmip_lookup_viewer_delay') || 100;
	# open vmip file and read vm ip address
	my $mstatus;
    for (my $i = 0; $i < $vmip_lookup_viewer_delay; $i++) {
		return if ($done);
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
	updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_LAUNCHING, 'Obtaining VM IP Address', $bogref);
	my $vmip = getVMIPAddress($vmhostname);
	if ($vmip =~ m/^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/) {
		$log->info("Obtained vmip: $vmip");
		$bogref->{'vmip'} = $vmip;
	}
	else {
		$log->error("Failed to obtain vmip: $vmip");
	}
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

if (open(my $fh, '>', "vmu_MonitorViewer_${clusterid}.pid")) {
	print $fh "$$\n";
	close($fh);
}

sub signal_handler {
	$log->info("MonitorViewer for: $execrunuid signal caught");
	$done = 1;
}
$SIG{INT} = \&signal_handler;
$SIG{TERM} = \&signal_handler;

my $vmhostname = construct_vmhostname($execrunuid, $clusterid, $procid);

# Initialize Log4perl
Log::Log4perl->init(getLoggingConfigString());

$log = Log::Log4perl->get_logger(q{});
$log->level($debug ? $TRACE : $INFO);
$log->info("MonitorViewer: $execrunuid Begin");
$tracelog = Log::Log4perl->get_logger('runtrace');
$tracelog->trace("$PROGRAM_NAME ($PID) called with args: @ARGV");
setHTCondorEnvironment();
identifyScript(\@ARGV);
# my $startupdir = runScriptDetached();
# chdir($startupdir);


my %bog;
my $bogfile = $execrunuid . '.bog';
loadProperties($bogfile, \%bog);
$bog{'vmhostname'} = $vmhostname;

# look for INITIAL_STATUS and then obtain vm ip address
obtain_vmip($execrunuid, \%bog, $vmhostname);

monitor($execrunuid, \%bog);
my $message = "Viewer shutdown complete";
updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_SHUTDOWN, $message, \%bog);

$log->info("MonitorViewer: $execrunuid Exit");
exit(0);
