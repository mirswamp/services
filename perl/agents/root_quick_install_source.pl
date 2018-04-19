#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2018 Software Assurance Marketplace

use strict;
use warnings;
use File::Spec::Functions;
use File::Copy qw(copy);
use File::Basename qw(basename);

my $same = 0;
my $diff = 0;
my $execute = 0;
my $interactive = 0;
my $INTERACTIVE_DEFAULT_YES = 1;
my $INTERACTIVE_DEFAULT_NO = 2;
my $INTERACTIVE_DEFAULT_DIFF = 3;
my $config = 0;

sub usage {
	print "usage: $0 [-h -s -d -e -i]\n";
	print "      - show changed files with cmp (default)\n";
	print "  -h  - show help and exit\n";
	print "  -s  - show same files\n";
	print "  -d  - show changed files with diff\n";
	print "  -e  - execute copy of changed files\n";
	print "  -iy - interactive execute copy of changed files (default y)\n";
	print "  -in - interactive execute copy of changed files (default n)\n";
	print "  -id - interactive execute copy of changed files (default d)\n";
	print "  -c  - show changed config files\n";
	exit;
}

sub handle_file { my ($src, $dst) = @_ ;
	system("cmp -s $src $dst");
	my $result = $? >> 8;
	if ($same) {
		print "$src => $dst\n" if (! $result);
	}
	elsif ($diff) {
		if ($result) {
			print "$src => $dst\n";
			system("diff $src $dst");
		}
	}
	elsif ($execute || $interactive) {
		if ($result) {
			my $do_copy = 1;
			my $done = 0;
			while (! $done) {
				print 'copy ', "$src => $dst";
				if ($interactive) {
					print "? [Y|n|d]: " if ($interactive == $INTERACTIVE_DEFAULT_YES);
					print "? [y|N|d]: " if ($interactive == $INTERACTIVE_DEFAULT_NO);
					print "? [y|n|D]: " if ($interactive == $INTERACTIVE_DEFAULT_DIFF);
					my $answer = <STDIN>;
					chomp $answer;
					if ($answer =~ m/^$/) {
						$answer = 'y' if ($interactive == $INTERACTIVE_DEFAULT_YES);
						$answer = 'n' if ($interactive == $INTERACTIVE_DEFAULT_NO);
						$answer = 'd' if ($interactive == $INTERACTIVE_DEFAULT_DIFF);
					}
					$do_copy = ($answer =~ m/^y$/i);
					$done = ($answer !~ m/^d$/i);
					system("diff $src $dst") if ($answer =~ m/^d$/i);
				}
				else {
					print "\n";
					$done = 1;
				}
			}
			if ($do_copy) {
				copy $src, $dst;
				print 'copied ', "$src => $dst\n";
				print "\n";
			}
		}
	}
	else {
		print "$src => $dst\n" if ($result);
	}
}

sub handle_files { my ($dir_dst, $files) = @_ ;
	foreach my $file (@$files) {
		my $src = $file;
		$file =~ s/^lib\/SWAMP\///;
		my $dst = catfile($dir_dst, $file);
		handle_file($src, $dst);
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
	elsif ($arg eq '-d') {
		$diff = 1;
		$foundargs = 1;
	}
	elsif ($arg eq '-e') {
		$execute = 1;
		$foundargs = 1;
	}
	elsif ($arg eq '-iy') {
		$interactive = $INTERACTIVE_DEFAULT_YES;
		$foundargs = 1;
	}
	elsif ($arg eq '-in') {
		$interactive = $INTERACTIVE_DEFAULT_NO;
		$foundargs = 1;
	}
	elsif ($arg eq '-id') {
		$interactive = $INTERACTIVE_DEFAULT_DIFF;
		$foundargs = 1;
	}
	elsif ($arg eq '-c') {
		$config = 1;
		$foundargs = 1;
	}
}

usage() if ($haveargs && ! $foundargs);

my @binfiles = glob("vmu_*.pl");
my @launchfiles = glob("vmu_*_launcher");
my @libfiles = glob("lib/SWAMP/*.pm");
my @otherfiles = qw(vmu_swamp_monitor);

my $bin_dst = '/opt/swamp/bin';
my $lib_dst = '/opt/swamp/perl5/SWAMP';

# bin files
handle_files($bin_dst, [@binfiles, @launchfiles, @otherfiles]);
# lib files
handle_files($lib_dst, [@libfiles]);
# swamp service
handle_file('../../../deployment/swamp/scripts/swampd-common', '/etc/init.d/swamp');
# condor submit
handle_file('../../../deployment/swamp/config/vmu_swampinabox_htcondor_submit', '/opt/swamp/etc/vmu_htcondor_submit');
handle_file('../../../deployment/swamp/config/libvirt_swamp_script.awk', '/opt/swamp/libexec/condor/libvirt_swamp_script.awk');
# log4perl
handle_file('../../../deployment/swamp/config/log4perl.conf', '/opt/swamp/etc/log4perl.conf');

# config files
if ($config) {
	handle_file('../../../deployment/swamp/config/no-build.xslt', '/opt/swamp/etc/no-build.xslt');
	handle_file('../../../deployment/swamp/config/Scarf_ToolList.json', '/opt/swamp/etc/Scarf_ToolList.json');
	# handle_file('../../../deployment/swamp/config/services.conf.swampinabox', '/opt/swamp/etc/services.conf');
	handle_file('../../../deployment/swamp/config/swamp.conf.singleserver', '/opt/swamp/etc/swamp.conf');
}
print "Hello World!\n";
