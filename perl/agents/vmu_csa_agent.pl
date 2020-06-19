#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

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
use Getopt::Long qw(GetOptions);
use IPC::Open3 qw(open3);
use Log::Log4perl::Level;
use Log::Log4perl;
use POSIX qw(:signal_h);

use FindBin qw($Bin);
use lib ("$FindBin::Bin/../perl5", "$FindBin::Bin/lib");

use SWAMP::Locking qw(swamplock);
use SWAMP::vmu_Support qw(
	listJobDirs
	getRunDirHistory
	use_make_path
	use_remove_tree
	identifyScript
	listDirectoryContents
	systemcall
	getSwampDir
	timing_log_assessment_timepoint
	getLoggingConfigString
	loadProperties
	constructJobDirName
    condorJobExists
	identifyPreemptedJobs
	construct_vmhostname
	create_empty_file
	isMetricRun
	getSwampConfig
	$global_swamp_config
	$HTCONDOR_POSTSCRIPT_FAILED
	$HTCONDOR_POSTSCRIPT_EXIT
	$HTCONDOR_JOB_INPUT_DIR
	$HTCONDOR_JOB_EVENTS_PATH
	$HTCONDOR_JOB_IP_ADDRESS_PATH
);
use SWAMP::vmu_AssessmentSupport qw(
	updateClassAdAssessmentStatus
	updateExecutionResults
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

# Initialize Log4perl
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

my $launchPadSleep = 2;
my $child_done = 0;
# set TERM signal handler for swamp service stop
$SIG{TERM} = sub { my ($sig) = @_ ;
	$log->info("$PID recieved TERM signal");
	$child_done = 1;
};
# now unblock TERM signal in child
sigprocmask(SIG_UNBLOCK, POSIX::SigSet->new(SIGTERM));

$global_swamp_config ||= getSwampConfig();
$log->info("starting process loop on bogDir: $bogDir ($PID)");
while (! $child_done) {
	# Now read all arun and mrun bog files in $bogDir
    my $bogFiles = readBogFiles($bogDir);
	my $nToProcess = scalar(@$bogFiles);
	if ($nToProcess > 0) {
    	$log->info("readBogFiles count: $nToProcess\n", sub {use Data::Dumper; Dumper($bogFiles);});
	}
	last if ($child_done);
	if ($nToProcess <= 0) {
    	my $jobdirs = listJobDirs($bogDir);
		if (scalar(@$jobdirs)) {
			my $history = getRunDirHistory();
    		foreach my $jobdir (@$jobdirs) {
				last if ($child_done);
				next if (! exists($history->{$jobdir}));
				next if ($debug); # preserve jobdir in debug mode
        		$log->info("cleanRundir removing $bogDir/$jobdir");
        		if (! use_remove_tree("$bogDir/$jobdir")) {
            		$log->error("cleanRunDir Error - $bogDir/$jobdir remove failed");
        		}
    		}
		}
		last if ($child_done);
		my $jobs = identifyPreemptedJobs();
		foreach my $execrunuid (@$jobs) {
			last if ($child_done);
			updateClassAdAssessmentStatus($execrunuid, 'arun', '', '', 'Preempted - Waiting in HTCondor Queue');
			updateExecutionResults($execrunuid, {'vm_password' => ''});
		}
		last if ($child_done);
    	sleep $launchPadSleep;
	}
    foreach my $bogfile  (@$bogFiles) {
		last if ($child_done);
        my %bog;
        loadProperties($bogfile, \%bog);
		my $execrunuid = $bog{'execrunid'};
		if (! $execrunuid) {
			$log->error("execrunid not found in: $bogfile");
			$log->info("BOG:\n", sub {use Data::Dumper; Dumper(\%bog);});
			next;
		}
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
		}
		timing_log_assessment_timepoint($execrunuid, 'read bog file');
		# assessment run priority is 0
		# metric run priority is -10
		my $job_priority = 0;
		my $jobtype = 'aswamp';
		if (isMetricRun($execrunuid)) {
			$job_priority = -10;
			$jobtype = 'mswamp';
		}
		my $user_uuid = $bog{'userid'};
		my $projectid = $bog{'projectid'};
		my $job_status_message = 'Creating HTCondor job';
		updateClassAdAssessmentStatus($execrunuid, $jobtype, $user_uuid, $projectid, $job_status_message);
		$log->debug("creating assessment job: $execrunuid $bogfile");
		$tracelog->trace("execrunuid: $execrunuid creating assessment job: $bogfile");
		my $submitfile = $execrunuid . '.sub';
		timing_log_assessment_timepoint($execrunuid, 'create condor job');
		my $jobdir = vmu_CreateHTCondorAssessmentJob($jobtype, \%bog, $bogfile, $submitfile, $job_priority);
		if (! $jobdir) {
			$log->error("CreateHTCondorAssessmentJob failed for: $execrunuid");
			next;
		}
		# submit from jobdir
		chdir $jobdir;
		$log->debug("starting assessment job: $execrunuid $submitfile");
		$tracelog->trace("execrunuid: $execrunuid starting assessment job: $submitfile");
		my $clusterid = startHTCondorJob(\%bog, $submitfile);
		if ($clusterid != -1) {
			timing_log_assessment_timepoint($execrunuid, 'condor job submitted');
			# turn database launch_flag off
			if (! setLaunchFlag($execrunuid, 0)) {
				$log->error("$PROGRAM_NAME: $execrunuid - setLaunchFlag 0 failed");
			}
			# mark this jobdir with the clusterid
			create_empty_file('ClusterId_' . $clusterid);
			$job_status_message = 'Waiting in HTCondor Queue';
			updateClassAdAssessmentStatus($execrunuid, $jobtype, $user_uuid, $projectid, $job_status_message);
			updateRunStatus($execrunuid, $job_status_message);
			$tracelog->trace("execrunuid: $execrunuid start succeeded");
			$log->info("$execrunuid clusterid: $clusterid");
		}
		else {
			$job_status_message = 'Failed to submit to HTCondor';
			$log->warn('Unable to submit BOG: cannot start HTCondor job.');
			updateClassAdAssessmentStatus($execrunuid, $jobtype, $user_uuid, $projectid, $job_status_message);
			updateRunStatus($execrunuid, $job_status_message);
			$tracelog->trace("$execrunuid start failed");
		}
		# return to rundir
		chdir $bogDir;
    }
}
$log->info("ending process loop on bogDir: $bogDir ($PID)");
$log->info("exiting ($PID)");
exit 0;

sub vmu_CreateHTCondorAssessmentJob { my ($jobtype, $bogref, $bogfile, $submitfile, $job_priority) = @_ ;
    my $execrunuid = $bogref->{'execrunid'};
	my $jobdir = constructJobDirName($jobtype);
	if (! use_make_path($jobdir)) {
		$log->error("Error - make_path failed for: $jobdir");
		return;
	}
	move $bogfile, $jobdir;
	chdir $jobdir;
	if ($bogref->{'use_docker_universe'}) {
		copy(catfile(getSwampDir(), 'etc', 'docker_htcondor_submit'), $submitfile);
	}
	else {
		copy(catfile(getSwampDir(), 'etc', 'vmu_htcondor_submit'), $submitfile);
		create_empty_file("delta.qcow2");
		create_empty_file("inputdisk.qcow2");
		create_empty_file("outputdisk.qcow2");
	}

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
		my $htcondor_assessment_max_retries = $global_swamp_config->get('htcondor_assessment_max_retries') || 3;
		my $owner = getpwuid($UID);
		print $fh "\n";
		print $fh "##### Dynamic Submit File Attributes #####";
		print $fh "\n\n";

		if ($climits) {
			print $fh "### Concurrency Limits\n";
			print $fh "concurrency_limits = $climits\n";
			print $fh "\n";
		}

		print $fh "### Job events and ip address path\n";
		print $fh "+JOB_EVENTS_PATH = \"$HTCONDOR_JOB_EVENTS_PATH\"\n";
		print $fh "+JOB_IP_ADDRESS_PATH = \"$HTCONDOR_JOB_IP_ADDRESS_PATH\"\n";
		print $fh "\n";

		if ($bogref->{'use_docker_universe'}) {
			my $docker_container = $bogref->{'platform_image'};
			print $fh "### Docker Image\n";
			print $fh "docker_image = " . $docker_container . "\n";
			print $fh "\n";

			print $fh "### Executable\n";
			# print $fh "executable = $HTCONDOR_JOB_INPUT_DIR/run.sh\n";
            # print $fh "arguments = --type=docker\n";
			print $fh "executable = /bin/bash\n";
            print $fh "arguments = \"-c 'ulimit -n 1024 && $HTCONDOR_JOB_INPUT_DIR/run.sh --type=docker'\"\n";

			print $fh "### Input File Transfer Settings\n";
			print $fh "transfer_input_files = $submitbundle\n";
			print $fh "\n";
		}
		else {
			print $fh "### Executable\n";
			print $fh "executable = " . construct_vmhostname($execrunuid, '$(CLUSTERID)', '$(PROCID)') . "\n";
			print $fh "\n";

			print $fh "### Input File Transfer Settings\n";
			print $fh "transfer_input_files = delta.qcow2, inputdisk.qcow2, outputdisk.qcow2, $submitbundle\n";
			print $fh "\n";
		}

		print $fh "### Start PRE- and POST- Script Settings\n";
		print $fh "+PreCmd = \"../../opt/swamp/bin/vmu_perl_launcher\"\n";
		print $fh "+PreArguments = \"PreAssessment $execrunuid $owner \$\$(UidDomain) \$(CLUSTERID) \$(PROCID) \$\$([NumJobStarts])\"\n";
		print $fh "+PostCmd = \"../../opt/swamp/bin/vmu_perl_launcher\"\n";
		print $fh "+PostArguments = \"PostAssessment $execrunuid $owner \$\$(UidDomain) \$(CLUSTERID) \$(PROCID) \$\$([NumJobStarts])\"\n";
		print $fh "\n";

		print $fh "### Job Priority\n";
		print $fh "+ViewerJob = false\n";
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
		print $fh "+SWAMP_submit_jobdir = \"$jobdir\"\n";
		print $fh "\n";

		print $fh "### Job Priority Scheduling\n";
		# group_vip_viewer | group_vip_assessment | group_viewer | group_assessment
		print $fh "accounting_group = group_assessment\n";
		my $accounting_group_user = $bogref->{'userid'};
		$accounting_group_user =~ s/\@/-at-/g;
		print $fh "accounting_group_user = $accounting_group_user\n";
		print $fh "\n";

		print $fh "### Queue the job\n";
		print $fh "+SuccessPostExitCode = 0\n";
		print $fh "max_retries = $htcondor_assessment_max_retries\n";
		print $fh "periodic_release = HoldReasonCode == $HTCONDOR_POSTSCRIPT_FAILED && ((NumJobStarts <= $htcondor_assessment_max_retries) && (PostExitCode == $HTCONDOR_POSTSCRIPT_EXIT))\n";
		print $fh "periodic_remove = HoldReasonCode =?= $HTCONDOR_POSTSCRIPT_FAILED && ((NumJobStarts > $htcondor_assessment_max_retries) || (PostExitCode != $HTCONDOR_POSTSCRIPT_EXIT))\n";
		print $fh "job_max_vacate_time = 60\n";
		print $fh "queue\n";
		close($fh);
	}
    my @files = ($bogfile, $submitfile);
    Archive::Tar->create_archive($submitbundle, COMPRESS_GZIP, @files);
	chdir $bogDir;
	listDirectoryContents($jobdir);
	return $jobdir;
}

sub vmu_CreateHTCondorViewerJob { my ($jobtype, $bogref, $bogfile, $submitfile, $job_priority) = @_ ;
    my $execrunuid = $bogref->{'execrunid'};
    my $jobdir = constructJobDirName($jobtype);
    if (! use_make_path($jobdir)) {
		$log->error("Error - make_path failed for: $jobdir");
		return;
	}
	move $bogfile, $jobdir;
	chdir $jobdir;
	if ($bogref->{'use_docker_universe'}) {
		copy(catfile(getSwampDir(), 'etc', 'docker_htcondor_submit'), $submitfile);
	}
	else {
		copy(catfile(getSwampDir(), 'etc', 'vmu_htcondor_submit'), $submitfile);
		create_empty_file("delta.qcow2");
		create_empty_file("inputdisk.qcow2");
		create_empty_file("outputdisk.qcow2");
	}
	my $submitbundle = $execrunuid . '_submitbundle.tar.gz';
	if (open(my $fh, ">>", $submitfile)) {
		my $owner = getpwuid($UID);
		print $fh "\n";
		print $fh "##### Dynamic Submit File Attributes #####";
		print $fh "\n";

		print $fh "### Job events and ip address path\n";
		print $fh "+JOB_EVENTS_PATH = \"$HTCONDOR_JOB_EVENTS_PATH\"\n";
		print $fh "+JOB_IP_ADDRESS_PATH = \"$HTCONDOR_JOB_IP_ADDRESS_PATH\"\n";
		print $fh "\n";

		if ($bogref->{'use_docker_universe'}) {
			my $docker_container = $bogref->{'platform_image'};
            print $fh "### Docker Image\n";
            print $fh "docker_image = " . $docker_container . "\n";
            print $fh "\n";

            print $fh "### No Executable\n";
            print $fh "\n";

            print $fh "### Input File Transfer Settings\n";
            print $fh "transfer_input_files = $submitbundle\n";
            print $fh "\n";
		}
		else {
			print $fh "### Executable\n";
			print $fh "executable = " . construct_vmhostname($execrunuid, '$(CLUSTERID)', '$(PROCID)') . "\n";
			print $fh "\n";

			print $fh "### Input File Transfer Settings\n";
			print $fh "transfer_input_files = delta.qcow2, inputdisk.qcow2, outputdisk.qcow2, $submitbundle\n";
			print $fh "\n";
		}

		print $fh "### Start PRE- and POST- Script Settings\n";
		print $fh "+PreCmd = \"../../opt/swamp/bin/vmu_perl_launcher\"\n";
		print $fh "+PreArguments = \"PreViewer $execrunuid $owner \$\$(UidDomain) \$(CLUSTERID) \$(PROCID) \$\$([NumJobStarts])\"\n";
		print $fh "+PostCmd = \"../../opt/swamp/bin/vmu_perl_launcher\"\n";
		print $fh "+PostArguments = \"PostViewer $execrunuid $owner \$\$(UidDomain) \$(CLUSTERID) \$(PROCID) \$\$([NumJobStarts])\"\n";
		print $fh "\n";

		print $fh "### Job Priority\n";
		print $fh "+ViewerJob = true\n";
		print $fh "priority = $job_priority\n";
		print $fh "\n";

		print $fh "### SWAMP Specific Attributes\n";
		print $fh "+SWAMP_vrun_execrunuid = \"$execrunuid\"\n";
		print $fh "+SWAMP_userid = \"$bogref->{'userid'}\"\n";
		print $fh "+SWAMP_projectid = \"$bogref->{'projectid'}\"\n";
		print $fh "+SWAMP_submit_jobdir = \"$jobdir\"\n";
		print $fh "+SWAMP_viewerinstanceid = \"$bogref->{'viewer_uuid'}\"\n";
		print $fh "\n";

		print $fh "### Job Priority Scheduling\n";
		# group_vip_viewer | group_vip_assessment | group_viewer | group_assessment
		print $fh "accounting_group = group_viewer\n";
		my $accounting_group_user = $bogref->{'userid'};
		$accounting_group_user =~ s/\@/-at-/g;
		print $fh "accounting_group_user = $accounting_group_user\n";
		print $fh "\n";

		print $fh "### Queue the job\n";
		print $fh "job_max_vacate_time = 1200\n";
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
	my $execrunuid = $bogref->{'execrunid'};
	my $clusterid = -1;
	$tracelog->trace("$execrunuid Calling condor_submit");
	$log->debug("condor_submit file: $submitfile cwd: ", getcwd());
	my ($output, $status) = systemcall("condor_submit $submitfile");
	if ($status) {
		$log->warn("Failed to start condor job using $submitfile: $status [$output]");
	}
	else {
		if ($output && $output =~ /submitted\ to\ cluster/sxm) {
			$clusterid = $output;
			$clusterid =~ s/^.*cluster\ //sxm;
			$clusterid =~ s/\..*$//sxm;
			$log->debug("Found cluster id <$clusterid>");
		}
		if ($clusterid == -1) {
			$log->error("submit job failed - no cluster id found");
		}
		else {
			if (! setSubmittedToCondorFlag($execrunuid, 1)) {
				$log->warn("startHTCondorJob: $execrunuid - setSubmittedToCondorFlag 1 failed");
			}
		}
	}
	return $clusterid;
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
	my $jobtype = 'vswamp';
	$bog{'vmhostname'} = $jobtype;
	updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_LAUNCHING, "Creating HTCondor job", \%bog);
	# viewer run priority is +10
	my $job_priority = +10;
	my $submitfile = $execrunuid . '.sub';
	my $jobdir = vmu_CreateHTCondorViewerJob($jobtype, \%bog, $bogfile, $submitfile, $job_priority);
	if (! $jobdir) {
		$log->error("CreateHTCondorViewerJob failed for: $execrunuid");
		return $ret;
	}
	# submit from jobdir
	chdir $jobdir;
	$log->info("runImmediate starting viewer job: $submitfile jobdir: $jobdir");
	my $clusterid = startHTCondorJob(\%bog, $submitfile);
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

