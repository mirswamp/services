#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2017 Software Assurance Marketplace

use strict;
use warnings;
use English '-no_match_vars';
use File::Copy;
use File::Basename;
use File::Spec::Functions;
use Log::Log4perl::Level;
use Log::Log4perl;

use FindBin qw($Bin);
use lib ("$FindBin::Bin/../perl5", "$FindBin::Bin/lib");

use SWAMP::vmu_Support qw(
	getStandardParameters
	identifyScript
	getSwampDir 
	getLoggingConfigString 
	getSwampConfig
	isSwampInABox
	buildExecRunAppenderLogFileName
	systemcall 
	loadProperties
	construct_vmhostname
);
use SWAMP::vmu_ViewerSupport qw(
	$VIEWER_STATE_NO_RECORD
	$VIEWER_STATE_LAUNCHING
	$VIEWER_STATE_READY
	$VIEWER_STATE_STOPPING
	$VIEWER_STATE_JOBDIR_FAILED
	$VIEWER_STATE_SHUTDOWN
	saveViewerDatabase
	updateClassAdViewerStatus
);

my $log;
my $tracelog;
my $config = getSwampConfig();
my $execrunuid;
my $clusterid;

sub logfilename {
	if (isSwampInABox($config)) {
		my $name = buildExecRunAppenderLogFileName($execrunuid);
		return $name;
	}
    my $name = basename($0, ('.pl'));
	chomp $name;
	$name =~ s/Post//sxm;
	$name .= '_' . $clusterid;
    return catfile(getSwampDir(), 'log', $name . '.log');
}

sub extract_outputdisk { my ($outputfolder) = @_ ;
    my $gfname = 'extract.gf';
    my $script;
    if (! open($script, '>', $gfname)) {
        $log->error("open failed for: $gfname");
        return 0;
    }
    print $script "add outputdisk.qcow2\n";
    print $script "run\n";
    print $script "mount /dev/sda /\n";
    print $script "glob copy-out /* $outputfolder\n";
    close($script);
    my ($output, $status) = systemcall("/usr/bin/guestfish -f $gfname");
    if ($status) {
        $log->error("extract_outputdisk - output extraction failed: $output $status");
        return 0;
    }
    return 1;
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
	exit(1);
}

my $vmhostname = construct_vmhostname($execrunuid, $clusterid, $procid);

Log::Log4perl->init(getLoggingConfigString());
$log = Log::Log4perl->get_logger(q{});
$log->level($debug ? $TRACE : $INFO);
$log->info("PostViewer: $execrunuid Begin");
$tracelog = Log::Log4perl->get_logger('runtrace');
$tracelog->trace("$PROGRAM_NAME ($PID) called with args: @ARGV");
identifyScript(\@ARGV);

my $outputfolder = q{output};

my %bog;
my $bogfile = $execrunuid . '.bog';
loadProperties($bogfile, \%bog);
$bog{'vmhostname'} = $vmhostname;

$log->info("Viewer is starting shutdown");
updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_STOPPING, 'Viewer is starting shutdown', \%bog);

my $status = extract_outputdisk($outputfolder);
if (! $status) {
    my $error_message = "Failed to extract viewer results for: $vmhostname";
	$log->error($error_message);
	updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_STOPPING, $error_message, \%bog);
	$log->info("PostViewer: $execrunuid Error Exit");
	exit(1);
}

$status = saveViewerDatabase(\%bog, $vmhostname, $outputfolder);
if (! $status) {
	my $error_message = "Failed to save viewer results for: $vmhostname";
	$log->error($error_message);
	updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_STOPPING, $error_message, \%bog);
	$log->info("PostViewer: $execrunuid Error Exit");
	exit(1);
}

$log->info("Viewer is completing shutdown");
updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_STOPPING, 'Viewer is completing shutdown', \%bog);
$log->info("PostViewer: $execrunuid Exit");
exit(0);
