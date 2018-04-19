#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2018 Software Assurance Marketplace

use 5.014;
use utf8;
use warnings;
use strict;

use Archive::Tar qw(COMPRESS_GZIP);
use Cwd qw(getcwd);
use English '-no_match_vars';
use File::Spec::Functions;
use File::Copy qw(copy move);
use File::Basename qw(basename);
use File::Path qw(make_path);
use Getopt::Long qw(GetOptions);
use IPC::Open3 qw(open3);
use Log::Log4perl::Level;
use Log::Log4perl;
use POSIX qw(:signal_h);

use FindBin qw($Bin);
use lib ("$FindBin::Bin/../perl5", "$FindBin::Bin/lib");

use SWAMP::Locking qw(swamplock);
	# switchExecRunAppenderLogFile
use SWAMP::vmu_Support qw(
	identifyScript
	listDirectoryContents
	systemcall
	getSwampDir
	getLoggingConfigString
	loadProperties
	getJobDir
	construct_vmhostname
	create_empty_file
	isMetricRun
);
use SWAMP::vmu_AssessmentSupport qw(
	updateClassAdAssessmentStatus
	updateRunStatus
	setLaunchFlag
	setSubmittedToCondorFlag
	isParasoftC
	isParasoftJava
	isGrammaTechCS
	isRedLizardG
	isSynopsysC
);
use SWAMP::vmu_ViewerSupport qw(
	$VIEWER_STATE_LAUNCHING
	updateClassAdViewerStatus
);

my $port;
my $host;
my $debug = 0;
my $bogDir;
my $runnow;

my @PRESERVEARGV = @ARGV;
GetOptions(
    'host=s'   => \$host,
    'port=i'   => \$port,
    'bog=s'    => \$bogDir,
    'debug'    => \$debug,
    'runnow=s' => \$runnow,
);

# Unless we're invoked with runnow
if (! defined($runnow)) {
    # Check for an instance of ourself
    if (! swamplock($PROGRAM_NAME)) {
        exit 0;
    }
}

Log::Log4perl->init(getLoggingConfigString());
my $log = Log::Log4perl->get_logger(q{});
$log->level($debug ? $TRACE : $INFO);
my $tracelog = Log::Log4perl->get_logger('runtrace');
$tracelog->trace("$PROGRAM_NAME ($PID) called with args: @PRESERVEARGV");
identifyScript(\@PRESERVEARGV);

if (! defined($bogDir)) {
    $log->error("$PROGRAM_NAME ($PID) - BOG directory is required - exiting");
	exit 0;
}
if (! chdir $bogDir) {
    $log->error("$PROGRAM_NAME ($PID) - chdir to directory $bogDir failed - exiting");
	exit 0;
}

$log->info("Starting ($PID)");
if (defined($runnow)) {
	$log->info("calling runImmediate on: $runnow ($PID)");
    runImmediate($runnow);
	$log->info("runImmediate exiting ($PID)");
    exit 0;
}

my $launchPadSleep = 1;
my $child_done = 0;
# set TERM signal handler for swamp service stop
$SIG{TERM} = sub { my ($sig) = @_ ;
	$log->info("$PID recieved TERM signal");
	$child_done = 1;
};
# now unblock TERM signal in child
sigprocmask(SIG_UNBLOCK, POSIX::SigSet->new(SIGTERM));

$log->info("starting process loop on bogDir: $bogDir ($PID)");
while (! $child_done) {
	# Now read all arun and mrun bog files in $bogDir
    my $bogFiles = readBogFiles($bogDir);
	my $nToProcess = scalar(@$bogFiles);
	if ($nToProcess > 0) {
    	$log->info("readBogFiles count: $nToProcess\n", sub {use Data::Dumper; Dumper($bogFiles);});
	}
	last if ($child_done);
    sleep $launchPadSleep if ($nToProcess <= 0);
    foreach my $bogfile  (@$bogFiles) {
		last if ($child_done);
		my $event_start = time();
        my %bog;
        loadProperties($bogfile, \%bog);
		my $execrunuid = $bog{'execrunid'};
		if (! $execrunuid) {
			$log->error("execrunid not found in: $bogfile");
			$log->info("BOG:\n", sub {use Data::Dumper; Dumper(\%bog);});
			next;
		}
		# switchExecRunAppenderLogFile($execrunuid);
		if ($bog{'launch_counter'} > 1) {
			my $dupstart = time();
			$log->info( "Checking duplicate: $execrunuid bog: $bogfile in condor queue");
			if (condorJobExists($execrunuid)) {
				# we can delete this bog file and skip the rest of the loop
				unlink $bogfile;
				$log->warn("Duplicate: $execrunuid bog: $bogfile removed from filesystem");
				my $duptime = time() - $dupstart;
				$log->warn("Duplicate found: $execrunuid bog: $bogfile time: $duptime seconds");
				next;
			}
			my $duptime = time() - $dupstart;
			$log->info("Duplicate not found: $execrunuid bog: $bogfile time: $duptime seconds");
			Log::Log4perl->get_logger('timetrace')->trace("condorJobExists $execrunuid elapsed: ", time() - $dupstart);
		}
		# assessment run priority is 0
		# metric run priority is -10
		my $job_priority = 0;
		my $vmhostname = 'aswamp';
		if (isMetricRun($execrunuid)) {
			$job_priority = -10;
			$vmhostname = 'mswamp';
		}
		my $user_uuid = $bog{'userid'};
		my $projectid = $bog{'projectid'};
		updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, 'Creating HTCondor job');
		$log->debug("creating assessment job: $execrunuid $bogfile");
		$tracelog->trace("execrunuid: $execrunuid creating assessment job: $bogfile");
		my $submitfile = $execrunuid . '.sub';
		my $jobdir = vmu_CreateHTCondorAssessmentJob($vmhostname, \%bog, $bogfile, $submitfile, $job_priority);
		# submit from jobdir
		chdir $jobdir;
		my $error_message = 'Failed to submit to HTCondor';
		$log->debug("starting assessment job: $execrunuid $submitfile");
		$tracelog->trace("execrunuid: $execrunuid starting assessment job: $submitfile");
		my ($clusterid, $start_time) = startHTCondorJob(\%bog, $submitfile);
		if ($clusterid != -1) {
			# turn database launch_flag off
			if (! setLaunchFlag($execrunuid, 0)) {
				$log->error("$PROGRAM_NAME: $execrunuid - setLaunchFlag 0 failed");
			}
			# mark this jobdir with the clusterid
			create_empty_file('ClusterId_' . $clusterid);
			my $message = 'Waiting in HTCondor Queue';
			updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $message);
			updateRunStatus($execrunuid, $message);
			$tracelog->trace("execrunuid: $execrunuid start succeeded");
			$log->info("$execrunuid clusterid: $clusterid");
		}
		else {
			$log->warn('Unable to submit BOG: cannot start HTCondor job.');
			updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $error_message);
			updateRunStatus($execrunuid, $error_message);
			$tracelog->trace("$execrunuid start failed");
		}
		# return to rundir
		chdir $bogDir;
		Log::Log4perl->get_logger('timetrace')->trace("csa_agent $execrunuid elapsed: ", time() - $event_start);
    }
}
$log->info("ending process loop on bogDir: $bogDir ($PID)");
$log->info("exiting ($PID)");
exit 0;

sub vmu_CreateHTCondorAssessmentJob { my ($vmhostname, $bogref, $bogfile, $submitfile, $job_priority) = @_ ;
    my $execrunuid = $bogref->{'execrunid'};
	my $jobdir = getJobDir($execrunuid, $vmhostname);
	make_path($jobdir, {'error' => \my $err});
	move $bogfile, $jobdir;
	chdir $jobdir;
	copy(catfile(getSwampDir(), 'etc', 'vmu_htcondor_submit'), $submitfile);
	create_empty_file("delta.qcow2");
	create_empty_file("inputdisk.qcow2");
	create_empty_file("outputdisk.qcow2");

	my $climits;
	if (isParasoftC($bogref)) {
		$climits = "PARASOFTC";
	}
	elsif (isParasoftJava($bogref)) {
		$climits = "PARASOFTJAVA";
	}
	elsif (isGrammaTechCS($bogref)) {
		$climits = "GRAMMATECHCS";
	}
	elsif (isRedLizardG($bogref)) {
		$climits = "REDLIZARDG";
	}
	elsif (isSynopsysC($bogref)) {
		$climits = "SYNOPSYSC";
	}
	my $submitbundle = $execrunuid . '_submitbundle.tar.gz';
	if (open(my $fh, ">>", $submitfile)) {
		my $owner = getpwuid($UID);
		print $fh "\n";
		print $fh "##### Dynamic Submit File Attributes #####";
		print $fh "\n";
		if ($climits) {
			print $fh "### Concurrency Limits\n";
			print $fh "concurrency_limits = $climits\n";
			print $fh "\n";
		}
		print $fh "### Executable\n";
		print $fh "executable = " . construct_vmhostname($execrunuid, '$(CLUSTERID)', '$(PROCID)') . "\n";
		print $fh "\n";
		print $fh "### Input File Transfer Settings\n";
		print $fh "transfer_input_files = delta.qcow2, inputdisk.qcow2, outputdisk.qcow2, $submitbundle\n";
		print $fh "\n";
		print $fh "### Start PRE- and POST- Script Settings\n";
		print $fh "+PreCmd = \"../../opt/swamp/bin/vmu_PreAssessment_launcher\"\n";
		print $fh "+PreArguments = \"$execrunuid $owner \$\$(UidDomain) \$(CLUSTERID) \$(PROCID)\"\n";
		print $fh "+PostCmd = \"../../opt/swamp/bin/vmu_PostAssessment_launcher\"\n";
		print $fh "+PostArguments = \"$execrunuid $owner \$\$(UidDomain) \$(CLUSTERID) \$(PROCID)\"\n";
		print $fh "\n";
		print $fh "### Job Priority\n";
		print $fh "priority = $job_priority\n";
		print $fh "\n";

		print $fh "### SWAMP Specific Attributes\n";
		if (isMetricRun($execrunuid)) {
			print $fh "+SWAMP_mrun_execrunuid = \"$execrunuid\"\n";
		}
		else {
			print $fh "+SWAMP_arun_execrunuid = \"$execrunuid\"\n";
		}
		print $fh "+SWAMP_userid = \"$bogref->{'userid'}\"\n";
		print $fh "+SWAMP_projectid = \"$bogref->{'projectid'}\"\n";
		print $fh "\n";

		print $fh "### Queue the job\n";
		print $fh "queue\n";
		close($fh);
	}
    my @files = ($bogfile, $submitfile);
    Archive::Tar->create_archive($submitbundle, COMPRESS_GZIP, @files);
	chdir $bogDir;
	listDirectoryContents($jobdir);
	return $jobdir;
}

sub vmu_CreateHTCondorViewerJob { my ($vmhostname, $bogref, $bogfile, $submitfile, $job_priority) = @_ ;
    my $execrunuid = $bogref->{'execrunid'};
    my $jobdir = getJobDir($execrunuid, $vmhostname);
    make_path($jobdir, {'error' => \my $err});
	move $bogfile, $jobdir;
	chdir $jobdir;
	copy(catfile(getSwampDir(), 'etc', 'vmu_htcondor_submit'), $submitfile);
	create_empty_file("delta.qcow2");
	create_empty_file("inputdisk.qcow2");
	create_empty_file("outputdisk.qcow2");

	my $submitbundle = $execrunuid . '_submitbundle.tar.gz';
	if (open(my $fh, ">>", $submitfile)) {
		my $owner = getpwuid($UID);
		print $fh "\n";
		print $fh "##### Dynamic Submit File Attributes #####";
		print $fh "\n";
		print $fh "### Executable\n";
		print $fh "executable = " . construct_vmhostname($execrunuid, '$(CLUSTERID)', '$(PROCID)') . "\n";
		print $fh "\n";
		print $fh "### Input File Transfer Settings\n";
		print $fh "transfer_input_files = delta.qcow2, inputdisk.qcow2, outputdisk.qcow2, $submitbundle\n";
		print $fh "\n";
		print $fh "### Start PRE- and POST- Script Settings\n";
		print $fh "+PreCmd = \"../../opt/swamp/bin/vmu_PreViewer_launcher\"\n";
		print $fh "+PreArguments = \"$execrunuid $owner \$\$(UidDomain) \$(CLUSTERID) \$(PROCID)\"\n";
		print $fh "+PostCmd = \"../../opt/swamp/bin/vmu_PostViewer_launcher\"\n";
		print $fh "+PostArguments = \"$execrunuid $owner \$\$(UidDomain) \$(CLUSTERID) \$(PROCID)\"\n";
		print $fh "\n";
		print $fh "### Job Priority\n";
		print $fh "priority = $job_priority\n";
		print $fh "\n";

		print $fh "### SWAMP Specific Attributes\n";
		print $fh "+SWAMP_vrun_execrunuid = \"$execrunuid\"\n";
		print $fh "+SWAMP_userid = \"$bogref->{'userid'}\"\n";
		print $fh "+SWAMP_projectid = \"$bogref->{'projectid'}\"\n";
		print $fh "+SWAMP_viewerinstanceid = \"$bogref->{'viewer_uuid'}\"\n";
		print $fh "\n";

		print $fh "### Queue the job\n";
		print $fh "queue\n";
		close($fh);
	}
    my @files = ($bogfile, $submitfile);
    Archive::Tar->create_archive($submitbundle, COMPRESS_GZIP, @files);
	chdir $bogDir;
	listDirectoryContents($jobdir);
	return $jobdir;
}

sub startHTCondorJob { my ($bogref, $submitfile) = @_ ;
    my $started    = 0;
    my $retry      = 0;
    my $output;
    my $status;
    my $start_time;

    while (! $started && ($retry++ < 3)) {
        $tracelog->trace("$bogref->{'execrunid'} Calling condor_submit");
        $log->debug("condor_submit file: $submitfile cwd: ", getcwd());
        ($output, $status) = systemcall("condor_submit $submitfile");
        if ($status) {
            $log->warn("Failed to start condor job using $submitfile: $output. Trying again in 5 seconds");
            sleep 5;
        }
        else {
            $start_time = time();
            $started = 1;
			if (! setSubmittedToCondorFlag($bogref->{'execrunid'}, 1)) {
				$log->warn("startHTCondorJob: ", $bogref->{'execrunid'}, " - setSubmittedToCondorFlag 1 failed");
			}
            last;
        }
    }
    if (! $started) {
        $log->error("Failed to start condor job: $output after $retry tries");
        $tracelog->trace("$bogref->{'execrunid'} condor_submit failed: $output after: $retry attempts");
    }
    my $clusterid = -1;
    if ($output =~ /submitted\ to\ cluster/sxm) {
        $clusterid = $output;
        $clusterid =~ s/^.*cluster\ //sxm;
        $clusterid =~ s/\..*$//sxm;
        $log->debug("Found cluster id <$clusterid>");
    }
    if ($clusterid == -1) {
        $log->error("submit job failed");
    }
    $bogref->{'clusterid'} = $clusterid;
    return ($clusterid, $start_time);
}

sub logfilename {
    # my $name = basename($0, ('.pl'));
	my $name = 'vmu_LaunchPad';
    return catfile(getSwampDir(), 'log', $name . '.log');
}

sub readBogFiles { my ($path) = @_ ;
	my $bogFiles = [];
    if (opendir(my $dh, $path)) {
        my @bogfiles = grep { /\.bog$/sxm && -f "$path/$_" } readdir($dh);
        if ( !closedir $dh ) {
            $log->error("Unable to closedir $path $OS_ERROR");
        }
        foreach my $file (@bogfiles) {
			# skip over vrun bog files
            next if ($file =~ m/vrun_/sxim); # Do not include vrun BOG files in this loop.
			push @$bogFiles, $file;
        }
    }
    else {
        $log->error("Cannot open $path $OS_ERROR");
    }
    return $bogFiles;
}

sub runImmediate { my ($bogfile) = @_ ;
	$log->info("runImmediate bogfile: $bogfile");
	# submit the BOG file immediately and exit.
	my %bog;
	my $ret = 0;
	loadProperties($bogfile, \%bog);
	my $execrunuid = $bog{'execrunid'};
	$log->info("runImmediate creating viewer job: $execrunuid $bogfile");
	my $vmhostname = 'vswamp';
	$bog{'vmhostname'} = $vmhostname;
	updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_LAUNCHING, "Creating HTCondor job", \%bog);
	# viewer run priority is +10
	my $job_priority = +10;
	my $submitfile = $execrunuid . '.sub';
	my $jobdir = vmu_CreateHTCondorViewerJob($vmhostname, \%bog, $bogfile, $submitfile, $job_priority);
	# submit from jobdir
	chdir $jobdir;
	$log->info("runImmediate starting viewer job: $submitfile jobdir: $jobdir");
	my ($clusterid, $start_time) = startHTCondorJob(\%bog, $submitfile);
	if ($clusterid != -1) {
		# mark this jobdir with the clusterid
		create_empty_file('ClusterId_' . $clusterid);
		$ret = 1;
		updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_LAUNCHING, 'Waiting in HTCondor Queue', \%bog);
	}
	# return to rundir
	chdir $bogDir;
	return $ret;
}

sub isJobInHistory { my ($execrunuid) = @_ ;
    my $cmd  = qq(condor_history);
       $cmd .= qq( -constraint ');
       $cmd .= qq(SWAMP_arun_execrunuid == "$execrunuid");
       $cmd .= qq( || SWAMP_mrun_execrunuid == "$execrunuid");
       $cmd .= qq( || SWAMP_vrun_execrunuid == "$execrunuid");
       $cmd .= qq(');
       $cmd .= qq( -format "%s\n" SWAMP_arun_execrunuid);
       $cmd .= qq( -format "%s\n" SWAMP_mrun_execrunuid);
       $cmd .= qq( -format "%s\n" SWAMP_vrun_execrunuid);
       $cmd .= qq( -limit 1);
    my ($output, $status) = systemcall($cmd);
    if ($status) {
        $log->error("isJobInHistory condor_history failed - $status output: $output");
        return 0;
    }
    if ($output =~ m/^$execrunuid$/) {
        $log->info("$execrunuid found from condor_history");
        return 1;
    }
    return 0;
}

sub isJobInQueue { my ($execrunuid) = @_ ;
    my $cmd  = qq(condor_q);
       $cmd .= qq( -format "%s\n" SWAMP_arun_execrunuid);
       $cmd .= qq( -format "%s\n" SWAMP_vrun_execrunuid);
       $cmd .= qq( -format "%s\n" SWAMP_mrun_execrunuid);
    my ($output, $status) = systemcall($cmd);
    if ($status) {
        $log->error("isJobInQueue condor_q failed - $status output: $output");
        return 0;
    }
    if ($output =~ m/$execrunuid/) {
        $log->info("$execrunuid found from condor_q");
        return 1;
    }
    return 0;
}

sub condorJobExists { my ($execrunuid) = @_ ;
    return isJobInQueue($execrunuid) || isJobInHistory($execrunuid);
}

