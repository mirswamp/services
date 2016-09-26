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
 
Given qr/a usable (\S+) package/, func ($c) { 
    use_ok( $1 );
#    VMTools::init("test","test", 1);
    VMTools::enableTestMode ();
};
When qr/I've called getVMDir with (.+)/, func ($c) {
    my $arg=$1;
    if ($arg eq 'nothing') {
        $arg = undef;
    }
    my $result=VMTools::getVMDir($arg); 
    print "Result: [$result]\n" if $ENV{VERBOSE};
    $c->stash->{'scenario'}->{VMTools}=$result;
};
When qr/I've called listVMs$/, func($c) {
    my ($results) = VMTools::listVMs();
    $c->stash->{'scenario'}->{VMTools}=$results;
};
When qr/I've called (.+) with (.+)$/, func($c) {
    my $results;
    if ($1 eq 'isMasterImage') {
        $results = VMTools::isMasterImage($2);
    }
    elsif ($1 eq 'vmExists') {
        $results = VMTools::vmExists($2);
    }
    $c->stash->{'scenario'}->{VMTools}=$results;
};
When qr/I call system with "(.+)"/, func($c) {
    my ($results, $status) = VMTools::systemcall($1);
    chomp $results;
    if (!$status) {
        $c->stash->{'scenario'}->{system}=$results;
    }
    else {
        $c->stash->{'scenario'}->{system}="$1 failed : $results";
    }
};
Then qr/the output contains "(.+)"/, func($c) {
    like ($c->stash->{'scenario'}->{system}, $1);
};
Then qr/the output is "(.+)"/, func($c) {
    is ($c->stash->{'scenario'}->{system}, $1);
};
Then qr/the return is (.+)/, func ($c) {
    print "Want Result: [$1]\n" if $ENV{VERBOSE};
   is( $c->stash->{'scenario'}->{VMTools}, $1 );
};
