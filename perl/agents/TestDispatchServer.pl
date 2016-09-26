#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#Copy

# Test server for Dispatcher interface (log collector, result collector, execute record collector)
use 5.014;
use utf8;
use warnings;
use strict;
use Cwd qw(abs_path);

use Getopt::Long qw/GetOptions/;
use Log::Log4perl;
use Log::Log4perl::Level;
use Pod::Usage qw/pod2usage/;
use English '-no_match_vars';
use File::Basename qw(basename);
use Carp 'croak';
use RPC::XML;
use RPC::XML::Server;

use SWAMP::SWAMPUtils qw(getSwampConfig getMethodName getLoggingConfigString );

our $VERSION = '1.00';
my $host = 'localhost';
my $port = '8083';
my $configfile;

my $help  = 0;
my $man   = 0;
my $debug = 0;

GetOptions(
    'host=s'   => \$host,
    'port=i'   => \$port,
    'config=s' => \$configfile,
    'help|?'   => \$help,
    'man'      => \$man,
    'debug'    => \$debug,
) or pod2usage(2);

if ($help) { pod2usage(1); }
if ($man) { pod2usage( '-verbose' => 2 ); }
sub logtag {
    ( my $name = $PROGRAM_NAME ) =~ s/\.pl//sxm;
    return basename($name);
}
sub logfilename {
    (my $name = $PROGRAM_NAME) =~s/\.pl//sxm;
    return "${name}.log";
}
Log::Log4perl->init( getLoggingConfigString() );
Log::Log4perl->get_logger(q{})->level( $debug ? $TRACE : $INFO );

# We're impersonating the dispatcher
my $config = getSwampConfig($configfile);
if ( !defined($port) ) {
    $port = int( $config->get('dispatcherPort') );
}
if ( !defined($host) ) {
    $host = $config->get('dispatcherHost');
}

my $daemon = RPC::XML::Server->new(
	'host' => $host,
	'port' => $port
);

# Add methods to our server
my @sig = ( 'struct', 'struct struct' );
$daemon->add_method(
    {
        'name'      => getMethodName('LOG_COLLECTOR_LOGSTATE'),
        'signature' => \@sig,
        'code'      => \&logState
    }
);

@sig = ( 'struct', 'struct struct' );
$daemon->add_method(
    {
        'name'      => getMethodName('LOG_COLLECTOR_LOGSTATUS'),
        'signature' => \@sig,
        'code'      => \&logStatus
    }
);

@sig = ( 'struct', 'struct struct' );
$daemon->add_method(
    {
        'name'      => getMethodName('LOG_COLLECTOR_LOGLOG'),
        'signature' => \@sig,
        'code'      => \&logLog
    }
);
@sig = ( 'struct', 'struct struct' );
$daemon->add_method(
    {
        'name'      => getMethodName('RESULT_COLLECTOR_SAVERESULT'),
        'signature' => \@sig,
        'code'      => \&saveResults
    }
);
@sig = ( 'struct', 'struct struct' );
$daemon->add_method(
    {
        'name'      => getMethodName('RUNCONTROLLER_DORUN'),
        'signature' => \@sig,
        'code'      => \&doRun
    }
);

# Here we go!
# Pass in a list of signals to gracefully exit on.
my @signals = qw/TERM HUP INT/;
my %map = ( 'signal' => \@signals );
trace("$PROGRAM_NAME: entering listen loop on $host at port:$port");
$daemon->server_loop(%map);
trace("Good bye");
exit 0;

sub trace {
    my $msg = shift;
    Log::Log4perl->get_logger(q{})->debug($msg);
    return;
}

sub logStatus {
    my $server = shift;
    my $href   = shift;
    foreach my $key ( keys %{$href} ) {
        trace("logStatus:$key = <${$href}{$key}>");
    }
    return { 0, "all is well" };
}

sub logState {
    my $server = shift;
    my $href   = shift;
    foreach my $key ( keys %{$href} ) {
        trace("logState:$key = <${$href}{$key}>");
    }
    return { 0, "all is well" };
}

sub saveResults {
    my $server = shift;
    my $href   = shift;
    foreach my $key ( keys %{$href} ) {
        trace("saveResults:$key = <${$href}{$key}>");
    }
    if ( $href->{'pathname'} ne abs_path( $href->{'pathname'} ) ) {
        return { 'error', 'not a canonical path' };
    }
    return { 0, "all is well" };
}

sub logLog {
    my $server = shift;
    my $href   = shift;
    foreach my $key ( keys %{$href} ) {
        trace("logLog:$key = <${$href}{$key}>");
    }
    if ( $href->{'pathname'} ne abs_path( $href->{'pathname'} ) ) {
        return { 'error', 'not a canonical path' };
    }
    return { 0, "all is well" };
}
sub doRun {
    my $server = shift;
    my $href = shift;
    trace("doRun execrunid = <${$href}{'execrunid'}>");
    return {};
}

__END__

=pod

=encoding utf8

=head1 NAME


=head1 SYNOPSIS



=head1 DESCRIPTION

=head1 OPTIONS

=over 8

=item --man

Show manual page for this script

=back

=head1 EXAMPLES

=head1 SEE ALSO

=cut
