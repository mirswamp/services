#/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

# Test the ResultCollector interface

use strict;
use warnings;

use Cwd qw(abs_path getcwd);
use English '-no_match_vars';
use File::Spec;
use File::Basename qw(basename);
use Getopt::Long;
use Log::Log4perl::Level;
use Log::Log4perl;
use Test::More ; #tests => 13;

BEGIN {
    use_ok('SWAMP::Client::ResultCollectorClient');
    use_ok('SWAMP::SWAMPUtils');
}

use SWAMP::Client::ResultCollectorClient qw(configureClient saveResult);
use SWAMP::SWAMPUtils qw(getHostAndPort getLoggingConfigString);
use subs qw(start_server stop_server callOK callFAIL);
my ($vol, $dir, undef) = File::Spec->splitpath(File::Spec->rel2abs($PROGRAM_NAME));
$dir = File::Spec->catpath($vol, $dir, q{});
require File::Spec->catfile($dir, 'util.pl');

my $configfile = 'test.conf';
my $useTestServer=1;
my $host;
my $port;
my $debug = 0;
GetOptions('config=s' => \$configfile, 'server!' => \$useTestServer, 'debug'=> \$debug);

# Set this in the environment, all subprocesses and their children will inherit
$ENV{'SWAMP_CONFIG'} = File::Spec->catfile($dir, $configfile);

sub logtag {
    return $PROGRAM_NAME;
}
sub logfilename {
    return "${PROGRAM_NAME}.log";
}

Log::Log4perl->init( getLoggingConfigString() );

my $cwd = getcwd();
chdir($dir);
my $canonname = File::Spec->rel2abs(basename($PROGRAM_NAME)); # This file should exist.

print STDERR "\n\$cannonname: $canonname\n\n";

my $log = Log::Log4perl->get_logger(q{});
$log->level($debug ? $TRACE : $INFO);
local $SIG{'__DIE__'} = sub { Log::Log4perl->get_logger(q{})->logconfess() };

# Try logging w/out a server
$log->info("A warning is expected here.");
ok (callFAIL (saveResult( { 'execrunid' => 'arunid1', 'pathname'  => $canonname} )), 'serverless saveResult');

my $cmd = "perl -I${cwd}/lib ${cwd}/TestDispatchServer.pl " . ( $debug ? q{--debug} : q{} );
$log->info("starting server: [$cmd]");
my $child = start_server($cmd) if ($useTestServer);
my ($tempport, $temphost) = getHostAndPort('dispatcher', $configfile);
if ( !defined($port) ) {
    $port = int( $tempport );
}
if ( !defined($host) ) {
    $host = $temphost;
}
is (defined($port) && defined($host), 1, "Read configuration");
    configureClient($host, $port);
ok( callOK(saveResult( { 'execrunid' => 'arunid1' , 'pathname' => $canonname } ) ), 'saveResult happy path');

ok( callOK(saveResult( { 'execrunid' => 'arunid1' ,
    'pathname' => $canonname,
    'gav' => 'a gav specification'}) ), 'saveResult with extra stuff');

ok( callFAIL( saveResult( { 'execrunid' => 'arunid1' , 'pathname' => basename($PROGRAM_NAME)} ) ), "saveResult with non-canonical path" );
if ($useTestServer) { stop_server($child); }
done_testing();
