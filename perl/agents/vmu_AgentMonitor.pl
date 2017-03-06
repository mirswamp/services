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
use File::Spec qw(devnull);
use File::Spec::Functions;
use File::Basename qw(basename);
use File::Path qw(remove_tree);
use Getopt::Long qw(GetOptions);
use Log::Log4perl;
use Log::Log4perl::Level;
use POSIX qw(setsid);
use RPC::XML::Server;
use RPC::XML;
use URI::Escape qw(uri_escape);

use FindBin qw($Bin);
use lib ("$FindBin::Bin/../perl5", "$FindBin::Bin/lib");

use SWAMP::vmu_Locking qw(swamplock);
use SWAMP::vmu_Support qw(
	identifyScript
	HTCondorJobStatus
	$HTCondor_No_Status
	$HTCondor_Unexpanded
	$HTCondor_Idle
	$HTCondor_Running
	$HTCondor_Removed
	$HTCondor_Completed
	$HTCondor_Held
	$HTCondor_Submission_Error
  	getSwampDir
  	getSwampConfig
  	getLoggingConfigString
	addExecRunLogAppender
	removeExecRunLogAppender
  	getJobDir
	construct_vmhostname
  	systemcall
	getUUID
);
use SWAMP::vmu_ViewerSupport qw(
	$VIEWER_STATE_NO_RECORD
	$VIEWER_STATE_LAUNCHING
	$VIEWER_STATE_READY
	$VIEWER_STATE_STOPPING
	$VIEWER_STATE_JOBDIR_FAILED
	$VIEWER_STATE_SHUTDOWN
	getViewerStateFromClassAd
	updateClassAdViewerStatus
	launchPadStart
	qmstoreviewer
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

my $config = getSwampConfig($configfile);
if (! defined($port)) {
    $port = $config->get('agentMonitorJobPort');
	$port = int($port) ;
}
if (! defined($serverhost)) {
    $serverhost = $config->get('agentMonitorHost');
}

my $daemon = RPC::XML::Server->new('host' => $serverhost, 'port' => $port);

# Add methods to our server

my @sig = ( 'int', 'int struct ' );
$daemon->add_method(
    {
        'name'      => 'agentMonitor.launchViewer',
        'signature' => \@sig,
        'code'      => \&_launchViewer
    }
);

@sig = ( 'int', 'int struct ' );
$daemon->add_method(
    {
        'name'      => 'agentMonitor.deleteJobDir',
        'signature' => \@sig,
        'code'      => \&_deleteJobDir
    }
);

@sig = ( 'int', 'int struct ' );
$daemon->add_method(
    {
        'name'      => 'agentMonitor.storeviewer',
        'signature' => \@sig,
        'code'      => \&_storeviewer
    }
);

my @signals = qw/TERM HUP INT/;
my %map = ('signal' => \@signals);
$log->info("$PROGRAM_NAME ($PID) entering listen loop at $serverhost on port: $port");
my $res = $daemon->server_loop(%map);
exit 0;

sub logfilename {
    (my $name = $PROGRAM_NAME) =~ s/\.pl//sxm;
	$name=basename($name);
	return catfile(getSwampDir(), 'log', $name . '.log');
}

# options contains
#	execrunuid
#	clusterid
#	procid
#	bog data for viewer
# returns:
# 	-1	wait
# 	 0	failure
#	>0	success
sub _deleteJobDir { my ($server, $options) = @_ ;
	my $execrunuid = $options->{'execrunuid'};
	addExecRunLogAppender($execrunuid) if defined $execrunuid;
	my $result = _deleteJobDirMain($server, $options);
	removeExecRunLogAppender() if defined $execrunuid;
	return $result;
}

sub _deleteJobDirMain { my ($server, $options) = @_ ;
	$tracelog->trace('_deleteJobDir options: ', sub {use Data::Dumper; Dumper($options);});
	# no execrunuid - cannot update class ad
	if (! defined($options->{'execrunuid'})) {
		$log->error('_deleteJobDir Error - no execrunuid');
		$tracelog->trace('_deleteJobDir - Error - no execrunuid');
		# failure
		return 0;
	}
	my $execrunuid = $options->{'execrunuid'};
	if (! defined($options->{'clusterid'})) {
		$log->error("_deleteJobDir Error - $execrunuid - no clusterid");
		$tracelog->trace("_deleteJobDir - Error - $execrunuid - no clusterid");
		# failure
		return 0;
	}
	my $clusterid = $options->{'clusterid'};
	if (! defined($options->{'procid'})) {
		$log->error("_deleteJobDir Error - $execrunuid $clusterid - no procid");
		$tracelog->trace("_deleteJobDir - Error - $execrunuid $clusterid - no procid");
		# failure
		return 0;
	}
	my $procid = $options->{'procid'};
	my $jobDir = getJobDir($execrunuid);
	my $jobDirPath = catdir(getSwampDir(), 'run', $jobDir);
	if (! -d $jobDirPath) {
		$tracelog->trace("_deleteJobDir - Error - $execrunuid $clusterid $procid - jobDir: $jobDirPath is not a directory");
		$log->error("_deleteJobDir - Error - $execrunuid $clusterid $procid - jobDir: $jobDirPath is not a directory");
		# failure
		return 0;
	}
	
	# return number of files removed - should be >0 on success, 0 on failure
	my $result = remove_tree($jobDirPath, {error => \my $error});
	if (@$error || ! $result) {
		my $error_string = '';
		foreach my $diag (@$error) {
			my ($file, $message) = %$diag;
			$error_string .= $file . ' ' . $message . ' ';
		}
		$tracelog->trace("_deleteJobDir - Error - $execrunuid $clusterid $procid - jobDir: $jobDirPath remove failed - result: $result");
		$log->error("_deleteJobDir - Error - $execrunuid $clusterid $procid - jobDir: $jobDirPath remove failed  - result: $result - error: $error_string");
		# set result to 0 on error in case it was >0 but an error occurred anyway
		$result = 0;
	}
	else {
		$tracelog->trace("_deleteJobDir - $execrunuid $clusterid $procid jobDir: $jobDirPath removed: $result");
		$log->info("_deleteJobDir - $execrunuid $clusterid $procid - jobDir: $jobDirPath removed: $result");
	}
	# return >0 on success, 0 on failure
	return $result;
}

sub _launchViewer { my ($server, $options) = @_ ;
	$tracelog->trace('_launchViewer options: ', sub {use Data::Dumper; Dumper($options);});
	my $stopping_poll_count = 24;
	my $stopping_poll_sleep_time = 5;
	my $state;
	# get current viewer instance state
	for (my $i = 0; $i < $stopping_poll_count; $i++) {
		my $viewerState = getViewerStateFromClassAd($options->{'project'}, $options->{'viewer'});
		# timeout or error condition 
		if (($i >= ($stopping_poll_count - 1)) || ! defined($viewerState->{'state'}) || defined($viewerState->{'error'})) {
			$log->error("_launchViewer not launching viewer - getViewerStateFromClassAd returns: ", sub {use Data::Dumper; Dumper($viewerState);});
			if ($i >= ($stopping_poll_count - 1)) {
				$log->error("_launchViewer timed out waiting for valid state after: ", $stopping_poll_sleep_time * $stopping_poll_count, " seconds");
			}
			$tracelog->trace("_launchViewer count: $i state: ", sub {use Data::Dumper; Dumper($viewerState);});
			return 0;
		}
		my $state = $viewerState->{'state'};
		# viewer is already launching or ready so return success
		if ($state == $VIEWER_STATE_LAUNCHING || $state == $VIEWER_STATE_READY) {
        	$log->info("_launchViewer not launching viewer - pending launchPadStart options: ", sub { use Data::Dumper; Dumper($options); });
        	$tracelog->trace('_launchViewer - pending'); 
        	return 1;
		}
		# viewer is shutdown or does not exist so launch
		if ($state == $VIEWER_STATE_SHUTDOWN || $state == $VIEWER_STATE_NO_RECORD) {
			last;
		}
		# viewer is stopping so sleep waiting for it to shutdown
		if ($state == $VIEWER_STATE_STOPPING) {
        	$log->info("_launchViewer waiting for shutdown viewerState: ", sub { use Data::Dumper; Dumper($viewerState); });
			sleep $stopping_poll_sleep_time;
		}
	}
	# OK to launch new viewer instance
	my $key = "$options->{'project'}.$options->{'viewer'}";
	$key =~s/\s//sxmg;
	$options->{'execrunid'} = "vrun.$key";
	$options->{'intent'} = 'VRUN'; # New field.
	$options->{'apikey'} = getUUID();
	# This is now the URL for the VM instead of project.
	# It needs to persist for THIS VM, but be unique next time.
	$options->{'urluuid'} = qq{proxy-}.uri_escape(getUUID()); 
	$options->{'platform'} = $config->get('master.viewer');
	$options->{'vmhostname'} = 'vswamp';
	$log->info("_launchViewer: invoking launchPadStart options: ", sub {use Data::Dumper; Dumper($options);});
	updateClassAdViewerStatus($options->{'execrunid'}, $VIEWER_STATE_LAUNCHING, 'Launching viewer', $options);
	my $result = launchPadStart($options);
	if (! $result) {
		$tracelog->trace('_launchViewer - launchPadStart failure'); 
		return 0;
	}
	$tracelog->trace('_launchViewer - launchPadStart success ');
	return 1;
}

sub _storeviewer { my ($server, $options) = @_ ;
	$tracelog->trace('__storeviewer options: ', sub {use Data::Dumper; Dumper($options);});
	my $result = qmstoreviewer($options);
	return $result;
}
