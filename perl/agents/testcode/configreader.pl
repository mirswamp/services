#!/usr/bin/env perl
use strict;
use warnings;
use ConfigReader::Simple;
use SWAMP::vmu_Support qw(getSwampConfig);

my $global_swamp_config = getSwampConfig();

# my $answer = $global_swamp_config->get('SWAMP-in-a-Box');
# if ($answer || '' =~ /yes/sxmi) {
if ($global_swamp_config->get('SWAMP-in-a-Box') || '' =~ m/yes/sxmi) {
	print "SWAMP-in-a-Box found: ", $global_swamp_config->get('SWAMP-in-a-Box'), "\n";
}

print "Hello World!\n";
