#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

use 5.014;
use utf8;
use warnings;
use strict;

use Cwd qw(getcwd);
use English '-no_match_vars';
use File::Basename qw(basename fileparse);
use File::Copy qw(copy);
use File::Spec::Functions;
use Getopt::Long qw(GetOptions);
use Log::Log4perl::Level;
use Log::Log4perl;
use Time::localtime;

use FindBin;
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );

use SWAMP::CodeDX qw(uploadanalysisrun);
use SWAMP::PackageTypes qw($GENERIC_PKG $JAVABYTECODE_PKG);
use SWAMP::FrameworkUtils qw(
	generateStatusOutJson 
	addHeaderJson
	saveStatusOutJson
);
use SWAMP::vmu_Support qw(
	from_json_file_wrapper
	use_make_path
	use_remove_tree
	runScriptDetached
	setHTCondorEnvironment
	identifyScript
	systemcall
	getLoggingConfigString 
	getSwampDir
	makezip
	getSwampConfig 
	$global_swamp_config
	timing_log_viewer_timepoint
);
use SWAMP::vmu_AssessmentSupport qw(
	$OUTPUT_FILES_CONF_FILE_NAME
	locate_output_files
	parse_statusOut
);
use SWAMP::vmu_ViewerSupport qw(
	$VIEWER_STATE_NO_RECORD
	$VIEWER_STATE_LAUNCHING
	$VIEWER_STATE_STOPPING
	$VIEWER_STATE_READY
	$VIEWER_STATE_ERROR
	$VIEWER_STATE_TERMINATING
	$VIEWER_STATE_TERMINATED
	getViewerStateFromClassAd
	updateClassAdViewerStatus
	launchViewer
);

my $startupdir = getcwd();
my $asdetached   = 1;
my $debug      = 0;

my $inputdir;
my $outputdir;

my $user_uuid;
my $viewer_name;
my $viewer_db_path;
my $viewer_db_checksum;
my $viewer_uuid;
my @file_path;
my $source_archive;
my $project_uuid;    # SWAMP project affiliation
my $configfile;


my $package_name;    # SWAMP package affiliation == CodeDX project
my $package_version; # SWAMP package version
my $tool_name;       # SWAMP Toolname
my $tool_version;	 # SWAMP Tool Version
my $platform_name;	 # SWAMP assessment platform name
my $platform_version;# SWAMP assessment platform version
my $start_date;		 # SWAMP project start date
my $end_date;
my $results_type;	 # results | warnings | errors

my $package_type = $GENERIC_PKG;    # Assume its some sort of source code.

my @PRESERVEARGV = @ARGV;
GetOptions(
	'user_uuid=s'			=> \$user_uuid,
    'viewer_name=s'         => \$viewer_name,
    'viewer_db_path=s'      => \$viewer_db_path,
	'viewer_db_checksum=s'  => \$viewer_db_checksum,
    'viewer_uuid=s'         => \$viewer_uuid,
    'indir=s'               => \$inputdir,
    'file_path=s'           => \@file_path,
    'source_archive_path=s' => \$source_archive,
    'outdir=s'              => \$outputdir,
    'package=s'             => \$package_name,
    'package_type=s'        => \$package_type,
    'project=s'             => \$project_uuid,
    'detached!'             => \$asdetached,
    'debug'                 => \$debug,
	#Header info in NativeViewer
	'package_name=s'		=> \$package_name,
	'package_version=s'		=> \$package_version,
	'tool_name=s'			=> \$tool_name,
	'tool_version=s'		=> \$tool_version,
	'platform_name=s'		=> \$platform_name,
	'platform_version=s'	=> \$platform_version,
	'start_date=s'			=> \$start_date,
	'end_date=s'			=> \$end_date,
	'config=s'				=> \$configfile,
	'results_type=s'		=> \$results_type,
);

# This is the start of a viewer run so remove the tracelog file if extant
my $tracelogfile = catfile(getSwampDir(), 'log', 'runtrace.log');
truncate($tracelogfile, 0) if (-r $tracelogfile);

# Initialize Log4perl
Log::Log4perl->init(getLoggingConfigString());

my $log = Log::Log4perl->get_logger(q{});
$log->level($debug ? $TRACE : $INFO);
my $tracelog = Log::Log4perl->get_logger('runtrace');
$tracelog->trace("$PROGRAM_NAME ($PID) called with args: @PRESERVEARGV");
setHTCondorEnvironment();
identifyScript(\@PRESERVEARGV);

if ($asdetached && ($viewer_name =~ /CodeDX/ixsm)) {
	print "SUCCESS\n"; # this string is propagated back to the database sys_eval to simply indicate that the script has started
	runScriptDetached();
}
chdir($startupdir);

$log->info("$PROGRAM_NAME ($PID) launchviewer:$viewer_name");

my $exitCode = 0;
if ($viewer_name =~ /Native/ixsm) {
    $exitCode = doNative();
}
elsif ($viewer_name =~ /CodeDX/isxm) {
    $exitCode = doViewerVM();
}
else {
    $log->error("viewer '$viewer_name' not supported.");
    $exitCode = 1;
}
exit $exitCode;

sub uploadResults { my ($viewerState, $execrunuid) = @_ ;
	my $sleep_time = 10;
	# poll for viewer ready before results are uploaded
	my $state = $viewerState->{'state'};
    for (my $i = 0; $i < 60; $i++) {
		if ($state == $VIEWER_STATE_READY) {
            $log->info("uploadResults - viewer is ready - project_uuid: $project_uuid viewer_name: $viewer_name");
			last;
		}
        sleep $sleep_time;
        $viewerState = getViewerStateFromClassAd($project_uuid, $viewer_name);
        if (defined($viewerState->{'error'}) || ! defined($viewerState->{'state'})) {
            $log->error("uploadResults - Error checking for viewer - project_uuid: $project_uuid viewer_name: $viewer_name");
            return 0;
        }
		$state = $viewerState->{'state'};
		if (($state != $VIEWER_STATE_READY) && ($state != $VIEWER_STATE_LAUNCHING)) {
            $log->info("uploadResults - viewer is being terminated - project_uuid: $project_uuid viewer_name: $viewer_name");
			return 0;
		}
    }
    if ($state != $VIEWER_STATE_READY) {
		$log->error('Error launch timed out after ', 60 * $sleep_time, " seconds - project_uuid: $project_uuid viewer_name: $viewer_name");
		return 0;
	}
    my $removeZip = 0;
	if ($package_type && ($package_type ne $JAVABYTECODE_PKG) && -r $source_archive) {
		if ($source_archive && $source_archive !~ /\.zip$/sxm && -r $source_archive) {
			$log->info('original source_archive: ', $source_archive);
			$source_archive = makezip($source_archive);
			$log->info('makezip source_archive: ', $source_archive);
			# If the name was changed to zip form, remove the zip when finished
			if ( $source_archive =~ /\.zip$/sxm ) {
				$removeZip = 1;
			}
		}
		push @file_path, $source_archive;
	}
	$log->info("Calling uploadanalysisrun $package_name ", sub {join ', ', map($_, @file_path);});
	my $result = uploadanalysisrun($viewerState->{'address'}, $viewerState->{'apikey'}, $viewerState->{'urluuid'}, $package_name, \@file_path);
	if ($result) {
		$log->info("uploaded results - package_name: $package_name viewer_name: $viewer_name");
	}
	else {
		$log->error("Unable to upload results - package_name: $package_name viewer_name: $viewer_name");
	}
	unlink $source_archive if ($removeZip);
	return $result;
}

sub doViewerVM {
	my $execrunuid = 'vrun_' . $project_uuid . '_' . $viewer_name;
	my $options = {};
	my $launch_result = 1;
    my $viewerState = getViewerStateFromClassAd($project_uuid, $viewer_name);
	# immediately test for error conditions
	if (defined($viewerState->{'error'}) || ! defined($viewerState->{'state'})) {
		$log->error("doViewerVM - Error checking for viewer - project_uuid: $project_uuid viewer_name: $viewer_name");
		return 1;
	}
	my $state = $viewerState->{'state'};
	if (
		($state != $VIEWER_STATE_READY) && 
		($state != $VIEWER_STATE_LAUNCHING) && 
		($state != $VIEWER_STATE_STOPPING) && 
		($state != $VIEWER_STATE_TERMINATING)
	) {
		updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_LAUNCHING, 'Launching Viewer VM', $options);
		$global_swamp_config ||= getSwampConfig($configfile);
		$options = {
			'resultsfolder' => $global_swamp_config->get('resultsFolder'),
			'projectid'     => $project_uuid,
			'viewer'        => $viewer_name,
			'viewer_uuid'   => $viewer_uuid,
			'userid'        => $user_uuid,
		};
		# It is OK to not have a viewer_db_path, it just means this is a NEW VRun VM.
		if (defined($viewer_db_path) && $viewer_db_path ne q{NULL}) {
			$options->{'db_path'} = $viewer_db_path;
		}
		$log->info("Calling launchViewer via RPC project_uuid: $project_uuid viewer_name: $viewer_name");
		# launch viewer vm asynchronously on submit node via rpc
		$launch_result = launchViewer($options);
		if (! $launch_result) {
			$log->error("launchViewer failed - project_uuid: $project_uuid viewer_name: $viewer_name");
			updateClassAdViewerStatus($execrunuid, $VIEWER_STATE_ERROR, 'Launch viewer error', $options);
		}
	}
	my $upload_result = 1;
	if ($launch_result && $package_name) {
		$log->info("Calling uploadResults for: $package_name");
		$upload_result = uploadResults($viewerState, $execrunuid);
	}
    return 0 if ($launch_result && $upload_result);
    return 1;
}

#print the vmu_launchviewr.pl command line arguments
sub printPara {
    $log->info("Start logging the variables...");
    $log->info("$viewer_name");
    $log->info("$viewer_db_path");
    $log->info("$viewer_db_checksum");
    $log->info("$viewer_uuid");
    $log->info("$inputdir");
	$log->info("$outputdir");
   	$log->info("File_path:");
	foreach(@file_path){
		$log->info("$_");
	}
    $log->info("$source_archive");
    $log->info("$project_uuid");
    $log->info("$asdetached");
	$log->info("$debug");
	$log->info("$package_name");
	$log->info("$package_version");
	$log->info("$tool_name");
	$log->info("$tool_version");
	$log->info("$platform_name");
	$log->info("$platform_version");
	$log->info("$start_date");
	$log->info("$end_date");
	$log->info("Ending...");
    return;
}

sub doNativeStatusOut { my ($results_type, $file, $outputdir) = @_ ;
	my $always_generate = 1; # REMOVE - this is for debugging
	$log->info("doNativeStatusOut - processing error file: $file results_type: $results_type outputdir: $outputdir");
	my $retCode = 0;
	if (! use_make_path($outputdir)) {
		$log->error("Error - use_make_path failed for: $outputdir");
		print "ERROR - use_make_path failed for: $outputdir\n";
		$retCode = 3;
		return $retCode;
	}
	if (! copy($file, $outputdir)) {
		$log->warning("Warning - copy: $file to: $outputdir failed - download of failed results will not be available");
	}
	$global_swamp_config ||= getSwampConfig($configfile);
	my ($htmlfile, $inputdir, $ext) = fileparse( $file, qr/\.[^.].*/sxm );
	my $assessment_report_filename = 'assessment-report.json';
	my $assessment_report_filepath = catfile($inputdir, $assessment_report_filename);
	# if assessment-report.json does not exist
	# and outputdisk.tar.gz exists then (this is for backward compatibility)
	# 	unarchive it in outputdir and generate assessment-report.json
	# 	save assessment-report.json in inputdir (this is for forward compatibility)
	# else create failedreport.json from assessment-report.json by adding header to report
	# save failedreport.json in outputdir for web ui
	my $report;
	if ($always_generate || ! -f $assessment_report_filepath || ! -r $assessment_report_filepath) {
		if ($results_type =~ m/warnings/sxmi) {
			$file = catfile($inputdir, 'outputdisk.tar.gz');
		}
		if (! -f $file || ! -r $file) {
			$log->error("Error - $file not found");
			print "ERROR - $file not found\n";
			$retCode = 3;
			return $retCode;
		}
		if ($file !~ m/.tar$|.tar.gz$/) {
			$log->error("Error - $file is not a tar archive");
			print "ERROR - $file is not a tar archive\n";
			$retCode = 3;
			return $retCode;
		}
		my $topdir = catdir($outputdir, 'out');
		if (! -d $topdir) {
			$log->info("Unbundling archive: $file to: $outputdir");
			my $cmd = "tar xf $file -C $outputdir";
			my ($output, $status) = systemcall($cmd);
			if ($status) {
				$log->error("Error - $cmd failed - $output $status $OS_ERROR");
				print "ERROR - $cmd failed - $output $status $OS_ERROR\n";
				$retCode = 3;
				return $retCode;
			}
		}
		else {
			$log->warn("Warning - $topdir already exists");
		}
		my $output_files = locate_output_files($topdir, $OUTPUT_FILES_CONF_FILE_NAME);
		my $statusOut_file = $output_files->{'statusOut'} || '';
		my $statusOut = parse_statusOut(catfile($topdir, $statusOut_file));
		$report = generateStatusOutJson($topdir, $output_files, $statusOut);
		# for forward compatibility
		my $preservereportfilepath = catfile($inputdir, 'assessment-report.json');
		my $saveResult = saveStatusOutJson($report, $preservereportfilepath);
		if (! $saveResult) {
			# this is just a warning because this failure results in the backward 
			# compatibility code being executed next time the report is requested
			$log->warn("Unable to save the error report json to: $preservereportfilepath $OS_ERROR");
		}
		if (! use_remove_tree($topdir)) {
			$log->warn("Warning - use_remove_tree failed for: $topdir");
		}
	}
	else {
		$report = from_json_file_wrapper($assessment_report_filepath);
	}
	my $reportTime = ctime();
	my $header = [
		$package_name, 
		$package_version, 
		$platform_name, 
		$platform_version, 
		$tool_name, 
		$tool_version, 
		$start_date, 
		$end_date, 
		$reportTime,
	];
	addHeaderJson($report, $header);
	my $webreportname = q{failedreport.json};
	my $webreportfilepath = catfile($outputdir, $webreportname);
	$log->info("report - file: $webreportfilepath url: ", $global_swamp_config->get('reporturl'), ' keys: ', sub{ join ', ', (keys %$report) });
	my $saveResult = saveStatusOutJson($report, $webreportfilepath);
	if (! $saveResult) {
		$log->error("Failed to save the error report json to: $webreportfilepath");
		print "Error - cannot save $webreportfilepath\n";
		$retCode = 3;
		return $retCode;
	}
	# Do not remove this print statement
	# This is the result returned to the calling program via the shell
	$log->info("doNativeStatusOut prints to database call: $webreportname");
	print "$webreportname\n";
	return $retCode;
}

sub doNativeHTML { my ($file, $outputdir) = @_ ;
	$log->info("doNativeHTML - processing html result: $file");
	my $retCode = 0;
	if (! use_make_path($outputdir)) {
		$log->error("Error make_path failed for: $outputdir");
		$retCode = 3;
		return $retCode;
	}
	chdir $outputdir;
	# basename of HTML archive
	my $base = basename($file);
	# test for HTML archive and index.html that is served to web browser
	if ((! -r $base) || (! -r 'index.html')) {
		$log->info("Copying $file to $outputdir");
		# archive not found in outputdir so copy it in
		if (! copy($file, $outputdir)) {
			$log->error("Cannot copy $file to $outputdir $OS_ERROR");
			print "ERROR Cannot copy $file to $outputdir $OS_ERROR\n";
			$retCode = 3;
		}
		# if copy succeeded unzip archive
		else {
			# -DD unzip and set all timestamps to current time
			# -K retain SUID/SGID/Tacky
			my ($output, $status) = systemcall("unzip -DD -K $base");
			if ($status) {
				$log->error("Cannot unzip $file to $outputdir - error: $output");
				$retCode = 3;
			}
			else {
				my ($output, $status) = systemcall("chgrp -R --reference=$outputdir $outputdir/*");
				if ($status) {
					$log->error("Cannot chgrp -R contents of $outputdir - error: $output");
					$retCode = 3;
				}
			}
		}
	}
	else {
		$log->info("Found $file in $outputdir");
	}
	# archive successfully unzipped
	if (! $retCode) {
		if (! -r 'index.html') {
			$log->error("Cannot find index.html in $outputdir");
			$retCode = 3;
		}
		else {
			# Do not remove this print statement
			# This is the result returned to the calling program via the shell
			$log->info("doNativeHTML prints to database call: index.html");
			print "index.html\n";
		}
	}
	return $retCode;
}

sub doNativeSCARF { my ($file, $tool_name) = @_ ;
	$log->info("doNativeSCARF - tool_name: $tool_name");
	my $retCode = 0;
	# constructs the arguments for the JSON parsing call
	my $webreportname   = q{nativereport.json};
	my $webreportpath = catfile($outputdir,$webreportname);
	$tool_name = checkToolStringSpace($tool_name);
	my $toolListPath = catfile(getSwampDir(), 'etc', 'Scarf_ToolList.json');
	my $parsingScript = catfile(getSwampDir(), 'bin', 'vmu_Scarf_CParsing');
	my $reportTime = ctime();
	if (! use_make_path($outputdir)) {
		$log->error("Error - make_path failed for: $outputdir");
		$retCode = 2;
		return $retCode;
	}
	# print the metadata information into a tempfile in the outputdir, for the CParsing program
	my $metaDataFile = q{SCARFmetaData};
	my $metaDataPath = catfile($outputdir, $metaDataFile);
	my $fullMetaDataResult = $package_name . "\n" . $tool_name . "\n" . $platform_name . "\n" . $start_date . "\n" . $package_version . "\n" . $tool_version . "\n" . $platform_version . "\n" . $end_date . "\n" . $reportTime . "\n" . 'package_uid' . "\n" . 'package_vesion_uid' . "\n" . 'tool_uid' . "\n" .'tool_version_uid' . "\n" . 'platform_uid' . "\n" . 'platform_version_uid';
	$log->info('Saving the assessment metadata to ', $metaDataPath);
	if(open my $fh, '>', $metaDataPath) {
		print $fh $fullMetaDataResult;
		close $fh;
	}
	else {
		$retCode = 2;
	}
	
	# concatenate strings into a command string and pass into the system call
	# append the assessment_start_time, assessment_end_time and report_generation_time because they are not in the SCARF file
	my $parsingCmd = $parsingScript . ' -input_file ' . $file . ' -output_file ' . $webreportpath . ' -tool_name ' . $tool_name . ' -tool_list ' . $toolListPath . ' -metadata_path ' . $metaDataPath;
	$log->info('cwd: ', getcwd(), ' command: ', $parsingCmd);
	my ($output, $status) = systemcall($parsingCmd);
	$log->info('Logging from vmu_Scarf_Parsing: ', $output);
	if ($status) {
		$log->error("Parsing the SCARF results into JSON threw an exception status: $status output: $output");
	}
	else {
		# Do not remove this print statement
		# This is the result returned to the calling program via the shell
		$log->info("doNativeSCARF prints to database call: $webreportname");
		print "$webreportname\n";
	}
	return $retCode;
}

# Native viewer needs to look at the report XML file found in $inputdir
sub doNative {
    # my $r = printPara();
	my $retCode = 0;
    foreach my $file (@file_path) {
		$log->info("doNative - processing file: $file results_type: $results_type");
		# process SONATYPE results
		if ($file =~ m/\.zip$/sxmi) {
			$retCode = doNativeHTML($file, $outputdir);
		}
		# process SCARF results
        # elsif ($file =~ m/\.xml$/sxmi) {
        elsif ($results_type =~ m/results/sxmi) {
			$retCode = doNativeSCARF($file, $tool_name);
            next;
        }
		# process ERROR results
		# elsif ($file =~ m/\.tar\.gz$/sxmi) {
		elsif (($results_type =~ m/errors/sxmi) || ($results_type =~ m/warnings/sxmi)) {
			$retCode = doNativeStatusOut($results_type, $file, $outputdir);
		}
		else {
			$log->error("doNative - cannot process file: $file results_type: $results_type");
			$retCode = 3;
		}
    }
    return $retCode;
}

# Split the toolname with space if there is space
# Returns the first string after split
sub checkToolStringSpace {
	my $toolName = shift;
	my @array = split(' ', $toolName);
	return $array[0];
}

sub logfilename {
    (my $name = $PROGRAM_NAME) =~ s/\.pl//sxm;
    $name = basename($name);
    return catfile(getSwampDir(), 'log', $name . '.log');
}
