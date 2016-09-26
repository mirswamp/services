#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#** @file AgentMonitor
# @brief AgentMonitor is the Server that provides virtual machine ID information to CSA Agents, as well as
#  forwards logging and results information to the Java collectors. It also provides launchPad services
#
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
#*

#** @class main
# @brief This application is the XMLRPC server that implements `swamp.launchPad.start` and
# `swamp.launchPad.createExecID`
#*

use 5.014;
use utf8;
use warnings;
use strict;
use FindBin qw($Bin);
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );

use Carp qw(croak carp);
use ConfigReader::Simple;
use Cwd qw(getcwd);
use English '-no_match_vars';
use Fcntl qw(:flock);
use File::Spec qw(devnull catfile);
use File::Basename qw(basename);
use Getopt::Long qw/GetOptions/;
use Log::Log4perl;
use Log::Log4perl::Level;
use POSIX qw(:sys_wait_h WNOHANG);    # for nonblocking read
use POSIX qw(setsid waitpid);
use Pod::Usage qw/pod2usage/;
use RPC::XML::Server;
use RPC::XML;

use SWAMP::HTCondorDefines;
use SWAMP::Locking qw(swamplock);
use SWAMP::AgentMonitorCommon qw(eventLog);
use SWAMP::Client::GatorClient qw(configureClient);

use SWAMP::SWAMPUtils qw(
  createBOGfileName
  diewithconfess
  getBuildNumber
  getLoggingConfigString
  getMethodName
  getSwampConfig
  getSWAMPDir
  getUUID
  saveProperties
  start_process
  stop_process
  uname
);

our $VERSION = '1.00';

if (!swamplock($PROGRAM_NAME)) {
    exit 0;
}

my $serverhost;
my $port;
my $debug = 0;

#** @var $asdaemon If true, daemonize ourselves at launchtime, else run in the foreground.
my $asdaemon = 0;

my $configfile;

my $help       = 0;
my $doinit     = 0;
my $man        = 0;
my $startupdir = getcwd;
my $testharness = 0;

#** @var %children this is a map of execrunid's indexed by process ID. if defined, the process ID is the associated csa_agent.
my %children;

local $SIG{'CHLD'} = sub {

    # don't change $! and $? outside handler
    local $OS_ERROR    = $OS_ERROR;
    local $CHILD_ERROR = $CHILD_ERROR;
    my $pid = 1;
    while ( $pid > 0 ) {
        $pid = waitpid( -1, WNOHANG );
    }
    return if $pid == -1;
    if ( !defined( $children{$pid} ) ) {
        return;
    }
    delete $children{$pid};
    cleanup_child( $pid, $CHILD_ERROR );
};

GetOptions(
    'host=s'   => \$serverhost,
    'port=i'   => \$port,
    'init'     => \$doinit,
    'config=s' => \$configfile,
    'debug'    => \$debug,
    'daemon'   => \$asdaemon,
    'testharness' => \$testharness,
    'help|?'   => \$help,
    'man'      => \$man,
) or pod2usage(2);

if ($help) { pod2usage(1); }
if ($man) { pod2usage( '-verbose' => 2 ); }

my $uname = uname();

if ($asdaemon) {
    chdir(q{/});
    open( STDIN, '<', File::Spec->devnull )
      || croak "can't read /dev/null: $OS_ERROR";
    open( STDOUT, '>', File::Spec->devnull )
      || croak "can't write to /dev/null: $OS_ERROR";
    defined( my $pid = fork() ) || croak "can't fork: $OS_ERROR";
    exit if $pid;    # non-zero now means I am the parent
    ( setsid() != -1 ) || croak "Can't start a new session: $OS_ERROR";
    open( STDERR, ">&STDOUT" ) || carp "Can't open STDERR $OS_ERROR";

    #    if ( open( my $pidfile, '>', '/tmp/swamp.pid' ) ) {
    #        print $pidfile "$PID\n";
    #        if ( !close $pidfile ) {
    #            carp "Cannot close $pidfile $OS_ERROR";
    #        }
    #    }
    #    else {
    #        carp "Cannot open $pidfile $OS_ERROR";
    #    }
}
chdir($startupdir);
Log::Log4perl->init( getLoggingConfigString() );
if ($asdaemon) {

    # Turn off logging to Screen appender
    Log::Log4perl->get_logger(q{})->remove_appender('Screen');
}

$SWAMP::AgentMonitorCommon::TEST_MODE = $testharness;

my $log = Log::Log4perl->get_logger(q{});
$log->level( $debug ? $TRACE : $INFO );

# Catch anyone who calls die.
local $SIG{'__DIE__'} = \&diewithconfess;

my $config;

$config = getSwampConfig($configfile);

if ( !defined($port) ) {
    $port = $config->get('agentMonitorPort');
}
if ( !defined($serverhost) ) {
    $serverhost = $config->get('agentMonitorHost');
}

my $qmPort = int( $config->get('quartermasterPort') );
my $qmHost = $config->get('quartermasterHost');
SWAMP::Client::GatorClient::configureClient( $qmHost, $qmPort);

$log->debug( "Current directory is " . getcwd );
$log->debug("Running on $uname");
my $daemon = RPC::XML::Server->new( 'host' => $serverhost, 'port' => $port );

# Add methods to our server
my @sig = ( 'struct', 'struct struct' );
$daemon->add_method(
    {
        'name'      => getMethodName('LAUNCHPAD_START'),
        'signature' => \@sig,
        'code'      => \&_launchpadStart
    }
);
@sig = ( 'struct', 'struct struct' );
$daemon->add_method(
    {
        'name'      => getMethodName('LAUNCHPAD_CREATEEXECID'),
        'signature' => \@sig,
        'code'      => \&_launchpadCreateID
    }
);

@sig = ('string');
$daemon->add_method(
    {
        'name'      => 'server.version',
        'signature' => \@sig,
        'code'      => sub {
            return "$VERSION." . getBuildNumber();
          }
    }
);

sub logtag {
    ( my $name = $PROGRAM_NAME ) =~ s/\.pl//sxm;
    return basename($name);
}

sub logfilename {
    ( my $name = $PROGRAM_NAME ) =~ s/\.pl//sxm;
    if ( $uname eq "Linux" ) {
        $name = basename($name);
        return getSWAMPDir() . "/log/${name}.log";
    }
    return "${name}.log";
}

# Here we go!
# Pass in a list of signals to gracefully exit on.
my @signals = qw/TERM HUP INT/;
my %map     = ( 'signal' => \@signals );
my $pv      = sprintf "%vd", $PERL_VERSION;
$log->info("$PROGRAM_NAME: under Perl $pv entering listen loop at $serverhost on port: $port");
startCSAAgent();    # Fire up the agent in case there are residual BOG files to process
my $res = $daemon->server_loop(%map);
for my $child ( keys %children ) {
		my $pid = waitpid( $child, WNOHANG );
		if ($pid != -1) {
				stop_process($child);
		}
}

# This is our chance to cleanup
$log->debug("Good bye");
exit 0;

#################
# XML RPC methods
sub _launchpadCreateID {
    my $server = shift;
    my $id     = getUUID();
    $log->debug("launchpadCreateID($id)");
    return { 'execrunid', $id };
}

#**  @method _launchpadStart( $server, \%bogref )
# @brief Create a CSAAgent, passing it a BOG spec on the command line \callgraph \callergraph
#
# @param server The RPCXML server object
# @param bogref Reference to a hashmap that is the BOG describing the assessment run to execute.
# @return empty hash on success, error on failure
#*
sub _launchpadStart {
    my $server    = shift;
    my $bogref    = shift;
    my $execrunid = ${$bogref}{'execrunid'};
    $log->debug("launchpadStart from $server->{'peerhost'}:$server->{'peerport'}($execrunid)");

    $log->info("launchpadStart for $execrunid");

    # The quartermaster places errors in the error key of BOG.
    # This should normally not make it as far as the LaunchPad, but belts
    # braces.
    # If there is an error key, do not proceed and instead return an error.
    if ( defined( $bogref->{'error'} ) ) {
	$log->error("job not launched: launchpadStart found an error key in the BOG for $execrunid");
        return { 'error', "Error creating job: $bogref->{'error'}" };
    }
    my $csaOpt = q{};

    # Persist the BOG to file
    my $bogfile = createBOGfileName($execrunid);
    if ( defined( $bogref->{'intent'} ) ) {
        if ( $bogref->{'intent'} eq 'VRUN' ) {
            $csaOpt = "--runnow $bogfile";# Submit this job NOW!
        }
    }
    if ( !saveProperties( $bogfile, $bogref, "Bill Of Goods File: $PROGRAM_NAME v${VERSION}" ) ) {
	$log->error("unable to create BOG file for $execrunid");
        return { 'error', "Cannot save BOG file $bogfile: $OS_ERROR" };
    }
    else {
	$log->info("saved $bogfile for run: $execrunid");
    }
    eventLog($execrunid, q{launchpadstart});
	Log::Log4perl->get_logger('viewer')->trace("$execrunid Calling startCSAAgent");
    startCSAAgent($csaOpt);
    return {};
}

# Need to create a CSA Agent, pass it the BOG folder
sub startCSAAgent {
    my $options = shift // q{};

    # We will fork() and save the child process ID in a map and continue running.
    # For now pass the BOG folder on the command line?
    my $dir = $config->get('bogrundir') || '/opt/swamp/run';
    $log->debug( "start_process: " . $config->get('csaagent') . " --bog $dir $options" );
    my $childID = start_process( $config->get('csaagent') . " --bog $dir $options" );
    if ( defined($childID) ) {
        $children{$childID} = 1;
	$log->info("started " . $config->get('csaagent') );
    }
    else {
        $log->error( "Unable to start " . $config->get('csaagent') );
    }
    return;
}

sub cleanup_child {
    my $pid   = shift;
    my $state = shift;
    $log->debug("Child $pid has $state");
    return;
}
__END__
=pod

=encoding utf8

=head1 NAME

LaunchPad 

=head1 SYNOPSIS

AgentMonitor [--port #] [--host host] [--help] [--man]

=head1 DESCRIPTION

=head1 OPTIONS

=over 8

=item --man

Show manual page

=back

=over 8

=item --help

Show this help message

=back

=over 8

=item --port

Specify port number this server will listen on.

=back

=over 8

=item --host

Specify host this server will bind to.

=back

=head1 METHODS

=over 8

=item launchPad

=back

=head1 EXAMPLES

=head1 SEE ALSO

=cut
