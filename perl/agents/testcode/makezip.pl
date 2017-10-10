#!/usr/bin/env perl
use strict;
use warnings;
use lib '../lib';
use SWAMP::SWAMPUtils;

my $oldname = '/home/tbricker/Downloads/python/swamp_python_151015/mock-1.3.0/mock-1.3.0-py2.py3-none-any.whl';
my $newname;
if (-r $oldname) {
	$newname = SWAMP::SWAMPUtils::makezip($oldname);
}
print "Hello World!\n";
