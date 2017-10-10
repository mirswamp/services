#!/usr/bin/env perl
use strict;
use warnings;
use lib "../lib";
use SWAMP::SWAMPUtils;

my $hash = {
	'key1'	=> '  value',
	'key2'	=> "line one \n line two",
	'key3'	=> "key3 - line one \n line two\nline three",
	'key4'	=> "this/is/a/path",
};

foreach my $key (keys %$hash) {
	my $propstring = SWAMP::SWAMPUtils::_getPropString($key, $hash->{$key});
	print "key: <$key>\n";
	print "value <", $hash->{$key}, ">\n";
	print "propstring: <", $propstring, ">\n";
	print "\n";
}
print "Hello World!\n";
