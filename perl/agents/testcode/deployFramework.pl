#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "../lib";
use SWAMP::AssessmentTools;

my $file = '/home/tbricker/morgridge/projects/deployment/UWTeam/c-assess-1.0.8.tar.gz';
$file = $ARGV[0] if (defined($ARGV[0]));
my $platform = 'noarch';
$platform = $ARGV[1] if (defined($ARGV[1]));
$platform .= '/';

print "Copying $file platform: $platform to input\n";

SWAMP::AssessmentTools::deployTarByPlatform($file, 1, 'input', $platform);
print "Hello World!\n";