#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2017 Software Assurance Marketplace

use strict;
use warnings;
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
	addExecRunLogAppender
	systemcall
	loadProperties
	checksumFile
	construct_vmhostname
	construct_vmdomainname
);
use SWAMP::vmu_AssessmentSupport qw(
	updateClassAdAssessmentStatus
	updateRunStatus
	updateExecutionResults
	saveResult
	isJavaPackage
	isCPackage
	isPythonPackage
	isRubyPackage
);

my $log;
my $clusterid;

sub logfilename {
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
		$log->error("extract_outputdisk - open failed for: $gfname");
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

# -1 open failure
# 0  no status
# 1  PASS
# 2  FAIL
# 4  retry
sub parse_status_output { my ($outputfolder) = @_ ;
	my $status = -1;
	my $weaknesses;
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
			$log->error("parse_status_output - status.out: $line");
			$status |= 2;
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
	return ($status, $weaknesses);
}

sub parse_lines_of_code { my ($bogref, $outputfolder) = @_ ;
	my $lines_of_code;
	my $fh;
	my $clocfile = catfile($outputfolder, 'cloc.out');
	if (! open($fh, '<', $clocfile)) {
		$log->error("parse_lines_of_code - read of $clocfile failed");
		return (0, $lines_of_code);
	}
	my @lines = <$fh>;
	close($fh);
	$lines_of_code = 0;
	foreach (@lines) {
		if (isJavaPackage($bogref)) {
			if (/,Java,/sxm) {
				my @LOC = split( /,/sxm, $_ );
				$lines_of_code += $LOC[-1];
			}
		}
		elsif (isCPackage($bogref)) {
			if ( /,C,/sxm || /,C\+\+,/sxm || /C.C\+\+\sHeader/sxm ) {
				my @LOC = split( /,/sxm, $_ );
				$lines_of_code += $LOC[-1];
			}
		}
		elsif (isPythonPackage($bogref)) {
			if (/,Python,/sxm) {
				my @LOC = split( /,/sxm, $_ );
				$lines_of_code += $LOC[-1];
			}
		}
		elsif (isRubyPackage($bogref)) {
			if (/,Ruby,/sxm) {
				my @LOC = split( /,/sxm, $_ );
				$lines_of_code += $LOC[-1];
			}
		}
	}
	return (1, $lines_of_code);
}

sub copy_parsed_results { my ($outputfolder, $resultsfolder) = @_ ;
	my $configfile = catfile($outputfolder, "parsed_results.conf");
	if (! -r $configfile) {
		$log->warn("copy_parsed_results - $configfile not found");
		return(0, '');
	}
	my $config = loadProperties($configfile);
	if (! defined($config)) {
		$log->error("copy_parsed_results - failed to read $configfile");
		return(0, '');
	}
	my $parsed_results_archive = catfile($outputfolder, $config->get('parsed-results-archive'));
	my ($output, $status) = systemcall("tar xf $parsed_results_archive --directory=$outputfolder");
	if ($status) {
		$log->error("copy_parsed_results - tar of $parsed_results_archive to $outputfolder failed: $output $status");
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
	my $parsed_results_file = $config->get('parsed-results-file');
	my $results_file = catfile($outputfolder, $parsed_results_dir, $parsed_results_file);
	if (! -r $results_file) {
		$log->error("copy_parsed_results - $results_file not found");
		return (0, '');
	}
	$log->info("copying: $results_file to: ", $resultsfolder);
	copy($results_file, $resultsfolder);
	return (1, catfile($resultsfolder, $parsed_results_file));
}

sub create_and_copy_results { my ($vmdomainname, $framework_said_pass, $inputfolder, $outputfolder, $resultsfolder) = @_ ;
	my $retval = 1;

	mkdir($resultsfolder);
	my ($uid, $gid) = (getpwnam('mysql'))[2, 3];
	chown($uid, $gid, $resultsfolder);
	chmod(0755, $resultsfolder);

	# add inputdisk.tar.gz
	my ($output, $status) = systemcall("tar cvfz inputdisk.tar.gz $inputfolder");
	if ($status) {
		$log->error("create_and_copy_results - tar of $inputfolder failed: $output $status");
		$retval = 0;
	}
	else {
		$log->info("copying: inputdisk.tar.gz to: ", $resultsfolder);
		copy('inputdisk.tar.gz', $resultsfolder);
	}

	# create vmlog directory and move files
	# <vmdomainname>.log from /var/log/libvirt/qemu for command line definition of vm
	# messages and boot.log from /var/log in vm
	# output of virsh dumpxml <vmdomainname> for xml definition of vm
	my $vmlog = catdir($resultsfolder, "vmlog");
	if (mkdir($vmlog)) {
		# /var/log/libvirt/qemu/<vmdomainname>.log
		my ($output, $status) = systemcall("find /var/log/libvirt/qemu -name ${vmdomainname}.log");
		my $vmdeflog = '';
		if (! $status) {
			$vmdeflog = $output;
			chomp $vmdeflog;
			if ($vmdeflog && -r $vmdeflog) {
				$log->info("copying: $vmdeflog to: ", $vmlog);
				copy($vmdeflog, $vmlog);
			}
		}
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

    # add outputdisk.tar.gz
    my $using_gnu_tar = 0;
    ($output, $status) = systemcall('tar --version');

    if ($output =~ /GNU tar/smi) {
        $log->info('We appear to be using GNU tar');
        $using_gnu_tar = 1;
    }

    my $outputarchive = 'outputdisk.tar.gz';
    ($output, $status) = systemcall("tar cvfz $outputarchive $outputfolder");

    if ($using_gnu_tar && $status == 1) {
        $log->warn("create_and_copy_results - tar of $outputfolder encountered potential problem: $output $status");
        $retval = 0;
    }
    elsif ($status) {
        $log->error("create_and_copy_results - tar of $outputfolder failed: $output $status");
        $retval = 0;
    }

    if (-r $outputarchive) {
        $log->info("copying: $outputarchive to: ", $resultsfolder);
        copy($outputarchive, $resultsfolder);
    }

	# add status.out, swamp_run.out, parsed_results.xml, weaknesses.txt, and package-archive
	my $status_file = catfile($outputfolder, 'status.out');
	if (! -r $status_file) {
		$log->error("create_and_copy_results - $status_file not found");
		$retval = 0;
	}
	else {
		$log->info("copying: $status_file to: ", $resultsfolder);
		copy($status_file, $resultsfolder);
	}
	my $logfile = '';
	my $swamp_run = catfile($outputfolder, 'swamp_run.out');
	if (! -r $swamp_run) {
		$log->error("create_and_copy_results - $swamp_run not found");
		$retval = 0;
	}
	else {
		$log->info("copying: $swamp_run to: ", $resultsfolder);
		copy($swamp_run, $resultsfolder);
		$logfile = catfile($resultsfolder, '/swamp_run.out');
	}

	(my $have_parsed_results, my $parsed_results_file) = copy_parsed_results($outputfolder, $resultsfolder);
	$log->info("parsed_results_file: $parsed_results_file status: $have_parsed_results");
	my $assessment_results_file = $parsed_results_file;
	if (! $have_parsed_results || ! $framework_said_pass) {
		my $error_results_file = catfile($outputfolder, 'results.tar.gz');
		if (-r $error_results_file) {
			$log->info("copying: $error_results_file to: ", $resultsfolder);
			copy($error_results_file, $resultsfolder);
		}
		else {
			$log->error("create_and_copy_results - $error_results_file not found");
			$retval = 0;
		}
		$assessment_results_file = catfile($resultsfolder, "outputdisk.tar.gz");
		$log->info("assessment_results_file set to: $assessment_results_file");
	}

	my $package_archive_file = '';
	my $fh;
	my $conf = catfile($inputfolder, 'package.conf');
	if (! open($fh, '<', $conf)) {
		$log->error("create_and_copy_results - read of $conf failed");
		$retval = 0;
	}
	else {
		my @lines = <$fh>;
		close($fh);
		chomp @lines;
		my $package_archive = (split '=', (grep {/package-archive/} @lines)[0])[1];
		my $archive_file = catfile($inputfolder, $package_archive);
		if (! $package_archive) {
			$log->error("create_and_copy_results - package-archive not found in $conf");
			$retval = 0;
		}
		elsif (! -r $archive_file) {
			$log->error("create_and_copy_results - $archive_file not found");
			$retval = 0;
		}
		else {
			$log->info("copying: $archive_file to: ", $resultsfolder);
			copy($archive_file, $resultsfolder);
			$package_archive_file = catfile($resultsfolder, $package_archive);
		}
	}
	$log->info("returning assessment_results_file: $assessment_results_file");
	return ($retval, $have_parsed_results, $assessment_results_file, $package_archive_file, $logfile);
}

sub compute_metrics { my ($execrunuid, $bogref, $outputfolder) = @_ ;
	my ($status, $lines_of_code) = parse_lines_of_code($bogref, $outputfolder);
	if ($status) {
		updateExecutionResults($execrunuid, {
			'status'			=> 'Computing metrics',
			'lines_of_code'		=> 'i__' . $lines_of_code,
		});
	}
	return $status;
}

sub save_results_in_database { my ($execrunuid, $weaknesses, $assessment_results_file, $logfile, $package_archive_file) = @_ ;
	$log->info("saving pathname: $assessment_results_file");
	my %results = (
			'execrunid'			=> $execrunuid,
			'weaknesses'		=> 'i__' . $weaknesses,
			'pathname'			=> $assessment_results_file,
			'sha512sum'			=> checksumFile($assessment_results_file),
			'logpathname'		=> $logfile,
			'log512sum'			=> checksumFile($logfile),
			'sourcepathname'	=> $package_archive_file,
			'source512sum'		=> checksumFile($package_archive_file),
			);
	my $status = saveResult(\%results);
	$log->info("saveResult returns: $status called with: ", sub {use Data::Dumper; Dumper(\%results);});
	return $status;
}

########
# Main #
########

# args: execrunuid uiddomain clusterid procid [debug]
# clusterid is global because it is used in logfilename
my ($execrunuid, $owner, $uiddomain, $procid, $debug) = getStandardParameters(\@ARGV, \$clusterid);
if (! $clusterid) {
	# we have no clusterid for the log4perl log file name
	exit(1);
}

my $vmhostname = construct_vmhostname($execrunuid, $clusterid, $procid);
my $vmdomainname = construct_vmdomainname($owner, $uiddomain, $clusterid, $procid);

# logger uses clusterid
Log::Log4perl->init(getLoggingConfigString());
$log = Log::Log4perl->get_logger(q{});
if (! $debug) {
	$log->remove_appender('Screen');
}
addExecRunLogAppender($execrunuid);
$log->level($debug ? $TRACE : $INFO);
$log->info("PostAssessment: $execrunuid Begin");
identifyScript(\@ARGV);

my $inputfolder = q{input};
my $outputfolder = q{output};

my %bog;
my $bogfile = $execrunuid . '.bog';
loadProperties($bogfile, \%bog);

my $message = 'Extracting assessment results';
updateClassAdAssessmentStatus($execrunuid, $vmhostname, $message);
my $status = extract_outputdisk($outputfolder);
if (! $status) {
	$message = 'Failed to extract assessment results';
	$log->info($message);
	updateClassAdAssessmentStatus($execrunuid, $vmhostname, $message);
}

$message = 'Post-Processing';
updateClassAdAssessmentStatus($execrunuid, $vmhostname, $message);
# attempt to log status.out
my $status_file = catfile($outputfolder, 'status.out');
if (-r $status_file) {
	my ($output, $status) = systemcall("cat $status_file");
	if (! $status) {
		$log->info("Contents of status.out:\n", $output);
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
($status, my $weaknesses) = parse_status_output($outputfolder);
my $framework_said_pass = ($status == 1);
$message = '';
if ($status < 0) {
	$message .= 'Failed to parse assessment results';
}
elsif ($status) {
	if ($status & 1) {
		$message .= 'Assessment passed ';
	}
	if ($status & 2) {
		$message .= 'Assessment failed ';
	}
	if ($status & 4) {
		$message .= 'Assessment retry ';
		$retry = 1;
	}
}
else {
	$message .= 'Assessment result not found ';
}
$log->info("Status: $message");
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

($status, my $have_parsed_results, my $assessment_results_file, my $package_archive_file, my $logfile) =
	create_and_copy_results($vmdomainname, $framework_said_pass, $inputfolder, $outputfolder, catdir($bog{'resultsfolder'}, $execrunuid));
if (! $status) {
	$message = 'Failed to preserve assessment results';
	updateClassAdAssessmentStatus($execrunuid, $vmhostname, $message);
}

$status = compute_metrics($execrunuid, \%bog, $outputfolder);
if (! $status) {
	$message = 'Failed to compute assessment result metrics';
	$log->info("Status: $message");
}

$message = 'Saving Results';
updateClassAdAssessmentStatus($execrunuid, $vmhostname, $message);
my $results_in_db = save_results_in_database($execrunuid, $weaknesses, $assessment_results_file, $logfile, $package_archive_file);
if (! $results_in_db) {
	$message = 'Failed to save assessment results in database';
	updateClassAdAssessmentStatus($execrunuid, $vmhostname, $message);
}

# FIXME - how should HTCondor be instructed to retry this job?
if (! $framework_said_pass || ! $have_parsed_results || ! $results_in_db) {
	$message = 'Finished with Errors';
	$message .= ' - Retry' if ($retry);
	$log->error("Assessment: $execrunuid $message");
	updateClassAdAssessmentStatus($execrunuid, $vmhostname, $message, 1);
	updateRunStatus($execrunuid, $message, 1);
}
else {
	$message = 'Finished';
	$log->info("Assessment: $execrunuid $message");
	updateClassAdAssessmentStatus($execrunuid, $vmhostname, $message, 1);
	updateRunStatus($execrunuid, $message, 1);
}

$log->info("PostAssessment: $execrunuid Exit");
exit(0);
