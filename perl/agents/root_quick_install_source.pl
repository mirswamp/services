#!/usr/bin/env perl
use strict;
use warnings;
use File::Spec::Functions;
use File::Copy qw(copy);
use File::Basename qw(basename);

my $same = 0;
my $cmp = 0;
my $diff = 0;

sub usage {
	print "usage: $0 [-h -s -c -d]\n";
	print "  -h - show help and exit\n";
	print "  -s - show same files\n";
	print "  -c - show changed files with cmp\n";
	print "  -d - show changed files with diff\n";
	exit;
}

sub handle_files { my ($dir_dst, $files) = @_ ;
	foreach my $file (@$files) {
		my $src = $file;
		$file =~ s/^lib\/SWAMP\///;
		my $dst = catfile($dir_dst, $file);
		system("cmp -s $src $dst");
		my $result = $? >> 8;
		if ($same) {
			print "$src => $dst\n" if (! $result);
		}
		elsif ($cmp) {
			print "$src => $dst\n" if ($result);
		}
		elsif ($diff) {
			if ($result) {
				print "$src => $dst\n";
				system("diff $src $dst");
			}
		}
		else {
			print 'copy ', "$src => $dst\n" if ($result);
			copy $src, $dst;
		}
	}
}

my $haveargs = 0;
my $foundargs = 0;
foreach my $arg (@ARGV) {
	$haveargs = 1;
	if ($arg eq '-h') {
		$foundargs = 0;
		last;
	}
	elsif ($arg eq '-s') {
		$same = 1;
		$foundargs = 1;
	}
	elsif ($arg eq '-c') {
		$cmp = 1;
		$foundargs = 1;
	}
	elsif ($arg eq '-d') {
		$diff = 1;
		$foundargs = 1;
	}
}

usage() if ($haveargs && ! $foundargs);

my @binfiles = glob("vmu_*.pl");
my @launchfiles = glob("vmu_*_launcher");
# my @libfiles = map {s/lib\/SWAMP\///r} glob("lib/SWAMP/*.pm");
my @libfiles = glob("lib/SWAMP/*.pm");

my $bin_dst = '/opt/swamp/bin';
my $lib_dst = '/opt/swamp/perl5/SWAMP';

handle_files($bin_dst, [@binfiles, @launchfiles]);
handle_files($lib_dst, [@libfiles]);
print "Hello World!\n";
