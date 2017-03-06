#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2017 Software Assurance Marketplace

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

use FindBin qw($Bin);
use lib ("$FindBin::Bin/../perl5", "$FindBin::Bin/lib");

use SWAMP::vmu_Locking qw(swamplock);
use SWAMP::vmu_Support qw(
	identifyScript
	listDirectoryContents
	systemcall
	getSwampDir
	getSwampConfig
	getLoggingConfigString
	addExecRunLogAppender
	removeExecRunLogAppender
	loadProperties
	getJobDir
	construct_vmhostname
	create_empty_file
	isMetricRun
);
use SWAMP::vmu_AssessmentSupport qw(
	updateClassAdAssessmentStatus
	isParasoftC
	isParasoftJava
	isGrammaTechCS
	isRedLizardG
);
use SWAMP::vmu_ViewerSupport qw(
	$VIEWER_STATE_NO_RECORD
	$VIEWER_STATE_LAUNCHING
	$VIEWER_STATE_READY
	$VIEWER_STATE_STOPPING
	$VIEWER_STATE_JOBDIR_FAILED
	$VIEWER_STATE_SHUTDOWN
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
$log->remove_appender('Screen');
my $tracelog = Log::Log4perl->get_logger('runtrace');
$tracelog->trace("$PROGRAM_NAME ($PID) called with args: @PRESERVEARGV");
identifyScript(\@PRESERVEARGV);

if (! defined($bogDir)) {
    $log->error("$PROGRAM_NAME ($PID) - BOG directory is required");
	exit 0;
}
if (! chdir $bogDir) {
    $log->error("$PROGRAM_NAME ($PID) - chdir to directory $bogDir failed");
	exit 0;
}

$log->info("$PROGRAM_NAME Starting ($PID)");
if (defined($runnow)) {
    runImmediate($runnow);
    exit 0;
}

# Now read all bog files in $bogDir
$log->info("bogDir: $bogDir");
while (1) {
    # Read in list of .bog files.
    my $bogFiles = readBogFiles($bogDir);
	my $nToProcess = scalar(@$bogFiles);
    last if ($nToProcess <= 0);
    $log->info("readBogFiles count: $nToProcess\n", sub {use Data::Dumper; Dumper($bogFiles);});
    foreach my $bogfile  (@$bogFiles) {
        my %bog;
        loadProperties($bogfile, \%bog);
		# check to see if a job with the same exec run id is currently running, or has
		# been run at some time in the past. this only applies to assessment runs.
		my $execrunuid = $bog{'execrunid'};
		addExecRunLogAppender($execrunuid);
		$log->info( "Checking duplicate $execrunuid in queue");
		if (isJobInQueue($execrunuid) || isJobInHistory($execrunuid)) {
			# we can delete this bog file and skip the rest of the loop
			unlink $bogfile;
			$log->warn("Duplicate $execrunuid removed from queue");
			next;
		}
        if (! defined($bog{'resultsfolder'})) {
            $bog{'resultsfolder'} = '/swamp/working/results';
        }
		#
		# assessment run priority is 0
		# metric run priority is -10
		my $job_priority = 0;
		my $vmhostname = 'aswamp';
		if (isMetricRun($execrunuid)) {
			$job_priority = -10;
			$vmhostname = 'mswamp';
		}
		updateClassAdAssessmentStatus($execrunuid, $vmhostname, 'Creating HTCondor job');
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
			# mark this jobdir with the clusterid
			create_empty_file('ClusterId_' . $clusterid);
			updateClassAdAssessmentStatus($execrunuid, $vmhostname, 'Waiting in HTCondor Queue');
			$tracelog->trace("execrunuid: $execrunuid start succeeded");
			$log->info("$execrunuid clusterid: $clusterid");
		}
		else {
			$log->warn('Unable to submit BOG: cannot start HTCondor job.');
			updateClassAdAssessmentStatus($execrunuid, $vmhostname, $error_message);
			$tracelog->trace("$execrunuid start failed");
		}
		# return to rundir
		chdir $bogDir;
    }
}
$log->info("$PROGRAM_NAME Exiting ($PID)");
removeExecRunLogAppender();
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
		my $projectid = (split '\.', $execrunuid)[1];
		print $fh "+SWAMP_projectid = \"$projectid\"\n";
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
    my $name = basename($0, ('.pl'));
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
            next if ($file =~ m/vrun/sxim); # Do not include vrun BOG files in this loop.
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

# Search the Condor history to see if a job with the same exec run id has
# been run before. This is for assessment runs only.
sub isJobInHistory {
    my $uuid = shift;
    my $res = 0;
    my $cmd = qq(condor_history -constraint 'SWAMP_arun_execrunuid == "$uuid"' -format "%s\n" SWAMP_arun_execrunuid);

    my $childpid = open3(\*HIS_IN, \*HIS_OUT, \*HIS_ERR, $cmd);
    if (!close(HIS_IN)) {
    $log->warn("unable to close condor_history input handle");
    }
    my @outlines = <HIS_OUT>;
    my @errlines = <HIS_ERR>;

    if (!close(HIS_OUT)) {
    $log->warn("unable to close condor_history output handle");
    }
    if (!close(HIS_ERR)) {
    $log->warn("unable to close condor_hisotry error  handle");
    }
    waitpid($childpid, 1);

    my $errnum = @errlines;
    if ($errnum > 0) {
        $log->warn("error in condor_history execution\n" . @errlines);
        return $res;
    }

    my $num = @outlines;
    # there is no header line in the output when we use the -format flag, so
    # any output at all indicates that we have found the uuid.
    if ($num > 0) {
        $log->info( "found job $uuid in Condor history");
        $res = 1;
    }

    return $res;
}

# check the Condor queue to see if the job is currently running.
# this works for both assessment runs and for vruns.
sub isJobInQueue {
    my $uuid = shift;
    my $res = 0;
    my $cmd = qq(condor_q -format "%s\n" SWAMP_arun_execrunuid -format "%s\n" SWAMP_vrun_execrunuid -format "%s\n" SWAMP_mrun_execrunuid);

    my $childpid = open3(\*HIS_IN, \*HIS_OUT, \*HIS_ERR, $cmd);
    if (!close(HIS_IN)) {
    $log->warn("problem closing condor_q input handle");
    }
    my @outlines = <HIS_OUT>;
    my @errlines = <HIS_ERR>;
    if (!close(HIS_OUT)) {
    $log->warn("problem closing condor_q output handle");
    }
    if (!close(HIS_ERR)) {
    $log->warn("problem closing condor_q error handle");
    }
    waitpid($childpid, 1);

    my $num = @errlines;
    if ($num > 0) {
        $log->warn("error in condor_q execution\n" . @errlines);
        return $res;
    }

    foreach my $id (@outlines) {
        if ($id =~ /$uuid/isxm) {
            $log->info("found job $uuid in Condor queue");
            $res = 1;
            last;
        }
    }
    return $res;
}
