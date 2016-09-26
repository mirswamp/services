# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#** @file TestVirtUtils.pm
# 
# @brief SWAMP interface to Virtual Machine functions, this NULL testing implementation of DomainAgent.
# Invoke client with 'FACADE=TestVirtUtils perl client.pl'
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 12/23/2013 16:05:32
#*
#
package SWAMP::TestVirtUtils;

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
        startDomain
    );
}

use English '-no_match_vars';
use Carp qw(croak carp);

sub startDomain {
    my ($self, $domain)=@_;
    print "TestVirt::StartDomain $domain\n";
    return 0;
}
sub shutdownDomain {
    my ($self, $domain)=@_;
    print "TestVirt::shutdownDomain $domain\n";
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
 

