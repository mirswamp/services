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
use Cwd qw(getcwd);
use Getopt::Long qw(GetOptions);
use File::Spec qw(devnull);
use File::Spec::Functions;
use File::Basename qw(basename);
use Log::Log4perl::Level;
use Log::Log4perl;
use POSIX qw(setsid);
use Storable qw(nstore lock_nstore retrieve);

use FindBin;
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );

use SWAMP::vmu_Locking qw(swamplock swampunlock);
use SWAMP::vmu_Support qw(
	identifyScript
	getSwampConfig
	getLoggingConfigString
	addExecRunLogAppender
	removeExecRunLogAppender
	getSwampDir
);
use SWAMP::vmu_AssessmentSupport qw(
	updateRunStatus
	doRun
);

my $startupdir = getcwd();
my $asdaemon = 1;
my $debug    = 0;
my $drain;
my $list;
my $execrunuid;

my @PRESERVEARGV = @ARGV;
GetOptions(
    'runid=s'      => \$execrunuid,
    'drain=i{0,1}' => \$drain,
    'list=i{0,1}'  => \$list,
    'daemon!'      => \$asdaemon,
    'debug'        => \$debug,
);

if ( defined($drain) || defined($list) ) {
    $asdaemon = 0;    # Draining the queue overrides daemonizing self
}

Log::Log4perl->init(getLoggingConfigString());
my $log = Log::Log4perl->get_logger(q{});
$log->level($debug ? $TRACE : $INFO);
$log->remove_appender('Screen');
my $tracelog = Log::Log4perl->get_logger('runtrace');
$tracelog->trace("$PROGRAM_NAME ($PID) called with args: @PRESERVEARGV");
identifyScript(\@PRESERVEARGV);

if ($asdaemon) {
    chdir(q{/});
    if (! open(STDIN, '<', File::Spec->devnull)) {
        $log->error("prefork - open STDIN to /dev/null failed: $OS_ERROR");
        exit;
    }
    if (! open(STDOUT, '>', File::Spec->devnull)) {
        $log->error("prefork - open STDOUT to /dev/null failed: $OS_ERROR");
        exit;
    }
    my $pid = fork();
    if (! defined($pid)) {
        $log->error("fork failed: $OS_ERROR");
        exit;
    }
    if ($pid) {
        # parent
        exit(0);
    }
    # child
    if (setsid() == -1) {
        $log->error("child - setsid failed: $OS_ERROR");
        exit;
    }
    if (! open(STDERR, ">&STDOUT")) {
        $log->error("child - open STDERR to STDOUT failed:$OS_ERROR");
        exit;
    }
}
chdir($startupdir);

if ( defined($list) ) {
    my $aref = loadQueue();
    $log->info("Queue has $#{$aref} items in it");
    foreach my $idx ( 0 .. $#{$aref} ) {
        print "$idx $aref->[$idx]\n";
        if ( $list != 0 && $idx >= $list ) {
            last;
        }
    }
    exit 0;
}
if ( isSWAMPRunning() ) {
    if ( defined($drain) ) {    # Drain the queue
        drainSwamp();
    }
    else {
        addExecRunLogAppender($execrunuid);
        $tracelog->trace("execrunuid: $execrunuid - calling doRun");
        $log->info("Attempting to launch run $execrunuid");
        if (! doRun($execrunuid)) {
            $tracelog->trace("execrunuid: $execrunuid - doRun failed");
            # If the call failed, save the run in the queue
            saveRun($execrunuid);
            updateRunStatus($execrunuid, 'Demand Queued', 1);
            $log->info("Unable to launch run $execrunuid. Added run to the queue.");
            removeExecRunLogAppender();
        }
        else {
            $tracelog->trace("execrunuid: $execrunuid - doRun succeeded");
            $log->info("Run $execrunuid successfully launched.");
            removeExecRunLogAppender();
            # Successful call to doRun() => try and drain the SWAMP.
            $drain = 0;
            drainSwamp();
        }
    }
}
else {                          # SWAMP is administratively off, just add item to queue and be done.
    if ( defined($execrunuid) ) {
        addExecRunLogAppender($execrunuid);
        saveRun($execrunuid);
        updateRunStatus($execrunuid, 'SWAMP Off Queued', 1);
        $log->info("SWAMP is Off at the moment. Run $execrunuid has been added to the queue.");
        removeExecRunLogAppender();
    }
    if ( defined($drain) ) {
        $log->error("SWAMP is Off at the moment and cannot be drained.");
    }
}
exit 0;

sub drainSwamp {
    my $aref = loadQueue();
	$log->info("drainSwamp count: ", scalar(@$aref), "\n", sub {use Data::Dumper; Dumper($aref);});
    foreach my $idx ( 0 .. $#{$aref} ) {
        if ( !defined( $aref->[$idx] ) ) {
            next;
        }
        my $execrunuid = $aref->[$idx];
        addExecRunLogAppender($execrunuid);
        $log->info("processing run " . $execrunuid . " from the queue.");
        # If the call succeeded, delete the
        # item from the queue
        if (doRun($execrunuid)) {
            updateRunStatus($execrunuid, 'Drain ReLaunch');
            $log->info("Run " . $execrunuid . " has been successfully launched from the queue.");
            $execrunuid = 'done';
        }
        else {
            updateRunStatus($execrunuid, 'Drain ReQueued', 1);
            $log->info("Run " . $execrunuid . " failed to launch and remains in the queue.");
        }
        removeExecRunLogAppender();
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
    my $aref = loadQueue();
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

sub loadQueue {
    my $filename = queueFilename();
    my $ret      = ();
    if ( swamplock($filename) ) {
        $ret = retrieve($filename);
        nstore( \my @arr, $filename );
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
