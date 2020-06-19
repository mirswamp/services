#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

use strict;
use warnings;
use English '-no_match_vars';
use File::Copy;
use File::Basename;
use File::Spec::Functions;
use Log::Log4perl::Level;
use Log::Log4perl;
use XML::XPath;

use FindBin qw($Bin);
use lib ("$FindBin::Bin/../perl5", "$FindBin::Bin/lib");

use SWAMP::ScarfXmlReader;
use SWAMP::vmu_Support qw(
	use_make_path
	getStandardParameters
	setHTCondorEnvironment
	identifyScript
	getSwampDir
	getLoggingConfigString
	isSwampInABox
	isMetricRun
	systemcall
	loadProperties
	checksumFile
	construct_vmhostname
	construct_vmdomainname
	computeDirectorySizeInBytes
	getSwampConfig
	$global_swamp_config
	timing_log_assessment_timepoint
	$HTCONDOR_POSTSCRIPT_EXIT
	$HTCONDOR_JOB_INPUT_DIR
	$HTCONDOR_JOB_OUTPUT_DIR
);
use SWAMP::vmu_AssessmentSupport qw(
	updateExecutionResults
	updateClassAdAssessmentStatus
	updateRunStatus
	saveMetricSummary
	saveMetricResult
	saveAssessmentResult
	setCompleteFlag
	$OUTPUT_FILES_CONF_FILE_NAME
	locate_output_files
	parse_statusOut
	isJavaPackage
	isCPackage
	isPythonPackage
	isRubyPackage
	isClocTool
	isSonatypeTool
	isSynopsysC
);

use SWAMP::FrameworkUtils qw(
	generateStatusOutJson
	saveStatusOutJson
);

use SWAMP::mongoDBUtils qw(
	mongoSaveAssessmentResult
);

$global_swamp_config = getSwampConfig();
my $log;
my $tracelog;
my $execrunuid;

my $inputarchive = 'inputdisk.tar.gz';
my $outputarchive = 'outputdisk.tar.gz';
# the output_files hash is populated from $OUTPUT_FILES_CONF_FILE_NAME
# if output_files.conf is not found or not sound, then defaults are used
# for result file names so output_files will always be a defined hash
# note that the hash should not be empty but keys should be tested
my $output_files;

# logfilesuffix is the HTCondor clusterid
my $logfilesuffix = ''; 
sub logfilename {
	my $name = catfile(getSwampDir(), 'log', $execrunuid . '_' . $logfilesuffix . '.log');
	return $name;
}

sub extract_outputdisk { my ($outputfolder) = @_ ;
	my ($output, $status) = systemcall(qq{LIBGUESTFS_BACKEND=direct /usr/bin/guestfish --ro -a outputdisk.qcow2 run : mount /dev/sda / : glob copy-out '/*' $outputfolder});
	if ($status) {
		$log->error("extract_outputdisk - output extraction failed: $output $status");
		return 0;
	}
	return 1;
}

sub unarchive_results { my ($outputfolder, $archive) = @_ ;
	my $results_archive = catfile($outputfolder, $archive);
	my ($output, $status) = systemcall("tar xf $results_archive --directory=$outputfolder");
	if ($status) {
		$log->error("unarchive_results - tar of $results_archive to $outputfolder failed: $output $status");
		return 0;
	}
	return 1;
}

# save parsed SCARF file if extant
sub copy_parsed_results { my ($outputfolder, $resultsfolder) = @_ ;
	if (! defined($output_files->{'parsedResultsConf'})) {
		return (0, '');
	}
	if (! defined($output_files->{'parsedResultsConf'}->{'parsed-results-archive'})) {
		return (0, '');
	}
	if (! unarchive_results($outputfolder, $output_files->{'parsedResultsConf'}->{'parsed-results-archive'})) {
		return (0, '');
	}
	my $parsed_results_dir = $output_files->{'parsedResultsConf'}->{'parsed-results-dir'};
	# weaknesses file does not have to be copied
	my $weaknesses_file = catfile($outputfolder, $parsed_results_dir, "weakness_count.out");
	$weaknesses_file = catfile($outputfolder, $parsed_results_dir, "weaknesses.txt") if (! -r $weaknesses_file);
	if (! -f $weaknesses_file || ! -r $weaknesses_file) {
		$log->warn("copy_parsed_results - $weaknesses_file not found");
		# this is not a failure
	}
	else {
		$log->info("copying: $weaknesses_file to: ", $resultsfolder);
		copy($weaknesses_file, $resultsfolder);
	}
	my $parsed_results_file_name = $output_files->{'parsedResultsConf'}->{'parsed-results-file'};
	my $parsed_results_file = catfile($outputfolder, $parsed_results_dir, $parsed_results_file_name);
	if (! -f $parsed_results_file || ! -r $parsed_results_file) {
		$log->error("copy_parsed_results - $parsed_results_file not found");
		return (0, '');
	}
	$log->info("copying: $parsed_results_file to: ", $resultsfolder);
	copy($parsed_results_file, $resultsfolder);
	return (1, catfile($resultsfolder, $parsed_results_file_name));
}

# save results archive if extant
sub copy_results { my ($outputfolder, $resultsfolder) = @_ ;
	if (! defined($output_files->{'resultsConf'})) {
		return (0, '', '');
	}
	if (! defined($output_files->{'resultsConf'}->{'results-archive'})) {
		return (0, '', '');
	}
	if (! unarchive_results($outputfolder, $output_files->{'resultsConf'}->{'results-archive'})) {
		return (0, '', '');
	}
	my $results_dir = $output_files->{'resultsConf'}->{'results-dir'};
	my $ahc_results_file_name = $output_files->{'resultsConf'}->{'ahc-results-file'};
	my $ahc_results_archive_name = $output_files->{'resultsConf'}->{'ahc-results-archive'};
	my $ahc_results_archive = catfile($outputfolder, $results_dir, $ahc_results_archive_name);
	if (! -f $ahc_results_archive || ! -r $ahc_results_archive) {
		$log->error("copy_results - $ahc_results_archive not found");
		return (0, '', '');
	}
	$log->info("copying: $ahc_results_archive to: ", $resultsfolder);
	copy($ahc_results_archive, $resultsfolder);
	return (1, $ahc_results_file_name, catfile($resultsfolder, $ahc_results_archive_name));
}

sub metricSummaryFunction { my ($href, $execrunuid_ref) = @_ ;
	my $metric_results = { 
		'execrunid' => $$execrunuid_ref
	};
    my $metricSummaries = $href->{'MetricSummaries'};
    foreach my $metricSummary (@$metricSummaries) {
        my $type = $metricSummary->{'Type'};
        my $sum = $metricSummary->{'Sum'};
        $metric_results->{$type} = $sum;
    }
	saveMetricSummary($metric_results);
}

sub parse_metric_loc { my ($execrunuid, $assessment_results_file) = @_ ;
    if (! $assessment_results_file) {
		$log->error("Error - assessment_results_file not specified - unable to obtain lines of code metrics");
		return;
	}
	if (! -r $assessment_results_file) {
		$log->error("Error - assessment_results_file: $assessment_results_file not found - unable to obtain lines of code metrics");
		return;
	}
    my $reader = new SWAMP::ScarfXmlReader($assessment_results_file);
    $reader->SetEncoding('UTF-8');
    $reader->SetMetricSummaryCallback(\&metricSummaryFunction);
	$reader->SetCallbackData(\$execrunuid);
    $reader->Parse();
}

sub coverity_lines_of_code { my ($package_archive_file) = @_ ;
	my $command = "/opt/swamp/thirdparty/cloc --quiet --csv $package_archive_file";
	my ($output, $status) = systemcall($command);
	if ($status) {
		$log->error("coverity_lines_of_code - /opt/swamp/thirdparty/cloc --quiet --csv $package_archive_file failed - output: $output $status");
		return -1;
	}
	my @lines = split "\n", $output;
	# skip blank line and header line
	shift @lines; shift @lines;
	# assume files,language,blank,comment,code
	my $locSum = 0;
	foreach my $line (@lines) {
		chomp $line;
		# my ($files, $language, $blank, $comment, $code) = split ',', $line;
		my (undef, undef, undef, undef, $code) = split ',', $line;
		$locSum += $code if ($code =~ m/^\d+$/);
	}
	return $locSum;
}

# currently we have 3 result types
# SCARF xml - from parsed_results.conf
# Sonatype zip - from results.conf
# error results.tar.gz - for no results
# Coverity is a special case that looks in parsed_results and results

sub preserve_assessment_results { my ($bogref, $framework_said_pass, $outputfolder, $resultsfolder) = @_ ;
	my $retval = 1;
	my $have_results = 0;
	my $assessment_results_file;
	if (isSonatypeTool($bogref)) {
		# add ahc results archive
		# obtain ahc results file - hard coded as index.html for now
		my $index_name;
		my $results_archive;
		($have_results, $index_name, $results_archive) = copy_results($outputfolder, $resultsfolder);
		$log->info("results_archive $results_archive status: $have_results");
		$assessment_results_file = $results_archive;
	}
	else {
		# add parsed_results.xml and weaknesses.txt
		my $parsed_results_file;
		($have_results, $parsed_results_file) = copy_parsed_results($outputfolder, $resultsfolder);
		$log->info("parsed_results_file: $parsed_results_file status: $have_results");
		$assessment_results_file = $parsed_results_file;
	}
	if (! $have_results || ! $framework_said_pass) {
		my $error_results_file = catfile($outputfolder, $output_files->{'resultsConf'}->{'results-archive'});
		if (-f -r $error_results_file) {
			$log->info("copying: $error_results_file to: ", $resultsfolder);
			copy($error_results_file, $resultsfolder);
		}
		else {
			$log->error("preserve_assessment_results - $error_results_file not found");
			$retval = 0;
		}
		$assessment_results_file = catfile($resultsfolder, $outputarchive);
		$log->info("assessment_results_file set to: $assessment_results_file");
	}
	$log->info("returning assessment_results_file: $assessment_results_file");
	return ($retval, $have_results, $assessment_results_file);
}

sub preserve_assessment_data { my ($vmdomainname, $inputfolder, $outputfolder, $resultsfolder) = @_ ;
	my $retval = 1;

	# add inputarchive
	my ($output, $status) = systemcall("tar -cvzf $inputarchive $inputfolder");
	if ($status) {
		$log->error("preserve_assessment_data - tar of $inputfolder failed: $output $status");
		$retval = 0;
	}
	else {
		$log->info("copying: $inputarchive to: ", $resultsfolder);
		copy($inputarchive, $resultsfolder);
	}

	# add versions.txt to output
	my $versions = catfile(getSwampDir(), 'etc', 'versions.txt');
	$log->info("copying: $versions to: ", $outputfolder);
	copy($versions, $outputfolder);

    # add outputarchive
    ($output, $status) = systemcall("tar --exclude='lost+found' -cvzf $outputarchive $outputfolder");
	if ($status) {
        $log->error("preserve_assessment_data - tar of $outputfolder failed: $output $status");
        $retval = 0;
    }
	else {
        $log->info("copying: $outputarchive to: ", $resultsfolder);
        copy($outputarchive, $resultsfolder);
    }

	# add statusOut
	my $status_file = '';
	if (defined($output_files->{'statusOut'})) {
		$status_file = catfile($outputfolder, $output_files->{'statusOut'});
	}
	if (! $status_file || ! -f $status_file || ! -r $status_file) {
		$log->error('preserve_assessment_data - ', $status_file || 'unknown', ' not found');
		$retval = 0;
	}
	else {
		$log->info("copying: $status_file to: ", $resultsfolder);
		copy($status_file, $resultsfolder);
	}
	
	# add runOut
	my $logfile = '';
	my $swamp_run;
	if (defined($output_files->{'runOut'})) {
		$swamp_run = catfile($outputfolder, $output_files->{'runOut'});
	}
	if (! $swamp_run || ! -f $swamp_run || ! -r $swamp_run) {
		$log->error('preserve_assessment_data - ', $swamp_run || 'unknown', ' not found');
		$retval = 0;
	}
	else {
		$log->info("copying: $swamp_run to: ", $resultsfolder);
		copy($swamp_run, $resultsfolder);
		$logfile = catfile($resultsfolder, $output_files->{'runOut'});
	}

	# add package-archive
	my $package_archive_file = '';
	my $fh;
	my $conf = catfile($inputfolder, 'package.conf');
	if (! open($fh, '<', $conf)) {
		$log->error("preserve_assessment_data - read of $conf failed");
		$retval = 0;
	}
	else {
		my @lines = <$fh>;
		close($fh);
		chomp @lines;
		my $package_archive = (split '=', (grep {/package-archive/} @lines)[0])[1];
		my $archive_file = catfile($inputfolder, $package_archive);
		if (! $package_archive) {
			$log->error("preserve_assessment_data - package-archive not found in $conf");
			$retval = 0;
		}
		elsif (! -f -r $archive_file) {
			$log->error("preserve_assessment_data - $archive_file not found");
			$retval = 0;
		}
		else {
			$log->info("copying: $archive_file to: ", $resultsfolder);
			copy($archive_file, $resultsfolder);
			$package_archive_file = catfile($resultsfolder, $package_archive);
		}
	}
	return ($retval, $package_archive_file, $logfile);
}

sub save_results { my ($bogref, $execrunuid, $run_results) = @_ ;
	$log->info('saving pathname: ', $run_results->{'pathname'});
	my $sql_status;
	if (isMetricRun($execrunuid)) {
		$sql_status = saveMetricResult($bogref, $run_results);
		$log->info("saveMetricResult returns: $sql_status called with: ", sub {use Data::Dumper; Dumper($run_results);});
	}
	else {
		$sql_status = saveAssessmentResult($bogref, $run_results);
		$log->info("saveAssessmentResult returns: $sql_status called with: ", sub {use Data::Dumper; Dumper($run_results);});
	}
    my $mongo_status = mongoSaveAssessmentResult($run_results);
	$log->info("mongoSaveAssessmentResult returns: $mongo_status");
	# do not include mongo_status in result
	return $sql_status;
}

########
# Main #
########

# args: execrunuid owner uiddomain clusterid procid numjobstarts [debug]
# execrunuid is global because it is used in logfilename
my ($owner, $uiddomain, $clusterid, $procid, $numjobstarts, $debug) = getStandardParameters(\@ARGV, \$execrunuid);
if (! $execrunuid) {
	# we have no execrunuid for the log4perl log file name
	exit(1);
}
$logfilesuffix = $clusterid if (defined($clusterid));

# Initialize Log4perl
Log::Log4perl->init(getLoggingConfigString());

timing_log_assessment_timepoint($execrunuid, 'post script - start');
$log = Log::Log4perl->get_logger(q{});
$log->level($debug ? $TRACE : $INFO);
$log->info("PostAssessment: $execrunuid Begin");
$tracelog = Log::Log4perl->get_logger('runtrace');
$tracelog->trace("$PROGRAM_NAME ($PID) called with args: @ARGV");
setHTCondorEnvironment();
identifyScript(\@ARGV);

my $vmhostname = construct_vmhostname($execrunuid, $clusterid, $procid);
my $vmdomainname = construct_vmdomainname($owner, $uiddomain, $clusterid, $procid);

my $inputfolder = $HTCONDOR_JOB_INPUT_DIR;
my $outputfolder = $HTCONDOR_JOB_OUTPUT_DIR;

my %bog;
my $bogfile = $execrunuid . '.bog';
loadProperties($bogfile, \%bog);
my $user_uuid = $bog{'userid'} || 'null';
my $projectid = $bog{'projectid'} || 'null';

my $job_status_message_suffix = '';
my $htcondor_assessment_max_retries = $global_swamp_config->get('htcondor_assessment_max_retries') || 3;
if ($numjobstarts > 0) {
	$job_status_message_suffix = " retry($numjobstarts/$htcondor_assessment_max_retries)";
}

my $job_status_message = 'Extracting assessment results' . $job_status_message_suffix;
updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $job_status_message);
if (! $bog{'use_docker_universe'}) {
	my $status = extract_outputdisk($outputfolder);
	if (! $status) {
		$job_status_message = 'Failed to extract assessment results' . $job_status_message_suffix;
		$log->info($job_status_message);
		updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $job_status_message);
	}
}

$job_status_message = 'Post-Processing' . $job_status_message_suffix;
updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $job_status_message);

#####################################
#	Process Assessment statusOut	#
#####################################

# process the statusOut file and possibly the runOut file
my $retry = 0;
my $framework_said_pass = 0;
my $weaknesses;
my $first_failure_task;
$job_status_message = '';
$output_files = locate_output_files($outputfolder, $OUTPUT_FILES_CONF_FILE_NAME);
my $statusOut_file = $output_files->{'statusOut'} || '';
my $statusOut = parse_statusOut(catfile($outputfolder, $statusOut_file));
if (! $statusOut) {
	$job_status_message .= 'Assessment statusOut error';
}
else {
	# attempt to log statusOutContent
	if (defined($statusOut->{'content'})) {
		$log->info("Contents of $statusOut_file:\n$statusOut->{'content'}");
	}
	else {
		$log->warn("Contents of $statusOut_file not found");
	}
	if ($statusOut->{'meta'}->{'all_pass'}) {
		$framework_said_pass = 1;
		$job_status_message .= 'Assessment passed ';
	}
	if ($statusOut->{'meta'}->{'fail_count'} > 0) {
		$job_status_message .= 'Assessment failed ';
		$first_failure_task = $statusOut->{'meta'}->{'first_failure'};
	}
	if ($statusOut->{'meta'}->{'retry'}) {
		$job_status_message .= 'Assessment retry ';
		$retry = 1;
	}
	$weaknesses = $statusOut->{'meta'}->{'weaknesses'};
}
$log->info("Status: $job_status_message");

# if not passed, attempt to log runOut
if (! $statusOut || ($statusOut->{'meta'}->{'fail_count'} > 0)) {
	if ($output_files->{'runOut'}) {
		my $runoutfile = catfile($outputfolder, $output_files->{'runOut'});
		if (-f -r $runoutfile) {
			my ($output, $status) = systemcall("cat $runoutfile");
			if (! $status) {
				$log->info("Contents of $runoutfile:\n", $output);
			}
			else {
				$log->warn("Contents of $runoutfile not found");
			}
		}
		else {
			$log->warn("$runoutfile not readable");
		}
	}
	else {
		$log->warn("Assessment runOut error");
	}
}

# create results folder
my $resultsfolder = catdir($bog{'resultsfolder'}, $execrunuid);
mkdir($resultsfolder);

#################################
#	Preserve Assessment Data	#
#################################

my ($status, $package_archive_file, $logfile) =
	preserve_assessment_data($vmdomainname, $inputfolder, $outputfolder, $resultsfolder);
my $locSum = -1;
if (! $status) {
	$job_status_message = 'Failed to preserve assessment data' . $job_status_message_suffix;
	updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $job_status_message);
}
else {
	if (isSynopsysC(\%bog)) {
		$locSum = coverity_lines_of_code($package_archive_file);
	}
}

#########################################################
#	Produce Assessmant statusOut Analysis Json File		#
#########################################################

my $assessment_report = generateStatusOutJson($outputfolder, $output_files, $statusOut );
my $assessment_report_filename = 'assessment-report.json';
my $assessment_report_filepath = catfile($resultsfolder, $assessment_report_filename);
$status = saveStatusOutJson($assessment_report, $assessment_report_filepath);
if (! $status) {
	$log->error("Error - failed to save assessment report to: $assessment_report_filepath");
}

#############################################################
#	Preserve Assessment Results in Working Filesystem		#
#############################################################

($status, my $have_results, my $assessment_results_file) =
	preserve_assessment_results(\%bog, $framework_said_pass, $outputfolder, $resultsfolder);
if (! $status) {
	$job_status_message = 'Failed to preserve assessment results' . $job_status_message_suffix;
	updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $job_status_message);
}
elsif ($have_results) {
	if (isMetricRun($execrunuid)) {
		if (isClocTool(\%bog)) {
			parse_metric_loc($execrunuid, $assessment_results_file);
		}
	}
}

#####################################################################
#	Save Assessment Results in Database and Store Filesystem		#
#####################################################################

$job_status_message = 'Saving Results' . $job_status_message_suffix;
updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $job_status_message);
my $run_results;
my $out_archive = catfile($resultsfolder, $outputarchive);
if (isMetricRun($execrunuid)) {
	$run_results = {
		'report'			=> $assessment_report,
		'reportpath'		=> $assessment_report_filepath,
		'execrunid'			=> $execrunuid,
		'pathname'			=> $assessment_results_file,
		'sha512sum'			=> checksumFile($assessment_results_file),
		'status_out'		=> $statusOut->{'content'},
		'status_out_error_msg'	=> $first_failure_task,
		'out_archive'		=> $out_archive,
	};
} 
else {
	$run_results = {
		'report'			=> $assessment_report,
		'reportpath'		=> $assessment_report_filepath,
		'execrunid'			=> $execrunuid,
		'weaknesses'		=> $weaknesses,
		'pathname'			=> $assessment_results_file,
		'sha512sum'			=> checksumFile($assessment_results_file),
		'logpathname'		=> $logfile,
		'log512sum'			=> checksumFile($logfile),
		'sourcepathname'	=> $package_archive_file,
		'source512sum'		=> checksumFile($package_archive_file),
		'status_out'		=> $statusOut->{'content'},
		'status_out_error_msg'	=> $first_failure_task,
		'locSum'			=> $locSum,
		'out_archive'		=> $out_archive,
	};
}
my $results_in_db = save_results(\%bog, $execrunuid, $run_results);
if (! $results_in_db) {
	$job_status_message = 'Failed to save assessment results in database' . $job_status_message_suffix;
	updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $job_status_message);
}

#############################################
#	Establish Result Status and Exit Code	#
#############################################

# signal condor to retry this job by exiting with ExitCode != 0
my $CondorExitCode = 0;
my $retries_remaining = 0;
if (! $framework_said_pass || ! $have_results || ! $results_in_db) {
	$job_status_message = 'Finished with Errors';
	# Modifying the job_status_message currently breaks the cli and/or plugins
	# This will be remedied once the complete_flag is used to detect finished jobs
	# $job_status_message .= " ($numjobstarts)" if ($numjobstarts > 0);
	if ($retry) {
		$retries_remaining = $htcondor_assessment_max_retries - $numjobstarts;
		if ($retries_remaining) {
			$job_status_message .= $job_status_message_suffix;
			$job_status_message .= " - Will retry $retries_remaining time";
			$job_status_message .= 's' if ($retries_remaining > 1);
		}
		$CondorExitCode = $HTCONDOR_POSTSCRIPT_EXIT;
	}
	$log->info("Assessment: $execrunuid $job_status_message");
	updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $job_status_message);
	updateRunStatus($execrunuid, $job_status_message, 1);
}
else {
	# no build is specified and source-files > compilable
	# warn not all source files are assessed
	if ($statusOut->{'meta'}->{'no_build'} && ($statusOut->{'meta'}->{'source_files'} > $statusOut->{'meta'}->{'compilable'})) {
		$job_status_message = 'Finished with Warnings';
	}
	# assess step is skipped
	# warn no source files are assessed
	elsif ($statusOut->{'meta'}->{'no_files'}) {
		$job_status_message = 'Finished with Warnings';
	}
	else {
		$job_status_message = 'Finished';
	}
	# Modifying the job_status_message currently breaks the cli and/or plugins
	# This will be remedied once the complete_flag is used to detect finished jobs
	# $job_status_message .= " ($numjobstarts)" if ($numjobstarts > 0);
	$log->info("Assessment: $execrunuid $job_status_message");
	updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $job_status_message);
	updateRunStatus($execrunuid, $job_status_message, 1);
}

#########################
# 	Set Complete Flag	#
#########################

# set complete flag and notify via email iff no retries remaining
if (! $retries_remaining) {
	if (! setCompleteFlag($execrunuid, 1)) {
		$log->warn("Assessment: $execrunuid - setCompleteFlag 1 failed");
	}
	if ($bog{'notify_when_complete_flag'}) {
		my $swamp_api_web_server = $global_swamp_config->get('swamp_api_web_server');
		if (! $swamp_api_web_server) {
			$log->error("assessment notification failed - no swamp_api_web_server found in swamp.conf");
		}
		else {
			my $notify_route = "execution_records/$execrunuid/notify";
			my $post_url = $swamp_api_web_server . '/' . $notify_route;
			my $command = "curl --silent --insecure -H 'Accept: application/json' --header \"Content-Length:0\" -X POST $post_url";
			my ($output, $status) = systemcall($command);
			if ($status || $output) {
				$log->error("$command failed - status: $status output: [$output]");
			}
			else {
				$log->info("$command succeeded - status: $status output: [$output]");
			}
		}
	}
	else {
		$log->debug("Email notification is not turned on for: $execrunuid", sub {use Data::Dumper; Dumper(\%bog);});
	}
}

#########################################
#	Compute Execution Directory Usage	#
#########################################

my $slot_size_end = computeDirectorySizeInBytes();
updateExecutionResults($execrunuid, {'slot_size_end' => $slot_size_end});

#####################
#	Exit Script		#
#####################

$log->info("PostAssessment: $execrunuid Exit $CondorExitCode");
if (! isSwampInABox($global_swamp_config)) {
	my $logfile = logfilename();
	my $central_log_dir = '/swamp/working/logs';
	if (! -d $central_log_dir) {
		if (! use_make_path($central_log_dir)) {
			$log->error("PostAssessment: $execrunuid - unable to create dir: $central_log_dir");
		}
	}
	if (-d $central_log_dir && -r $logfile) {
		copy($logfile, $central_log_dir);
	}
}
timing_log_assessment_timepoint($execrunuid, 'post script - exit');
exit($CondorExitCode);
