#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#** @file master.pl
#
# @brief Simple master script that reads a script file and sends commands over a virtual serial link to a VM
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 07/22/2014 16:33:42
#*

use 5.010;
use utf8;
use warnings;
use strict;
use FindBin qw($Bin);
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );

use Getopt::Long qw/GetOptions/;
use Pod::Usage qw/pod2usage/;
use English '-no_match_vars';
use Fcntl qw(O_RDWR O_NDELAY O_NOCTTY);
use Carp qw(carp croak);
use Sys::Virt;
use XML::Simple;

my $help = 0;
my $man  = 0;
my $domain;
my $dev    = '/dev/pts/5';
my $nodisk = 0;
my $script;
my $cmd;

my $port;
my $devicexml =
q{<disk type='file' device='disk'><driver name="qemu" type="qcow2" cache="none" /><source file='/home/dboulineau/smalldisk.qcow2'/><target bus="virtio" dev="vdd" /> </disk>};

sub catch_zap {
    my $signame = shift;
    detachDisk( $domain, $devicexml ) if ( !$nodisk );
    if ( !close($port) ) {
        carp "Error closing port: $OS_ERROR";
    }
    croak "Oops caught a $signame";
}
local $SIG{'INT'} = \&catch_zap;

our $VERSION = '0.00';

GetOptions(
    'help|?' => \$help,
    'p=s'    => \$dev,
    'd=s'    => \$domain,
    'n'      => \$nodisk,
    's=s'    => \$script,
    'man'    => \$man,
) or pod2usage(2);

if ($help) { pod2usage(1); }
if ($man) { pod2usage( '-verbose' => 2 ); }

if ($domain) {
    $dev = getChannel($domain);
}
my @commands;
if ($script) {
    open( my $fh, '<', $script ) || croak "NO script $OS_ERROR";
    while (<$fh>) {
        next if (/^#/); # ignore comments
        push @commands, $_;
    }
    if ( !close($fh) ) {
        carp "Error closing script: $OS_ERROR";
    }
}
#
# Server side                       Client
# send 'message\n'
#                                   read 'message\n'
# send 'EOM\n'
#                                   read 'EOM\n'

attachDisk( $domain, $devicexml ) if ( !$nodisk );
if ( sysopen( $port, $dev, O_RDWR | O_NDELAY | O_NOCTTY ) ) {
    my $pc = 0;    # program counter
    while (1) {
        print "CMD:";
        if ( !$script ) {
            $cmd = <>;
            last if ( $cmd =~ /^exit/sxm );
        }
        else {
            if ( $pc > $#commands ) {
                print "End of script\n";
                last;
            }
            else {
                $cmd = $commands[ $pc++ ];
            }
        }
        chomp $cmd;
        print "Send [$cmd]\n";
        my $res = syswrite( $port, $cmd );
        if ( !defined($res) ) {
            carp "Write error $OS_ERROR\n";
        }
        my $in;
        my $nTries = 0;
        my $resp   = q{};
        my $ack    = 0;
        while ( $nTries++ < 60 ) {
            while ( defined( sysread( $port, $in, 40 ) ) ) {
                $resp .= $in;
                if ( $resp =~ /S-EOT/sxm ) {
                    $ack = 1;
                }
            }
            last if ($ack);
            sleep 1;
        }
        if ( !$ack ) {
            carp "ERROR: did not get an ack from client ($nTries) [$resp]\n";
            last;
        }
        print "Response:\n[$resp]\n";
        last if ( $cmd eq q{quit} );
    }
    if ( !close($port) ) {
        carp "Error closing port: $OS_ERROR";
    }
}
else {
    croak "Cannot open $dev $OS_ERROR";
}
detachDisk( $domain, $devicexml ) if ( !$nodisk );

sub detachDisk {
    my $name   = shift;
    my $device = shift;
    my $addr   = shift;
    my $con    = Sys::Virt->new( address => $addr, readonly => 0 );
    my $dom    = $con->get_domain_by_name($name);
    return $dom->detach_device( $device, Sys::Virt::Domain::DEVICE_MODIFY_LIVE );
}

sub attachDisk {
    my $name   = shift;
    my $device = shift;
    my $addr   = shift;
    my $con    = Sys::Virt->new( address => $addr, readonly => 0 );
    my $dom    = $con->get_domain_by_name($name);
    return $dom->attach_device( $device, Sys::Virt::Domain::DEVICE_MODIFY_LIVE );
}

sub getChannel {
    my $name = shift;
    my $addr = shift;
    my $con  = Sys::Virt->new( address => $addr, readonly => 1 );
    my $dom  = $con->get_domain_by_name($name);
    my $xml  = $dom->get_xml_description();
    my $xs   = XML::Simple->new( 'KeepRoot' => 1, 'ForceArray' => 1, 'NoSort' => 1 );
    my $ref  = $xs->XMLin($xml);
    my $dev  = $ref->{'domain'}[0]->{'devices'}[0]->{'channel'}[0]->{'source'}[0]->{'path'};
    return $dev;
}
