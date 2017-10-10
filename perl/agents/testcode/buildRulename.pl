#!/usr/bin/env perl
use strict;
use warnings;
use lib "../lib";
use SWAMP::ToolLicense;

my $rulename = SWAMP::ToolLicense::build_rulename('parasoft', time(), 'swamp24680', '10.129.65.61', 1);
print 'rulename: <', $rulename, ">\n";
print "Hello World!\n";
