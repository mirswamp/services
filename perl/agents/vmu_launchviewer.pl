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
use Getopt::Long qw(GetOptions);
use Log::Log4perl::Level;
use Log::Log4perl;
use POSIX qw(setsid);
use XML::LibXML;
use XML::LibXSLT;

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
my $tool_name;       # SWAMP Toolname
my $package_name;    # SWAMP package affiliation == CodeDX project, ThreadFix application
my $project_name;    # SWAMP project affiliation

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
    'tool_name=s'           => \$tool_name,
    'outdir=s'              => \$outputdir,
    'package=s'             => \$package_name,
    'package_type=s'        => \$package_type,
    'project=s'             => \$project_name,
    'daemon!'               => \$asdaemon,
    'debug'                 => \$debug,
);

Log::Log4perl->init(getLoggingConfigString());
my $log = Log::Log4perl->get_logger(q{});
$log->level($debug ? $TRACE : $INFO);
$log->remove_appender('Screen');
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
$log->info("");
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
			'project'       => $project_name,
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
			$log->info("Calling uploadanalysysrun $package_name", sub { use Data::Dumper; Dumper(\@file_path); });
			$retCode = uploadanalysisrun($viewerState->{'address'}, $viewerState->{'apikey'}, $viewerState->{'urluuid'}, $package_name, \@file_path);
		}
		elsif ($viewer_name eq 'ThreadFix') {
			$log->info("Calling threadfix_uploadanalysysrun $package_name", sub { use Data::Dumper; Dumper(\@file_path); });
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

# Native viewer needs to look at the report XML file found in $inputdir
sub doNative {
	my $config = getSwampConfig();
    my $retCode = 0;
    foreach my $file (@file_path) {
        my ( $htmlfile, $dir, $ext ) = fileparse( $file, qr/\.[^.].*/sxm );
        my $filetype = `file $file`;

        if ( $filetype !~ /XML.*document/sxm ) {
            $log->info("File $file: not XML");
            make_path($outputdir);
            if ( cp( $file, $outputdir )) {
                $log->info("Copied $file to $outputdir ret=[${htmlfile}${ext}]");
				my $topdir = 'out';
				$topdir = 'output' if ($file =~ m/outputdisk.tar.gz$/);
                my $report = generatereport(catfile($outputdir, $htmlfile . $ext), $topdir);
				my $savereport = catfile($outputdir, 'assessmentreport.html');
				$log->info("report - file: $savereport url: ", $config->get('reporturl'), ' keys: ', sub{ join ', ', (keys %$report) });
                savereport($report, $savereport, $config->get('reporturl'));
                system("/bin/chmod 644 $savereport");
                print "assessmentreport.html\n";
            }
            else {
                $log->error("Cannot copy $file to $outputdir $OS_ERROR");
                print "ERROR Cannot copy $file to $outputdir $OS_ERROR\n";
                $retCode = 3;
            }
            next;
        }
        my $isCommon = 1; # SCARF files 
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
            my $style_doc  = XML::LibXML->load_xml( 'location' => "$xsltfile", 'no_cdata' => 1 );
            my $stylesheet = $xslt->parse_stylesheet($style_doc);
            my $results    = $stylesheet->transform($source);
            my $filename   = q{nativereport.html};
            $log->info('Creating:', catfile($outputdir, $filename));
            make_path($outputdir);
            $stylesheet->output_file( $results, catfile($outputdir, $filename));
            print "$filename\n";
        }
        else {
            $log->error("Loading $file threw an exception.");
            print "ERROR Cannot load $file as XML document\n";
            $retCode = 2;
        }
    }
    return $retCode;
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
    return File::Spec->catfile(getSwampDir(), 'etc', $xsltfile);
}

sub logfilename {
    (my $name = $PROGRAM_NAME) =~ s/\.pl//sxm;
    $name = basename($name);
    return catfile(getSwampDir(), 'log', $name . '.log');
}
