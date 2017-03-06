#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2017 Software Assurance Marketplace

use strict;
use warnings;
use File::Copy;
use File::Remove qw(remove);
use File::Basename;
use File::Spec::Functions;
use Log::Log4perl::Level;
use Log::Log4perl;

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
	systemcall 
	displaynameToMastername 
	insertIntoInit
	construct_vmhostname
	create_empty_file
);
use SWAMP::vmu_ViewerSupport qw(
	$VIEWER_STATE_NO_RECORD
	$VIEWER_STATE_LAUNCHING
	$VIEWER_STATE_READY
	$VIEWER_STATE_STOPPING
	$VIEWER_STATE_JOBDIR_FAILED
	$VIEWER_STATE_SHUTDOWN
	createrunscript 
	copyvruninputs 
	updateClassAdViewerStatus
);

my $log;
my $clusterid;

sub logfilename {
    my $name = basename($0, ('.pl'));
	chomp $name;
	$name =~ s/Pre//sxm;
	$name .= '_' . $clusterid;
    return catfile(getSwampDir(), 'log', $name . '.log');
}

sub patchDeltaQcow2ForInit { my ($execrunuid, $imagename, $vmhostname) = @_ ;
	my $swampdir = getSwampDir();
	my $runshcmd =
		"\"#!/bin/bash\\n/bin/chmod 01777 /mnt/out;[ -r /etc/profile.d/vmrun.sh ] && . /etc/profile.d/vmrun.sh;[ -r $swampdir/etc/profile.d/vmrun.sh ] && . $swampdir/etc/profile.d/vmrun.sh;/bin/chown 0:0 /mnt/out;/bin/chmod +x /mnt/in/run.sh && cd /mnt/in && nohup /mnt/in/run.sh > /mnt/out/nohup.out 2>&1 &\\n\"";
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
	my $imagename = displaynameToMastername($bogref->{'platform'});
	$log->info("Creating base image from: $imagename");
	my ($output, $status) = systemcall("qemu-img create -b $imagename -f qcow2 delta.qcow2");
	if ($status) {
		$log->error("createQcow2Disks - base image creation failed: $imagename $output $status");
		return;
	}
	# input qcow2
	($output, $status) = systemcall("$GUESTFISH_ENV_KEY virt-make-fs --format=qcow2 $inputfolder inputdisk.qcow2 --size=+1G");
	if ($status) {
		$log->error("createQcow2Disks - input disk creation failed: $inputfolder $output $status");
		return;
	}
	# output qcow2
	($output, $status) = systemcall("$GUESTFISH_ENV_KEY virt-make-fs --format=qcow2 $outputfolder outputdisk.qcow2 --size=3G");
	if ($status) {
		$log->error("createQcow2Disks - output disk creation failed: $outputfolder $output $status");
		return;
	}
	return $imagename;
}

sub populateInputDirectory { my ($bogref, $inputfolder) = @_ ;
	my $result = copyvruninputs($bogref, $inputfolder);
	if (! $result) {
		$log->error("populateInputDirectory - copyvruninputs failed with $inputfolder");
		return 0;
	}
	$result = createrunscript($bogref, $inputfolder);
	if (! $result) {
		$log->error("populateInputDirectory - createrunscript failed with $inputfolder");
		return 0;
	}
	return 1;
}

sub extractBogFile { my ($execrunuid, $inputfolder) = @_ ;
	my $submitbundle = $execrunuid . '_submitbundle.tar.gz';
	my ($output, $status) = systemcall("tar xzf $submitbundle");
	if ($status) {
		$log->error("extractBogFile - $submitbundle tar failed: $output $status");
		return;
	}
	my %bog;
	my $bogfile = $execrunuid . '.bog';
	loadProperties($bogfile, \%bog);
	copy($bogfile, $inputfolder);
	return \%bog;
}

########
# Main #
########

# args: execrunuid owner uiddomain clusterid procid [debug]
# clusterid is global because it is used in logfilename
my ($execrunuid, $owner, $uiddomain, $procid, $debug) = getStandardParameters(\@ARGV, \$clusterid);
if (! $clusterid) {
	# we have no clusterid for the log4perl log file name
	exit(1);
}

my $vmhostname = construct_vmhostname($execrunuid, $clusterid, $procid);

# logger uses clusterid
Log::Log4perl->init(getLoggingConfigString());
$log = Log::Log4perl->get_logger(q{});
if (! $debug) {
	$log->remove_appender('Screen');
}
$log->level($debug ? $TRACE : $INFO);
$log->info("PreViewer: $execrunuid Begin");
identifyScript(\@ARGV);
listDirectoryContents();

my $inputfolder = q{input};
mkdir($inputfolder);
my $outputfolder = q{output};
mkdir($outputfolder);

my $error_message = 'Unable to Start VM';
my $bogref = extractBogFile($execrunuid, $inputfolder);
if (! $bogref) {
	$log->error("extractBogFile failed for: $execrunuid");
	updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_LAUNCHING, $error_message, $bogref);
	exit(1);
}
$bogref->{'vmhostname'} = $vmhostname;

my $status = populateInputDirectory($bogref, $inputfolder);
if (! $status) {
	$log->error("populateInputDirectory failed for: $execrunuid");
	updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_LAUNCHING, $error_message, $bogref);
	exit(1);
}
my $imagename = createQcow2Disks($bogref, $inputfolder, $outputfolder);
if (! $imagename) {
	$log->error("createQcow2Disks failed for: $execrunuid");
	updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_LAUNCHING, $error_message, $bogref);
	exit(1);
}
if (! patchDeltaQcow2ForInit($execrunuid, $imagename, $vmhostname)) {
	$log->error("patchDeltaQcow2ForInit failed for: $execrunuid $imagename $vmhostname");
	updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_LAUNCHING, $error_message, $bogref);
	exit(1);
}

my $eventsfolder = q{events};
mkdir($eventsfolder);
create_empty_file(catfile($eventsfolder, 'JobVMEvents.log'));
$log->info("Starting virtual machine for: $execrunuid $imagename $vmhostname");
updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_LAUNCHING, "Starting VM", $bogref);

listDirectoryContents();
$log->info("Starting vmu_MonitorViewer for: $execrunuid $imagename $vmhostname");
if (my $pid = fork()) {
	# Parent
	$log->info("vmu_MonitorViewer $execrunuid pid: $pid");
}
else {
	# Child
	$debug ||= '';
	my $script = catfile(getSwampDir(), 'bin', 'vmu_MonitorViewer.pl');
	exec("/opt/perl5/perls/perl-5.18.1/bin/perl $script $execrunuid $owner $uiddomain $clusterid $procid $debug");
}

$log->info("PreViewer: $execrunuid Exit");
exit(0);
