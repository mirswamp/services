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

use SWAMP::vmu_Locking qw(swamplock swampunlock);
use SWAMP::vmu_Support qw(
	runScriptDetached
	identifyScript
	getSwampConfig
	getLoggingConfigString
	switchExecRunAppenderLogFile
	getSwampDir
	$LAUNCHPAD_SUCCESS
	$LAUNCHPAD_BOG_ERROR
	$LAUNCHPAD_FILESYSTEM_ERROR
	$LAUNCHPAD_CHECKSUM_ERROR
	$LAUNCHPAD_FORK_ERROR
	$LAUNCHPAD_FATAL_ERROR
);
use SWAMP::vmu_AssessmentSupport qw(
	updateClassAdAssessmentStatus
	updateRunStatus
	doRun
);

my $startupdir = getcwd();
my $asdetached = 1;
my $debug    = 0;
my $drain;
my $list;
my $execrunuid;

my @PRESERVEARGV = @ARGV;
GetOptions(
    'runid=s'      => \$execrunuid,
    'drain=i{0,1}' => \$drain,
    'list=i{0,1}'  => \$list,
    'detached!'    => \$asdetached,
    'debug'        => \$debug,
);

if ( defined($drain) || defined($list) ) {
    $asdetached = 0;    # Draining the queue overrides detatching self
}

# This is the start of an assessment run so remove the tracelog file if extant
my $tracelogfile = catfile(getSwampDir(), 'log', 'runtrace.log');
truncate($tracelogfile, 0) if (-r $tracelogfile);

Log::Log4perl->init(getLoggingConfigString());
my $log = Log::Log4perl->get_logger(q{});
$log->level($debug ? $TRACE : $INFO);
my $tracelog = Log::Log4perl->get_logger('runtrace');
$tracelog->trace("$PROGRAM_NAME ($PID) called with args: @PRESERVEARGV");
identifyScript(\@PRESERVEARGV);

runScriptDetached() if ($asdetached);
chdir($startupdir);

if (defined($list)) {
	listQueue();
    exit 0;
}

if (defined($drain)) {    
	listQueue();
	if (isSWAMPRunning()) {
		drainSwamp();
	}
	else {
        $log->info("SWAMP is Off at the moment and cannot be drained.");
        print "SWAMP is Off at the moment and cannot be drained.", "\n";
    }
	exit 0;
}

if (isSWAMPRunning()) {
	switchExecRunAppenderLogFile($execrunuid);
	$tracelog->trace("execrunuid: $execrunuid - calling doRun");
	$log->info("Attempting to launch run $execrunuid");
	my $status = doRun($execrunuid);
	# HTCondor submit succeeded
	if ($status == $LAUNCHPAD_SUCCESS) {
		$tracelog->trace("execrunuid: $execrunuid - doRun succeeded");
		$log->info("Run $execrunuid successfully launched.");
		# set database status to success
		
		# Successful call to doRun() => try to drain the SWAMP.
		$drain = 0;
		drainSwamp();
	}
	# BOG file created on submit node
	elsif ($status == $LAUNCHPAD_FORK_ERROR) {
		$tracelog->trace("execrunuid: $execrunuid - doRun failed - status: $status - bog queued");
		$log->error("execrunuid: $execrunuid - doRun failed - status: $status - bog queued");
		my $status_message = 'HTCondor Submit Failed - BOG Queued';
		# this is terminal case so update collector and database
		updateClassAdAssessmentStatus($execrunuid, '', '', '', $status_message);
		updateRunStatus($execrunuid, $status_message, 1);
		# set database status to success
	}
	else {
		$tracelog->trace("execrunuid: $execrunuid - doRun failed - status: $status uuid queued");
		$log->error("execrunuid: $execrunuid - doRun failed - status: $status uuid queued");
		my $status_message = 'HTCondor Submit Aborted - UUID Queued';
		updateClassAdAssessmentStatus($execrunuid, '', '', '', $status_message);
		updateRunStatus($execrunuid, $status_message, 1);
		# set database status to failure
		saveRun($execrunuid);
	}
}
# SWAMP is administratively off, just add item to queue and be done.
else { 
    if ( defined($execrunuid) ) {
        switchExecRunAppenderLogFile($execrunuid);
        saveRun($execrunuid);
		my $status_message = 'SWAMP off Queued';
		updateClassAdAssessmentStatus($execrunuid, '', '', '', $status_message);
        updateRunStatus($execrunuid, $status_message, 1);
        $log->info("SWAMP is Off at the moment. Run $execrunuid has been added to the queue.");
    }
}
exit 0;

sub listQueue {
    my $aref = loadQueue(0);
    $log->info("Queue has " . scalar(@$aref) . " items in it");
    print "Queue has " . scalar(@$aref) . " items in it", "\n";
	my $index = 0;
    foreach my $execrunuid (@$aref) {
        print "$index) $execrunuid\n";
		$index += 1;
		last if (defined($list) && $list != 0 && $index >= $list);
    }
	print "Count: $index\n";
}

sub drainSwamp {
    my $aref = loadQueue(1);
	$log->info("drainSwamp count: ", scalar(@$aref), "\n", sub {use Data::Dumper; Dumper($aref);});
    foreach my $idx ( 0 .. $#{$aref} ) {
        if ( !defined( $aref->[$idx] ) ) {
            next;
        }
        my $execrunuid = $aref->[$idx];
        switchExecRunAppenderLogFile($execrunuid);
        $log->info("processing run " . $execrunuid . " from the queue.");
        # If the call succeeded, delete the
        # item from the queue
        if (doRun($execrunuid) == $LAUNCHPAD_SUCCESS) {
			my $status_message = 'Drain ReLaunch';
			updateClassAdAssessmentStatus($execrunuid, '', '', '', $status_message);
            updateRunStatus($execrunuid, $status_message);
            $log->info("Run " . $execrunuid . " has been successfully launched from the queue.");
            $aref->[$idx] = 'done';
        }
        else {
			my $status_message = 'Drain ReQueued';
			updateClassAdAssessmentStatus($execrunuid, '', '', '', $status_message);
            updateRunStatus($execrunuid, $status_message, 1);
            $log->info("Run " . $execrunuid . " failed to launch and remains in the queue.");
        }
        if ( $drain != 0 && $idx >= $drain ) {
            last;
        }
    }
    my @list;
    foreach my $idx ( 0 .. $#{$aref} ) {
        if ( defined( $aref->[$idx] ) && $aref->[$idx] ne 'done' ) {
            push @list, $aref->[$idx];
        }
    }
    saveQueue( \@list );
    return;
}

sub saveRun {
    my $erunid = shift;
    $log->info("Adding $erunid to the queue");
    my $aref = loadQueue(1);
    push @{$aref}, $erunid;
    saveQueue($aref);
    return;
}

sub isSWAMPRunning {
    my $config = getSwampConfig();
    my $ret    = 0;
    if ( $config->exists('SWAMPState') ) {
        $ret = ( $config->get('SWAMPState') =~ /ON/sxmi );
    }
    return $ret;
}

sub queueFilename {
    return catfile(getSwampDir(), 'log', 'runqueue');
}

sub loadQueue { my ($truncate) = @_ ;
    my $filename = queueFilename();
    my $ret = [];
    if ( swamplock($filename) ) {
		# file is locked - safe to test it
        $ret = retrieve($filename) if (! -z $filename);
        nstore( \my @arr, $filename ) if ($truncate);
        swampunlock($filename);
    }
    return $ret;
}

sub saveQueue {
    my $aref = shift;
    lock_nstore( $aref, queueFilename() );
    return;
}

sub logfilename {
    ( my $name = $PROGRAM_NAME ) =~ s/\.pl//sxm;
    $name = basename($name);
    return catfile(getSwampDir(), 'log', $name . '.log');
}
