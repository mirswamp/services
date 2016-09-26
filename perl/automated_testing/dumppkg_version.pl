#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#** @file dumppkg_version.pl
# 
# @brief 
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 03/17/2014 08:54:41
#*

use 5.014;
use utf8;
use warnings;
use strict;
use FindBin qw($Bin);
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );

use DBI;
use Getopt::Long qw/GetOptions/;
use Pod::Usage qw/pod2usage/;
use English '-no_match_vars';
use Carp qw(carp croak);

my $help = 0;
my $man  = 0;
our $VERSION = '0.00';

GetOptions(
    'help|?' => \$help,
    'man'    => \$man,
) or pod2usage(2);

if ($help) { pod2usage(1); }
if ($man) { pod2usage( '-verbose' => 2 ); }
## mysql user database name
my $db = "package_store";
## mysql database user name
my $user = "web";

## mysql database password
my $pass = 'MNH$f4xP7vWQ$64d';

## user hostname : This should be "localhost" but it can be diffrent too
my $host = "swa-csadata-pd-01.mirsam.org";

## SQL query
my $query = "show tables";
$query = qq{describe package_version;};

my $dbh = DBI->connect( "DBI:mysql:$db:$host", $user, $pass );
my $sqlQuery = $dbh->prepare($query)
  or die "Can't prepare $query: $dbh->errstr\n";

my $rv = $sqlQuery->execute
  or die "can't execute the query: $sqlQuery->errstr";

my $row0;
while ( my @row = $sqlQuery->fetchrow_array() ) {
    $row0 .= qq{"$row[0]"|};
}
print "$row0\n";

my $rc = $sqlQuery->finish;

$query = qq{SELECT * FROM package_version;};

$dbh = DBI->connect( "DBI:mysql:$db:$host", $user, $pass );
$sqlQuery = $dbh->prepare($query)
  or die "Can't prepare $query: $dbh->errstr\n";

$rv = $sqlQuery->execute
  or die "can't execute the query: $sqlQuery->errstr";

while ( my @row = $sqlQuery->fetchrow_array() ) {
    foreach my $cell (@row) {
        #my $tables = "@row";
        if (defined($cell)) {
            print qq{"$cell"|};
        }
        else {
            print qq{"NULL"|};
        }
    }
    print "\n";
}

$rc = $sqlQuery->finish;
exit(0);

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


