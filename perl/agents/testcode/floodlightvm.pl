#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2018 Software Assurance Marketplace

#** @file floodlight.pl
#
# @brief
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 09/03/2014 13:05:44
#*

use 5.010;
use utf8;
use warnings;
use strict;
use FindBin qw($Bin);
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib", "$FindBin::Bin/../lib" );

use Getopt::Long qw/GetOptions/;
use Pod::Usage qw/pod2usage/;
use English '-no_match_vars';
use Carp qw(carp croak);
use JSON qw(from_json to_json);

my $help = 0;
my $man  = 0;
our $VERSION = '1.00';

#my $ip1=q{128.104.7.168};
my $ip1        = q{128.104.7.0/24}; # This is the current dev VM environment
my $serverIP  ;#  = q{128.104.7.184};
my $serverMAC ;# = q{52:54:00:D3:06:EC};
my $verbose    = 0;
my $floodlight = "http://swa-flood-dt-01:8080";
my $off;

GetOptions(
    'help|?'       => \$help,
    'vmip=s'       => \$ip1,
    'off'          => \$off,
    'ip=s'         => \$serverIP,
    'mac=s'        => \$serverMAC,
    'verbose!'     => \$verbose,
    'floodlight=s' => \$floodlight,
    'man'          => \$man,
) or pod2usage(2);

if ($help) { pod2usage(1); }
if ($man) { pod2usage( '-verbose' => 2 ); }

if ($off) {

    # Fetch all of the flows from the controll
    my ( $output, $status ) =
      systemcall("curl -s -X GET $floodlight/wm/staticflowentrypusher/list/all/json");
    my $ref      = from_json($output);
    my $nRemoved = 0;
    foreach my $key ( keys $ref ) {
        foreach my $rulename ( keys $ref->{$key} ) {

            # If the rulename contains the name ps-dev-license, remove it. If
            # you are looking for a specific VM using this license server then
            # the search pattern needs to change
            if ( $rulename =~ /^ps-dev-license/sxm ) {
                my ( $curlout, $curlstatus ) = systemcall(
qq{curl -s -X DELETE -d '{"name":"$rulename"}'  $floodlight/wm/staticflowentrypusher/json}
                );
                if ($curlstatus) {
                    carp "Unable to remove rule $rulename";
                }
                else {
                    ++$nRemoved;
                }
            }
        }
    }
    print "Removed $nRemoved rules\n" if ($verbose);

    exit 0;
}

if (!$serverMAC && !$serverIP) {
    pod2usage("Need to specify either license server MAC address or license server IP address");
}

# Fetch the switch information
my ( $output, $status ) = systemcall("curl -s -X GET $floodlight/wm/core/controller/switches/json");

my $ref = from_json($output);

my $idx = 0;    # Flows must have unique names, use a simple counter

my $address = "$floodlight/wm/staticflowentrypusher/json";

# Need a flow for each switch
foreach my $switch (@$ref) {
    my $data;

    # Only allow connections to port 2002 on the license server
    my %flow = (
        "switch"     => $switch->{dpid},
        "name"       => "ps-dev-license-$ip1-$idx",
        "priority"   => 65,
        'dst-port'   => '2002', # This specifies to port to open
        'protocol'   => '6',    # TCP protocol. If no protocol is specified,
                                # Any proto is allowed
        'ether-type' => '2048',
        'active'     => 'true',
        'actions'    => 'output=flood'
    );
    if ($serverMAC) {
        $flow{'dst-mac'} = $serverMAC;
    }
    else {
        $flow{'dst-ip'} = $serverIP . '/32';
    }
    $flow{'src-ip'} = $ip1;

    print "Adding rule $flow{'name'}\n" if ($verbose);
    $data = to_json( \%flow );
    `curl -s -q -X POST -d '$data' $address`;

    $idx++;

    # Update the flow rule for the reverse direction, allowing any port back

    delete $flow{'dst-port'};
    $flow{'name'} = "ps-dev-license-$ip1-$idx";
    print "Adding rule $flow{'name'}\n" if ($verbose);
    if ($serverMAC) {
        $flow{'src-mac'} = $serverMAC;
    }
    else {
        $flow{'src-ip'} = $serverIP . '/32';
    }
    $flow{'dst-ip'} = $ip1;

      $data = to_json( \%flow );
    `curl -s -X POST -d '$data' $address`;
    $idx++;
}

#** @function systemcall( $command )
# @brief Run an external process and wait for it to finish
#
# @param $command the entire command line of the process to run
# @return the output (STDOUT and STDERR) of the process and process exit status. 0 => success.
#*
sub systemcall {
    my ($command) = @_;
    my $handler = $SIG{'CHLD'};
    local $SIG{'CHLD'} = 'DEFAULT';
    my ( $output, $status ) = ( $_ = qx{$command 2>&1}, $CHILD_ERROR >> 8 );
    local $SIG{'CHLD'} = $handler;

    if ($status) {
        my $msg = "$command failed with status $status";
        if ( defined($output) ) {
            $msg .= "($output)";
        }
        carp $msg;
    }
    return ( $output, $status );
}

__END__
=pod

=encoding utf8

=head1 NAME

floodlightvm.pl - manipulate the floodlights controller to allow/prevent access
to the Parasoft license server

=head1 SYNOPSIS

floodlightvm.pl [--off] [--mac xx:xx:xx:xx:xx:xx] [--ip xx.xx.xx.xx[/xx]]
[--verbose] [--vmip xx.xx.xx.xx[/xx]]

=head1 DESCRIPTION

floodlightvm.pl either allows access to port 2002 on a specified host or
removes access to port 2002. It does this by creating static flow rules on the
floodlight controller in the dev environment using the Static Flow Pusher API
(http://www.openflowhub.org/display/floodlightcontroller/Static+Flow+Pusher+API). 

The rules created are all named 'ps-dev-license-clientIP-NN' so they can be
easily recognized/removed. This script can be run multiple times to add flows
for multiple single client IP addresses.

=head1 OPTIONS

=over 8

=item B<--ip I<xx.xx.xx.xx[/xx]>>

Specify the IP address of the license server

=item B<--mac I<xx:xx:xx:xx:xx:xx>>

Specify the MAC address of the license server

=item B<--ip I<xx.xx.xx.xx[/xx]>>

Specify the IP address of the client for which access is desired. If not
specified, all VM IP addresses in dev (128.104.7.0/24) are allowed access.

=item B<--verbose>

Emit some indication of what is going on in the script

=item B<--off> 

Turn off access to port 2002 on the license server.

=item B<--help>

Display brief help for this script


=item B<--man>

Show manual page for this script

=back

=head1 EXAMPLES

perl floodlightvm.pl --mac 52:54:00:D3:06:EC --vmip 128.104.7.22

perl floodlightvm.pl --mac 52:54:00:D3:06:EC --vmip 128.104.7.23

perl floodlightvm.pl --off

=cut


