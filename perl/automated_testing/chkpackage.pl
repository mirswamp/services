#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#** @file chkpackage.pl
# 
# @brief Check a package against the database for consistency
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 02/04/2014 12:10:33
#*

use 5.014;
use utf8;
use warnings;
use strict;
use FindBin qw($Bin);
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );

use Getopt::Long qw/GetOptions/;
use ConfigReader::Simple;

use File::Basename qw(basename);
use Pod::Usage qw/pod2usage/;
use English '-no_match_vars';
use Carp qw(carp croak);
use Log::Log4perl qw(:easy);
use Log::Log4perl::Level;
use Test::More;

my $help = 0;
my $man  = 0;
my $pkg;
my $csv;
my $verbose=0;
my $publicOnly=0;
my $pkgfile;
our $VERSION = '0.00';

GetOptions(
    'help|?' => \$help,
    'pkg=s' => \$pkg,
    'file=s' => \$pkgfile,
    'csv=s' => \$csv,
    'public' => \$publicOnly,
    'verbose'=> \$verbose,
    'man'    => \$man,
) or pod2usage(2);
my %labelmap =(
    'package-archive' => 'package_path',
    'package-dir' => 'source_path',
    'build-sys' => 'build_system',
    'build-file' => 'build_file',
    'build-target' => 'build_target',
    'build-cmd' =>'build_cmd',
    'build-dir' => 'build_dir',
    'build-opt' => 'build_opt',
    'config-opt' => 'config_opt',
    'config-dir' => 'config_dir',
    'config-cmd' => 'config_cmd',
    'package-classpath' => 'bytecode_class_path',
    'package-auxclasspath' => 'bytecode_aux_class_path',
    'package-srcdir' => 'bytecode_source_path',
);
if ($help) { pod2usage(1); }
if ($man) { pod2usage( '-verbose' => 2 ); }
Log::Log4perl->easy_init($INFO);
my @packageFiles;
if (!$pkgfile) {
   push @packageFiles, $pkg; 
}
else {
    if (open(my $fd, '<', $pkgfile)) {
        
       while (<$fd>) {
           chomp;
           push @packageFiles,$_;
       }
       close($fd);
    }
    else {
       die "Cannot open pkgfile $pkgfile $OS_ERROR"; 
    }
}
foreach my $pkg0 (@packageFiles)  {
    $pkg = $pkg0;
    my %pkgconfig;
if (loadProperties($pkg, \%pkgconfig) > 0) {
    note("#####\nPackage: $pkgconfig{'package-short-name'}-$pkgconfig{'package-version'}\n");
    if (open(my $fd, '<', $csv)) {
        my @fields;
        my $found=0;
        while (<$fd>)  {
            chomp;
            if ($. == 1) {
                $_ =~s/"//gsxm;
                @fields = split(/\|/,$_);
            }
            my $patt=$pkgconfig{'package-archive'};
            $patt =~s/\+/./g;
            if (/$patt/sxm && isViewable($_)) { # { !/"private"/) {
                $found = 1;
                if ($verbose) {
                    print "Examining $patt [$_]\n";
                }
                pass("Checking $patt");
                my %dbRecord;
                my @line=split(/\|/,$_);
                for (my $ii=0; $ii <= $#fields;$ii++) {
                    $line[$ii] = trim($line[$ii]);
                    $line[$ii] =~s/^"//;
                    $line[$ii] =~s/"$//;
                    if ($verbose) {
                        print "<$line[$ii]> => <$fields[$ii]>\n";
                    }
                    $dbRecord{$fields[$ii]} = $line[$ii];
                }
                note("Version Updated: $dbRecord{'update_date'}");
                foreach my $key (keys %labelmap) {
                    # If the package config contains a key we don't have, that's bad.
                    if (defined($pkgconfig{$key}) && !defined($dbRecord{$labelmap{$key}})) {
                        print "$labelmap{$key} : [$pkgconfig{$key}] ne MISSING\n";
                        next;
                    }
                    if ($dbRecord{$labelmap{$key}} eq 'NULL') {
                        $dbRecord{$labelmap{$key}} = '';
                    }
                    if (!defined($pkgconfig{$key})) {
                        if ($key eq 'build-dir' || $key eq 'config-dir') {
                            $pkgconfig{$key} = q{.};
                        }
                        else {
                            $pkgconfig{$key} = q{};
                        }
                    }
                    if ($verbose) {
                        print "Comparing: $labelmap{$key} : [$pkgconfig{$key}] vs [$dbRecord{$labelmap{$key}}]\n";
                    }
                    if ($pkgconfig{$key} ne $dbRecord{$labelmap{$key}}) {
                        if ($key eq 'package-archive') {
                            if ($pkgconfig{$key} eq basename($dbRecord{$labelmap{$key}})) {
                                next;
                            }
                        }
                        # Skip what are considered equivalent values
                        if ($key eq q{build-dir} || $key eq q{config-dir}) {
                            if ($pkgconfig{$key} eq q{.} &&  $dbRecord{$labelmap{$key}} eq q{} || 
                                $pkgconfig{$key} eq q{} &&  $dbRecord{$labelmap{$key}} eq q{.}) {
                                next;
                            }
                        }
                        fail("$labelmap{$key} : Should be [$pkgconfig{$key}], not [$dbRecord{$labelmap{$key}}]");
                    }
                }
            }
        }
        close($fd);
        if (!$found) {
            fail("Cannot find an entry for $pkgconfig{'package-archive'}");
        }
    }
    else {
        die "Cannot open csv file $OS_ERROR";
    }
    print "\n";
}
else {
    fail("$pkg seems to be empty");
}
}
done_testing();

sub isViewable {
    my $line=shift;
    if ($publicOnly && $line =~ /("private"|"protected")/) {
        return 0;
    }
    return 1;
}
#** @function trim( @out )
# @brief remove leading and trailing whitespace from input
#
# @param out The data to be trimmed, a LIST or scalar
# @return trimmed version of input
#*
sub trim {
    my @out = @_;
    for (@out) {
        s/^\s+//sxm;
        s/\s+$//sxm;
    }
    return wantarray ? @out : $out[0];
}

#** @method loadProperties( $file , \%hash)
# @brief Read a files of properties (key value pairs) into a hashmap
#
# @param file - the name of the property file to read
# @param hash - the hash reference to fill with properties from $file
# @return a ConfigReader::Simple object.
# @see {@link getSwampConfig}
#*
sub loadProperties {
    my $file    = shift;
    my $hashref = shift;
    my $config;
    Log::Log4perl->get_logger(q{})->debug("loadProperties: reading $file");
    $config = ConfigReader::Simple->new($file);

    if ( defined($hashref) && ref($hashref) eq "HASH" ) {
        my $nItems = 0;
        foreach my $key ( $config->directives() ) {
            $hashref->{$key} = $config->get($key);
            $nItems++;
        }
        return $nItems;
    }
    else {
        return $config;
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


