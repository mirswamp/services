# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

package SWAMP::FrameworkUtils;
use 5.014;
use utf8;
use strict;
use warnings;
use English '-no_match_vars';
use File::Basename qw(basename dirname);
use File::Spec::Functions;
use XML::Simple;
use JSON qw(to_json);

use SWAMP::vmu_Support qw(
	trim
	getSwampDir
	systemcall
);

use parent qw(Exporter);
our (@EXPORT_OK);
BEGIN {
    require Exporter;
    @EXPORT_OK = qw(
		generateStatusOutJson
		addHeaderJson
		saveStatusOutJson
	);
}

# if specific error files are larger than this value in bytes
# they will be initially collapsed in the error report
my $MAX_INITIAL_COLLAPSE_SIZE = 2048;

sub _addSourceFiles { my ($topdir, $output_files) = @_;
	my $source_compiles_file = q{source-compiles.xml};
	if (defined($output_files->{'buildConf'}->{'source-compiles'})) {
		$source_compiles_file = $output_files->{'buildConf'}->{'source-compiles'};
	}
	elsif (defined($output_files->{'buildConf'}->{'no-build-failures'})) {
		$source_compiles_file = $output_files->{'buildConf'}->{'no-build-failures'};
	}
	my $source_xml;
	my $source_compiles_path = catfile($topdir, $source_compiles_file);
	# source-compiles.xml should be at the topdir level
	# if it is not there, look in the build archive
	if (-f $source_compiles_path && -r $source_compiles_path) {
		$source_xml = $source_compiles_path;
	}
	else {
		my $archive_content = _addArchiveFileContent($topdir, $output_files, 'buildConf', $source_compiles_file);
		return if (! $archive_content || !exists($archive_content->{'content'}));
		$source_xml = $archive_content->{'content'};
	}
	my $success_source_files = [];
	my $fail_source_files = [];
	my $parsed_xml = eval {XMLin($source_xml);};
	if (defined($parsed_xml)) {
		foreach my $source (@{$parsed_xml->{'source-compile'}}) {
			my $source_file = $source->{'source-file'};
			my $exit_code = $source->{'exit-code'};
			if (! $exit_code) {
				push @$success_source_files, $source_file;
			}
			else {
				my $output = $source->{'output'};
				push @$fail_source_files, $source_file . "\n" . $output;
			}
		}
	}
	my $source_files = {
		'success'	=> $success_source_files,
		'fail'		=> $fail_source_files,
	};
	return $source_files;
}

sub _addStatusMessage { my ($statusOut) = @_;
	my $first_failure = $statusOut->{'meta'}->{'first_failure'};
	my $short_message = $statusOut->{'status'}->{$first_failure}->{'short'};
	my $long_message = $statusOut->{'status'}->{$first_failure}->{'long'};
	my $content;
	# both short and long message exists
	if (defined($short_message) && defined($long_message)) {
		$content = $short_message . "\n" . $long_message;
	}
	# only short message exists
	elsif (defined($short_message)) {
		$content = $short_message;
	}
	# only long message exists
	elsif (defined($long_message)) {
		$content = $long_message;
	}
	# neither short nor long message exists
	else {
		$content = q{Internal Error};
	}
	return $content;
}

my $archiveFileKeys = {
	'buildConf'			=> {
		'archive'	=> 'build-archive',
		'dir'		=> 'build-dir',
		'alt-dir'	=> 'build-root-dir',
	},
	'resultsConf'		=> {
		'archive'	=> 'results-archive',
		'dir'		=> 'results-dir',
	},
	'parsedResultsConf'	=> {
		'archive'	=> 'parsed-results-archive',
		'dir'		=> 'parsed-results-dir',
	}
};

sub _contentFileFromArchive { my ($archive, $file) = @_ ;
	my $command = qq{tar -O -xzf $archive $file};
	my ($output, $status, $error_output) = systemcall($command, 1);
	return if ($status);
	return $output;
}

sub _addArchiveFileContent { my ($topdir, $output_files, $archive_key, $filename_or_key) = @_ ;
	return if (! defined($output_files->{$archive_key}));
	my $archive = $output_files->{$archive_key}->{$archiveFileKeys->{$archive_key}->{'archive'}};
	my $dir = $output_files->{$archive_key}->{$archiveFileKeys->{$archive_key}->{'dir'}};
	if (! $dir && defined($archiveFileKeys->{$archive_key}->{'alt-dir'})) {
		$dir = $output_files->{$archive_key}->{$archiveFileKeys->{$archive_key}->{'alt-dir'}};
	}
	return if (! $archive || ! $dir);
	$archive = catfile($topdir, $archive);
	# first look for filename_or_key as key in archive hash
	my $output_filename = $output_files->{$archive_key}->{$filename_or_key};
	# if not found in archive hash then assume it is a filename
	$output_filename = $filename_or_key if (! defined($output_filename));
	# file path starts from dir
	$output_filename = catfile($dir, $output_filename);
	my $content = _contentFileFromArchive($archive, $output_filename);
	return if (! $content);
	my $retval = {
		'name'		=> $output_filename,
		'content'	=> $content,
	};
	return $retval;
}

sub _addFlatFileContent { my ($topdir, $output_files, $filename_or_key) = @_ ;
	# first look for filename_or_key as key in top level hash
	my $output_filename = $output_files->{$filename_or_key};
	# if not found in top level hash then assume it is a filename
	$output_filename = $filename_or_key if (! defined($output_filename));
	# file path starts from topdir
	$output_filename = catfile($topdir, $output_filename);
	if (open(my $fh, '<', $output_filename)) {
		my $content = do { local $/; <$fh> };
		close($fh);
		my $retval = {
			'name'		=> $output_filename,
			'content'	=> $content,
		};
		return $retval;
	}
	return;
}

sub _addFileContent { my ($topdir, $output_files, $archive_key, $filename_or_key) = @_ ;
	# look in top level of output_files
	if (! $archive_key) {
		my $retval = _addFlatFileContent($topdir, $output_files, $filename_or_key);
		return $retval;
	}
	# descend into archive_key level of output_files if specified
	my $retval = _addArchiveFileContent($topdir, $output_files, $archive_key, $filename_or_key);
	return $retval;
}

sub _addFailedAssessment { my ($topdir, $output_files, $assessment) = @_ ;
	if ((
			# execution-successful element extant and matches true
			defined($assessment->{'execution-successful'}) && 
			($assessment->{'execution-successful'} !~ m/true/i)
		) ||
		(
			# execution-successful element not extant and exit-code != 0
			! defined($assessment->{'execution-successful'}) && 
			(defined($assessment->{'exit-code'}) && ($assessment->{'exit-code'} != 0))
		)) {
		my $retval = [];
		if (defined($assessment->{'stdout'})) {
			my $content = _addFileContent($topdir, $output_files, 'resultsConf', $assessment->{'stdout'});
			push @$retval, $content if ($content);
		}
		if (defined($assessment->{'stderr'})) {
			my $content = _addFileContent($topdir, $output_files, 'resultsConf', $assessment->{'stderr'});
			push @$retval, $content if ($content);
		}
		return $retval if (scalar(@$retval));
	}
	return;
}

sub _addAssessFiles { my ($topdir, $output_files) = @_;
	return if (! defined($output_files->{'resultsConf'}));
	my $assessment_summary_file = q{assessment_summary.xml};
	if (defined($output_files->{'resultsConf'}->{'assessment-summary-file'})) {
		$assessment_summary_file = $output_files->{'resultsConf'}->{'assessment-summary-file'};
	}
	my $archive_content = _addArchiveFileContent($topdir, $output_files, 'resultsConf', $assessment_summary_file);
	return if (! $archive_content || ! defined($archive_content->{'content'}));
	my $content_xml = eval {XMLin($archive_content->{'content'});};
	return if (! $content_xml);
	my $assessments = $content_xml->{'assessment-artifacts'}->{'assessment'};
	return if (! $assessments);
	my $retval = [];
	if (ref $assessments eq q{ARRAY}) {
		foreach my $assessment (@$assessments) {
			my $contents = _addFailedAssessment($topdir, $output_files, $assessment);
			foreach my $content ($contents) {
				push @$retval, $content if ($content);
			}
		}
	}
	elsif (ref $assessments eq q{HASH}) {
		my $content = _addFailedAssessment($topdir, $output_files, $assessments);
		$retval = $content if ($content);
	}
	return $retval if (scalar(@$retval));
	return;
}

#############################################
#	Framework Task Specific Error Messages	#
#############################################

# assess					long				build_assess.out, assessment_summary.xml
# build						long				build_stdout.out, build_stderr.out
# build-archive									build_assess.out
# chdir-build-dir			long
# chdir-config-dir			long
# chdir-package-dir			long
# configure					long				config_stdout.out, config_stderr.out
# fetch-pkg-dependencies	long
# flow-typed									flow_typed_stdout1.out, flow_typed_stderr1.out
# gem-unpack									gem_unpack.out, gem_unpack.err
# install-os-dependencies						build_assess.out
# install-pip-dependencies						pip_install.out, pip_install.err
# no-build-setup			short				source-compiles.xml
# package-unarchive			long				build_assess.out
# parse-results									resultparser_stdout.out, resultparser_stderr.out
# read-gem-spec									gem-name-err.spec
# setup						short, long			run.out
# swamp-maven-plugin-install long
# tool-package-compatibility short, long
# tool-runtime-compatibility short, long
# validate-package			long

sub _addErrorFiles { my ($topdir, $output_files, $statusOut) = @_;
	return if (! defined($statusOut->{'meta'}->{'first_failure'}));

	# assess
	if ($statusOut->{'meta'}->{'first_failure'} eq q{assess}) {
		my $assess_summary = _addAssessFiles($topdir, $output_files);
		return $assess_summary;
	}

	my $retval = [];

	# build
	if ($statusOut->{'meta'}->{'first_failure'} eq q{build}) {
		my $stdout = _addFileContent($topdir, $output_files, 'buildConf', 'build-stdout-file');
		if (! $stdout) {
			$stdout = _addFileContent($topdir, $output_files, 'buildConf', 'build_stdout.out');
			if (! $stdout) {
				$stdout = _addFileContent($topdir, $output_files, 'buildConf', 'build.out');
			}
		}
		my $stderr = _addFileContent($topdir, $output_files, 'buildConf', 'build-stderr-file');
		if (! $stderr) {
			$stderr = _addFileContent($topdir, $output_files, 'buildConf', 'build_stderr.out');
			if (! $stderr) {
				$stderr = _addFileContent($topdir, $output_files, 'buildConf', 'build.err');
			}
		}
		push @$retval, $stdout if ($stdout);
		push @$retval, $stderr if ($stderr);
		return if (! scalar(@$retval));
		return $retval;
	}

	# build-archive, package-unarchive
	# buildAssessOut is added categorically

	# configure
	if ($statusOut->{'meta'}->{'first_failure'} eq q{configure}) {
		my $stdout = _addFileContent($topdir, $output_files, 'buildConf', 'config-stdout-file');
		if (! $stdout) {
			$stdout = _addFileContent($topdir, $output_files, 'buildConf', 'config_stdout.out');
			if (! $stdout) {
				$stdout = _addFileContent($topdir, $output_files, 'buildConf', 'configure_stdout.out');
				if (! $stdout) {
					$stdout = _addFileContent($topdir, $output_files, 'buildConf', 'config.out');
				}
			}
		}
		my $stderr = _addFileContent($topdir, $output_files, 'buildConf', 'config-stderr-file');
		if (! $stderr) {
			$stderr = _addFileContent($topdir, $output_files, 'buildConf', 'config_stderr.out');
			if (! $stderr) {
				$stderr = _addFileContent($topdir, $output_files, 'buildConf', 'configure_stderr.out');
			}
		}
		push @$retval, $stdout if ($stdout);
		push @$retval, $stderr if ($stderr);
		return if (! scalar(@$retval));
		return $retval;
	}

	# flow-typed
	if ($statusOut->{'meta'}->{'first_failure'} eq q{flow-typed}) {
		my $stdout = _addFileContent($topdir, $output_files, 'resultsConf', 'flow-typed_stdout1.out');
		my $stderr = _addFileContent($topdir, $output_files, 'resultsConf', 'flow-typed_stderr1.out');
		push @$retval, $stdout if ($stdout);
		push @$retval, $stderr if ($stderr);
		return if (! scalar(@$retval));
		return $retval;
	}

	# gem-install
	if ($statusOut->{'meta'}->{'first_failure'} eq q{gem-install}) {
		my $stdout = _addFileContent($topdir, $output_files, 'buildConf', 'gem_install.out');
		my $stderr = _addFileContent($topdir, $output_files, 'buildConf', 'gem_install.err');
		push @$retval, $stdout if ($stdout);
		push @$retval, $stderr if ($stderr);
		return if (! scalar(@$retval));
		return $retval;
	}

	# gem-unpack
	if ($statusOut->{'meta'}->{'first_failure'} eq q{gem-unpack}) {
		my $stdout = _addFileContent($topdir, $output_files, 'buildConf', 'gem_unpack.out');
		my $stderr = _addFileContent($topdir, $output_files, 'buildConf', 'gem_unpack.err');
		push @$retval, $stdout if ($stdout);
		push @$retval, $stderr if ($stderr);
		return if (! scalar(@$retval));
		return $retval;
	}

	# install-os-dependencies
	# buildAssessOut is added categorically

	# install-pip-dependencies
	if ($statusOut->{'meta'}->{'first_failure'} eq q{install-pip-dependencies}) {
		my $stdout = _addFileContent($topdir, $output_files, 'buildConf', 'pip_install.out');
		my $stderr = _addFileContent($topdir, $output_files, 'buildConf', 'pip_install.err');
		push @$retval, $stdout if ($stdout);
		push @$retval, $stderr if ($stderr);
		return if (! scalar(@$retval));
		return $retval;
	}

	# parse-results
	if ($statusOut->{'meta'}->{'first_failure'} eq q{parse-results}) {
		my $stdout = _addFileContent($topdir, $output_files, 'parsedResultsConf', 'resultparser-stdout-file');
		my $stderr = _addFileContent($topdir, $output_files, 'parsedResultsConf', 'resultparser-stderr-file');
		push @$retval, $stdout if ($stdout);
		push @$retval, $stderr if ($stderr);
		return if (! scalar(@$retval));
		return $retval;
	}

	# read-gem-spec									
	if ($statusOut->{'meta'}->{'first_failure'} eq q{read-gem-spec}) {
		my $stderr = _addFileContent($topdir, $output_files, 'buildConf', 'gem-name-err.spec');
		push @$retval, $stderr if ($stderr);
		return if (! scalar(@$retval));
		return $retval;
	}

	# setup
	# runOut is added categorically

	return;
}

my $doNotCollapse = {
	'buildAssessOut'	=> {
		'all'						=> 1,
		'assess'					=> 1,
		'build-archive'				=> 1,
		'package-archive'			=> 1,
		'install-os-dependencies'	=> 1,
	},
	'runOut'			=> {
		'setup'						=> 1,
	},
};

sub _should_collapse { my ($statusOut, $key) = @_ ;
	# sourceFiles + all_pass + no_build + source_files > compilable
	if ($key eq q{sourceFiles}) {
		return JSON::false if (
			$statusOut->{'meta'}->{'all_pass'} &&
			$statusOut->{'meta'}->{'no_build'} &&
			$statusOut->{'meta'}->{'source_files'} > $statusOut->{'meta'}->{'compilable'}
		);
	}
	return JSON::true if (! defined($statusOut->{'meta'}->{'first_failure'}));
	# buildAssessOut + asssess | build-archive | package-archive | install-os-dependencies
	# runOut + setup
	my $first = $statusOut->{'meta'}->{'first_failure'};
	return JSON::false if (defined($doNotCollapse->{$key}->{$first}));
	return JSON::true;
}

#################################################
#	Framework Task Specific Warning Messages	#
#################################################

# assess			status SKIP short no files
# no-build-setup	source-files > compilable

sub generateStatusOutJson { my ($topdir, $output_files, $statusOut) = @_ ;
	my $status_list = [];
	if ($statusOut) {

		# status message
		my ($name, $content, $anchor);
		# include specific warning
		if (defined($statusOut->{'meta'}->{'all_pass'}) && ($statusOut->{'meta'}->{'all_pass'})) {
			if ($statusOut->{'meta'}->{'no_build'} && ($statusOut->{'meta'}->{'source_files'} > $statusOut->{'meta'}->{'compilable'})) {
				$name = q{no-build-setup};
				$content = qq{Source files: $statusOut->{'meta'}->{'source_files'} > Compilable: $statusOut->{'meta'}->{'compilable'}};
				$anchor = qq{task-warn-no-build-setup-pass};
			}
			elsif (($statusOut->{'status'}->{'assess'}->{'status'} eq q{SKIP}) && $statusOut->{'meta'}->{'no_files'}) {
				$name = q{assess};
				$content = q{No files found to assess};
				$anchor = qq{task-warn-assess-skip};
			}
			else {
				$name = q{Success};
				$content = q{No warnings or errors found.};
				$anchor = qq{task-def-all};
			}
		}
		# OR include specific error
		elsif (defined($statusOut->{'meta'}->{'first_failure'})) {
			$name = $statusOut->{'meta'}->{'first_failure'};
			$content = _addStatusMessage($statusOut);
			$anchor = qq{task-debug-$statusOut->{'meta'}->{'first_failure'}};
		}
		# assessment failed and there is no first failure
		else {
			$name = q{all};
			$content = q{Internal Error}; 
			$anchor = q{task-debug-all};
		}
		if (defined($name) && defined($content) && defined($anchor)) {
			push @$status_list, {
				'name'		=> $name,
				'content'	=> $content,
				'collapsed'	=> JSON::false,
				'anchor'	=> $anchor,
			};
		} 

		# categorically include statusOut
		if (defined($output_files->{'statusOut'})) {
			my $content = $statusOut->{'content'};
			# strip the optional duration and duration unit from all lines
			$content =~ s/\s+\d+\.?\d*(?:s|ms|ns)?\s*$//gms;
			push @$status_list, {
				'name'		=> $output_files->{'statusOut'},
				'content'	=> $content,
				'collapsed'	=> JSON::false,
			};
		}

		# categorically include source file list
		# Source files should be part of the report for all assessments, not just no-build
		if (defined($statusOut->{'meta'}->{'no_build'})) {
			my $source_files = _addSourceFiles($topdir, $output_files);
			if ($source_files) {
        		push @$status_list, {
					'name'		=> q{Source Files},
					'content'	=> $source_files,
					'collapsed'	=> _should_collapse($statusOut, 'sourceFiles'),
				};
			}
		}

		# include the appropriate error files based on the first failed task
		# typically an stdout and stderr from the relevant archive
		# some tasks will have only one file
		# the assess task specifically my have a file for each tool executed
        my $error_files = _addErrorFiles($topdir, $output_files, $statusOut);
		if ($error_files) {
			foreach my $error_file (@$error_files) {
				my $collapsed = JSON::true;
				$collapsed = JSON::false if (length($error_file->{'content'}) < $MAX_INITIAL_COLLAPSE_SIZE);
				push @$status_list, {
					'name'		=> $error_file->{'name'},
					'content'	=> $error_file->{'content'},
					'collapsed'	=> $collapsed,
				};
			}
		}
		
		# categorically include buildAssessOut
		if (defined($output_files->{'buildAssessOut'})) {
			my $content = _addFileContent($topdir, $output_files, undef, 'buildAssessOut');
			$content = $content->{'content'} if ($content);
			push @$status_list, {
				'name'		=> $output_files->{'buildAssessOut'},
				'content'	=> $content,
				'collapsed'	=> _should_collapse($statusOut, 'buildAssessOut') || $error_files,
			};
		}

		# categorically include runOut
		if (defined($output_files->{'runOut'})) {
			my $content = _addFileContent($topdir, $output_files, undef, 'runOut');
			$content = $content->{'content'} if ($content);
			push @$status_list, {
				'name'		=> $output_files->{'runOut'},
				'content'	=> $content,
				'collapsed'	=> _should_collapse($statusOut, 'runOut'),
			};
		}
		
		# include versions
		my $versions_file = catfile($topdir, q{versions.txt});
		if (-f -r $versions_file) {
			my $cmd = qq{cat $versions_file};
			my ($output, $status) = systemcall($cmd);
			if (! $status) {
        		push @$status_list, {
					'name'		=> q{Component Versions},
					'content'	=> $output,
					'collapsed'	=> JSON::false,
				};
			}
		}
    }
	else {
		
		# status message
		push @$status_list, {
			'name'		=> q{Status Not Found},
			'content'	=> q{Unable to determine the final status of the assessment.},
			'collapsed'	=> JSON::false,
			'anchor'	=> q{#_missing-or-invalid-status-out-file},
		};
		
		# include versions
		my $versions_file = catfile($topdir, q{versions.txt});
		if (-f -r $versions_file) {
			my $cmd = qq{cat $versions_file};
			my ($output, $status) = systemcall($cmd);
			if (! $status) {
        		push @$status_list, {
					'name'		=> q{Component Versions},
					'content'	=> $output,
					'collapsed'	=> JSON::false,
				};
			}
		}
	}
	my $report = {
		'status'	=> $status_list,
	};
	return $report;
}

sub addHeaderJson { my ($report, $header) = @_ ;
	$report->{'assessment_start_ts'} = $header->[6];
	$report->{'assessment_end_ts'} = $header->[7];
	$report->{'report_generation_ts'} = $header->[8]; 
}

sub saveStatusOutJson { my ( $report, $filename) = @_;
	my $json_string = to_json($report);
	my $fh;
	if (! open $fh, '>', $filename) {
		return 0;
	}
	# prints the converted json string into the Json file
	print $fh $json_string;
	close $fh;
	return 1;
}

1;
