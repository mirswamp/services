#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

use strict;
use warnings;
use FindBin::libs;
use File::Basename;

# This will find step definitions and feature files in the directory you point
# it at below
use Test::BDD::Cucumber::Loader;

# This harness prints out nice TAP
use Test::BDD::Cucumber::Harness::TestBuilder;

my $dir = dirname($0);
my @poddirs = qw( blib script );
print "PODDIRS=@poddirs\n";
# Load a directory with Cucumber files in it. It will recursively execute any
# file matching .*_steps.pl as a Step file, and .*\.feature as a feature file.
# The features are returned in @features, and the executor is created with the
# step definitions loaded.
my ( $executor, @features ) = Test::BDD::Cucumber::Loader->load(
    $dir );

# Create a Harness to execute against. TestBuilder harness prints TAP
my $harness = Test::BDD::Cucumber::Harness::TestBuilder->new({});

# For each feature found, execute it, using the Harness to print results
$executor->execute( $_, $harness ) for @features;
Test::BDD::Cucumber::Harness::TestBuilder::done_testing();
