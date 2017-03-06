#!/usr/bin/env perl
use strict;
use warnings;
use File::Copy qw(copy);

my @binfiles = glob("vmu_*.pl");
my @launchfiles = glob("vmu_*_launcher");
my @libfiles = glob("lib/SWAMP/*.pm");

my $bin_dst = '/opt/swamp/bin';
my $lib_dst = '/opt/swamp/perl5/SWAMP';

foreach my $bin_file (@binfiles, @launchfiles) {
	print "copy $bin_file, $bin_dst\n";
	copy $bin_file, $bin_dst;
}

foreach my $lib_file (@libfiles) {
	print "copy $lib_file, $lib_dst\n";
	copy $lib_file, $lib_dst;
}
print "Hello World!\n";
