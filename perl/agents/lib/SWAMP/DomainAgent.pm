# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#** @file DomainAgent.pm
# 
# @brief SWAMP interface to virtual machines. This abstraction layer is the interface that is used by clients
# wishing to manipulate VMs (Domains).
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 12/29/2013 13:05:32
#*
#
package SWAMP::DomainAgent;

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
        defineDomain
        isDefined
        shutdownDomain
        startDomain
    );
}

use English '-no_match_vars';
use Carp qw(croak carp);
my $package= $ENV{'FACADE'} // 'VirtUtils';
my $packagefile="SWAMP/$package.pm";
$package = "SWAMP::$package";
require $packagefile;

sub startDomain {
    return $package->startDomain(@_);
}
sub shutdownDomain {
    return $package->shutdownDomain(@_);
}

sub isDefined {
    return 0;
}
sub defineDomain {
    return;
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
 

