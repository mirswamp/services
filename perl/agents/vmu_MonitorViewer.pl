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
	getLoggingConfigString
	getSwampConfig
	isSwampInABox
	buildExecRunAppenderLogFileName
	loadProperties
	construct_vmhostname
	deleteJobDir
);
use SWAMP::vmu_ViewerSupport qw(
	$VIEWER_STATE_NO_RECORD
	$VIEWER_STATE_LAUNCHING
	$VIEWER_STATE_READY
	$VIEWER_STATE_STOPPING
	$VIEWER_STATE_JOBDIR_FAILED
	$VIEWER_STATE_SHUTDOWN
	updateClassAdViewerStatus
);
use SWAMP::Libvirt qw(getVMIPAddress);

my $log;
my $tracelog;
my $config = getSwampConfig();
my $execrunuid;
my $clusterid;
my $events_file = catfile('events', 'JobVMEvents.log');
my $MAX_OPEN_ATTEMPTS = 5;
my $done = 0;

my %status_seen = ();
my $FINAL_STATUS	= 'VIEWERUP';
my $status_messages = {
	'RUNSHSTART'			=> ['Starting viewer vm run script', 				$VIEWER_STATE_LAUNCHING	],
	'NOIP'					=> ['Viewer vm has no ip address', 					$VIEWER_STATE_STOPPING	],
	'NOIPSHUTDOWN'			=> ['Shutting down viewer vm for no ip address', 	$VIEWER_STATE_STOPPING	],
	'LEGACYVIEWERDB'		=> ['Unbundling legacy viewer database', 			$VIEWER_STATE_LAUNCHING	],
	'VIEWERDB'				=> ['Unbundling viewer database', 					$VIEWER_STATE_LAUNCHING	],
	'MYSQLSTART'			=> ['Starting mysql service', 						$VIEWER_STATE_LAUNCHING	],
	'MYSQLFAIL'				=> ['Service mysql failed to start', 				$VIEWER_STATE_STOPPING	],
	'MYSQLSHUTDOWN'			=> ['Shutting down viewer vm for no mysql', 		$VIEWER_STATE_STOPPING	],
	'MYSQLRUN'				=> ['Service mysql running', 						$VIEWER_STATE_LAUNCHING	],
	'MYSQLEMPTY'			=> ['Restoring empty mysql database', 				$VIEWER_STATE_LAUNCHING	],
	'MYSQLGRANT'			=> ['Granting privileges for viewer database', 		$VIEWER_STATE_LAUNCHING	],
	'MYSQLDROP'				=> ['Dropping viewer database', 					$VIEWER_STATE_LAUNCHING	],
	'EMPTYDB'				=> ['Restoring empty viewer database', 				$VIEWER_STATE_LAUNCHING	],
	'USERDB'				=> ['Restoring user database', 						$VIEWER_STATE_LAUNCHING	],
	'CREATEPROXY'			=> ['Creating proxy directory', 					$VIEWER_STATE_LAUNCHING	],
	'APIKEY'				=> ['Inserting APIKEY', 							$VIEWER_STATE_LAUNCHING	],
	'BASEURL'				=> ['Inserting DefaultConfiguration', 				$VIEWER_STATE_LAUNCHING	],
	'CONFIG'				=> ['Restoring viewer configuration', 				$VIEWER_STATE_LAUNCHING	],
	'EMPTYCONFIG'			=> ['Initializing viewer configuration', 			$VIEWER_STATE_LAUNCHING	],
	'PROPERTIES'			=> ['Copying viewer properties', 					$VIEWER_STATE_LAUNCHING	],
	'WARFILE'				=> ['Restoring viewer war file', 					$VIEWER_STATE_LAUNCHING	],
	'TOMCATSTART'			=> ['Starting tomcat service', 						$VIEWER_STATE_LAUNCHING	],
	'TOMCATFAIL'			=> ['Service tomcat failed to start', 				$VIEWER_STATE_STOPPING	],
	'TOMCATSHUTDOWN'		=> ['Shutting down viewer vm for no tomcat', 		$VIEWER_STATE_STOPPING	],
	'TOMCATRUN'				=> ['Service tomcat running', 						$VIEWER_STATE_LAUNCHING	],
	'TIMESHUTDOWN'			=> ['Shutting down viewer after timeout', 			$VIEWER_STATE_STOPPING	],
	'VIEWERDBBACKUP'		=> ['Starting viewer database backup', 				$VIEWER_STATE_STOPPING	],
	'VIEWERDBDUMPFAIL'		=> ['Viewer database dump failed', 					$VIEWER_STATE_STOPPING	],
	'VIEWERDBDUMPSUCCESS'	=> ['Viewer database dump succeeded', 				$VIEWER_STATE_STOPPING	],
	'VIEWERDBCONFIGFAIL'	=> ['Viewer configuration tar failed', 				$VIEWER_STATE_STOPPING	],
	'VIEWERDBCONFIGSUCCESS'	=> ['Viewer configuration tar succeeded', 			$VIEWER_STATE_STOPPING	],
	'VIEWERDBNOBUNDLE'		=> ['Starting viewer user data bundling', 			$VIEWER_STATE_STOPPING	],
	'VIEWERDBBUNDLEFAIL'	=> ['Viewer user data bundling failed', 			$VIEWER_STATE_STOPPING	],
	'VIEWERDBBUNDLESUCCESS'	=> ['Viewer user data bundling succeeded', 			$VIEWER_STATE_STOPPING	],
	$FINAL_STATUS			=> ['Viewer is up', 								$VIEWER_STATE_READY		],
};

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
		if ($mstatus && exists($status_messages->{$mstatus})) {
			my ($message, $state) = @{$status_messages->{$mstatus}};
			$log->info("Status: $mstatus state: $state message: $message");
			# this is where VIEWER_STATE_READY is set
			if ($mstatus eq $FINAL_STATUS) {
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
				my $state = $VIEWER_STATE_NO_RECORD;
				updateClassAdViewerStatus($execrunuid, $state, $message, $bogref);
				$poll_count = 0;
			}
		}
		sleep $sleep_time;
		$poll_count += 1;
	}
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

Log::Log4perl->init(getLoggingConfigString());
$log = Log::Log4perl->get_logger(q{});
$log->level($debug ? $TRACE : $INFO);
$log->info("MonitorViewer: $execrunuid Begin");
$tracelog = Log::Log4perl->get_logger('runtrace');
$tracelog->trace("$PROGRAM_NAME ($PID) called with args: @ARGV");
identifyScript(\@ARGV);

my %bog;
my $bogfile = $execrunuid . '.bog';
loadProperties($bogfile, \%bog);
$bog{'vmhostname'} = $vmhostname;


updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_LAUNCHING, 'Obtaining VM IP Address', \%bog);
my $vmip = getVMIPAddress($config, $vmhostname);
$bog{'vmip'} = $vmip;
my $message;
if ($vmip =~ m/^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/) {
	$message = 'Obtained vmip';
	$log->info($message . ": $vmip");
}
else {
	$message = 'Failed to obtain vmip';
	$log->error($message . ": $vmip");
}
monitor($execrunuid, \%bog);
$message = "Viewer is shutting down";
updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_STOPPING, $message, \%bog);

# signal delete jobdir on sumbit node
my $status = deleteJobDir($execrunuid);
if ($status) {
	$log->info("MonitorViewer - job directory for: $execrunuid successfully deleted");
	updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_SHUTDOWN, "Viewer shutdown complete", \%bog);
}
else {
	$log->error("MonitorViewer - job directory for: $execrunuid deletion failed");
	updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_JOBDIR_FAILED, "Viewer shutdown incomplete", \%bog);
}

$log->info("MonitorViewer: $execrunuid Exit");
exit(0);
