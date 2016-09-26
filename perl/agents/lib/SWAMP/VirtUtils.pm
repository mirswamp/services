# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#** @file VirtUtils.pm
# 
# @brief SWAMP inteface to libvirt, this package should not be directly included, instead use the DomainAgent package facade.
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 12/23/2013 16:05:32
#*
#
package SWAMP::VirtUtils;

use 5.014;
use utf8;
use strict;
use warnings;
use parent qw(Exporter);

BEGIN {
    our $VERSION = '1.00';
}
our (@EXPORT_OK);
BEGIN {
    require Exporter;
    @EXPORT_OK = qw(
        shutdownDomain
    );
}

use English '-no_match_vars';
use Carp qw(croak carp);
use Sys::Virt;
use Sys::Virt::Domain;

my $virtConnection = 1;
my $uri;
my $vmm = Sys::Virt->new( 'uri' => $uri, 'readonly' => 1 );
$vmm->register_close_callback(
## use critic
    sub {
        my $con    = shift;
        my $reason = shift;
        #warnMessage( 'register_close_callback', "shutting down: closed reason=$reason" );
        $virtConnection = 0;
    }
);

sub startDomain {
    my $domname = shift;
    if ( !$vmm->is_alive() ) {
        return -1;
    }
    my $dom = $vmm->get_domain_by_name($domname);
    $dom->create();
    return 0;
}
sub shutdownDomain {
    my $domname = shift;
    if ( !$vmm->is_alive() ) {
        return -1;
    }
    my $dom = $vmm->get_domain_by_name($domname);
    $dom->shutdown();
    return 0;
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
 

