# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#** @file Floodlight.pm
#
# @brief Floodlight API interface
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 09/08/2014 09:49:49
#*
#
package SWAMP::Floodlight;

use 5.014;
use utf8;
use strict;
use warnings;
use parent qw(Exporter);
use Carp qw(carp croak);
use JSON qw(from_json);
use Log::Log4perl;

use SWAMP::SWAMPUtils qw(systemcall);

BEGIN {
    our $VERSION = '0.84';
}
our (@EXPORT_OK);

BEGIN {
    require Exporter;
    @EXPORT_OK = qw(deleteFlows
    );
}

use English '-no_match_vars';
use Carp qw(croak carp);

sub deleteFlows {
    my $domain     = shift;
    my $floodlight = shift;
    my $log        = Log::Log4perl->get_logger(q{});
    my $route      = "$floodlight/wm/staticflowentrypusher";
    my $ret        = 1;                                        # Assume all is well.
    my ( $output, $status ) = systemcall(qq{curl -s -X GET $route/list/all/json});
    if ($status) {
        $log->error("Unable to acquire list of floodlight flows: $status [$output]");
        $ret = 0;
    }
    else {
        my $ref = from_json($output);

        foreach my $switchid ( keys $ref ) {

            # Keys of the switchid array are flow names
            foreach my $flowname ( keys $ref->{$switchid} ) {

                # Delete rules matching this domain (VM) name
                if ( $flowname =~ /^${domain}.vm.cosalab.org/sxm ) {
                    ( $output, $status ) =
                      systemcall(qq{curl -s -X DELETE -d '{"name":"$flowname"}'  $route/json});
                    if ($status) {
                        $log->error("Unable to remove flow: [$flowname] $status <$output>");
                        $ret = 0;
                    }
                }
            }
        }
    }
    return $ret;
}

1;

__END__
=pod

=encoding utf8

=head1 NAME

SWAMP::Floodlight - Interface to floodlight controller

=head1 SYNOPSIS

 use SWAMP::Floodlight qw(deleteFlows);

 if (deleteFlows($myvmname, 'http://swa-flood-dt-01.cosalab.org:8080')) {
    say "All workflows associated with $myvmname have been removed";
 }

=head1 DESCRIPTION

The SWAMP::Floodlight module implements stateless methods for manipulating the floodlight 
controller. Currently the only method implemented is deleteFlows which takes are parameters the 
name of a virtual machine and the name of the floodlight controller.

=head1 COPYRIGHT

    Copyright (c) 2014 Software Assurance Marketplace, Morgridge Institute for Research

    This library is free software; you can redistribute it and/or modify it
    under the same terms as Perl itself.

=cut
