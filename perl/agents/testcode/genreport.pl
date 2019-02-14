#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2019 Software Assurance Marketplace

#** @file genreport.pl
#
# @brief Generate an HTML report from a failed arun tarball.
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 04/25/2014 13:22:53
#*

use 5.014;
use utf8;
use warnings;
use strict;
use FindBin qw($Bin);
use Time::HiRes qw(gettimeofday tv_interval);
use File::Basename qw(basename dirname);
use Getopt::Long qw/GetOptions/;
use Pod::Usage qw/pod2usage/;
use English '-no_match_vars';
use Carp qw(carp croak);
use Archive::Tar;
use Data::Dumper;

use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/../lib" );
use SWAMP::vmu_FrameworkUtils qw(generatereport savereport);

my $help = 0;
my $man  = 0;
our $VERSION = '0.00';
my $tarfile;
my $native  = 0;
my $verbose = 0;
my $reportname = q{errorreport.html};
my $autoname = 0;

GetOptions(
    'autoname'  => \$autoname,
    'verbose'   => \$verbose,
    'native'    => \$native,
    'tarball=s' => \$tarfile,
    'report=s' => \$reportname,
    'help|?'    => \$help,
    'man'       => \$man,
) or pod2usage(2);

if ($help) { pod2usage(1); }
if ($man) { pod2usage( '-verbose' => 2 ); }
pod2usage( '-verbose' => 2) if (!$tarfile);

use constant {
    'HTML' => 1,
    'TEXT' => 2,
};
if ($autoname) {
    # Build report name from tarball path
    my $dirname = dirname($tarfile);
    $dirname =~s/^.*A-Results\///;    
    $dirname =~s/\//_/gsxm;
    $reportname = qq{$dirname.html};
}


my $report = generatereport($tarfile, 'output');    # Hashmap containing error report

savereport( $report, $reportname, q{.} );

__END__
=pod

=encoding utf8

=head1 NAME

genreport - Command line native viewer for failed assessment result.

=head1 SYNOPSIS

genreport --tar tarball [--report errorfile.html]

=head1 DESCRIPTION

genreport will examine a failed SWAMP assessment run results file (e.g. results.tar.gz) and emit an
error report in the same manner as the native viewer.

=head1 OPTIONS

=over 8

=item --man

Show this manual page 

=item --help

Show brief help.

=item --tar I<filename>

Specify the results to be analyzed.

=item --report I<errorreport.html>

The name of the error report to output. If not specified F<errorreport.html> is used.

=back

=head1 EXAMPLES

C<genreport --tar ~/Downloads/results.tar.gz && open errorreport.html>

=head1 AUTHOR

Dave Boulineau L<dboulineau@continuousassurance.org>

=cut

