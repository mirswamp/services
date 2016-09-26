#/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

# Test Launchpad interface
use strict;
use warnings;

use Test::More;
use File::Spec;
use English '-no_match_vars';
use Getopt::Long;
use Cwd;
use Log::Log4perl;
use Log::Log4perl::Level;
use File::Spec qw(catpath catfile);
use Data::Dumper qw(Dumper);

BEGIN {
    use_ok('SWAMP::Client::AgentClient');
    use_ok('SWAMP::SWAMPUtils');
}

use SWAMP::Client::AgentClient qw(configureClient listJobs execNodePing);
use SWAMP::Client::LaunchPadClient qw(configureClient launchPadStart launchPadCreateID );
use SWAMP::SWAMPUtils qw(getHostAndPort getSwampConfig getLoggingConfigString);

use subs qw(start_server callOK);
my ( $vol, $dir, undef ) =
  File::Spec->splitpath( File::Spec->rel2abs($PROGRAM_NAME) );
$dir = File::Spec->catpath( $vol, $dir, q{} );
require File::Spec->catfile( $dir, 'util.pl' );


my $configfile='test.conf';
my $bogfile;
my $useTestServer = 1;
my $host;
my $port;
my $debug = 0;
GetOptions(
    'config=s' => \$configfile,
    'bog=s' => \$bogfile,
    'server!'  => \$useTestServer,
    'debug'    => \$debug
);
# Set this in the environment, all subprocesses and their children will inherit
$ENV{'SWAMP_CONFIG'} = File::Spec->catfile($dir, $configfile);

sub logtag {
    return $PROGRAM_NAME;
}
sub logfilename {
    return "${PROGRAM_NAME}.log";
}
Log::Log4perl->init( getLoggingConfigString() );
my $log = Log::Log4perl->get_logger(q{});
$log->level( $debug ? $TRACE : $INFO );
my $cwd = getcwd();
$log->debug("process started in $cwd");
chdir($dir);
unlink glob "*.bog"; # This test needs to start with a well defined environment
unlink glob ".agent*"; # This test needs to start with a well defined environment
unlink glob ".hypervisors"; # This test needs to start with a well defined environment
$log->debug("process now in in ".getcwd());
my $cmd = "perl -I${cwd}/lib ${cwd}/AgentMonitor.pl --init --testharness " . ( $debug ? q{--debug} : q{} ).q{ }.($configfile ? qq{--config $configfile} : q{} ) ;
$log->info("starting server: [$cmd]");
my $child = start_server( $cmd) if ($useTestServer);
$cmd = "perl -I${cwd}/lib ${cwd}/LaunchPad.pl --testharness --init " . ( $debug ? q{--debug} : q{} ).q{ }.($configfile ? qq{--config $configfile} : q{} ) ;
$log->info("starting server: [$cmd]");
my $child2 = start_server( $cmd) if ($useTestServer);

my ($tempport, $temphost) = getHostAndPort ('agentMonitor', $configfile);
if ( !defined($port) ) {
    $port = int( $tempport );
}
if ( !defined($host) ) {
    $host = $temphost;
}

is( defined($port) && defined($host), 1, 'Read configuration' );
$log->debug("Calling AgentClient::configureClient <$host>, <$port>");
SWAMP::Client::LaunchPadClient::configureClient( $host, $port );
my $config     = getSwampConfig($configfile);
$port = $config->get('agentMonitorJobPort');
SWAMP::Client::AgentClient::configureClient( $host, $port );

{
    my $res = listJobs();
}
execNodePing('127.0.0.1', SWAMP::SWAMPUtils->ALIVE, 4, 4);

my $res = launchPadCreateID();
is( callOK( $res ) , 1, 'launchpadCreateID' );
my $execrunid = $res->{'execrunid'};
#my %bog = ( 'execrunid' => $execrunid, 'package' => 'testpackage' ,
#'toolname' => 'toolname',
#'toolpath' => 'toolpath',
#'toolinvoke' => 'toolinvoke',
#'tooldeploy' => 'tooldeploy',
#'packagename' => 'packagename',
#'platform' => 'Solaris;)',
#'packagesourcepath' => 'packagesourcepath',
#'packagebuildoutputpath' => 'packagebuildoutputpath',
#'packagedeploy' => 'packagedeploy',
#'packagepath' => 'packagepath',
#'resultsfolder' => 'resultsfolder',
#);
my %bog = (
    'toolexecutable'  => 'toolpath packageinvoke',
    'toolname'    => 'FindBugs.1.2.3.4',
    'packagename' => 'guice-3.0.0.jar',

    # Package path is needed by invokeResultCollector
    'packagepath'   => 'packagepath',
    'toolpath'      => '/opt/findbugs.tar.gz',
    'tooldirectory' => 'findbugs',
    'toolarguments' => '',
    'gav'           => 'com.jolira:guice:3.0.0',
    'execrunid'     => $execrunid,
    'packagebuild'  => '',
    'packagedeploy' => '',
    'tooldeploy'    => 'tar xvf toolpath',
    'platform'      => 'Solaris;)',
    'resultsfolder' => 'resultsfolder',
    'packagesourcepath' => 'guice-3.0.0',
    'packagebuildfile' => 'test.xml',
    'packagebuildtarget'  => '',
    'packagebuildtool' => 'gradle'
);
$log->info("runid is ".$res->{'execrunid'});
$res = launchPadStart(\%bog);
is (callOK($res), 1, 'launchpadStart');
sleep 2; # Wait for the testagent to start the job
$res = listJobs();
print Dumper($res);
is (callOK($res), 1, 'launchpadListJobs');
isnt ($res->{$execrunid}->{'id'}, undef, 'test job started');
if ($useTestServer) { 
    stop_server($child); 
    stop_server($child2); 
}

done_testing();
