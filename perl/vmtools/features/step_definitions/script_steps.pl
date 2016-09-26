#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

use warnings;
use strict;

use Test::More;
use Test::BDD::Cucumber::StepFile;
use Method::Signatures;
 
#Scenario:
#    Given a script named vm_output
#    And a script named vm_cleanup
##    When I've asked for the version
#    Then the result is "vm_output:"
sub getInstallDir() {
    my $installdir='';
    if (-r 'blib/script/vm_output') {
        $installdir='blib/script';
    }
    elsif (-r 'vm_output') {
        $installdir='.';
    }
}
sub makeCmd($) {
    my $base=shift;
    my $cmd=undef;
    my $pwd=`pwd`;
    my $ls=`ls blib`;
    if (-r "blib/script/${base}") {
        $cmd="perl -I blib/lib blib/script/$base";
    }
    elsif (-r "$base") {
        $cmd="perl -I lib ./$base";
    }
    else {
        die "Cannot find $base anywhere! (I am $pwd) $ls";
    }
    return $cmd;
}

Given qr/a valid install/, func ($c) { 
    my $installdir=getInstallDir();
    ok(-r "$installdir/vm_output", 'Install OK');
};
Given qr/a script named (\S+)/, func ($c) {
    my $installdir=getInstallDir();
    ok(-r "$installdir/$1",  "Have found \"$1\"");
};

When qr/I've run (\S+) (.+)/, func ($c) {
    my $results='';
    my $args=$2;
    if ($2 eq "with no args") {
        $args="";
    }
    my $cmd=makeCmd($1);

    $results=`$cmd $args 2>&1`;
    ok(length($results));
    $c->stash->{'scenario'}->{run} = $results;
};
When qr/I've asked "(.*)"/, func($c) {
    my $cmd=makeCmd($1);
    print "RES:$cmd\n";
    my $results=`$cmd 2>&1`;
    ok(length($results));
    $c->stash->{'scenario'}->{asked} = $results;
};
#Then qr/the result is "(.*)"/, func($c) {
#    like( $c->stash->{'
#};
Then qr/the output looks like "(.+)"/, func ($c) {
   like( $c->stash->{'scenario'}->{'run'}, qr/$1/ );
};
Then qr/the output is the following/, func ($c) {
   my $res = $c->data();
   is( $c->stash->{'scenario'}->{'run'}, $res );
};
