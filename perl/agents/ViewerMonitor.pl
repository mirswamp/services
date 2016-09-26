#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#** @file ViewerMonitor
# @brief ViewerMonitor is the Server that runs on the csaweb server and creates .htaccess files for Viewer
# instances. The agentMonitor will invoke methods on this server via the ViewerMonitorClient package, no other clients are expected currently.
# When agentMonitor is informed of a viewer VM being 'ready', it will invoke viewerMonitor.setup
# When agentMonitor is informed of a viewer VM being 'finished', it will invoke viewerMonitor.teardown
#
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 01/04/2014 06:26:33

#** @class main
# @brief This application is the XMLRPC server that implements `swamp.viewerMonitor.setup` and
# `swamp.viewerMonitor.teardown`
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

use SWAMP::Locking qw(swamplock);

use SWAMP::SWAMPUtils qw(
  diewithconfess
  getBuildNumber
  getLoggingConfigString
  getMethodName
  getSwampConfig
  getSWAMPDir
  getUUID
  createhtaccess
  saveProperties
  start_process
  stop_process
  removehtaccess
  uname
);

our $VERSION = '1.00';

if (!swamplock($PROGRAM_NAME)) {
    exit 0;
}

my $serverhost;
my $port;
my $debug = 0;

#** @var $asdaemon If true, daemonize ourselves at launch time, else run in the foreground.
my $asdaemon = 0;

my $configfile;

my $help       = 0;
my $doinit     = 0;
my $man        = 0;
my $startupdir = getcwd;

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
    open( STDERR, '>&STDOUT' ) || carp "Can't open STDERR $OS_ERROR";

}
chdir($startupdir);
Log::Log4perl->init( getLoggingConfigString() );
if ($asdaemon) {

    # Turn off logging to Screen appender
    Log::Log4perl->get_logger(q{})->remove_appender('Screen');
}
my $log = Log::Log4perl->get_logger(q{});
$log->level( $debug ? $TRACE : $INFO );

# Catch anyone who calls die.
local $SIG{'__DIE__'} = \&diewithconfess;

my $config;

$config = getSwampConfig($configfile);

if ( !defined($port) ) {
    $port = $config->get('viewerMonitorPort');
}
if ( !defined($serverhost) ) {
    $serverhost = $config->get('viewerMonitorHost');
}

$log->debug( 'Current directory is ' . getcwd );
$log->debug("Running on $uname");
my $daemon = RPC::XML::Server->new( 'host' => $serverhost, 'port' => $port );

# Add methods to our server
my @sig = ( 'struct', 'struct struct' );
$daemon->add_method(
    {
        'name'      => getMethodName('VIEWER_MONITOR_SETUP'),
        'signature' => \@sig,
        'code'      => \&_viewerMonitorSetup
    }
);
@sig = ( 'struct', 'struct struct' );
$daemon->add_method(
    {
        'name'      => getMethodName('VIEWER_MONITOR_TEARDOWN'),
        'signature' => \@sig,
        'code'      => \&_viewerMonitorTeardown
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
    $name = basename($name);
    return getSWAMPDir() . "/log/${name}.log";
}

# Here we go!
# Pass in a list of signals to gracefully exit on.
my @signals = qw/TERM HUP INT/;
my %map     = ( 'signal' => \@signals );
my $pv      = sprintf '%vd', $PERL_VERSION;
$log->info("$PROGRAM_NAME: under Perl $pv entering listen loop at $serverhost on port: $port");
my $res = $daemon->server_loop(%map);

# When we return from server_loop, it is time to exit.
for my $child ( keys %children ) {
    $log->debug("Stopping child process $child");
    stop_process($child);
}

# This is our chance to cleanup
$log->debug('Good bye');
exit 0;

#################
# XML RPC methods
#**  @method _viewerMonitorTeardown( $server, \%ref )
# @brief Remove the .htaccess file associated with the project referenced in the \%ref map.
#
# @param server The RPCXML server object
# @param ref Reference to a hashmap that describes the project being stopped.
# @return empty hash on success, error on failure
#*
sub _viewerMonitorSetup {
    my $server = shift;
    my $ref = shift;
    my $projuuid = $ref->{'project_uuid'};
    my $authuuid = $ref->{'auth_uuid'};
    my $viewerip = $ref->{'viewer_ip'};
    my $webroot = $ref->{'webroot'};
    $log->info("_viewerMonitorSetup() $webroot $projuuid $viewerip $authuuid");
    # Make folder $webroot/$projuuid
    # Create $webroot/$projuuid/.htaccess
    my ($output, $status) = createhtaccess($ref->{'webroot'},
        $ref->{'project_uuid'},
        $ref->{'viewer_ip'},
        $ref->{'auth_uuid'});
    if ($status) {
        return {};
    }
    else {
	    $log->error("Cannot create .htaccess $output");
        return {'error', "Cannot create .htaccess file: $output" };
    }
}

#**  @method _viewerMonitorTeardown( $server, \%ref )
# @brief Remove the .htaccess file associated with the project referenced in the \%ref map.
#
# @param server The RPCXML server object
# @param ref Reference to a hashmap that describes the project being stopped.
# @return empty hash on success, error on failure
#*
sub _viewerMonitorTeardown {
    my $server    = shift;
    my $ref = shift;
    $log->info("_viewerMonitorTeardown() $ref->{'webroot'} $ref->{'project_uuid'}");
    my ($output, $status) = removehtaccess($ref->{'webroot'}, $ref->{'project_uuid'});
    if ($status) {
        return {};
    }
    else {
        return {'error', "Cannot remove .htaccess file: $output" };
    }
    return {};
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

ViewerMonitor 

=head1 SYNOPSIS

ViewerMonitor [--port #] [--host host] [--help] [--man]

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
