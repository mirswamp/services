#/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

# Test some VMTools methods

use 5.014;
use strict;
use warnings;

use Carp qw(croak);
use English '-no_match_vars';
use Test::More;

BEGIN {
    use_ok('VMTools', qw(setvmprojectdir setvmimagedir));
}

is( setvmprojectdir(q{/}),          1, 'Set project dir to valid path' );
is( setvmprojectdir(undef),         0, 'Set project dir to invalid path' );
is( setvmprojectdir($PROGRAM_NAME), 0, 'Set project dir to non-path' );
is( setvmprojectdir(q{.}),          1, 'Set project dir to valid relative path' );
done_testing();
