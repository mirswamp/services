#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

use strict;
use warnings;
use File::Copy;

use Getopt::Long; 

my $file=shift or die "No filename provided";
my $tmpfile="tmpfile.$$";

sub increaseVersion($) {
    my $ver=shift;
    $ver += 0;
    $ver = 1+int($ver*100);
    my $dec = $ver % 100;
    $dec = "0$dec" if ($dec < 10);
    return ($ver - $dec)/100 . "." . $dec;
}

open(FILE, $file) or die "Cannot open $file $!\n";
if (!open(OUT, ">$tmpfile")) {
    close FILE;
    die "Cannot create tmpfile $!\n";
}

while (<FILE>) {
    if (/VERSION\s+=/) {
        my ($first, $second)=split("=", $_);
        $first =~ s/\s+$//;
        $second =~s/["';]//g;
        $_ = $first . " = '" . increaseVersion($second) . "';\n";
        print "VERSION definition $_\n";
    }
    print OUT $_;
}
close FILE;
close OUT;
move( $tmpfile,$file);
