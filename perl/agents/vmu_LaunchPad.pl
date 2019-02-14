#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2019 Software Assurance Marketplace

use 5.014;
use utf8;
use warnings;
use strict;
use Cwd qw(getcwd);
use English '-no_match_vars';
use POSIX qw(:signal_h WNOHANG waitpid);
use File::Copy qw(move);
use File::Basename qw(basename);
use File::Spec qw(devnull);
use File::Spec::Functions;
use Getopt::Long qw(GetOptions);
use Log::Log4perl;
use Log::Log4perl::Level;
use RPC::XML::Server;
use RPC::XML;

use FindBin qw($Bin);
use lib ("$FindBin::Bin/../perl5", "$FindBin::Bin/lib");

use SWAMP::Locking qw(swamplock);
use SWAMP::vmu_Support qw(
	runScriptDetached
	identifyScript
	getSwampDir
	getLoggingConfigString
	saveProperties
	start_process
	systemcall
	isAssessmentRun
	isMetricRun
	isViewerRun
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
	setCompleteFlag
);

if (! swamplock($PROGRAM_NAME)) {
    exit 0;
}

my $serverhost;
my $port;
my $debug = 0;
my $asdetached = 0;
my $configfile;
my $startupdir = getcwd();
my $sigtermmask = POSIX::SigSet->new(SIGTERM);

my @PRESERVEARGV = @ARGV;
GetOptions(
    'host=s'   => \$serverhost,
    'port=i'   => \$port,
    'config=s' => \$configfile,
    'debug'    => \$debug,
    'detached'   => \$asdetached,
);

Log::Log4perl->init(getLoggingConfigString());
my $log = Log::Log4perl->get_logger(q{});
$log->level($debug ? $TRACE : $INFO);
my $tracelog = Log::Log4perl->get_logger('runtrace');
$tracelog->trace("$PROGRAM_NAME ($PID) called with args: @PRESERVEARGV");
identifyScript(\@PRESERVEARGV);
runScriptDetached() if ($asdetached);

my $assessment_child_pid;
my $child_pids = {};
my $child_script = catfile(getSwampDir(), 'bin', 'vmu_csa_agent.pl');
# reap children so they do not become zombies
# this is not a wait for the child to exit
# it is a wait to consume their exit status
# from the kernel process table when they exit
# sending SIGCHLD to this parent
local $SIG{'CHLD'} = sub {
	$log->info("received CHLD signal");
	while ((my $child_pid = waitpid(-1, &WNOHANG)) > 0) {
		$log->info("reaped: $child_pid");
		$child_pids->{$child_pid} = 0;
		if ($child_pid == $assessment_child_pid) {
			$log->warn("$child_script: $child_pid has exited - restarting");
			sigprocmask(SIG_BLOCK, $sigtermmask);
			$assessment_child_pid = startCSAAgent();
			if (! $assessment_child_pid) {
				$log->error("Error - unable to restart: $child_script - shutting down");
				# send INT to self to break out of server_loop
				$log->info("sending INT to: $PID");
				kill 'INT', $PID;
			}
			sigprocmask(SIG_UNBLOCK, $sigtermmask);
		}
	}
};

chdir($startupdir);

$global_swamp_config ||= getSwampConfig($configfile);
if (! defined($port)) {
    $port = $global_swamp_config->get('launchPadPort');
}
if (! defined($serverhost)) {
    $serverhost = $global_swamp_config->get('launchPadHost');
}

my $daemon = RPC::XML::Server->new('host' => $serverhost, 'port' => $port);
if (! ref($daemon)) {
	$log->error("Error - $PROGRAM_NAME $PID no daemon: $daemon - exiting");
	exit(2);
}

# Add methods to our server
my @sig = ( 'int', 'int struct' );
$daemon->add_method(
    {
        'name'      => 'swamp.launchPad.start',
        'signature' => \@sig,
        'code'      => \&_launchpadStart
    }
);

@sig = ( 'int', 'int string string string int' );
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

# start any jobs that are in the filesystem BOG queue
# block TERM
sigprocmask(SIG_BLOCK, $sigtermmask);
# set TERM handler to terminate children
$SIG{TERM} = sub { my ($sig) = @_ ;
	$log->info("received TERM signal");
	foreach my $child_pid (keys %$child_pids) {
		# send TERM to child_pid if it has not already exited
		if ($child_pids->{$child_pid}) {
			$log->info("sending TERM to: $child_pid");
			kill 'TERM', $child_pid;
		}
	}
	# now send INT to self to break out of server_loop
	$log->info("sending INT to: $PID");
	kill 'INT', $PID;
};
# start child script
$assessment_child_pid = startCSAAgent();
if (! $assessment_child_pid) {
	$log->error("Error - unable to start: $child_script - exiting");
	exit 0;
}
# unblock TERM
sigprocmask(SIG_UNBLOCK, $sigtermmask);

# start server loop - exit on INT
$log->info("$PROGRAM_NAME ($PID) entering listen loop at $serverhost on port: $port");
my $res = $daemon->server_loop('signal' => ['INT']);
# reap any remaining children that have been terminated
$log->info("$PROGRAM_NAME ($PID) waiting for children");
while ((my $child_pid = wait()) != -1) {
	$log->info("reaped child: $child_pid");
}
$log->info("$PROGRAM_NAME ($PID) leaving listen loop - exiting");
exit 0;

# type - arun | mrun | vrun
# graceful_shutdown - 0 | 1
sub _launchpadKill { my ($server, $execrunuid, $jobid, $type, $graceful_shutdown) = @_ ;
	my $complete_flag = 1; # terminated
	my $retval = $LAUNCHPAD_SUCCESS;
	$log->info("_launchpadKill condor_rm $execrunuid $jobid $type $graceful_shutdown");
	# issue condor_rm jobid
	# currently the default (configured) behavior for condor_rm is
	# viewer - graceful shutdown with timeout before hard kill
	# metric and assessment - hard kill after short timeout
	# in the future, to provide hard kill for viewer - use condor_vacate_job
	my ($output, $status) = systemcall("condor_rm $jobid");
	if ($status) {
		$log->error("_launchpadKill condor_rm failed for $execrunuid $jobid $type $graceful_shutdown: $status $output");
		$complete_flag = 0; # terminate failed
		$retval = $LAUNCHPAD_FATAL_ERROR;
	}
	elsif ($output !~ m/Job $jobid marked for removal/) {
		$log->error("_launchpadKill condor_rm failed for $execrunuid $jobid $type $graceful_shutdown: $output");
		$complete_flag = 0; # terminate failed
		$retval = $LAUNCHPAD_FATAL_ERROR;
	}
	if (! setCompleteFlag($execrunuid, $complete_flag)) {
		$log->warn("_launchpadKill: $execrunuid - setCompleteFlag $complete_flag failed");
	}
	return $retval;
}

sub _launchpadStart { my ($server, $bogref) = @_ ;
	my $status = $LAUNCHPAD_SUCCESS;
    my $execrunuid = $bogref->{'execrunid'};
	$tracelog->trace("_launchpadStart - execrunuid: $execrunuid from ", $server->{'peerhost'}, ':', $server->{'peerport'});
    my $bogfile = $execrunuid . '.bog';
    my $tempfile = $execrunuid . '.tmp';
	# block TERM
	sigprocmask(SIG_BLOCK, $sigtermmask);
	# first attempt to write file as $tempfile
    if (! saveProperties($tempfile, $bogref, "Bill Of Goods File: $PROGRAM_NAME")) {
		$log->error("_launchpadStart - execrunuid: $execrunuid error saving: $bogfile");
		$tracelog->trace("_launchpadStart - execrunuid: $execrunuid error saving: $bogfile");
        $status = $LAUNCHPAD_FILESYSTEM_ERROR;
    }
	else {
		# then move $tempfile to $bogfile
		move $tempfile, $bogfile;
		$log->info("_launchpadStart - execrunuid: $execrunuid saved: $bogfile");
		$tracelog->trace("_launchpadStart - execrunuid: $execrunuid saved: $bogfile");
		if (isViewerRun($execrunuid)) {
			my $csaOpt = "--runnow $bogfile";
			$tracelog->trace("_launchpadStart - execrunuid: $execrunuid calling startCSAAgent csaOpt: $csaOpt");
			my $child_pid = startCSAAgent($csaOpt);
			if (! $child_pid) {
				$status = $LAUNCHPAD_FORK_ERROR;
			}
		}
	}
	# unblock TERM
	sigprocmask(SIG_UNBLOCK, $sigtermmask);
    return $status;
}

sub startCSAAgent { my ($options) = @_ ;
	$options ||= q{};
    my $dir = catdir(getSwampDir(), 'run');
	$log->info("start_process $child_script --bog $dir $options" );
    $tracelog->trace( "startCSAAgent - start_process $child_script --bog $dir $options" );
    my $child_pid = start_process("$child_script --bog $dir $options");
    if (defined($child_pid)) {
    	$tracelog->trace( "startCSAAgent - start_process returned child_pid: $child_pid");
		$log->info("start_process returned child_pid: $child_pid");
		$child_pids->{$child_pid} = 1;
    	return $child_pid;
    }
    else {
        $tracelog->trace( "startCSAAgent - start_process $child_script failed");
		$log->error("start_process $child_script failed");
		return 0;
    }
}
