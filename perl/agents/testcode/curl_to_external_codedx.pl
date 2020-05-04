#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

use strict;
use warnings;
use FindBin qw($Bin);
use Log::Log4perl qw(:easy);
use File::Spec;
use File::Copy;
use File::Path qw(make_path remove_tree);
use Data::UUID;
use Cwd;
use DBI;
use lib "$Bin/../lib";
use SWAMP::CodeDX;
use SWAMP::vmu_Support qw(
	loadProperties
	getVMIPAddress
	makezip
);
use SWAMP::CodeDX qw(
	uploadanalysisrun
);

my $apikey = Data::UUID->new()->create_str();
my $project = 'codedx';
my $host = 'codedx.mirsam.org';
my $execution_record_uuid;

sub read_bogfile { my ($bogfile) = @_ ;
	my $bog = {};
	if (! loadProperties($bogfile, $bog)) {
		print "Error - unable to load: $bogfile\n";
		usage();
	}
	return $bog;
}

sub showURL {
	if (defined($host) || getVMIP()) {
		print "https://$host/$project\n";
	}
}

sub getBOG {
	my $out_tarfile = File::Spec->catfile('/swamp/working/results', $execution_record_uuid, 'outputdisk.tar.gz');
	if (! -f $out_tarfile) {
		print "Warning - $out_tarfile not found - no bog\n";
		return;
	}
	my $bogfile = "output/${execution_record_uuid}.bog";
	system("tar xf $out_tarfile $bogfile");
	my $bog = read_bogfile($bogfile);
	return $bog;
}

sub curlNewResult {
	my $bog = getBOG();
	my $packageName = $bog->{'packagename'};
	my $packagePath = $bog->{'packagepath'};
	if (! $packageName || ! $packagePath) {
		print "Error - no package\n";
		return;
	}
	my $zippackage = makezip($packagePath);
	my $parsed_results = File::Spec->catfile('/swamp/working/results', $execution_record_uuid, 'parsed_results.xml');
	my $result_files = [$zippackage, $parsed_results];
	
	# curl new result to codedx
	print "Curling assessment result: ", (join ', ', @$result_files), " for: $packageName\n";
	my $result = uploadanalysisrun($host, $apikey, $project, $packageName, $result_files);
	print "uploadanalysisrun result: $result\n";
}

# menu items

sub show_codedx_url {
	showURL();
}

sub usage {
	print "usage: $0 [<execution_record_uuid>] [<codedx version>]\n";
	exit 1;
}

Log::Log4perl::easy_init($TRACE);

foreach my $arg (@ARGV) {
	print "arg: <$arg>\n";
	if ($arg =~ m/[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}/) {
		$execution_record_uuid = $arg;
		print "Execution record uuid: $execution_record_uuid\n";
	}
}

while (1) {
	print "u)rl c)url h)elp q)uit Enter: ";
	my $command = <STDIN>;
	chomp $command;
	my $prefix = $command =~ m/^\+/;
	if ($command eq 'u') {
		show_codedx_url();
	}
	elsif ($command eq 'c') {
		if (! defined($execution_record_uuid)) {
			print "Enter execution record uuid: ";
			$execution_record_uuid = <STDIN>;
			chomp $execution_record_uuid;
		}
		curlNewResult();
		$execution_record_uuid = undef;
	}
	elsif ($command eq 'h') {
	}
	elsif (! $command || $command eq 'q') {
		last;
	}
	else {
		print "command <$command> not found\n";
	}
	print "\n";
}

print "Hello World!\n";
