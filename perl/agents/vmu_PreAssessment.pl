#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2018 Software Assurance Marketplace

use strict;
use warnings;
use English '-no_match_vars';
use Sys::Hostname;
use File::Copy;
use File::Remove qw(remove);
use File::Basename;
use File::Spec::Functions;
use Log::Log4perl::Level;
use Log::Log4perl;
use POSIX qw(strftime);

use FindBin qw($Bin);
use lib ("$FindBin::Bin/../perl5", "$FindBin::Bin/lib");

use Readonly;
Readonly::Scalar my $GUESTFISH_ENV_KEY => 'LIBGUESTFS_BACKEND=direct';

use SWAMP::vmu_Support qw(
	getStandardParameters
	identifyScript
	listDirectoryContents
	getSwampDir
	loadProperties
	getLoggingConfigString
	getSwampConfig
	isSwampInABox
	buildExecRunAppenderLogFileName
	systemcall
	insertIntoInit
	displaynameToMastername
	construct_vmhostname
	create_empty_file
);
use SWAMP::vmu_AssessmentSupport qw(
	identifyAssessment
	copyAssessmentInputs
	createAssessmentConfigs
	builderUser
	builderPassword
	updateExecutionResults
	updateClassAdAssessmentStatus
);

my $log;
my $tracelog;
my $config = getSwampConfig();
my $execrunuid;
my $clusterid;
my $builderUser;
my $builderPassword;
my $hostname = hostname();

sub logfilename {
	if (isSwampInABox($config)) {
		my $name = buildExecRunAppenderLogFileName($execrunuid);
		return $name;
	}
    my $name = basename($0, ('.pl'));
	chomp $name;
	$name =~ s/Pre//sxm;
	$name .= '_' . $clusterid;
    return catfile(getSwampDir(), 'log', $name . '.log');
}

sub patchDeltaQcow2ForInit { my ($imagename, $vmhostname) = @_ ;
	my $swampdir = getSwampDir();
	my $runshcmd =
		"\"#!/bin/bash\\n/bin/chmod 01777 /mnt/out;[ -r /etc/profile.d/vmrun.sh ] && . /etc/profile.d/vmrun.sh;[ -r $swampdir/etc/profile.d/vmrun.sh ] && . $swampdir/etc/profile.d/vmrun.sh;/bin/chown 0:0 /mnt/out;/bin/chmod +x /mnt/in/run.sh && cd /mnt/in && nohup /mnt/in/run.sh > /mnt/out/runsh.out 2>&1 &\\n\"";
	my $gfname = 'init.gf';
	my $script;
	if (! open($script, '>', $gfname)) {
		$log->error("patchDeltaQcow2ForInit - open failed for: $gfname");
		return 0;
	}
	print $script "#!/usr/bin/guestfish -f\n";
	my ($ostype, $status) = insertIntoInit($imagename, $script, $runshcmd, $vmhostname, $imagename);
	if ($status) {
		$log->error("patchDeltaQcow2ForInit - insertIntoInit failed");
		close($script);
		return 0;
	}
	close($script);
	(my $output, $status) = systemcall("$GUESTFISH_ENV_KEY /usr/bin/guestfish -f $gfname -a delta.qcow2 -i </dev/null");
	if ($status) {
		$log->error("patchDeltaQcow2ForInit - guestfish -f $gfname failed: $output $status");
		return 0;
	}
	return 1;
}

sub createQcow2Disks { my ($bogref, $inputfolder, $outputfolder) = @_ ;
	# delta qcow2
	$log->info('Creating base image for: ', $bogref->{'platform'});
	my $imagename = displaynameToMastername($bogref->{'platform'});
	if (! $imagename) {
		$log->error("createQcow2Disks - base image creation failed - no image");
		return;
	}
	if (! -r $imagename) {
		$log->error("createQcow2Disks - base image creation failed - $imagename not readable");
		return;
	}
	my ($output, $status) = systemcall("qemu-img create -b $imagename -f qcow2 delta.qcow2");
	if ($status) {
		$log->error("createQcow2Disks - base image creation failed: $imagename $output $status");
		return;
	}
	# input qcow2
	($output, $status) = systemcall("$GUESTFISH_ENV_KEY virt-make-fs --type=ext3 --format=qcow2 $inputfolder inputdisk.qcow2 --size=+1G");
	if ($status) {
		$log->error("createQcow2Disks - input disk creation failed: $inputfolder $output $status");
		return;
	}
	# output qcow2
	($output, $status) = systemcall("$GUESTFISH_ENV_KEY virt-make-fs --type=ext3 --format=qcow2 $outputfolder outputdisk.qcow2 --size=3G");
	if ($status) {
		$log->error("createQcow2Disks - output disk creation failed: $outputfolder $output $status");
		return;
	}
	return $imagename;
}

sub populateInputDirectory { my ($bogref, $inputfolder) = @_ ;
	$builderUser = builderUser();
	$builderPassword = builderPassword();
	my $retval = 1;
	my $result = copyAssessmentInputs($bogref, $inputfolder);
	if (! $result) {
		$log->error("populateInputDirectory - copyInputs failed with $inputfolder");
		$retval = 0;
	}
	$log->debug("Adding arun.sh to $inputfolder");
	copy(catfile(getSwampDir(), 'bin', 'arun.sh'), catfile($inputfolder, 'run.sh'));
	$result = createAssessmentConfigs($bogref, $inputfolder, $builderUser, $builderPassword);
	if (! $result) {
		$log->error("populateInputDirectory - createAssessmentConfigs failed with $inputfolder");
		$retval = 0;
	}
	listDirectoryContents($inputfolder);
	return $retval;
}

sub extractBogFile { my ($execrunuid, $outputfolder) = @_ ;
	my $submitbundle = $execrunuid . '_submitbundle.tar.gz';
	my ($output, $status) = systemcall("tar xzf $submitbundle");
	if ($status) {
		$log->error("extractBogFile - $submitbundle tar failed: $output $status");
		return;
	}
	my %bog;
	my $bogfile = $execrunuid . '.bog';
	loadProperties($bogfile, \%bog);

	# copy bogfile and submitfile to outputfolder
    my $submitfile = $execrunuid . '.sub';
	copy($bogfile, $outputfolder);
	copy($submitfile, $outputfolder);

	return \%bog;
}

sub exit_prescript_with_error {
	$log->info("Exiting $PROGRAM_NAME ($PID) with error");
	$log->info("Unlinking delta, input, and output disks for HTCondor");
	unlink 'delta.qcow2' if (-e 'delta.qcow2');
	unlink 'inputdisk.qcow2' if (-e 'inputdisk.qcow2');
	unlink 'outputdisk.qcow2' if (-e 'outputdisk.qcow2');
	exit(1);
}

########
# Main #
########

# args: execrunuid owner uiddomain clusterid procid [debug]
# execrunuid is global because it is used in logfilename
# clusterid is global because it is used in logfilename
my ($owner, $uiddomain, $procid, $debug) = getStandardParameters(\@ARGV, \$execrunuid, \$clusterid);
if (! $execrunuid || ! $clusterid) {
	# we have no execrunuid or clusterid for the log4perl log file name
	exit_prescript_with_error();
}

my $vmhostname = construct_vmhostname($execrunuid, $clusterid, $procid);

Log::Log4perl->init(getLoggingConfigString());
$log = Log::Log4perl->get_logger(q{});
$log->level($debug ? $TRACE : $INFO);
$log->info("PreAssessment: $execrunuid Begin");
$tracelog = Log::Log4perl->get_logger('runtrace');
$tracelog->trace("$PROGRAM_NAME ($PID) called with args: @ARGV");
identifyScript(\@ARGV);
listDirectoryContents();

my $inputfolder = q{input};
mkdir($inputfolder);
my $outputfolder = q{output};
mkdir($outputfolder);

my $error_message = 'Unable to Start VM';
my $bogref = extractBogFile($execrunuid, $outputfolder);
if (! $bogref) {
	$log->error("extractBogFile failed for: $execrunuid");
	updateClassAdAssessmentStatus($execrunuid, $vmhostname, 'null', 'null', $error_message);
	exit_prescript_with_error();
}

identifyAssessment($bogref);
my $user_uuid = $bogref->{'userid'} || 'null';
my $projectid = $bogref->{'projectid'} || 'null';

my $status = populateInputDirectory($bogref, $inputfolder);
if (! $status) {
	$log->error("populateInputDirectory failed for: $execrunuid");
	updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $error_message);
	exit_prescript_with_error();
}
my $imagename = createQcow2Disks($bogref, $inputfolder, $outputfolder);
if (! $imagename) {
	$log->error("createQcow2Disks failed for: $execrunuid");
	updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $error_message);
	exit_prescript_with_error();
}
if (! patchDeltaQcow2ForInit($imagename, $vmhostname)) {
	$log->error("patchDeltaQcow2ForInit failed for: $execrunuid $imagename $vmhostname");
	updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $error_message);
	exit_prescript_with_error();
}

my $eventsfolder = q{events};
mkdir($eventsfolder);
create_empty_file(catfile($eventsfolder, 'JobVMEvents.log'));
$log->info("Starting virtual machine for: $execrunuid $imagename $vmhostname");
updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, 'Starting virtual machine');
updateExecutionResults($execrunuid, {
	'status'						=> 'Starting virtual machine',
	'execute_node_architecture_id'	=> $hostname,
	'vm_hostname'					=> $vmhostname,
	'vm_username'					=> $builderUser,
	'vm_password'					=> $builderPassword,
	'vm_image'						=> $imagename,
	'tool_filename'					=> $bogref->{'toolpath'},
	'run_date'						=> strftime("%Y-%m-%d %H:%M:%S", gmtime(time())),
});

listDirectoryContents();
$log->info("Starting vmu_MonitorAssessment for: $execrunuid $imagename $vmhostname");
if (my $pid = fork()) {
	# Parent
	$log->info("vmu_MonitorAssessment $execrunuid pid: $pid");
}
else {
	# Child
	$debug ||= '';
	my $script = catfile(getSwampDir(), 'bin', 'vmu_MonitorAssessment.pl');
	exec("/opt/perl5/perls/perl-5.18.1/bin/perl $script $execrunuid $owner $uiddomain $clusterid $procid $debug");
}

$log->info("PreAssessment: $execrunuid Exit");
exit(0);
