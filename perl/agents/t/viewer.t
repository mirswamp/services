#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

use strict;
use warnings;

use Test::More;
use File::Spec;
use English '-no_match_vars';
use Cwd qw(abs_path getcwd);
use Getopt::Long;
use Log::Log4perl;
use Log::Log4perl::Level;

BEGIN {
    use_ok('SWAMP::Client::AgentClient');
    use_ok('SWAMP::SWAMPUtils');
    use_ok('SWAMP::AgentMonitorCommon');
    use_ok('SWAMP::Client::GatorClient');
    use_ok('SWAMP::Locking');
}

use SWAMP::SWAMPUtils qw(getSwampConfig getLoggingConfigString);
use SWAMP::AgentMonitorCommon qw(:common);
use SWAMP::Client::AgentClient qw(isViewerAvailable setViewerState configureClient abortViewer);
use SWAMP::Locking qw(swamplock swampunlock);

use subs qw(start_server stop_server callFAIL callOK);

my $childA;
my $debug = 0;
my ( $vol, $dir, undef ) =
  File::Spec->splitpath( File::Spec->rel2abs($PROGRAM_NAME) );
$dir = File::Spec->catpath( $vol, $dir, q{} );
require File::Spec->catfile( $dir, 'util.pl' );

GetOptions( 'debug' => \$debug );

Log::Log4perl->init( getLoggingConfigString() );
my $log = Log::Log4perl->get_logger(q{});
$log->level( $debug ? $TRACE : $INFO );
local $SIG{'__DIE__'} = sub { Log::Log4perl->get_logger(q{})->logconfess() };

# These calls are directly into the AgentMonitorCommon library, not thru XML-RPC interface.
is (getViewerCount('CodeDX', 'projectX'), 0, 'Check for access to viewer');
is (incViewerCount('CodeDX', 'projectX'), 1, 'Inc access to viewer');
is (getViewerCount('CodeDX', 'projectX'), 1, 'Retry access to viewer');
clearViewerCount('CodeDX', 'projectX');
is (getViewerCount('CodeDX', 'projectX'), 0, 'Try access to viewer after clear');
is( getViewerState( 'CodeDX', 'projectX' ), 'UNDEFINED', 'Check undefined viewer' );
is( saveViewerState({ 'viewer' => 'CodeDX', 'project' => 'projectX', 'state' => 'running' , 'domain' => 'vswamp9000' } ), 'UNDEFINED', 'set viewer state running.' );
foreach my $idx (0..100) {
    my $tmpproj = "project_$idx";
    my $tmpdom = "vswamp$idx";
    is( saveViewerState({ 'viewer' => 'CodeDX', 'project' => $tmpproj, 'state' => 'running' , 'domain' => $tmpdom } ), 'UNDEFINED', 'set viewer state running.' );
}
is( getViewerState( 'CodeDX', 'projectX' ), 'running', 'get running state' );
my ($proj, $viewer, $state)=getViewerByDomain('vswamp9000');
is ($proj, 'projectX', 'Get project by domain');
is ($viewer, 'CodeDX', 'Get viewer by domain');
is ($state, 'running', 'Get state by domain');
foreach my $idx (10..100) {
    next if ($idx %2);
    my $tmpproj = "project_$idx";
    my $tmpdom = "vswamp$idx";
    is( getViewerState( 'CodeDX', $tmpproj ), 'running', "get running state $idx" );
    ($proj, $viewer, $state)=getViewerByDomain($tmpdom);
    is ($proj, $tmpproj, "Get project[$idx] by domain");
    is ($viewer, 'CodeDX', "Get viewer[$idx] by domain");
    is ($state, 'running', "Get state[$idx] by domain");
}
($proj, $viewer, $state)=getViewerByDomain('non-existentdomain');
is ($proj, undef, 'Get project by domain (fail)');
is ($viewer, undef, 'Get viewer by domain (fail)');
is ($state, undef, 'Get state by domain (fail)');
is( saveViewerState( {'viewer' => 'CodeDX', 'project' => 'projectX', 'state' => 'ready', 'ipaddress' => '127.0.0.1' } ),     'running', 'set viewer state ready.' );
is( saveViewerState( {'viewer' => 'CodeDX', 'project' => 'projectX', 'state' => 'UNDEFINED' } ), 'ready',   'set viewer state undef.' );
is( getViewerState( 'CodeDX', 'projectX' ), 'UNDEFINED', 'Check viewer state undefinded' );


my $cwd        = getcwd();
chdir($dir);
# Remove any viewer persistant data.
unlink ('.viewerinfo');
# Start an agentMonitor server and talk to it's isViewerAvailable and setViewerState methods
startAgent();
my $ref = isViewerAvailable( 'viewer' => 'CodeDX', 'project' => 'projectABC' );
foreach my $kk (keys %{$ref}) {
    print "KEY: $kk = $ref->{$kk}\n";
    if ($kk eq 'error') {
       my $map = $ref->{$kk}; 
       foreach my $k2 (keys %{$map}) {
        print "erro:$k2 $map->{$k2}\n";
       }
    }
}
is( $ref->{'ready'}, 0, 'viewer not available' );
is( setViewerState( 'viewer' => 'CodeDX', 'project' => 'projectABC', 'state' => 'started' ), 1,
    'setViewerState' );
is( setViewerState( 'viewer' => 'CodeDX', 'project' => 'projectABC', 'state' => 'ready', 'ipaddress' => '127.0.0.1', 'domain' => 'vswamp2000' ), 1,
    'setViewerState' );
$ref = isViewerAvailable( 'viewer' => 'CodeDX', 'project' => 'projectABC' );
abortViewer( 'viewer' => 'CodeDX', 'project' => 'projectABC' );
is( $ref->{'ready'}, 1, "viewer is available at $ref->{'address'}"  );
stop_server($childA);

# Test locking services
my $token='codeDX.projectABC';
is (swamplock($token), 1, 'Acquire a lock');
#is (swamplock($token), 0, 'Not acquire a locked object'); Same process can always get lock
is (swampunlock($token), 1, 'Release locked object');
is (swampunlock($token), 0, 'Release unlocked object');
done_testing();


sub startAgent {
    my $configfile = 'test.conf';
    my ( $port, $host );
    # Set this in the environment, all subprocesses and their children will inherit
    $ENV{'SWAMP_CONFIG'} = File::Spec->catfile( $dir, $configfile );
    my $config = getSwampConfig();
    $port = $config->get('agentMonitorJobPort');
    $host = $config->get('agentMonitorHost');
    SWAMP::Client::AgentClient::configureClient( $host, $port );


    my $cmdA = "perl -I${cwd}/lib ${cwd}/AgentMonitor.pl --testharness " . ( $debug ? q{--debug} : q{} );
    $childA = start_server($cmdA);

}

sub logtag {
    return $PROGRAM_NAME;
}

sub logfilename {
    return "${PROGRAM_NAME}.log";
}
