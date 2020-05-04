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
);
use SWAMP::vmu_AssessmentSupport qw(
	updateExecutionResults
	updateClassAdAssessmentStatus
	updateRunStatus
	saveMetricSummary
	saveMetricResult
	saveAssessmentResult
	setCompleteFlag
	isJavaPackage
	isCPackage
	isPythonPackage
	isRubyPackage
	isClocTool
	isSonatypeTool
	isSynopsysC
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

# logfilesuffix is the HTCondor clusterid
my $logfilesuffix = ''; 
sub logfilename {
	my $name = catfile(getSwampDir(), 'log', $execrunuid . '_' . $logfilesuffix . '.log');
	return $name;
}

sub extract_outputdisk { my ($outputfolder) = @_ ;
	# my $gfname = 'extract.gf';
	# if (open(my $fh, '>', $gfname)) {
		# print $fh "add-ro outputdisk.qcow2\n";
		# print $fh "run\n";
		# print $fh "mount /dev/sda /\n";
		# print $fh "glob copy-out /* $outputfolder\n";
		# close($fh);
	# }
	# else {
		# $log->error("extract_outputdisk - open failed for: $gfname");
		# return 0;
	# }
	# my ($output, $status) = systemcall("/usr/bin/guestfish -f $gfname");
	my ($output, $status) = systemcall(qq{/usr/bin/guestfish --ro -a outputdisk.qcow2 run : mount /dev/sda / : glob copy-out '/*' $outputfolder});
	if ($status) {
		$log->error("extract_outputdisk - output extraction failed: $output $status");
		return 0;
	}
	return 1;
}

# -1 open failure
# 0  no status
# 1  PASS
# 2  FAIL
# 4  retry
sub parse_status_output { my ($outputfolder) = @_ ;
	my $status = -1;
	my $weaknesses;
	my $first_failure_task = '';
	my $fh;
	my $status_file = catfile($outputfolder, 'status.out');
	if (! open($fh, '<', $status_file)) {
		$log->error("parse_status_output - read of $status_file failed");
		return ($status, undef);
	}
	my @lines = <$fh>;
	close($fh);
	$status = 0;
	foreach my $line (@lines) {
		if ($line =~ m/^PASS:\s*all/sxm) {
			$log->info("parse_status_output - status.out: $line");
			$status |= 1;
		}
		elsif ($line =~ m/^FAIL:/sxm) {
			$log->info("parse_status_output - status.out: $line");
			$status |= 2;
			if (! $first_failure_task) {
				my @parts = split ' ', $line;
				$first_failure_task = $parts[1];
			}
		}
		elsif ($line =~ m/^NOTE:\s*retry/sxm) {
			$log->info("parse_status_output - status.out: $line");
			$status |= 4;
		}
		elsif ($line =~ m/parse-results\s*\(weaknesses\s*:\s*(\d+)\)/sxm) {
			$log->info("parse_status_output - weaknesses: $1");
			$weaknesses = $1;
		}
	}
	return ($status, $weaknesses, $first_failure_task);
}

sub load_config { my ($outputfolder, $configfilename) = @_ ;
	my $configfile = catfile($outputfolder, $configfilename);
	if (! -r $configfile) {
		$log->warn("load_config - $configfile not found");
		return;
	}
	my $config = loadProperties($configfile);
	if (! defined($config)) {
		$log->error("load_config - failed to read $configfile");
		return;
	}
	return $config;
}

sub unarchive_results { my ($outputfolder, $config, $archive) = @_ ;
	my $results_archive = catfile($outputfolder, $config->get($archive));
	my ($output, $status) = systemcall("tar xf $results_archive --directory=$outputfolder");
	if ($status) {
		$log->error("unarchive_results - tar of $results_archive to $outputfolder failed: $output $status");
		return 0;
	}
	return 1;
}

# save parsed SCARF file if extant
sub copy_parsed_results { my ($outputfolder, $resultsfolder) = @_ ;
	my $config = load_config($outputfolder, 'parsed_results.conf');
	if (! $config) {
		return(0, '');
	}
	if (! unarchive_results($outputfolder, $config, 'parsed-results-archive')) {
		return (0, '');
	}
	my $parsed_results_dir = $config->get('parsed-results-dir');
	my $weaknesses_file = catfile($outputfolder, $parsed_results_dir, "weaknesses.txt");
	if (! -r $weaknesses_file) {
		$log->error("copy_parsed_results - $weaknesses_file not found");
		# this is not a failure
	}
	else {
		$log->info("copying: $weaknesses_file to: ", $resultsfolder);
		copy($weaknesses_file, $resultsfolder);
	}
	my $parsed_results_file_name = $config->get('parsed-results-file');
	my $parsed_results_file = catfile($outputfolder, $parsed_results_dir, $parsed_results_file_name);
	if (! -r $parsed_results_file) {
		$log->error("copy_parsed_results - $parsed_results_file not found");
		return (0, '');
	}
	$log->info("copying: $parsed_results_file to: ", $resultsfolder);
	copy($parsed_results_file, $resultsfolder);
	return (1, catfile($resultsfolder, $parsed_results_file_name));
}

# save results archive if extant
sub copy_results { my ($outputfolder, $resultsfolder) = @_ ;
	my $config = load_config($outputfolder, 'results.conf');
	if (! $config) {
		return(0, '', '');
	}
	if (! unarchive_results($outputfolder, $config, 'results-archive')) {
		return (0, '', '');
	}
	my $results_dir = $config->get('results-dir');
	my $ahc_results_file_name = $config->get('ahc-results-file');
	my $ahc_results_archive_name = $config->get('ahc-results-archive');
	my $ahc_results_archive = catfile($outputfolder, $results_dir, $ahc_results_archive_name);
	if (! -r $ahc_results_archive) {
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

sub old_coverity_lines_of_code { my ($outputfolder) = @_ ;
	my $config = load_config($outputfolder, 'results.conf');
	if (! $config) {
		return -1;
	}
	if (! unarchive_results($outputfolder, $config, 'results-archive')) {
		return -1;
	}
    my $results_dir = $config->get('results-dir');
    my $assessment_summary_name = $config->get('assessment-summary-file');
    my $assessment_summary_file = catfile($outputfolder, $results_dir, $assessment_summary_name);
    if (! -r $assessment_summary_file) {
        return -1;
    }   
    my $xp = XML::XPath->new(filename => $assessment_summary_file);
    my $nodeset = $xp->find('/assessment-summary/assessment-artifacts/assessment/stdout');
    my $locSum;
    foreach my $node ($nodeset->get_nodelist) {
        my $file = $node->string_value();
        my $locfile = catfile($outputfolder, $results_dir, $file);
        if (open(my $fh, '<', $locfile)) {
            while (my $line = <$fh>) {
                if ($line =~ m/Total LoC input to cov-analyze\s*:\s*(\d+)/) {
                    $locSum += $1; 
                    last;
                }
            }
        }
    }   
	return -1 if (! defined($locSum));
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
		my $error_results_file = catfile($outputfolder, 'results.tar.gz');
		if (-r $error_results_file) {
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

	# create vmlog directory and move files
	# <vmdomainname>.log from /var/log/libvirt/qemu for command line definition of vm
	# messages and boot.log from /var/log in vm
	my $vmlog = catdir($resultsfolder, "vmlog");
	if (mkdir($vmlog)) {
		# /var/log/libvirt/qemu/<vmdomainname>.log
		# my ($output, $status) = systemcall("find /var/log/libvirt/qemu -name ${vmdomainname}.log");
		# my $vmdeflog = '';
		# if (! $status) {
			# $vmdeflog = $output;
			# chomp $vmdeflog;
			# if ($vmdeflog && -r $vmdeflog) {
				# $log->info("copying: $vmdeflog to: ", $vmlog);
				# copy($vmdeflog, $vmlog);
			# }
		# }
		# /var/log/messages
		my $mlog = catfile($outputfolder, 'messages');
		if (-r $mlog) {
			$log->info("copying: $mlog to: ", $vmlog);
			copy($mlog, $vmlog);
		}
		# /var/log/boot.log
		my $blog = catfile($outputfolder, 'boot.log');
		if (-r $blog) {
			$log->info("copying: $blog to: ", $vmlog);
			copy($blog, $vmlog);
		}
		# dumpxml <vmdomainname> from monitor
		if ($vmdomainname) {
			my $vmxml = catfile($outputfolder, $vmdomainname . '_dump.xml');
			if (-r $vmxml) {
				$log->info("copying: $vmxml to: ", $vmlog);
				copy($vmxml, $vmlog);
			}
		}
	}

	# add versions.txt to output
	my $versions = catfile(getSwampDir(), 'etc', 'versions.txt');
	$log->info("copying: $versions to: ", $outputfolder);
	copy($versions, $outputfolder);

    # add outputarchive
    # my $using_gnu_tar = 0;
    # ($output, $status) = systemcall('tar --version');
    # if ($output =~ /GNU tar/smi) {
        # $log->info('We appear to be using GNU tar');
        # $using_gnu_tar = 1;
    # }
    ($output, $status) = systemcall("tar --exclude='lost+found' -cvzf $outputarchive $outputfolder");
    # if ($using_gnu_tar && $status == 1) {
        # $log->warn("preserve_assessment_data - tar of $outputfolder encountered potential problem: $output $status");
        # $retval = 0;
    # }
    # els
	if ($status) {
        $log->error("preserve_assessment_data - tar of $outputfolder failed: $output $status");
        $retval = 0;
    }
    # if (-r $outputarchive) {
	else {
        $log->info("copying: $outputarchive to: ", $resultsfolder);
        copy($outputarchive, $resultsfolder);
    }

	# add status.out
	my $status_file = catfile($outputfolder, 'status.out');
	if (! -r $status_file) {
		$log->error("preserve_assessment_data - $status_file not found");
		$retval = 0;
	}
	else {
		$log->info("copying: $status_file to: ", $resultsfolder);
		copy($status_file, $resultsfolder);
	}
	
	# add swamp_run.out
	my $logfile = '';
	my $swamp_run = catfile($outputfolder, 'swamp_run.out');
	if (! -r $swamp_run) {
		$log->error("preserve_assessment_data - $swamp_run not found");
		$retval = 0;
	}
	else {
		$log->info("copying: $swamp_run to: ", $resultsfolder);
		copy($swamp_run, $resultsfolder);
		$logfile = catfile($resultsfolder, 'swamp_run.out');
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
		elsif (! -r $archive_file) {
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

sub save_results_in_database { my ($bogref, $execrunuid, $weaknesses, $assessment_results_file, $logfile, $package_archive_file, $status_out, $first_failure_task, $locSum) = @_ ;
	$log->info("saving pathname: $assessment_results_file");
	my $sql_status;
	my $run_results;
	if (isMetricRun($execrunuid)) {
		$run_results = {
			'execrunid'			=> $execrunuid,
			'pathname'			=> $assessment_results_file,
			'sha512sum'			=> checksumFile($assessment_results_file),
			'status_out'		=> $status_out,
			'status_out_error_msg'	=> $first_failure_task,
		};
		$sql_status = saveMetricResult($bogref, $run_results);
		$log->info("saveMetricResult returns: $sql_status called with: ", sub {use Data::Dumper; Dumper($run_results);});
	}
	else {
		$run_results = {
			'execrunid'			=> $execrunuid,
			'weaknesses'		=> $weaknesses,
			'pathname'			=> $assessment_results_file,
			'sha512sum'			=> checksumFile($assessment_results_file),
			'logpathname'		=> $logfile,
			'log512sum'			=> checksumFile($logfile),
			'sourcepathname'	=> $package_archive_file,
			'source512sum'		=> checksumFile($package_archive_file),
			'status_out'		=> $status_out,
			'status_out_error_msg'	=> $first_failure_task,
			'locSum'			=> $locSum,
		};
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

my $inputfolder = q{input};
my $outputfolder = q{output};

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
my $status = extract_outputdisk($outputfolder);
if (! $status) {
	$job_status_message = 'Failed to extract assessment results' . $job_status_message_suffix;
	$log->info($job_status_message);
	updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $job_status_message);
}

$job_status_message = 'Post-Processing' . $job_status_message_suffix;
updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $job_status_message);
# attempt to log status.out
my $status_out = '';
my $status_file = catfile($outputfolder, 'status.out');
if (-r $status_file) {
	my ($output, $status) = systemcall("cat $status_file");
	if (! $status) {
		$log->info("Contents of status.out:\n", $output);
		$status_out = $output;
	}
	else {
		$log->warn("Contents of status.out not found");
	}
}
# -1 open failure
# 0  no status
# 1  PASS
# 2  FAIL
# 4  retry
my $retry = 0;
($status, my $weaknesses, my $first_failure_task) = parse_status_output($outputfolder);
my $framework_said_pass = ($status == 1);
$job_status_message = '';
if ($status < 0) {
	$job_status_message .= 'Failed to parse status.out';
}
elsif ($status) {
	if ($status & 1) {
		$job_status_message .= 'Assessment passed ';
	}
	if ($status & 2) {
		$job_status_message .= 'Assessment failed ';
	}
	if ($status & 4) {
		$job_status_message .= 'Assessment retry ';
		$retry = 1;
	}
}
else {
	$job_status_message .= 'Assessment status.out not found ';
}
$log->info("Status: $job_status_message");
# if not passed, attempt to log run.out
if (! $status || ! ($status & 1)) {
	my $runoutfile = catfile($outputfolder, 'run.out');
	if (-r $runoutfile) {
		my ($output, $status) = systemcall("cat $runoutfile");
		if (! $status) {
			$log->info("Contents of run.out:\n", $output);
		}
		else {
			$log->warn("Contents of run.out not found");
		}
	}
}

# create results folder
my $resultsfolder = catdir($bog{'resultsfolder'}, $execrunuid);
mkdir($resultsfolder);

($status, my $package_archive_file, my $logfile) =
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

$job_status_message = 'Saving Results' . $job_status_message_suffix;
updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $job_status_message);
my $results_in_db = save_results_in_database(\%bog, $execrunuid, $weaknesses, $assessment_results_file, $logfile, $package_archive_file, $status_out, $first_failure_task, $locSum);
if (! $results_in_db) {
	$job_status_message = 'Failed to save assessment results in database' . $job_status_message_suffix;
	updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $job_status_message);
}

# signal condor to retry this job by exiting with ExitCode != 0
my $CondorExitCode = 0;
my $retries_remaining = 0;
if (! $framework_said_pass || ! $have_results || ! $results_in_db) {
	$job_status_message = 'Finished with Errors';
	if ($retry) {
		$retries_remaining = $htcondor_assessment_max_retries - $numjobstarts;
		if ($retries_remaining) {
			$job_status_message .= $job_status_message_suffix;
			$job_status_message .= " - Will retry $retries_remaining time";
			$job_status_message .= 's' if ($retries_remaining > 1);
		}
		$CondorExitCode = $HTCONDOR_POSTSCRIPT_EXIT;
	}
	$log->error("Assessment: $execrunuid $job_status_message");
	updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $job_status_message);
	updateRunStatus($execrunuid, $job_status_message, 1);
}
else {
	$job_status_message = 'Finished';
	$log->info("Assessment: $execrunuid $job_status_message");
	updateClassAdAssessmentStatus($execrunuid, $vmhostname, $user_uuid, $projectid, $job_status_message);
	updateRunStatus($execrunuid, $job_status_message, 1);
}

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

my $slot_size_end = computeDirectorySizeInBytes();
updateExecutionResults($execrunuid, {'slot_size_end' => $slot_size_end});

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
