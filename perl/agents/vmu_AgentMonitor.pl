#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

use 5.014;
use utf8;
use warnings;
use strict;
use Cwd qw(getcwd);
use English '-no_match_vars';
use File::Spec qw(devnull);
use File::Spec::Functions;
use File::Basename qw(basename);
use Getopt::Long qw(GetOptions);
use Log::Log4perl;
use Log::Log4perl::Level;
use RPC::XML::Server;
use RPC::XML;
use URI::Escape qw(uri_escape);

use FindBin qw($Bin);
use lib ("$FindBin::Bin/../perl5", "$FindBin::Bin/lib");

use SWAMP::Locking qw(swamplock);
use SWAMP::vmu_Support qw(
	use_remove_tree
	runScriptDetached
	identifyScript
  	getSwampDir
  	getLoggingConfigString
	construct_vmhostname
	getUUID
	launchPadStart
	platformIdentifierToImage
	isDCPlatform
	$LAUNCHPAD_SUCCESS
    $LAUNCHPAD_BOG_ERROR
    $LAUNCHPAD_FILESYSTEM_ERROR
    $LAUNCHPAD_CHECKSUM_ERROR
    $LAUNCHPAD_FORK_ERROR
    $LAUNCHPAD_FATAL_ERROR
  	getSwampConfig
	$global_swamp_config
);
use SWAMP::vmu_ViewerSupport qw(
	$VIEWER_STATE_LAUNCHING
	updateClassAdViewerStatus
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

my @PRESERVEARGV = @ARGV;
GetOptions(
    'host=s'   => \$serverhost,
    'port=i'   => \$port,
    'config=s' => \$configfile,
    'debug'    => \$debug,
    'detached'   => \$asdetached,
);

# Initialize Log4perl
Log::Log4perl->init(getLoggingConfigString());

my $log = Log::Log4perl->get_logger(q{});
$log->level($debug ? $TRACE : $INFO);
my $tracelog = Log::Log4perl->get_logger('runtrace');
$tracelog->trace("$PROGRAM_NAME ($PID) called with args: @PRESERVEARGV");
identifyScript(\@PRESERVEARGV);

runScriptDetached() if ($asdetached);
chdir($startupdir);

$global_swamp_config ||= getSwampConfig($configfile);
if (! defined($port)) {
    $port = $global_swamp_config->get('agentMonitorPort');
	$port = int($port) ;
}
if (! defined($serverhost)) {
    $serverhost = $global_swamp_config->get('agentMonitorHost');
}

my $daemon = RPC::XML::Server->new('host' => $serverhost, 'port' => $port);
if (! ref($daemon)) {
	$log->error("Error - $PROGRAM_NAME $PID no daemon: $daemon - exiting");
	exit(2);
}

# Add methods to our server

my @sig = ( 'int', 'int struct ' );
$daemon->add_method(
    {
        'name'      => 'agentMonitor.launchViewer',
        'signature' => \@sig,
        'code'      => \&_launchViewer
    }
);

# start server loop - exit on TERM
$log->info("$PROGRAM_NAME ($PID) entering listen loop at $serverhost on port: $port");
my $res = $daemon->server_loop('signal' => ['TERM']);
$log->info("$PROGRAM_NAME ($PID) leaving listen loop - exiting");
exit 0;

sub logfilename {
    (my $name = $PROGRAM_NAME) =~ s/\.pl//sxm;
	$name=basename($name);
	return catfile(getSwampDir(), 'log', $name . '.log');
}

sub _launchViewer { my ($server, $options) = @_ ;
	$tracelog->trace("_launchViewer options: ", sub {use Data::Dumper; Dumper($options);});
	my $key = $options->{'projectid'} . '_' . $options->{'viewer'};
	$key =~ s/\s//sxmg;
	$options->{'execrunid'} = 'vrun' . '_' . $key;
	$options->{'apikey'} = getUUID();
	# This is now the URL for the VM instead of projectid.
	# It needs to persist for THIS VM, but be unique next time.
	$options->{'urluuid'} = qq{proxy-}.uri_escape(getUUID()); 
	$options->{'platform_identifier'} = $global_swamp_config->get('master.viewer');
	$options->{'platform_type'} = $global_swamp_config->get('master.viewer.type');
	$options->{'platform_type'} = 'VM' if (! $options->{'platform_type'});
	$options->{'platform_image'} = platformIdentifierToImage($options);
	$options->{'vmhostname'} = 'vswamp';
	$options->{'use_docker_universe'} = isDCPlatform($options->{'platform_type'});
	# FIXME this is temporary for switching on use_baked_viewer
	$options->{'use_baked_viewer'} = 1;
	$log->info("_launchViewer: invoking launchPadStart options: ", sub {use Data::Dumper; Dumper($options);});
	updateClassAdViewerStatus($options->{'execrunid'}, $VIEWER_STATE_LAUNCHING, 'Launching viewer', $options);
	if ((my $status = launchPadStart($options)) != $LAUNCHPAD_SUCCESS) {
		$tracelog->trace("_launchViewer - launchPadStart failed - status: $status"); 
		return 0;
	}
	$tracelog->trace('_launchViewer - launchPadStart success ');
	return 1;
}
