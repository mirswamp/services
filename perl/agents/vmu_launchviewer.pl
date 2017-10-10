#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2017 Software Assurance Marketplace

use 5.014;
use utf8;
use warnings;
use strict;

use Cwd qw(getcwd abs_path);
use English '-no_match_vars';
use File::Basename qw(basename fileparse);
use File::Copy qw(cp);
use File::Path qw(make_path);
use File::Spec qw(devnull);
use File::Spec::Functions;
use File::stat;
use Getopt::Long qw(GetOptions);
use Log::Log4perl::Level;
use Log::Log4perl;
use POSIX qw(setsid);
use XML::LibXML;
use XML::LibXSLT;
use XML::DOM;
use Time::localtime;

use FindBin;
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );

use SWAMP::CodeDX qw(uploadanalysisrun);
use SWAMP::ThreadFix qw(threadfix_uploadanalysisrun);
use SWAMP::vmu_PackageTypes qw($GENERIC_PKG $JAVABYTECODE_PKG);
use SWAMP::vmu_FrameworkUtils qw(generatereport savereport);
use SWAMP::vmu_Support qw(
	identifyScript
	systemcall
	getLoggingConfigString 
	getSwampConfig 
	getSwampDir
	makezip
);
use SWAMP::vmu_ViewerSupport qw(
	$VIEWER_STATE_NO_RECORD
	$VIEWER_STATE_LAUNCHING
	$VIEWER_STATE_READY
	$VIEWER_STATE_STOPPING
	$VIEWER_STATE_JOBDIR_FAILED
	$VIEWER_STATE_SHUTDOWN
	$VIEWER_STATE_TERMINATING
	$VIEWER_STATE_TERMINATED
	$VIEWER_STATE_TERMINATE_FAILED
	getViewerStateFromClassAd
	launchViewer
);

use constant 'OK'      => 	1;
use constant 'NOTOK'   =>	0;
use constant 'ERROR'   =>  -1;
use constant 'TIMEOUT' =>	2;

my $startupdir = getcwd();
my $asdaemon   = 1;
my $debug      = 0;

#** @var $inputdir The absolute path location where raw results can currently be found.
my $inputdir;

#** @var $outputdir optional folder into which results will be written. Currently this is only for the Native viewer
my $outputdir;

#** @var $viewer_name The textual name of the view to invoke. Native, CodeDX, or ThreadFix.
my $viewer_name;
my $invocation_cmd;
my $sign_in_cmd;
my $add_user_cmd;
my $add_result_cmd;
my $viewer_path;
my $viewer_checksum;
my $viewer_db_path;
my $viewer_db_checksum;
my $viewer_uuid;
my @file_path;
my $source_archive;
my $project_name;    # SWAMP project affiliation


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
    'viewer_name=s'         => \$viewer_name,
    'invocation_cmd=s'      => \$invocation_cmd,
    'sign_in_cmd=s'         => \$sign_in_cmd,
    'add_user_cmd=s'        => \$add_user_cmd,
    'add_result_cmd=s'      => \$add_result_cmd,
    'viewer_path=s'         => \$viewer_path,
    'viewer_checksum=s'     => \$viewer_checksum,
    'viewer_db_path=s'      => \$viewer_db_path,
	'viewer_db_checksum=s'  => \$viewer_db_checksum,
    'viewer_uuid=s'         => \$viewer_uuid,
    'indir=s'               => \$inputdir,
    'file_path=s'           => \@file_path,
    'source_archive_path=s' => \$source_archive,
    #'tool_name=s'           => \$tool_name,
    'outdir=s'              => \$outputdir,
    'package=s'             => \$package_name,
    'package_type=s'        => \$package_type,
    'project=s'             => \$project_name,
    'daemon!'               => \$asdaemon,
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

if ($asdaemon && ($viewer_name =~ /CodeDX/ixsm) || ($viewer_name =~ /ThreadFix/ixsm)) {
	print "SUCCESS\n"; # this string is propagated back to the database sys_eval to simply indicate that the script has started
    chdir(q{/});
    if (! open(STDIN, '<', File::Spec->devnull)) {
		$log->error("prefork - open STDIN to /dev/null failed: $OS_ERROR");
		exit ERROR;
	}
    if (! open(STDOUT, '>', File::Spec->devnull)) {
		$log->error("prefork - open STDOUT to /dev/null failed: $OS_ERROR");
		exit ERROR;
	}
    my $pid = fork();
	if (! defined($pid)) {
		$log->error("fork failed: $OS_ERROR");
		exit ERROR;
	}
    if ($pid) {
    	# parent
		exit(0);
	}
	# child
    if (setsid() == -1) {
		$log->error("child - setsid failed: $OS_ERROR");
		exit ERROR;
	}
    if (! open(STDERR, ">&STDOUT")) {
 		$log->error("child - open STDERR to STDOUT failed:$OS_ERROR");
		exit ERROR;
	}
}
chdir($startupdir);

$log->info("$PROGRAM_NAME ($PID) launchviewer:$viewer_name");

my $exitCode = 0;
if ($viewer_name =~ /Native/ixsm) {
    $exitCode = doNative();
}
elsif ($viewer_name =~ /CodeDX/isxm || $viewer_name =~ /ThreadFix/isxm) {
    $exitCode = doViewerVM();
}
else {
    $log->error("viewer '$viewer_name' not supported.");
    $exitCode = 1;
}
exit $exitCode;

sub doViewerVM {
	my $config = getSwampConfig();
    my $retCode = NOTOK;
	my $sleep_time = 10;

    my $viewerState = getViewerStateFromClassAd($project_name, $viewer_name);
	if (defined($viewerState->{'error'}) || ! defined($viewerState->{'state'})) {
		$log->error("Error checking for viewer - project_name: $project_name viewer_name: $viewer_name");
		return ERROR;
	}

    my $removeZip = 0;
    if ($source_archive && $source_archive !~ /\.zip$/sxm) {
		$log->info("original source_archive: $source_archive");
        $source_archive = makezip(abs_path($source_archive));
		$log->info("makezip source_archive: $source_archive");
        # If the name was changed to zip form, remove the zip when finished
        if ( $source_archive =~ /\.zip$/sxm ) {
            $removeZip = 1;
        }
    }

	# if viewer is not ready or launching then launch it
	my $state = $viewerState->{'state'};
	if ($state != $VIEWER_STATE_READY && $state != $VIEWER_STATE_LAUNCHING) {
		my %launchMap = (
			'resultsfolder' => $config->get('resultsFolder'),
			'projectid'     => $project_name,
			'viewer'        => $viewer_name,
			'viewer_uuid'   => $viewer_uuid,
		);
		# It is OK to not have a viewer_db_path, it just means this is a NEW VRun VM.
		if (defined($viewer_db_path) && $viewer_db_path ne q{NULL}) {
			$launchMap{'db_path'} = $viewer_db_path;
		}
		$log->info("Calling launchViewer via RPC project_name: $project_name viewer_name: $viewer_name");
		$retCode = launchViewer(\%launchMap);
        if ($retCode != OK) {
            $log->error("launchViewer failed - project_name: $project_name viewer_name: $viewer_name return: $retCode");
			unlink $source_archive if ($removeZip);
			return $retCode;
        }
	}

	# poll for viewer ready
    for (my $i = 0; $i < 60; $i++) {
		if ($state == $VIEWER_STATE_READY) {
            $log->info("viewer is ready - project_name: $project_name viewer_name: $viewer_name");
			last;
		}
		if (($state == $VIEWER_STATE_TERMINATING) || ($state == $VIEWER_STATE_TERMINATED)){
            $log->info("viewer is terminated by user - project_name: $project_name viewer_name: $viewer_name");
			# terminate could still fail here
			return 0;
		}
		if ($state == $VIEWER_STATE_TERMINATE_FAILED) {
            $log->info("viewer user terminate failed - project_name: $project_name viewer_name: $viewer_name");
			return ERROR;
		}
        sleep $sleep_time;
        $viewerState = getViewerStateFromClassAd($project_name, $viewer_name);
        if (defined($viewerState->{'error'}) || ! defined($viewerState->{'state'})) {
            $log->error("Error checking for viewer - project_name: $project_name viewer_name: $viewer_name");
			unlink $source_archive if ($removeZip);
            return ERROR;
        }
		$state = $viewerState->{'state'};
    }
    if ($state != $VIEWER_STATE_READY) {
		$log->error('Error launch timed out after ', 60 * $sleep_time, "seconds - project_name: $project_name viewer_name: $viewer_name");
		unlink $source_archive if ($removeZip);
		return TIMEOUT;
	}
	if ($package_name) {
		if ($viewer_name ne 'ThreadFix' && $package_type && $package_type ne $JAVABYTECODE_PKG) {
			push @file_path, $source_archive;
		}
		if ($viewer_name eq 'CodeDX') {
			$log->info("Calling uploadanalysysrun $package_name ", sub { use Data::Dumper; Dumper(\@file_path); });
			$retCode = uploadanalysisrun($viewerState->{'address'}, $viewerState->{'apikey'}, $viewerState->{'urluuid'}, $package_name, \@file_path);
		}
		elsif ($viewer_name eq 'ThreadFix') {
			$log->info("Calling threadfix_uploadanalysysrun $package_name ", sub { use Data::Dumper; Dumper(\@file_path); });
			$retCode = threadfix_uploadanalysisrun($viewerState->{'address'}, $viewerState->{'apikey'}, $viewerState->{'urluuid'}, $package_name, \@file_path);
		}
		if ($retCode == OK) {
			$log->info("uploaded results - package_name: $package_name viewer_name: $viewer_name");
		}
		else {
			$log->error("Unable to upload results - package_name: $package_name viewer_name: $viewer_name return: $retCode");
		}
	}
    if ($retCode == OK) {
        $retCode = 0;
    }
    elsif ($retCode == NOTOK) {
        $retCode = 1;
    }
	unlink $source_archive if ($removeZip);
    return $retCode;
}

#print the vmu_launchviewr.pl command line arguments
sub printPara {
    $log->info("Start logging the variables...");
    $log->info("$viewer_name");
    $log->info("$invocation_cmd");
    $log->info("$sign_in_cmd");
    $log->info("$add_user_cmd");
    $log->info("$add_result_cmd");
    $log->info("$viewer_path");
    $log->info("$viewer_checksum");
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
    $log->info("$tool_name");
    $log->info("$package_name");
    $log->info("$project_name");
    $log->info("$asdaemon");
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
	my $config = getSwampConfig();
	my $retCode = 0;
	my ( $htmlfile, $dir, $ext ) = fileparse( $file, qr/\.[^.].*/sxm );
	make_path($outputdir);
	if ( cp( $file, $outputdir )) {
		$log->info("Copied $file to $outputdir ret=[${htmlfile}${ext}]");
		my $topdir = 'out';
		$topdir = 'output' if ($file =~ m/outputdisk.tar.gz$/);
		my $report = generatereport(catfile($outputdir, $htmlfile . $ext), $topdir);
		my $savereport = catfile($outputdir, 'assessmentreport.html');
		$log->info("report - file: $savereport url: ", $config->get('reporturl'), ' keys: ', sub{ join ', ', (keys %$report) });
		# save the header information and pass them into the saverepost()
		my @header = ($package_name, $tool_name, $platform_name, $start_date, $package_version, $tool_version, $platform_version, $end_date);
		savereport($report, $savereport, $config->get('reporturl'),\@header);
		system("/bin/chmod 644 $savereport");
		# Do not remove this print statement
		# This is the result returned to the calling program via the shell
		$log->info("doNativeError returns: assessmentreport.html");
		print "assessmentreport.html\n";
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
	if (! -r $base) {
		$log->info("Copying $file to $outputdir");
		# archive not found in outputdir so copy it in
		if (! cp($file, $outputdir)) {
			$log->error("Cannot copy $file to $outputdir $OS_ERROR");
			print "ERROR Cannot copy $file to $outputdir $OS_ERROR\n";
			$retCode = 3;
		}
		# if copy succeeded unzip archive
		else {
			my ($output, $status) = systemcall("unzip $base");
			if ($status) {
				$log->error("Cannot unzip $file to $outputdir - error: $output");
				$retCode = 3;
			}
		}
	}
	else {
		$log->info("Found $file in $outputdir");
	}
	# archive successfully unzipped
	if (! $retCode) {
		if (! -r "index.html") {
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
	$log->info("doNativeSCARF - processing xml result: $file");
	my $retCode = 0;
	my $isCommon = 1;
	if ( system("head $file|grep -q '<AnalyzerReport'") != 0 ) {
		$isCommon = 0;
	}
	my $xsltfile = getXSLTFile( $tool_name, $isCommon );
	$log->info("Transforming $tool_name $file with $xsltfile");

	my $xslt = XML::LibXSLT->new();
	my $source;

	# Wrap this in an eval to catch any exceptions parsing output from the assessment.
	my $success = eval { $source = XML::LibXML->load_xml( 'location' => $file ); };
	
	if ( defined($success) ) {
		my $style_doc;  
		# wrap the load style_doc in an eval to catch any exceptions
		my $xslt_success = eval { $style_doc = XML::LibXML->load_xml( 'location' => "$xsltfile", 'no_cdata' => 1 ); };
		if( defined($xslt_success)){
			# save the elements to insert
			# my $file_creation_time = ctime((stat($file))->mtime); 
			addReportTime($source);
			my $stylesheet = $xslt->parse_stylesheet($style_doc);
			my $results    = $stylesheet->transform($source);
			# insert the header information into the HTML
			my $fullResult = insertHTML($results);
			my $filename   = q{nativereport.html};
			$log->info('Creating:', catfile($outputdir, $filename));
			make_path($outputdir);
			my $fullPath = catfile($outputdir, $filename);
			# open the HTML file path
			if ( open my $fh, '>', $fullPath ) {
				print $fh $fullResult;
				close $fh;
				# Do not remove this print statement
				# This is the result returned to the calling program via the shell
				$log->info("doNativeSCARF returns: $filename");
				print "${filename}\n";
			}
			else {
				$retCode = 2;
			}
		}
		else {
			$log->error("Loading $xsltfile threw an exception.");
			print "ERROR Cannot load $xsltfile as XML document\n";
			$retCode = 2;
		}
	}
	else {
		$log->error("Loading $file threw an exception.");
		print "ERROR Cannot load $file as XML document\n";
		$retCode = 2;
	}
	return $retCode;
}

# Native viewer needs to look at the report XML file found in $inputdir
sub doNative {
    #my $r = printPara();
	my $retCode = 0;
    foreach my $file (@file_path) {
		$log->info("doNative - processing file: $file");
        if ($file =~ m/\.xml$/sxmi) {
			$retCode = doNativeSCARF($file, $tool_name);
            next;
        }
		elsif ($file =~ m/\.zip$/sxmi) {
			$retCode = doNativeHTML($file, $outputdir);
		}
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


sub insertHTML {
	my $original = shift;
	#my $CompletionTime = shift;	

	# split the HTML in the position where the NativeViewer Header will get included	
	my $delimiter  = "<h1>Place_to_insert_NativeViewer_Headerinfo</h1>";
	my @strs = split(/$delimiter/,$original );

	my $FirstLineInfo = '<div class="row"><div class="col-sm-3"><h2>Package Name</h2><span>'. ($package_name).'</span></div><div class="col-sm-3"><h2>Tool Name</h2><span>'.($tool_name).'</span></div> <div class="col-sm-3"><h2>Platform Name</h2><span>'.($platform_name).'</span></div><div class="col-sm-3"><h2>Assessment Start Time</h2><span>'.($start_date).'</span></div></div>';

	my $SecondLineInfo = '<div class="row"><div class="col-sm-3"><h2>Package Version</h2><span>'. ($package_version).'</span></div><div class="col-sm-3"><h2>Tool Version</h2><span>'.($tool_version).'</span></div> <div class="col-sm-3"><h2>Platform Version</h2><span>'.($platform_version).'</span></div><div class="col-sm-3"><h2>Assessment Complete Time</h2><span>'.($end_date).'</span></div></div>';
	
	return join "", $strs[0],$FirstLineInfo,$SecondLineInfo,$strs[1];
}



# add the report-generation-time element into the parsed_results.xml 
sub addReportTime {
	my $source = shift;
	my $root = $source->getDocumentElement();
	my $reportTime = $source->createElement("Report_Time");
	my $localT = ctime();
	$reportTime->appendText($localT);
	$root->appendChild($reportTime);
}

sub getXSLTFile {
    my $tool     = shift;
    my $isCommon = shift;
    my $xsltfile;
    my $suffix = q{};
    if ($isCommon) {
        $suffix = q{_common};
    }
    my %lookup = ( 
		'CodeSonar'	=> 'codesonar',
		'PMD' => 'pmd', 
        'Findbugs' => 'findbugs',
        'Archie' => 'archie',
        'error-prone' => 'generic',
        'checkstyle' => 'generic',
        'Pylint' => 'generic',
        'cppcheck' => 'cppcheck',
        'clang' => 'clang-sa',
        'gcc' => 'gcc',
		'Dawn' => 'dawn',
		'RevealDroid' => 'reveal',
		'android' => 'androidlint',

	);
    foreach my $key (keys %lookup) {
		if ($tool =~ /$key/isxm) {
            $xsltfile = "$lookup{$key}${suffix}.xslt";
            last;
        }
    }
	if (! $xsltfile) {
		$xsltfile = 'generic_common.xslt';
	}
	$log->info('The style file used is ',$xsltfile);
    return File::Spec->catfile(getSwampDir(), 'etc', $xsltfile);
}

sub logfilename {
    (my $name = $PROGRAM_NAME) =~ s/\.pl//sxm;
    $name = basename($name);
    return catfile(getSwampDir(), 'log', $name . '.log');
}
