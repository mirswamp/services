#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#** @file testcodedx.pl
# 
# @brief 
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 01/26/2014 16:08:41
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
use Log::Log4perl qw(:easy);
use Log::Log4perl::Level;
use SWAMP::CodeDX qw(listprojects createproject deleteproject uploadanalysisrun);
#curl -ks -H "API-Key: 1630F0BA-CAE5-11E3-9F83-53FD4FF1555B"  -X GET  https://128.104.7.47/proxy-1631263E-CAE5-11E3-9F83-53FD4FF1555B/api/project
my $help = 0;
my $man  = 0;
our $VERSION = '0.00';
my $host = '128.104.7.47';
my $project='proxy-1631263E-CAE5-11E3-9F83-53FD4FF1555B'; # A SWAMP project
my $key = '1630F0BA-CAE5-11E3-9F83-53FD4FF1555B';
my $dolist=0;
my $doadd=0;
my $package;
my $rmpackage;
my @files;
my $verbose = 0;
GetOptions(
    'help|?' => \$help,
    'man'    => \$man,
    'proj=s' => \$project,
    'key=s' => \$key,
    'host=s' => \$host,
    'list' => \$dolist,
    'add' => \$doadd,
    'verbose' => \$verbose,
    'package=s' => \$package,
    'rm=s' => \$rmpackage,
    'files=s' => \@files,
) or pod2usage(2);

if ($help) { pod2usage(1); }
if ($man) { pod2usage( '-verbose' => 2 ); }
Log::Log4perl->easy_init($TRACE);
if ($dolist) {
    my %proj = listprojects($host, $key, $project);
    foreach my $id (keys %proj) {
        print "<$id><$proj{$id}>\n";
    }
}
if ($doadd && defined($package) ) {
    my $resp = createproject($host, $key, $project, $package);
    print "After create <$package> = $resp\n";
    my %proj = listprojects($host, $key, $project);
    foreach my $id (keys %proj) {
        print "<$id><$proj{$id}>\n";
    }
}
if (defined($rmpackage) ) {
    my $resp = deleteproject($host, $key, $project, $rmpackage);
    if ($resp ) {
        say "Success!";
    }
    else {

        say "Fail!";
    }
    if ($verbose) {
        my %proj = listprojects($host, $key, $project);
        foreach my $id (keys %proj) {
            print "<$id><$proj{$id}>\n";
        }
    }
}
if (@files) {
    my $resp = uploadanalysisrun($host, $key, $project, $package,\@files );
    if ($resp ) {
        say "Success!";
    }
    else {

        say "Fail!";
    }
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


