#!/opt/perl5/perls/perl-5.18.1/bin/perl

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
	getSwampConfig
	loadProperties
	makezip
	getVMIPAddress
);
use SWAMP::vmu_ViewerSupport qw(
	copyvruninputs
	createrunscript
);
use SWAMP::CodeDX qw(
	uploadanalysisrun
);

# default vm and viewer
my $configfile = '/opt/swamp/etc/swamp.conf';
my $global_swamp_config = getSwampConfig($configfile);
my $codedx_version = '2.8.3';
my $vmname = 'codedx_' . $codedx_version;
my $codedx_viewername;

my $apikey = Data::UUID->new()->create_str();
my $project = 'proxy-' . $apikey;
my $vmip;
my $execution_record_uuid;

sub read_bogfile { my ($bogfile) = @_ ;
	my $bog = {};
	if (! loadProperties($bogfile, $bog)) {
		print "Error - unable to load: $bogfile\n";
		usage();
	}
	return $bog;
}

sub vmExists { my ($vmname) = @_ ;
	my $result = `virsh list --all | grep $vmname`;
	return 'running' if ($result =~ m/running/);
	return 'not running'  if ($result);
	return undef;
}

sub removeVM { my ($vmname, $state) = @_ ;
	my $result;
	if ($state eq 'running') {
		$result = `virsh destroy $vmname`;
	}
	if (! $result || $result =~ m/destroyed/) {
		$result = `virsh undefine $vmname`;
	}
	return 1 if ($result && $result =~ m/undefined/);
	return 0;
}

sub stopVM {
	# remove codedx vm if extant
	my $state = vmExists($vmname);
	if ($state) {
		print "Attempting to remove: $vmname\n";
		if (! removeVM($vmname, $state)) {
			print "Error - unable to remove: $vmname\n";
			usage();
		}
	}
	$vmip = undef;
}

sub get_new_database { my ($path) = @_ ;
	my $retval = 1;

	# obtain file list
	my @files = `find -L . -maxdepth 1 -type f`;
	chomp @files;
	my $codedxsql = grep(/codedx.sql.gz$/, @files);
	my $viewerdb = grep(/viewerdb.tar.gz$/, @files);

	# if path is empty then delete codedx.sql.gz and viewerdb.tar.gz
	if (! $path) {
		if ($viewerdb) {
			print "Removing viewerdb.tar.gz\n";
			unlink 'viewerdb.tar.gz';
		}
		if ($codedxsql) {
			print "Removing codedx.sql.gz\n";
			unlink 'codedx.sql.gz';
		}
	}
	# error if path is not readable
	elsif (! -r $path) {
		print "Path: $path is not readable\n";
		$retval = 0;
	}
	# codedx.sql.gz specified - remove viewerdb.tar.gz if extant
	elsif ($path =~ m/codedx.sql.gz$/) {
		if ($viewerdb) {
			print "Removing viewerdb.tar.gz\n";
			unlink 'viewerdb.tar.gz';
		}
		print "Copying $path\n";
		File::Copy::copy($path, '.');
	}
	# viewerdb.tar.gz specified - remove codedx.sql.gz if extant
	elsif ($path =~ m/viewerdb.tar.gz$/) {
		if ($codedxsql) {
			print "Removing codedx.sql.gz\n";
			unlink 'codedx.sql.gz';
		}
		print "Copying $path\n";
		File::Copy::copy($path, '.');
	}
	# error if path is not database file
	else {
		print "Path: $path is not a database file\n";
		$retval = 0;
	}
	return $retval;
}

my $codedx_input_dir = './codedx_input';
sub setupInput { my ($reuse_input_dir) = @_ ;
	if ($reuse_input_dir && -d $codedx_input_dir) {
		print "Reusing input directory: $codedx_input_dir\n";
		return 1;
	}
	if (-d $codedx_input_dir) {
		print "Deleting input directory: $codedx_input_dir\n";
		File::Path::remove_tree($codedx_input_dir);
	}
	print "Creating input directory: $codedx_input_dir\n";
	File::Path::make_path($codedx_input_dir);
	my $bog = {
		'viewer'	=> 'CodeDX',
		'urluuid'	=> $project,
		'apikey'	=> $apikey,
		'db_path'	=> '',
	};

	copyvruninputs($bog, $codedx_input_dir);

	# replace codedx.war
	my $warfile = File::Spec->catfile($Bin, '..', '..', '..', '..', 'proprietary', 'SecureDecisions', "codedx.${codedx_version}.war");
	print "Copying $warfile to $codedx_input_dir as codedx.war\n";
	File::Copy::copy($warfile, File::Spec->catfile($codedx_input_dir, 'codedx.war'));

	# replace empty-codedx-<codedx_version>.sql
	my $emptydb = File::Spec->catfile($Bin, '..', '..', '..', '..', 'deployment', 'SecureDecisions', "emptydb-codedx.${codedx_version}.sql");
	print "Copying $emptydb to $codedx_input_dir as emptydb-codedx.sql\n";
	File::Copy::copy($emptydb, File::Spec->catfile($codedx_input_dir, 'emptydb-codedx.sql'));

	createrunscript($bog, $codedx_input_dir);

	return 1;
}

sub startVM {
	# start codedx vm
	print "Starting vm: $vmname with platform: $codedx_viewername\n";
	my $script = File::Spec->catfile($Bin, '..', '..', 'vmtools', 'start_vm');
	my $result = `$script $codedx_input_dir --name $vmname $codedx_viewername`;
}

sub getVMIP {
	# obtain vmip of codedx vm
	$vmip = getVMIPAddress($vmname);
	if (! $vmip) {
		print "Error - unable to get ip address for: $vmname\n";
		return 0;
	}
	return 1;
}

sub showURL {
	if (defined($vmip) || getVMIP()) {
		print "https://$vmip/$project\n";
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
	my $result = uploadanalysisrun($vmip, $apikey, $project, $packageName, $result_files);
	print "uploadanalysisrun result: $result\n";
}

# menu items

# shutdown, input, start
sub start_codedx { my ($reuse_input_dir) = @_ ;
	stopVM();
	if (setupInput($reuse_input_dir)) {
		startVM();
	}
}

sub show_codedx_status {
	my $state = vmExists($vmname);
	if ($state) {
		print "$vmname: $state\n";
	}
	else {
		print "$vmname: state unknown\n";
	}
}

sub show_codedx_url {
	my $state = vmExists($vmname);
	if ($state && ($state eq 'running')) {
		showURL();
		return;
	}
	show_codedx_status();
}

sub guestfish_display_file { my ($file, $preserve) = @_ ;
	my $result;
	if ($preserve) {
		$result = `virt-copy-out -d $vmname -m /dev/sdc:/mnt/out -m /dev/sdb:/mnt/in $file .`;
	}
	else {
		$result = `guestfish --ro -d $vmname -m /dev/sdc:/mnt/out -m /dev/sdb:/mnt/in -i cat $file 2>&1`;
	}
	print "$result\n";
}

sub curl_result {
	my $state = vmExists($vmname);
	if ($state && ($state eq 'running')) {
		if (defined($vmip) || getVMIP()) {
			curlNewResult();
		}
		return;
	}
	show_codedx_status();
}

sub usage {
	print "usage: $0 [<execution_record_uuid>] [<codedx version>]\n";
	exit 1;
}

Log::Log4perl::easy_init($TRACE);

sub build_vmname { my ($codedx_version) = @_ ;
	$vmname = 'codedx_' . $codedx_version;
	$vmname =~ s/\.//g;
	print "CodeDX version: $codedx_version\n";
	print "vmname: $vmname\n";
}

foreach my $arg (@ARGV) {
	print "arg: <$arg>\n";
	if ($arg =~ m/[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}/) {
		$execution_record_uuid = $arg;
		print "Execution record uuid: $execution_record_uuid\n";
	}
	elsif ($arg =~ m/^[0-9].[0-9].[0-9]$/) {
		$codedx_version = $arg;
	}
}
build_vmname($codedx_version);

if (-r $configfile) {
	if ($global_swamp_config) {
		$codedx_viewername = $global_swamp_config->get('master.viewer');
		print "CodeDX viewer platform: $codedx_viewername\n";
	}
	else {
		print "Error - viewer platform name not found in: $configfile - exiting\n";
		exit(0);
	}
}
else {
	print "Error - $configfile not found or not readable - exiting\n";
	exit(0);
}

while (1) {
	print "v)ersion [+|-]x)ecute codedx s)tatus u)rl c)url d)atabase [+]r)un.out gf [+]m)ysql gf [+]t)omcat gf h)elp q)uit Enter: ";
	my $command = <STDIN>;
	chomp $command;
	my $prefix = $command =~ m/^\+/;
	if ($command eq 'v') {
		print "Enter CodeDX version: ";
		$codedx_version = <STDIN>;
		chomp $codedx_version;
		build_vmname($codedx_version);
	}
	elsif ($command =~ m/x$/) {
		my $dostart = 1;
		if ($prefix) {
			print "Enter full path to viewerdb.tar.gz: ";
			my $path = <STDIN>;
			chomp $path;
			$dostart = get_new_database($path);
		}
		my $reuse_input_dir = $command =~ m/^\-/;
		start_codedx($reuse_input_dir) if ($dostart);
	}
	elsif ($command eq 's') {
		show_codedx_status();
	}
	elsif ($command eq 'u') {
		show_codedx_url();
	}
	elsif ($command eq 'c') {
		if (! defined($execution_record_uuid)) {
			print "Enter execution record uuid: ";
			$execution_record_uuid = <STDIN>;
			chomp $execution_record_uuid;
		}
		curl_result();
		$execution_record_uuid = undef;
	}
	elsif ($command eq 'h') {
	}
	elsif ($command =~ m/r$/) {
		guestfish_display_file('/mnt/out/run.out', $prefix);
	}
	elsif ($command =~ m/d$/) {
		# always preserve codedx.sql file
		guestfish_display_file('/mnt/out/codedx.sql', 1);
		# zip it 
		system("gzip codedx.sql");
	}
	elsif ($command =~ m/m$/) {
		guestfish_display_file("/var/lib/mysql/$vmname.err", $prefix);
	}
	elsif ($command =~ m/t$/) {
		guestfish_display_file('/opt/tomcat/logs/catalina.out', $prefix);
	}
	elsif (! $command || $command eq 'q') {
		last;
	}
	else {
		print "command <$command> not found\n";
	}
	print "\n";
}
stopVM();

print "Hello World!\n";
