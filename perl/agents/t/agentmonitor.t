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
}

use SWAMP::Client::AgentClient
  qw(configureClient addVmID createVmID removeVmID queryVmID listVmID agentLogState getSuitableMachines agentLogLog);
use SWAMP::SWAMPUtils qw(getSwampConfig getHostAndPort getLoggingConfigString getHostname);
use SWAMP::AgentMonitorCommon qw(:common);

use subs qw(start_server stop_server callFAIL callOK);
my ( $vol, $dir, undef ) =
  File::Spec->splitpath( File::Spec->rel2abs($PROGRAM_NAME) );
$dir = File::Spec->catpath( $vol, $dir, q{} );
require File::Spec->catfile( $dir, 'util.pl' );

my $host;
my $port;
my $configfile    = 'test.conf';
my $useTestServer = 1;
my $debug         = 0;
GetOptions(
    'host=s'   => \$host,
    'port=s'   => \$port,
    'config=s' => \$configfile,
    'server!'  => \$useTestServer,
    'debug'    => \$debug
);

# Set this in the environment, all subprocesses and their children will inherit
$ENV{'SWAMP_CONFIG'} = File::Spec->catfile( $dir, $configfile );

sub logtag {
    return $PROGRAM_NAME;
}

sub logfilename {
    return "${PROGRAM_NAME}.log";
}
Log::Log4perl->init( getLoggingConfigString() );
my $log = Log::Log4perl->get_logger(q{});
$log->level( $debug ? $TRACE : $INFO );
local $SIG{'__DIE__'} = sub { Log::Log4perl->get_logger(q{})->logconfess() };

my $cwd = getcwd();
$log->debug("process started in $cwd");
chdir($dir);
$log->debug( "process now in in " . getcwd() );
unlink glob "*.bog";           # This test needs to start with a well defined environment
unlink glob ".agent*";         # This test needs to start with a well defined environment
unlink glob ".hypervisors";    # This test needs to start with a well defined environment

my ( $tempport, $temphost ) = getHostAndPort('agentMonitor');
my $config = getSwampConfig();
$tempport = $config->get('agentMonitorJobPort');
if ( !defined($port) ) {
    $port = int($tempport);
}
if ( !defined($host) ) {
    $host = $temphost;
}

my $childA;
my $childB;
if ($useTestServer) {
    my $cmdA = "perl -I${cwd}/lib ${cwd}/AgentMonitor.pl --testharness " .       ( $debug ? q{--debug} : q{} );
    my $cmdB = "perl -I${cwd}/lib ${cwd}/TestDispatchServer.pl " . ( $debug ? q{--debug} : q{} );
    $log->info("starting server: [$cmdA]");
    $childA = start_server($cmdA);
    $log->info("starting server: [$cmdB]");
    $childB = start_server($cmdB);
}
is( defined($port) && defined($host), 1, "Read configuration" );
if ( defined($port) && defined($host) ) {
    configureClient( $host, $port );
}

my $tmpId = createVmID();
like( $tmpId, qr/^[A-F,0-9]{8}-[A-F,0-9]{4}-[A-F,0-9]{4}-[A-F,0-9]{4}-[A-F,0-9]{12}$/, 'createID' );
isnt( createVmID(), $tmpId, 'createID unique' );
ok( callFAIL( queryVmID('id1') ), 'queryVmID' );
my $id0 = 'id1';
is( removeVmID( \$id0 ), 0, 'removeVmID' );
ok( callOK( addVmID( 'id1', 'arun0', 'domain1' ) ), 'addVmID id1' );
ok( callFAIL( addVmID( 'id1', 'arun0', 'domain1' ) ), 're-addVmID 1' );
ok( callOK( queryVmID('id1') ), 'queryVmID' );

for ( my $ii = 2 ; $ii < 10 ; ++$ii ) {
    ok( callOK( addVmID( "id$ii", "arun$ii", "domain$ii" ) ), "addVmID $ii" );
}

#is (agentGetDomainState('id1'), 'UNKNOWN', 'query unset domain state');

ok( callOK( agentLogState( time, 'domain1', 'running', 'running on empty' ) ),
    'agentLogState running' );

#is (agentGetDomainState('id1'), 'running', 'query domain state');

ok( callOK( agentLogState( time, 'domain1', 'shutdown', 'goodbye' ) ), 'agentLogState shutdown' );

#is (agentGetDomainState('id1'), 'shutdown', 'query domain state');
#is (agentGetDomainState('bogusid'), 'INVALID_DOMAIN', 'query bogus domain state');

my %status = ( 'state' => 'running', 'startCount' => 3, 'sshIpAddress' => '127.0.0.1' );

# NB These require the dispatch service to be running too.
ok( callOK( agentLogLog( 'id1', '/etc/hosts' ) ),        'agentLogLog happy path' );
ok( callOK( agentLogLog( 'id1', '/etc/../etc/hosts' ) ), 'agentLogLog non-canonical path' );

my $ref = listVmID();

foreach my $key ( keys %{$ref} ) {
    my $k = $key;
    $k =~ s/id//;
    my $v = $ref->{$key}->{'domain'};
    $v =~ s/domain//;
    is( $v, $k, "check listVmID $key" );
    my $copy = $key;
    is( removeVmID( \$copy ), 1, "remove $key" );
}

#my @machineList = qw/127.0.0.1 10.0.0.254/;
#
# N.B. these methods are directly in the AgentMonitorCommon package and aren't
# being called through the AgentClient interface. Keep that in mind when evaluating
# the data being manipulated.

setViabilityFrequency(5);
setHypervisorViability( '127.0.0.1', SWAMP::SWAMPUtils->ALIVE, 8, 32 );
sleep 6;
my @machineList = getHypervisorList();
cmp_ok( $#machineList, '==', -1, 'Empty list after timer' );

setHypervisorViability( '127.0.0.1', SWAMP::SWAMPUtils->DEAD );
setHypervisorViability( '127.0.0.2', SWAMP::SWAMPUtils->ALIVE, 24, 128 );
@machineList = getHypervisorList();
cmp_ok( $#machineList, '==', 0, 'Single item list if 1 alive hypervisor' );

setHypervisorViability( '127.0.0.1', SWAMP::SWAMPUtils->ALIVE, 8, 32 );
@machineList = getHypervisorList();
cmp_ok( $#machineList, '>=', 0, 'Get list of hypervisors' );


# Test the add/remove Job methods
is( addJob( $machineList[0] ),     1, 'added a job' );
is( numberJobs( $machineList[0] ), 1, 'numberJobs call 1' );
is( addJob( $machineList[0] ),     2, 'added job on same host' );
is( numberJobs( $machineList[0] ), 2, 'numberJobs call 2' );

# In the order of decreasing load, the first machine is now loaded
my @machines = buildSuitableMachineList( \@machineList );

is( removeJob( $machineList[0] ), 1, 'remove a job call 1' );
is( removeJob( $machineList[0] ), 0, 'remove a job call 2' );
is( removeJob( $machineList[0] ), 0, 'remove a job will not go negative' );

# Test the set/delete VMID methods
is( setVMID( 'vmid0', 'runid', 'domain0' ), 1, 'call setVMID' );
is( setVMID( 'vmid0', 'runid', 'domain0' ), 0, 'already defined call to setVMID' );
is( getDomainID('vmid0'), 'domain0', 'Check domain name of valid VM ID' );
is( deleteVMID('vmid'),   0,         'removeVMID invalid ID' );
is( isValidVMID('vmid'),  0,         'check invalid VM ID' );
is( isValidVMID('vmid0'), 1,         'check valid VM ID' );
is( setVMID( 'vmid0', 'runid', 'domain0' ), 0, 'already defined call to setVMID' );
is( deleteVMID('vmid0'),  1, 'removeVMID valid ID' );
is( isValidVMID('vmid0'), 0, 'check formerly valid VM ID' );

# Test the jobLaunched/Finished methods
is( jobLaunched(),        1, 'jobLaunched first call' );
is( jobLaunched(),        2, 'jobLaunched second call' );
is( numberJobsLaunched(), 2, 'number jobs launched' );
is( jobFinished(),        1, 'job one finished' );
is( jobFinished(),        0, 'job two finished' );
is( jobFinished(),        0, 'job finished cannot be negative' );

# Test HTCondor methods
is( getClusterHypervisor('runid'), undef, 'Get hypervisor for invalid run' );
is( isClusterID('runid'),          0,     'Check invalid HTCondor job ID' );
setClusterInfo( 'runid', 'jobid', 0 );
is( getClusterHypervisor('runid'), 'UNKNOWN', 'Get hypervisor for new run' );
is( isClusterID('runid'),          1,         'Check valid HTCondor job' );
is( getClusterID('runid'),         'jobid',   'Read HTCondor job ID' );
setClusterHypervisor( 'runid', 'exec1' );
is( getClusterHypervisor('runid'), 'exec1', 'Get hypervisor for running run' );
is( removeClusterID('runid'),      1,       'Remove HTCondor job ID' );
is( isClusterID('runid'),          0,       'Check removed HTCondor job' );
is( getClusterHypervisor('runid'), undef,   'Get hypervisor for removed ID' );
is( grabLaunchToken('run0'),       1,       'Grab the launch token when available' );
is( grabLaunchToken('run1'),       1,       'Grab the launch token when still available' );
is( grabLaunchToken('run2'),       0,       'Grab the launch token when not available' );
is( releaseLaunchToken('run0'),    1,       'Release the launch token when owner' );
is( releaseLaunchToken('run0'),    0,       'Release the launch token when already released' );
is( releaseLaunchToken('run2'),    0,       'Release the launch token when not owner' );

if ($useTestServer) {
    stop_server($childA);
    stop_server($childB);
}

done_testing();
