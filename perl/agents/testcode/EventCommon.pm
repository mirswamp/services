# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2019 Software Assurance Marketplace

#** @file EventCommon.pm
# 
# @brief 
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 05/29/2014 08:50:07
#*
#
package EventCommon;

use 5.010;
use utf8;
use strict;
use warnings;
use parent qw(Exporter);

BEGIN {
    $EventCommon::VERSION = '0.84';
}
our (@EXPORT_OK);
BEGIN {
    require Exporter;
    @EXPORT_OK = qw(fakeInsert
    realInsert
    timeToSecs);
}

use English '-no_match_vars';
use Carp qw(croak carp);
use Time::Local qw(timelocal timegm);
use SWAMP::Client::GatorClient qw(insertExecEvent);

sub fakeInsert {
    my $ref = shift;
    say "$ref->{'execrecorduuid'},$ref->{'eventtime'},$ref->{'eventname'},$ref->{'eventpayload'}";
}
sub realInsert {
    my $ref = shift;
    insertExecEvent( $ref );
}
sub timeToSecs {
    my $date=shift;
    my $time = shift;
    my ($yy,$mm,$dd) = split(/\//sxm,$date);
    my ($hh,$min,$sec) = split(/:/sxm,$time);
    return timegm($sec, $min, $hh, $dd, $mm - 1, $yy);
}

1;

__END__
=pod

=encoding utf8

=head1 NAME

=head1 SYNOPSIS

Write the Manual page for this package

=head1 DESCRIPTION

=head1 OPTIONS

=over 8

=item 


=back

=head1 EXAMPLES

=head1 SEE ALSO

=cut
 

