#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#** @file master.pl
# 
# @brief  Simple script to create a random number of files containing random
# data in a folder called 'disktest'
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 07/22/2014 16:33:42
# for Research
#*

#use 5.014;
use utf8;
use warnings;
use strict;
use FindBin qw($Bin);
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );

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
srand(time());

my $nfiles=5+int(rand(50));
print "Creating $nfiles files\n";
foreach (0..$nfiles) {
	my $size=1+int(rand(1000));
	qx{dd if=/dev/urandom of=disktest/random.$_ bs=256 count=$size > /dev/null 2>&1};
}
