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
use Cwd qw(getcwd);
use Getopt::Long qw(GetOptions);
use File::Spec qw(devnull);
use File::Spec::Functions;
use File::Basename qw(basename);
use Log::Log4perl::Level;
use Log::Log4perl;
use Storable qw(nstore lock_nstore retrieve);

use FindBin;
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );
# use lib ( "$FindBin::Bin/lib", "$FindBin::Bin/../perl5" );

use SWAMP::vmu_Support qw(
	runScriptDetached
	setHTCondorEnvironment
	identifyScript
	getLoggingConfigString
	getSwampDir
	timetrace_event
	timetrace_elapsed
	$LAUNCHPAD_SUCCESS
	$LAUNCHPAD_BOG_ERROR
	$LAUNCHPAD_FILESYSTEM_ERROR
	$LAUNCHPAD_CHECKSUM_ERROR
	$LAUNCHPAD_FORK_ERROR
	$LAUNCHPAD_FATAL_ERROR
	getSwampConfig
	$global_swamp_config
);
use SWAMP::vmu_AssessmentSupport qw(
	updateClassAdAssessmentStatus
	updateRunStatus
	doRun
	getLaunchExecrunuids
);

my $startupdir = getcwd();
my $asdetached = 1;
my $debug    = 0;
my $list;
my $execrunuid;
my $configfile;

my @PRESERVEARGV = @ARGV;
GetOptions(
    'runid=s'      => \$execrunuid,
    'list=i{0,1}'  => \$list,
    'detached!'    => \$asdetached,
    'debug'        => \$debug,
	'config=s'     => \$configfile,
);

if ( defined($list) ) {
    $asdetached = 0;    # Listing the queue overrides detatching self
}

# This is the start of an assessment run so remove the tracelog file if extant
my $tracelogfile = catfile(getSwampDir(), 'log', 'runtrace.log');
truncate($tracelogfile, 0) if (-r $tracelogfile);

Log::Log4perl->init(getLoggingConfigString());
my $log = Log::Log4perl->get_logger(q{});
$log->level($debug ? $TRACE : $INFO);
my $tracelog = Log::Log4perl->get_logger('runtrace');
$tracelog->trace("$PROGRAM_NAME ($PID) called with args: @PRESERVEARGV");
setHTCondorEnvironment();
identifyScript(\@PRESERVEARGV);

runScriptDetached() if ($asdetached);
chdir($startupdir);

if (defined($list)) {
	listQueue(0); # list to tty
    exit 0;
}

if (isSWAMPRunning()) {
	$tracelog->trace("execrunuid: $execrunuid - calling doRun");
	$log->info("Attempting to launch run $execrunuid");
	my $event_start = timetrace_event($execrunuid, 'assessment', 'calldorun start');
	my $status = doRun($execrunuid);
	timetrace_elapsed($execrunuid, 'assessment', 'calldorun', $event_start);
	# HTCondor submit succeeded
	if ($status == $LAUNCHPAD_SUCCESS) {
		$tracelog->trace("execrunuid: $execrunuid - doRun succeeded");
		$log->info("Run $execrunuid successfully launched.");
	}
	# BOG file created on submit node
	elsif ($status == $LAUNCHPAD_FORK_ERROR) {
		$tracelog->trace("execrunuid: $execrunuid - doRun failed - status: $status - bog queued in filesystem on submit node");
		$log->error("execrunuid: $execrunuid - doRun failed - status: $status - bog queued in filesystem on submit node");
		my $job_status_message = 'HTCondor Submit Failed - BOG Queued';
		updateClassAdAssessmentStatus($execrunuid, '', '', '', $job_status_message);
		updateRunStatus($execrunuid, $job_status_message, 1);
	}
	else {
		$tracelog->trace("execrunuid: $execrunuid - doRun failed - status: $status execrunuid remains queued in database");
		$log->error("execrunuid: $execrunuid - doRun failed - status: $status execrunuid remains queued in database");
		my $job_status_message = 'HTCondor Submit Aborted - UUID Queued';
		updateClassAdAssessmentStatus($execrunuid, '', '', '', $job_status_message);
		# updateRunStatus($execrunuid, $status_message, 1);
	}
}
# SWAMP is administratively off, just add item to queue and be done.
else { 
    if ( defined($execrunuid) ) {
		my $job_status_message = 'SWAMP off - Queued';
		updateClassAdAssessmentStatus($execrunuid, '', '', '', $job_status_message);
        updateRunStatus($execrunuid, $job_status_message, 1);
        $log->info("SWAMP is Off at the moment. Run $execrunuid has been added to the queue.");
    }
}
listQueue(1); # list to log
exit 0;

sub listQueue { my ($dolog) = @_ ;
	my $dbaref = getLaunchExecrunuids();
	my $print_string = '';
	if (! $dbaref) {
		$print_string = "Error - failed to retrieve execution record uuids from Database Queue";
	}
	else {
		$print_string .=  "Database Queue has " . scalar(@$dbaref) . " items in it\n";
		my $count = 0;
		foreach my $execrunuid (@$dbaref) {
			$print_string .= "$count) $execrunuid\n";
			$count += 1;
		}
		$print_string .= "Count: $count\n";
	}
	if ($dolog) {
		$log->info($print_string);
	}
	else {
		print $print_string;
	}
}

sub isSWAMPRunning {
    $global_swamp_config ||= getSwampConfig($configfile);
    my $ret    = 0;
    if ( $global_swamp_config->exists('SWAMPState') ) {
        $ret = ( $global_swamp_config->get('SWAMPState') =~ /ON/sxmi );
    }
    return $ret;
}

sub logfilename {
    ( my $name = $PROGRAM_NAME ) =~ s/\.pl//sxm;
    $name = basename($name);
    return catfile(getSwampDir(), 'log', $name . '.log');
}
