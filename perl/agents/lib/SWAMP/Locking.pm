# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

package SWAMP::Locking;
use 5.010;
use utf8;
use strict;
use warnings;
use English '-no_match_vars';
use Fcntl qw(LOCK_UN LOCK_NB LOCK_EX O_RDONLY O_CREAT);

use parent qw(Exporter);
our (@EXPORT_OK);
BEGIN {
    require Exporter;
    @EXPORT_OK = qw(
      swamplock
      swampunlock
    );
}

my %locks;

sub _cleanToken {
    my $token = shift;
    $token =~ s/\s//sxm;
    $token =~ s/[:\?]//sxm;
    return $token;
}

sub swamplock {
    my $token = _cleanToken(shift);
    my $ret   = 0;

    if ( sysopen my $fh, $token, O_RDONLY | O_CREAT ) {
        if ( flock $fh, ( LOCK_EX | LOCK_NB ) ) {
            $locks{$token} = $fh;
            $ret = 1;
        }
    }
    return $ret;
}

sub swampunlock {
    my $token  = _cleanToken(shift);
    my $unlink = shift // 0;
    my $ret    = 0;
    if ( exists( $locks{$token} ) ) {
        if ( !flock $locks{$token}, ( LOCK_UN | LOCK_NB ) ) {
            return 0;
        }
        if ( close( $locks{$token} ) ) {
            if ($unlink) { unlink $token; }
            delete $locks{$token};
            $ret = 1;
        }
    }
    return $ret;
}

sub releaseAllLocks {
    foreach my $token ( keys %locks ) {
        swampunlock($token);
    }
    return;
}

1;
