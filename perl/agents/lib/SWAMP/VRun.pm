# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#** @file VRun.pm
#
# 1.25.2014
# NB: This file is probably going to be obsoleted, methods in here are implemented in AgentMonitor and accessed thru AgentClient iface.
#
# @brief This package contains the methods common to creating ViewRun VMs.
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 12/23/2013 14:27:58
#*
#
package SWAMP::VRun;

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
      isViewerRunning
      launchViewer
      tearDownViewer
    );
}

use English '-no_match_vars';
use Carp qw(croak carp);
use Log::Log4perl;
use Log::Log4perl::Level;

use SWAMP::DomainAgent qw(shutdownDomain isDefined startDomain defineDomain);

#** @function _makeViewerKey( %options )
# @brief Create a unique key for a viewer. A viewer can be uniquely 
# identified by it's viewer type and project.
#
# @param %options - HASH of options, keys `viewer` and `project` mandatory.
# @return The textual ID of a viewer.
#*
sub _makeViewerKey {
    my %options = (@_);
    return "$options{'viewer'}_$options{'project'}";
}
my %running;
sub _getViewerRunning {
    my $key = shift;
    my $ret = 0;
    if (defined($running{$key}) ) {
        $ret = $running{$key};
    }
    return $ret;
}
sub _setViewerRunning {
    my $key = shift;
    my $state = shift;
    $running{$key} = $state;
    return;
}
sub isViewerRunning {
    my %options = (@_);
    my $key = _makeViewerKey(@_);
    my $ret = _getViewerRunning($key);
    print "isViewerRunning($key) = $ret\n";
    return $ret;
}

sub launchViewer {
    my %options = (@_);
    my $key = _makeViewerKey(@_);
    if (_getViewerRunning($key) ) {
        print "launchViewer($key) ALREADY RUNNING\n";
    }
    else {
        print "launchViewer($key)\n";
        _setViewerRunning($key, 1);
        # Pseudo code. Need to define all inputs we
        # will need.
        #if (!isDefined($key)) {
        #    definedDomain($key);
        #}
        #startDomain($key);
    }
    return;
}
sub tearDownViewer {
    my %options = (@_);
    my $key = _makeViewerKey(@_);
    if (_getViewerRunning($key) ) {
        print "tearDownViewer($key)\n";
        shutdownDomain("test");
        _setViewerRunning($key, 0);
        return;
    }
    else {
        print "tearDownViewer($key) NOT running\n";
    }
    return _getViewerRunning($key);
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
 

