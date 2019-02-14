#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2019 Software Assurance Marketplace

#** @file testframeworkutil.pl
#
# @brief
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 04/30/2014 12:40:26
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
use Data::Dumper;
use SWAMP::FrameworkUtils qw(ReadStatusOut);

my $help = 0;
my $man  = 0;
our $VERSION = '0.00';

GetOptions(
    'help|?' => \$help,
    'man'    => \$man,
) or pod2usage(2);

if ($help) { pod2usage(1); }
if ($man) { pod2usage( '-verbose' => 2 ); }
my $s = ReadStatusOut(shift);

if ( !@{ $s->{'#errors'} } && !@{ $s->{'#warnings'} } ) {
    if ( exists $s->{all} && $s->{all}{status} eq 'PASS' ) {
        #say "success";
    }
    else {
        my $errCnt   = scalar @{ $s->{'#errors'} };
        my $warnCnt  = scalar @{ $s->{'#warnings'} };
        my $filename = $s->{'#filename'};

        print "$filename   (errors: $errCnt, warnings: $warnCnt)\n";
        print "Errors:\n\t",   join( "\n\t", @{ $s->{'#errors'} } ),   "\n" if $errCnt;
        print "Warnings:\n\t", join( "\n\t", @{ $s->{'#warnings'} } ), "\n" if $warnCnt;
        foreach my $t ( @{ $s->{'#order'} } ) {
            my $status   = $t->{status};
            my $taskName = $t->{task};
            print "$status $taskName\n";
        }
        #say "no success";
    }
}
else {
#    say Dumper($s);
    say "bad status.out file";
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


