#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#
# simple slave client for executing remote commands over virtual serial port.
use 5.008;
use utf8;
use warnings;
use strict;
use FindBin qw($Bin);
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );

use Getopt::Long qw/GetOptions/;
use Pod::Usage qw/pod2usage/;
use English '-no_match_vars';
use Carp qw(carp croak);
use Fcntl qw(O_RDWR O_NDELAY O_NOCTTY);

my $dev = "/dev/virtio-ports/arbitrary.virtio.serial.port.name";

#my $dev = "/dev/vport0p2";
my $com;

my $help = 0;
my $man  = 0;
our $VERSION = '1.00';

GetOptions(
    'help|?' => \$help,
    'p=s'    => \$dev,
    'man'    => \$man,
) or pod2usage(2);

sub catch_zap {
    my $signame = shift;
    if ( !close($com) ) {
        carp "Error closing port $OS_ERROR";
    }
    croak "Oops catch $signame";
}
local $SIG{'INT'} = \&catch_zap;

if ($help) { pod2usage(1); }
if ($man) { pod2usage( '-verbose' => 2 ); }

if ( sysopen( $com, $dev, O_RDWR | O_NOCTTY ) ) {
    my $in;
    while (1) {
      WAIT:
        print "spinwait\n";
        $in = q{};
        if ( defined( sysread( $com, $in, 512 ) ) ) {
            print "Got [$in]\n";
        }
        goto WAIT if ( $in eq q{} );
        print "Done reading \n";
        my $ret = syswrite( $com, "you said: $in\n" );
        if ( !defined($ret) ) {
            carp "Write error: $OS_ERROR";
            last;
        }
        if ( $in =~ /^quit/sxm ) {
            sleep 1;
            syswrite( $com, "goodbye\nS-EOT\n" );
            last;
        }
        elsif ( $in =~ /version/sxm ) {
            showversion();
        }
        elsif ( $in =~ /^run\ (.*)$/sxm ) {
            syswrite( $com, qx{$1 2>&1} );
        }
        syswrite( $com, "S-EOT\n" );
    }
    if ( !close $com ) {
        carp "Error closing port $OS_ERROR";
    }
}
else {
    carp "Error opening $dev $OS_ERROR";
}

sub showversion {
    syswrite( $com,
        "prog:$PROGRAM_NAME perl:$PERL_VERSION os:$OSNAME exe:$EXECUTABLE_NAME uid:$UID gid:$GID\n"
    );
    return;
}
