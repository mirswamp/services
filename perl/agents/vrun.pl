#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#** @file vrun.pl
#
# @brief Test harness for VRuns
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 12/23/2013 14:32:01
#*

use 5.014;
use utf8;
use warnings;
use strict;
use FindBin qw($Bin);
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );

use Getopt::Long qw/GetOptions/;
use Pod::Usage qw/pod2usage/;
use English '-no_match_vars';
use Carp qw(carp croak);

use SWAMP::VRun qw(isViewerRunning launchViewer tearDownViewer);

my $help   = 0;
my $man    = 0;
my $viewer = 'CodeDX';
my $project;
our $VERSION = '0.00';

GetOptions(
    'help|?'    => \$help,
    'viewer=s'  => \$viewer,
    'project=s' => \$project,
    'man'       => \$man,
) or pod2usage(2);

if ($help) { pod2usage(1); }
if ($man) { pod2usage( '-verbose' => 2 ); }

if ( !isViewerRunning( 'project' => $project , 'viewer' => $viewer) ) {
    launchViewer( 'project' => $project, 'viewer' => $viewer );
    launchViewer( 'project' => $project, 'viewer' => $viewer );
    tearDownViewer( 'project' => $project, 'viewer' => $viewer );
    tearDownViewer( 'project' => $project, 'viewer' => $viewer );
}

__END__
=pod

=encoding utf8

=head1 NAME


=head1 SYNOPSIS



=head1 DESCRIPTION

=head1 OPTIONS

=over 8

=item --man

Show manual page for this script

=back

=head1 EXAMPLES

=head1 SEE ALSO

=cut


