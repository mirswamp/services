#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2017 Software Assurance Marketplace

use 5.014;
use utf8;
use warnings;
use strict;
use Cwd qw(getcwd);
use English '-no_match_vars';
use File::Basename qw(basename);
use File::Spec qw(devnull);
use File::Spec::Functions;
use Getopt::Long qw(GetOptions);
use Log::Log4perl;
use Log::Log4perl::Level;
use POSIX qw(:sys_wait_h setsid);
use RPC::XML::Server;
use RPC::XML;

use FindBin qw($Bin);
use lib ("$FindBin::Bin/../perl5", "$FindBin::Bin/lib");

use SWAMP::vmu_Locking qw(swamplock);
use SWAMP::vmu_Support qw(
	identifyScript
	getSwampDir
	getSwampConfig
	getLoggingConfigString
	switchExecRunAppenderLogFile
	getUUID
	createBOGfileName
	saveProperties
	start_process
	stop_process
	systemcall
	getHTCondorJobId
	$LAUNCHPAD_SUCCESS
	$LAUNCHPAD_BOG_ERROR
	$LAUNCHPAD_FILESYSTEM_ERROR
	$LAUNCHPAD_CHECKSUM_ERROR
	$LAUNCHPAD_FORK_ERROR
	$LAUNCHPAD_FATAL_ERROR
);

if (! swamplock($PROGRAM_NAME)) {
    exit 0;
}

my $serverhost;
my $port;
my $debug = 0;
my $asdaemon = 0;
my $configfile;
my $startupdir = getcwd();

my @PRESERVEARGV = @ARGV;
GetOptions(
    'host=s'   => \$serverhost,
    'port=i'   => \$port,
    'config=s' => \$configfile,
    'debug'    => \$debug,
    'daemon'   => \$asdaemon,
);

Log::Log4perl->init(getLoggingConfigString());
my $log = Log::Log4perl->get_logger(q{});
$log->level($debug ? $TRACE : $INFO);
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

local $SIG{'CHLD'} = sub {
	$log->info("CHLD signal");
	while ((my $childID = waitpid(-1, &WNOHANG)) > 0) {
		$log->info("reaped: $childID");
	}
};

chdir($startupdir);

my $config = getSwampConfig($configfile);
if (! defined($port)) {
    $port = $config->get('agentMonitorPort');
}
if (! defined($serverhost)) {
    $serverhost = $config->get('agentMonitorHost');
}

my $daemon = RPC::XML::Server->new('host' => $serverhost, 'port' => $port);

# Add methods to our server
my @sig = ( 'int', 'int struct' );
$daemon->add_method(
    {
        'name'      => 'swamp.launchPad.start',
        'signature' => \@sig,
        'code'      => \&_launchpadStart
    }
);

@sig = ( 'int', 'int string string' );
$daemon->add_method(
    {
        'name'      => 'swamp.launchPad.kill',
        'signature' => \@sig,
        'code'      => \&_launchpadKill
    }
);

sub logfilename {
    (my $name = $PROGRAM_NAME) =~ s/\.pl//sxm;
	$name = basename($name);
    return catfile(getSwampDir(), 'log', $name . '.log');
}

my @signals = qw/TERM HUP INT/;
my %map     = ( 'signal' => \@signals );
$log->info("$PROGRAM_NAME ($PID) entering listen loop at $serverhost on port: $port");
# start any jobs that are in the runqueue
startCSAAgent();
my $res = $daemon->server_loop(%map);
exit 0;

sub _launchpadKill { my ($server, $execrunuid, $jobid) = @_ ;
	switchExecRunAppenderLogFile($execrunuid);
	# issue condor_rm jobid
	my ($output, $status) = systemcall("condor_rm $jobid");
	if ($status) {
		$log->error("_launchpadKill condor_rm failed for $execrunuid $jobid: $status $output");
		return $LAUNCHPAD_FATAL_ERROR;
	}
	if ($output !~ m/Job $jobid marked for removal/) {
		$log->error("_launchpadKill condor_rm failed for $execrunuid $jobid: $output");
		return $LAUNCHPAD_FATAL_ERROR;
	}
	return $LAUNCHPAD_SUCCESS;
}

sub _launchpadStart { my ($server, $bogref) = @_ ;
    my $execrunuid = ${$bogref}{'execrunid'};
	switchExecRunAppenderLogFile($execrunuid);
	$tracelog->trace("_launchpadStart - execrunuid: $execrunuid from ", $server->{'peerhost'}, ':', $server->{'peerport'});
    my $csaOpt = q{};
    # Persist the BOG to file
    my $bogfile = createBOGfileName($execrunuid);
    if (defined( $bogref->{'intent'})) {
        if ($bogref->{'intent'} eq 'VRUN') {
            $csaOpt = "--runnow $bogfile";
        }
    }
    if (! saveProperties($bogfile, $bogref, "Bill Of Goods File: $PROGRAM_NAME")) {
		$log->error("_launchpadStart - execrunuid: $execrunuid error saving: $bogfile");
		$tracelog->trace("_launchpadStart - execrunuid: $execrunuid error saving: $bogfile");
        return $LAUNCHPAD_FILESYSTEM_ERROR;
    }
    else {
		$log->info("_launchpadStart - execrunuid: $execrunuid saved: $bogfile");
		$tracelog->trace("_launchpadStart - execrunuid: $execrunuid saved: $bogfile");
    }
	$tracelog->trace("_launchpadStart - execrunuid: $execrunuid calling startCSAAgent csaOpt: $csaOpt");
    my $status = startCSAAgent($execrunuid, $csaOpt);
    return $status;
}

sub startCSAAgent { my ($execrunuid, $options) = @_ ;
	$options ||= q{};
    my $dir = catdir(getSwampDir(), 'run');
	my $script = catfile(getSwampDir(), 'bin', 'vmu_csa_agent_launcher');
    $log->info( "startCSAAgent - start_process $script --bog $dir $options" );
    $tracelog->trace( "startCSAAgent - start_process $script --bog $dir $options" );
    my $childPID = start_process("$script --bog $dir $options");
    if (defined($childPID)) {
    	$tracelog->trace( "startCSAAgent - start_process returned childPID: $childPID");
    	$log->info( "startCSAAgent - start_process returned childPID: $childPID");
    	return $LAUNCHPAD_SUCCESS;
    }
    else {
        $tracelog->trace( "startCSAAgent - start_process $script failed");
        $log->error( "startCSAAgent - start_process $script failed");
		return $LAUNCHPAD_FORK_ERROR;
    }
}
