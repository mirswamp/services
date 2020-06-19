#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

use strict;
use warnings;
use File::Spec::Functions;
use File::Copy qw(copy);
use File::Basename qw(basename);
use FindBin qw($Bin);

my $debug = 0;
my $same = 0;
my $diff = 0;
my $all = 0;
my $execute = 0;
my $web_all = 0;
my $web_html = 0;
my $web_server = 0;
my $interactive = 0;
my $INTERACTIVE_DEFAULT_YES = 1;
my $INTERACTIVE_DEFAULT_NO = 2;
my $INTERACTIVE_DEFAULT_DIFF = 3;
my $config = 0;

sub usage {
	print "usage: $0 [-h -s -d -e -w|-wh|-ws -iy|-in|-id]\n";
	print "  -h  - show help and exit\n";
	print "      - show changed files with cmp (default)\n";
	print "  -d  - show changed files with diff\n";
	print "  -s  - show same files\n";
	print "  -a  - show all files\n";
	print "  -e  - execute copy of changed files\n";
	print "  -iy - interactive execute copy of changed files (default y)\n";
	print "  -in - interactive execute copy of changed files (default n)\n";
	print "  -id - interactive execute copy of changed files (default d)\n";
	print "  -c  - show changed config files\n";
	print "  -w  - copy web html and server to /var/www\n";
	print "  -wh - copy web html to /var/www/html\n";
	print "  -ws - copy web server to /var/www/swamp-web-server\n";
	exit;
}

sub handle_file { my ($src, $dst) = @_ ;
	system("cmp -s $src $dst");
	my $result = $? >> 8;
	if ($same || $diff || $all) {
		if (! $result && ($same || $all)) {
			print "==\t" if ($all);
			print "$src => $dst\n";
		}
		elsif ($result && ($diff || $all)) {
			print "<>\t" if ($all);
			print "$src => $dst\n";
			system("diff $src $dst") if ($diff);
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
		$file = basename($file);
		my $dst = catfile($dir_dst, $file);
		if ($debug) {
			print "handling file: $file dst: $dir_dst\n";
		}
		else {
			handle_file($src, $dst);
		}
	}
}

my $haveargs = 0;
my $foundargs = 0;
foreach my $arg (@ARGV) {
	$haveargs = 1;
	$foundargs = 1;
	if ($arg eq '-h') {
		$foundargs = 0;
		last;
	}
	elsif ($arg eq '-s') {
		$same = 1;
	}
	elsif ($arg eq '-d') {
		$diff = 1;
	}
	elsif ($arg eq '-a') {
		$all = 1;
	}
	elsif ($arg eq '-e') {
		$execute = 1;
	}
	elsif ($arg eq '-w') {
		$web_all = 1;
	}
	elsif ($arg eq '-wh') {
		$web_html = 1;
	}
	elsif ($arg eq '-ws') {
		$web_server = 1;
	}
	elsif ($arg eq '-iy') {
		$interactive = $INTERACTIVE_DEFAULT_YES;
	}
	elsif ($arg eq '-in') {
		$interactive = $INTERACTIVE_DEFAULT_NO;
	}
	elsif ($arg eq '-id') {
		$interactive = $INTERACTIVE_DEFAULT_DIFF;
	}
	elsif ($arg eq '-c') {
		$config = 1;
	}
	elsif ($arg eq '-debug') {
		$debug = 1;
	}
	else {
		$foundargs = 0;
	}
}

usage() if ($haveargs && ! $foundargs);
chdir($Bin);

my @binfiles = glob("vmu_*.pl");
my @libfiles = glob("lib/SWAMP/*.pm");
my @viewercommonfiles = glob("../../../deployment/Common/*");
my @viewercodedxfiles = glob("../../../deployment/SecureDecisions/*");
my @otherfiles = qw(vmu_perl_launcher vmu_swamp_monitor);

my $bin_dst = '/opt/swamp/bin';
my $lib_dst = '/opt/swamp/perl5/SWAMP';
my $tpc_dst = '/opt/swamp/thirdparty/common';
my $tpcs_dst = '/opt/swamp/thirdparty/codedx/swamp';

# web application files
my $www_front_end_src = '../../../www-front-end';
my $www_front_end_dst = '/var/www/html';
my $swamp_web_server_src  = '../../../swamp-web-server';
my $swamp_web_server_dst  = '/var/www/swamp-web-server';
if ($web_all || $web_html) {
	print "diff $www_front_end_src $www_front_end_dst\n";
	my $command = qq{diff -qr $www_front_end_src $www_front_end_dst 2> /dev/null | grep -v 'Only in' | sed 's/^Files //' | sed 's/ and.*\$//'};
	system($command);
	if ($execute) {
		$command = qq{cp -r $www_front_end_src/* $www_front_end_dst/.};
		print "$command\n";
		system($command);
	}
}
if ($web_all || $web_server) {
	print "diff $swamp_web_server_src $swamp_web_server_dst\n";
	my $command = qq{diff -qr $swamp_web_server_src $swamp_web_server_dst 2> /dev/null | grep -v 'Only in' | sed 's/^Files //' | sed 's/ and.*\$//'};
	system($command);
	if ($execute) {
		$command = qq{cp -r $swamp_web_server_src/* $swamp_web_server_dst/.};
		print "$command\n";
		system($command);
	}
}

# bin files
handle_files($bin_dst, [@binfiles, @otherfiles]);
# lib files
handle_files($lib_dst, [@libfiles]);
# viewer files
handle_files($tpc_dst, [@viewercommonfiles]);
handle_files($tpcs_dst, [@viewercodedxfiles]);
# swamp service
handle_file('../../../deployment/swamp/scripts/swampd-common', '/etc/init.d/swamp');
# condor submit
handle_file('../../../deployment/swamp/config/vmu_swampinabox_htcondor_submit', '/opt/swamp/etc/vmu_htcondor_submit');
handle_file('../../../deployment/swamp/config/docker_swampinabox_htcondor_submit', '/opt/swamp/etc/docker_htcondor_submit');
handle_file('../../../deployment/swamp/config/libvirt_swamp_script.awk', '/opt/swamp/libexec/condor/libvirt_swamp_script.awk');
# log4perl
handle_file('../../../deployment/swamp/config/log4perl.conf', '/opt/swamp/etc/log4perl.conf');
# sudo_config
handle_file('../../../deployment/swampinabox/singleserver/config_templates/sudoers/10_swamp_sudo_config', '/etc/sudoers.d/10_swamp_sudo_config');

# config files
if ($config || $all) {
	# handle_file('../../../deployment/swampinabox/singleserver/config_templates/config.d/swampinabox_10_main.conf', '/etc/condor/config.d/swampinabox_10_main.conf');
	# handle_file('../../../deployment/swampinabox/singleserver/config_templates/config.d/swampinabox_90_concurrency_limits.conf', '/etc/condor/config.d/swampinabox_90_concurrency_limits.conf');

	handle_file('../../../deployment/swampinabox/singleserver/config_templates/htcondor/swampinabox_10_main.conf', '/opt/swamp/htcondor/local/config/swampinabox_10_main.conf');
	handle_file('../../../deployment/swampinabox/singleserver/config_templates/htcondor/swampinabox_90_concurrency_limits.conf', '/opt/swamp/htcondor/local/config/swampinabox_90_concurrency_limits.conf');

	handle_file('../../../deployment/swamp/config/no-build.xslt', '/opt/swamp/etc/no-build.xslt');
	handle_file('../../../deployment/swamp/config/Scarf_ToolList.json', '/opt/swamp/etc/Scarf_ToolList.json');
	# handle_file('../../../deployment/swamp/config/services.conf.swampinabox', '/opt/swamp/etc/services.conf');
	handle_file('../../../deployment/swamp/config/swamp.conf.singleserver', '/opt/swamp/etc/swamp.conf');
}
print "Hello World!\n";
