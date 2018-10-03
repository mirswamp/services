#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2018 Software Assurance Marketplace

use 5.014;
use utf8;
use warnings;
use strict;

use Cwd qw(getcwd abs_path);
use English '-no_match_vars';
use File::Basename qw(basename fileparse);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec::Functions;
use Getopt::Long qw(GetOptions);
use Log::Log4perl::Level;
use Log::Log4perl;
use Time::localtime;

use FindBin;
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );

use SWAMP::CodeDX qw(uploadanalysisrun);
use SWAMP::ThreadFix qw(threadfix_uploadanalysisrun);
use SWAMP::PackageTypes qw($GENERIC_PKG $JAVABYTECODE_PKG);
use SWAMP::FrameworkUtils qw(generateErrorJson saveErrorJson);
use SWAMP::vmu_Support qw(
	runScriptDetached
	identifyScript
	systemcall
	getLoggingConfigString 
	$global_swamp_config
	getSwampConfig 
	getSwampDir
	makezip
	timetrace_event
	timetrace_elapsed
);
use SWAMP::vmu_ViewerSupport qw(
	$VIEWER_STATE_NO_RECORD
	$VIEWER_STATE_LAUNCHING
	$VIEWER_STATE_READY
	$VIEWER_STATE_ERROR
	needToLaunch
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


my $package_name;    # SWAMP package affiliation == CodeDX project, ThreadFix application
my $package_version; # SWAMP package version
my $tool_name;       # SWAMP Toolname
my $tool_version;	 # SWAMP Tool Version
my $platform_name;	 # SWAMP assessment platform name
my $platform_version;# SWAMP assessment platform version
my $start_date;		 # SWAMP project start date
my $end_date;

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
    'detached!'               => \$asdetached,
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
);

# This is the start of a viewer run so remove the tracelog file if extant
my $tracelogfile = catfile(getSwampDir(), 'log', 'runtrace.log');
truncate($tracelogfile, 0) if (-r $tracelogfile);

Log::Log4perl->init(getLoggingConfigString());
my $log = Log::Log4perl->get_logger(q{});
$log->level($debug ? $TRACE : $INFO);
my $tracelog = Log::Log4perl->get_logger('runtrace');
$tracelog->trace("$PROGRAM_NAME ($PID) called with args: @PRESERVEARGV");
identifyScript(\@PRESERVEARGV);

if ($asdetached && ($viewer_name =~ /CodeDX/ixsm) || ($viewer_name =~ /ThreadFix/ixsm)) {
	print "SUCCESS\n"; # this string is propagated back to the database sys_eval to simply indicate that the script has started
	runScriptDetached();
}
chdir($startupdir);

$log->info("$PROGRAM_NAME ($PID) launchviewer:$viewer_name");

my $exitCode = 0;
if ($viewer_name =~ /Native/ixsm) {
    $exitCode = doNative();
}
elsif ($viewer_name =~ /CodeDX/isxm || $viewer_name =~ /ThreadFix/isxm) {
	my $event_start = timetrace_event($project_uuid, 'viewer', 'launch start'); 
    $exitCode = doViewerVM();
	timetrace_elapsed($project_uuid, 'viewer', 'launch', $event_start);
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
		return 0 if ($state != $VIEWER_STATE_LAUNCHING && $state != $VIEWER_STATE_NO_RECORD);
        sleep $sleep_time;
        $viewerState = getViewerStateFromClassAd($project_uuid, $viewer_name);
        if (defined($viewerState->{'error'}) || ! defined($viewerState->{'state'})) {
            $log->error("uploadResults - Error checking for viewer - project_uuid: $project_uuid viewer_name: $viewer_name");
            return 0;
        }
		$state = $viewerState->{'state'};
    }
    if ($state != $VIEWER_STATE_READY) {
		$log->error('Error launch timed out after ', 60 * $sleep_time, " seconds - project_uuid: $project_uuid viewer_name: $viewer_name");
		return 0;
	}
	if (($viewer_name ne 'ThreadFix') && $package_type && ($package_type ne $JAVABYTECODE_PKG)) {
		push @file_path, $source_archive;
	}
	my $result = 0;
	if ($viewer_name eq 'CodeDX') {
		$log->info("Calling uploadanalysysrun $package_name ", sub {join ', ', map(abs_path($_), @file_path);});
		$result = uploadanalysisrun($viewerState->{'address'}, $viewerState->{'apikey'}, $viewerState->{'urluuid'}, $package_name, \@file_path);
	}
	elsif ($viewer_name eq 'ThreadFix') {
		$log->info("Calling threadfix_uploadanalysysrun $package_name ", sub {join ', ', map(abs_path($_), @file_path);});
		$result = threadfix_uploadanalysisrun($viewerState->{'address'}, $viewerState->{'apikey'}, $viewerState->{'urluuid'}, $package_name, \@file_path);
	}
	if ($result) {
		$log->info("uploaded results - package_name: $package_name viewer_name: $viewer_name");
	}
	else {
		$log->error("Unable to upload results - package_name: $package_name viewer_name: $viewer_name");
	}
	return $result;
}

sub doViewerVM {
	$global_swamp_config ||= getSwampConfig($configfile);
    my $viewerState = getViewerStateFromClassAd($project_uuid, $viewer_name);
	if (defined($viewerState->{'error'}) || ! defined($viewerState->{'state'})) {
		$log->error("doViewerVM - Error checking for viewer - project_uuid: $project_uuid viewer_name: $viewer_name");
		return 1;
	}

    my $removeZip = 0;
    if ($source_archive && $source_archive !~ /\.zip$/sxm) {
		$log->info('original source_archive: ', abs_path($source_archive));
        $source_archive = makezip(abs_path($source_archive));
		$log->info('makezip source_archive: ', abs_path($source_archive));
        # If the name was changed to zip form, remove the zip when finished
        if ( $source_archive =~ /\.zip$/sxm ) {
            $removeZip = 1;
        }
    }

	# if viewer state indicates need to launch then launch new viewer vm 
	my $state = $viewerState->{'state'};
	my $execrunuid = 'vrun_' . $project_uuid . '_' . $viewer_name;
	my $options = {};
	my $launch_result = 1;
	if (needToLaunch($state)) {
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
	unlink $source_archive if ($removeZip);
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

sub doNativeError { my ($file, $outputdir) = @_ ;
	$log->info("doNativeError - processing error result: $file");
	$global_swamp_config ||= getSwampConfig($configfile);
	my $retCode = 0;
	my $JSONname  = q{failedreport.json};
	my ( $htmlfile, $dir, $ext ) = fileparse( $file, qr/\.[^.].*/sxm );
	make_path($outputdir);
	if ( copy( $file, $outputdir )) {
		$log->info("Copied $file to $outputdir ret=[${htmlfile}${ext}]");
		my $topdir = 'out';
		my $reportTime = ctime();
		# save the header information and pass them into the saverepost()
		my @header = ($package_name, $tool_name, $platform_name, $start_date, $package_version, $tool_version, $platform_version, $end_date, $reportTime);
		$topdir = 'output' if ($file =~ m/outputdisk.tar.gz$/);
		my $report = generateErrorJson(catfile($outputdir, $htmlfile . $ext), $topdir, @header);
		my $savereport = catfile($outputdir, $JSONname);
		$log->info("report - file: $savereport url: ", $global_swamp_config->get('reporturl'), ' keys: ', sub{ join ', ', (keys %$report) });
		my$saveResult = saveErrorJson($report, $savereport);
	    if ($saveResult == 0) {
            $log->error("Failed to save the error report json to: $savereport");
        }
		# Do not remove this print statement
		# This is the result returned to the calling program via the shell
		$log->info("doNativeError returns: $JSONname");
		print "${JSONname}\n";
	}
	else {
		$log->error("Cannot copy $file to $outputdir $OS_ERROR");
		print "ERROR Cannot copy $file to $outputdir $OS_ERROR\n";
		$retCode = 3;
	}
	return $retCode;
}

sub doNativeHTML { my ($file, $outputdir) = @_ ;
	$log->info("doNativeHTML - processing html result: $file");
	my $retCode = 0;
	make_path($outputdir);
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
			$log->info("doNativeHTML returns: index.html");
			print "index.html\n";
		}
	}
	return $retCode;
}

sub doNativeSCARF { my ($file, $tool_name) = @_ ;
	$log->info("doNativeSCARF - tool_name: $tool_name");
	my $retCode = 0;
	# constructs the arguments for the JSON parsing call
	my $JSONname   = q{nativereport.json};
	my $JSONPath = catfile($outputdir,$JSONname);
	$tool_name = checkToolStringSpace($tool_name);
	my $toolListPath = catfile(getSwampDir(), 'etc', 'Scarf_ToolList.json');
	my $parsingScript = catfile(getSwampDir(), 'bin', 'vmu_Scarf_CParsing');
	my $reportTime = ctime();
	make_path($outputdir);
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
	my $parsingCmd = $parsingScript . ' -input_file ' . $file . ' -output_file ' . $JSONPath . ' -tool_name ' . $tool_name . ' -tool_list ' . $toolListPath . ' -metadata_path ' . $metaDataPath;
	$log->info('cwd: ', getcwd(), ' command: ', $parsingCmd);
	my ($output, $status) = systemcall($parsingCmd);
	$log->info('Logging from vmu_Scarf_Parsing: ', $output);
	if ($status) {
		$log->error("Parsing the SCARF results into JSON threw an exception status: $status output: $output");
	}
	else {
		# Do not remove this print statement
		# This is the result returned to the calling program via the shell
		$log->info("doNativeSCARF returns: $JSONname");
		print "${JSONname}\n";
	}
	return $retCode;
}

# Native viewer needs to look at the report XML file found in $inputdir
sub doNative {
    # my $r = printPara();
	my $retCode = 0;
    foreach my $file (@file_path) {
		$log->info("doNative - processing file: $file");
		# process SCARF results
        if ($file =~ m/\.xml$/sxmi) {
			$retCode = doNativeSCARF($file, $tool_name);
            next;
        }
		# process SONATYPE results
		elsif ($file =~ m/\.zip$/sxmi) {
			$retCode = doNativeHTML($file, $outputdir);
		}
		# process ERROR results
		elsif ($file =~ m/\.tar\.gz$/sxmi) {
			$retCode = doNativeError($file, $outputdir);
		}
		else {
			$log->error("doNative - cannot process file: $file");
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
