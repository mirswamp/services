#/usr/bin/env perl

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
    use_ok('SWAMP::SWAMPUtils');
    use_ok('SWAMP::AgentMonitorCommon');
}

use SWAMP::SWAMPUtils qw(getLoggingConfigString getHostname);
use SWAMP::AgentMonitorCommon qw(:common);

my ( $vol, $dir, undef ) =
  File::Spec->splitpath( File::Spec->rel2abs($PROGRAM_NAME) );
$dir = File::Spec->catpath( $vol, $dir, q{} );
require File::Spec->catfile( $dir, 'util.pl' );

my $configfile    = 'test.conf';
my $debug         = 0;
GetOptions(
    'config=s' => \$configfile,
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

# N.B. these methods are directly in the AgentMonitorCommon package and aren't
# being called through the AgentClient interface. Keep that in mind when evaluating
# the data being manipulated.
my $machineA = '127.0.0.2';
my $machineB = '127.0.0.1';

setHypervisorViability( $machineA, SWAMP::SWAMPUtils->ALIVE, 24, 128 );
my @machineList = getHypervisorList();
cmp_ok( $#machineList, '==', 0, 'Single item list if 1 alive hypervisor' );

setHypervisorViability( $machineB, SWAMP::SWAMPUtils->ALIVE, 8, 32 );
@machineList = getHypervisorList();
cmp_ok( $#machineList, '>=', 0, 'Get list of hypervisors' );

my @machines = buildSuitableMachineList( \@machineList );
# Test the add/remove Job methods
is( addJob( $machineA ),     1, 'added a job' );
is( numberJobs( $machineA ), 1, 'numberJobs call 1' );
is( addJob( $machineA ),     2, 'added job on same host' );
is( numberJobs( $machineA ), 2, 'numberJobs call 2' );

is( removeJob( $machineA ), 1, 'remove a job call 1' );
is( removeJob( $machineA), 0, 'remove a job call 2' );
is( removeJob( $machineA), 0, 'remove a job will not go negative' );

setHypervisorViability( $machineB, SWAMP::SWAMPUtils->ALIVE, 7, 32 );
setHypervisorViability( $machineB, SWAMP::SWAMPUtils->ALIVE, 8, 31 );

done_testing();
