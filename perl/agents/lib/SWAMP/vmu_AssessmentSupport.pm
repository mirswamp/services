# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

package SWAMP::vmu_AssessmentSupport;
use strict;
use warnings;
use English '-no_match_vars';
use Log::Log4perl;
use File::Basename qw(basename);
use File::Copy qw(copy);
use File::Spec::Functions;
use POSIX qw(strftime);

use SWAMP::vmu_Support qw(
	use_make_path
	getUUID
	from_json_wrapper
    trim
    systemcall
    getSwampDir
	timing_log_assessment_timepoint
	loadProperties
    saveProperties
	checksumFile
	launchPadStart
	job_database_connect
	job_database_disconnect
	platformIdentifierToImage
	imageToPlatformIdentifier
	isSwampInABox
	isAssessmentRun
	isMetricRun
	isViewerRun
	isDCPlatform
	isVMPlatform
	$LAUNCHPAD_SUCCESS
	$LAUNCHPAD_BOG_ERROR
	$LAUNCHPAD_FILESYSTEM_ERROR
	$LAUNCHPAD_CHECKSUM_ERROR
	$LAUNCHPAD_FORK_ERROR
	$LAUNCHPAD_FATAL_ERROR
    getSwampConfig
	$global_swamp_config
	$HTCONDOR_JOB_IP_ADDRESS_FILE
	$HTCONDOR_JOB_EVENTS_FILE
	$HTCONDOR_JOB_IP_ADDRESS_TTY
	$HTCONDOR_JOB_EVENTS_TTY
);
use SWAMP::PackageTypes qw(
    $C_CPP_PKG_STRING
    $JAVA7SRC_PKG_STRING
    $JAVA7BYTECODE_PKG_STRING
    $JAVA8SRC_PKG_STRING
    $JAVA8BYTECODE_PKG_STRING
    $PYTHON2_PKG_STRING
    $PYTHON3_PKG_STRING
    $ANDROID_JAVASRC_PKG_STRING
    $RUBY_PKG_STRING
    $RUBY_SINATRA_PKG_STRING
    $RUBY_ON_RAILS_PKG_STRING
    $RUBY_PADRINO_PKG_STRING
    $ANDROID_APK_PKG_STRING
    $WEB_SCRIPTING_PKG_STRING
	$DOT_NET_PKG_STRING
);

our $OUTPUT_FILES_CONF_FILE_NAME = 'output_files.conf';
use parent qw(Exporter);
our (@EXPORT_OK);
BEGIN {
    require Exporter;
    @EXPORT_OK = qw(
      identifyAssessment
      builderUser
      builderPassword
      updateRunStatus
      updateAssessmentStatus
      updateClassAdAssessmentStatus
      saveMetricResult
      saveAssessmentResult
	  saveMetricSummary
	  getLaunchExecrunuids
	  incrementLaunchCounter
	  setLaunchFlag
	  setCompleteFlag
	  setSubmittedToCondorFlag
      doRun
      updateExecutionResults
      copyAssessmentInputs
      createAssessmentConfigs
      needsFloodlightAccessTool
	  $OUTPUT_FILES_CONF_FILE_NAME
	  locate_output_files
	  parse_statusOut
	  parse_statusOutLines
	  isClocTool
	  isSonatypeTool
      isRubyTool
      isFlake8Tool
      isBanditTool
      isAndroidTool
      isHRLTool
      isParasoftC
      isParasoftJava
      isParasoft9Tool
      isParasoft10Tool
	  isOWASPDCTool
      isGrammaTechCS
      isGrammaTechTool
      isRedLizardG
      isRedLizardTool
	  isSynopsysC
	  isSynopsysTool
      isJavaTool
      isJavaBytecodePackage
      isJavaPackage
      isCPackage
      isPythonPackage
      isRubyPackage
      isScriptPackage
	  isDotNetPackage
    );
}

my $log = Log::Log4perl->get_logger(q{});
my $tracelog = Log::Log4perl->get_logger('runtrace');

sub _randoString {
    return join q{}, @_ [ map { rand @_ } 1 .. shift ] ;
}

sub builderUser {
    my $result = 'builder';
    return $result;
}
sub builderPassword {
    my $result = _randoString(8, q{a}..q{z},q{0}..q{9},q{A}..q{Z},q{!},q{_});
    return $result;
}

sub identifyAssessment { my ($bogref) = @_ ;
	$log->info('Execrunuid: ', $bogref->{'execrunid'}, "\n",
		'  Package: ', $bogref->{'packagename'}, ' ',  $bogref->{'packagepath'}, "\n",
		'  Tool: ', $bogref->{'toolname'}, ' ',  $bogref->{'toolpath'}, "\n",
		'  Platform: ', $bogref->{'platform_identifier'}, "\n",
		'  Type: ', $bogref->{'platform_type'}, "\n",
		'  Image: ', $bogref->{'platform_image'}
	);
}

my $bogtranslator = {
	'platforms'	=> {
		'platform_identifier'		=> 'platform_identifier',
	},
	'tools'		=> {
		'tool_name'					=> 'toolname',
		'tool_path'					=> 'toolpath',
		'version_string'			=> 'tool-version',
	},
	'packages'	=> {
		'package_name' 				=> 'packagename', 			
		'package_version' 			=> 'packageversion', 			
		'package_build_settings'	=> 'packagebuild_settings',
		'build_target' 				=> 'packagebuild_target',		
		'build_system' 				=> 'packagebuild_system',		
		'build_dir' 				=> 'packagebuild_dir',		
		'build_opt' 				=> 'packagebuild_opt',		
		'build_cmd' 				=> 'packagebuild_cmd',		
		'config_opt' 				=> 'packageconfig_opt',		
		'config_dir' 				=> 'packageconfig_dir',		
		'config_cmd' 				=> 'packageconfig_cmd',		
		'package_path' 				=> 'packagepath',			
		'source_path' 				=> 'packagesourcepath',		
		'build_file' 				=> 'packagebuild_file',		
		'package_type' 				=> 'packagetype',			
		'bytecode_class_path'		=> 'packageclasspath',		
		'bytecode_aux_class_path'	=> 'packageauxclasspath',		
		'bytecode_source_path'		=> 'packagebytecodesourcepath',	
		'android_sdk_target'		=> 'android_sdk_target', 		
		'android_redo_build'		=> 'android_redo_build', 		# boolean converted to string
		'use_gradle_wrapper'		=> 'use_gradle_wrapper', 		# boolean converted to string
		'android_lint_target'		=> 'android_lint_target',		
		'language_version'			=> 'language_version', 		
		'maven_version'				=> 'maven_version', 			
		'android_maven_plugin'		=> 'android_maven_plugin', 		
		'package_language'			=> 'package_language', 		
		'exclude_paths'				=> 'exclude_paths',
	},
};

sub _translateToBOG { my ($merge, $title, $hashref, $keepnulls) = @_ ;
	foreach my $key (keys %$hashref) {
		if (exists($bogtranslator->{$title}->{$key})) {
			my $newkey = $bogtranslator->{$title}->{$key};
			if (defined($hashref->{$key})) {
				my $value = $hashref->{$key};
				if ($key eq 'IsBuildNeeded' || $key eq 'android_redo_build' || $key eq 'use_gradle_wrapper') {
					$value = 'false' if ($value eq 0);
					$value = 'true' if ($value eq 1);
				}
				$merge->{$newkey} = $value;
			}
			elsif ($keepnulls) {
				$merge->{$newkey} = 'null';
			}
		}
	}
}

sub _computeBOG { my ($execrunuid) = @_ ;
	my ($tool_path, $package_path);
	my ($tool_version_checksum, $package_version_checksum);
    my $dbh = job_database_connect();
	my $bog_query_result;
    if ($dbh) {
        my $query = q{SELECT * FROM assessment.exec_run_view WHERE execution_record_uuid = ?};
        my $sth = $dbh->prepare($query);
        $sth->bind_param(1, $execrunuid);
        $sth->execute();
        if ($sth->err) {
            $log->error("select assessment.exec_run_view - execute error: ", $sth->errstr);
        }
        else {
            $bog_query_result = $sth->fetchrow_hashref();
			if ($sth->err) {
            	$log->error("select assessment.exec_run_view - fetch error: ", $sth->errstr);
				$bog_query_result = undef;
			}
        }
		$sth->finish();
        job_database_disconnect($dbh);
	}
	else {
		$log->error("_computeBOG - database connection failed");
		return $LAUNCHPAD_BOG_ERROR;
	}
	if (! $bog_query_result) {
		return $LAUNCHPAD_BOG_ERROR;
	}
	$log->debug('bog_query_result: ', sub { use Data::Dumper; Dumper($bog_query_result); });

	$global_swamp_config ||= getSwampConfig();
	my $compute_bog_checksums = $global_swamp_config->get('computeBOGChecksums');
	if ($compute_bog_checksums) {
		# verify tool_path and tool_version_checksum
		$tool_path = $bog_query_result->{'tool_path'};
		$tool_version_checksum = $bog_query_result->{'tool_checksum'};
		if ($tool_path && $tool_version_checksum) {
			if (! -r $tool_path) {
				$log->error("$tool_path not readable");
				return $LAUNCHPAD_FILESYSTEM_ERROR;
			}
			elsif ((my $checksum = checksumFile($tool_path)) ne $tool_version_checksum) {
				$log->error("checksum mismatch for: $tool_path found: $checksum - expected: $tool_version_checksum");
				return $LAUNCHPAD_CHECKSUM_ERROR;
			}
		}
		else {
			$log->error("no tool_path or no tool_version_checksum");
			$log->error('tool_path: ', $tool_path || '', ' tool_version_checksum: ', $tool_version_checksum || '');
			return $LAUNCHPAD_BOG_ERROR;
		}

		# veryify package_path and package_version_checksum
		$package_path = $bog_query_result->{'package_path'};
		$package_version_checksum = $bog_query_result->{'pkg_checksum'};
		if ($package_path && $package_version_checksum) {
			if (! -r $package_path) {
				$log->error("$package_path not readable");
				return $LAUNCHPAD_FILESYSTEM_ERROR;
			}
			elsif ((my $checksum = checksumFile($package_path)) ne $package_version_checksum) {
				$log->error("checksum mismatch for: $package_path found: $checksum - expected: $package_version_checksum");
				return $LAUNCHPAD_CHECKSUM_ERROR;
			}
		}
		else {
			$log->error("no package_path or no package_version_checksum");
			$log->error('package_path: ', $package_path || '', ' package_version_checksum: ', $package_version_checksum || '');
			return $LAUNCHPAD_BOG_ERROR;
		}
	}

	# compute final bog
	my $bog = {};

	# notify_when_complete_flag
	$bog->{'notify_when_complete_flag'} = $bog_query_result->{'notify_when_complete_flag'};

	# compute package dependency list
	$bog->{'packagedependencylist'} = $bog_query_result->{'dependency_list'};
	
	# job and user information
	$bog->{'execrunid'} = $execrunuid;
	$bog->{'launch_counter'} = $bog_query_result->{'launch_counter'};
	$bog->{'projectid'} = $bog_query_result->{'project_uuid'};
	$bog->{'userid'} = $bog_query_result->{'user_uuid'};
	$bog->{'user_cnf'} = $bog_query_result->{'user_cnf'};
	
	# Other bog entries - not from the database
	$bog->{'version'} = '2';
	my $results_folder = $global_swamp_config->get('resultsFolder');
	$bog->{'resultsfolder'} = $results_folder;
	if (! -d $results_folder) {
		$log->error("results folder: ", defined($results_folder) ? $results_folder : 'not defined', ' is not a directory.');
		return $LAUNCHPAD_BOG_ERROR;
	}
	
	# translate database keywords to framework keywords
	_translateToBOG($bog, 'platforms', $bog_query_result, 1);
	_translateToBOG($bog, 'tools', $bog_query_result, 1);
	_translateToBOG($bog, 'packages', $bog_query_result, 1);
	
	# translate database platform value to framework platform value
	if (! $bog->{'platform_identifier'}) {
		$log->error("no platform identifier in database record");
		return $LAUNCHPAD_BOG_ERROR;
	}
	# read preferred assessment platform type from config
	my $preferred_platform_type = $global_swamp_config->get('preferred_platform_type');
	# if preferred assessment platform type is not specified default to VM
	if (! $preferred_platform_type) {
		$log->warn('no preferred_platform_type in config - defaulting to VM');
		$preferred_platform_type = 'VM';
	}
	# if preferred assessment platform type is incorrectly specified default to VM
	elsif (! isDCPlatform($preferred_platform_type) && ! isVMPlatform($preferred_platform_type)) {
		$log->warn("preferred_platform_type incorrectly specified in config $preferred_platform_type - defaulting to VM");
		$preferred_platform_type = 'VM';
	}
	$log->info('initial platform_identifier: ', $bog->{'platform_identifier'}, " preferred_platform_type: $preferred_platform_type");
	# search for preferred platform type image
	$bog->{'platform_type'} = $preferred_platform_type;
	my $platform_image = platformIdentifierToImage($bog);
	# if preferred platform type is not found search for alternate platform type
	if (! $platform_image) {
		$log->warn("preferred platform type image file not found for: ", $bog->{'platform_identifier'});
		if (isDCPlatform($preferred_platform_type)) {
			$preferred_platform_type = 'VM';
		}
		else {
			$preferred_platform_type = 'DC';
		}
		$bog->{'platform_type'} = $preferred_platform_type;
		$platform_image = platformIdentifierToImage($bog);
		if (! $platform_image) {
			$log->error("no image file for ", $bog->{'platform_identifier'});
			return $LAUNCHPAD_BOG_ERROR;
		}
	}
	$bog->{'use_docker_universe'} = isDCPlatform($bog->{'platform_type'});
	$log->info('use_docker_universe: ', $bog->{'use_docker_universe'});
	$bog->{'platform_image'} = $platform_image;
	my $platform_identifier = imageToPlatformIdentifier($platform_image);
	if (! $platform_identifier) {
		$log->error("no platform component in $platform_image for ", $bog->{'platform_identifier'});
		return $LAUNCHPAD_BOG_ERROR;
	}
	$bog->{'platform_identifier'} = $platform_identifier;
	$log->info('final platform_identifier: ', $bog->{'platform_identifier'});
	
    return $bog;
}
    
sub incrementLaunchCounter { my ($execrunuid, $current) = @_ ;
	my $success = 0;
	return 1 if (isViewerRun($execrunuid));
	if (my $dbh = job_database_connect()) {
		my $database;
		if (isAssessmentRun($execrunuid)) {
			$database = 'assessment';	
		}
		elsif (isMetricRun($execrunuid)) {
			$database = 'metric';
		}
		my $query = qq{CALL ${database}.increment_launch_counter (?, \@r);};
		my $sth = $dbh->prepare($query);
		$sth->bind_param(1, $execrunuid);
		$sth->execute();
		my $result;
		if (! $sth->err) {
			$result = $dbh->selectrow_array('SELECT @r');
		}
		else {
			$log->error("incrementLaunchCounter $database - error: ", $sth->errstr);
		}
		job_database_disconnect($dbh);
		if (! $result || ($result < 0)) {
			$log->error("incrementLaunchCounter $database - error: ", defined($result) ? $result : 'undefined');
		}
		elsif ($result != ($current + 1)) {
			$log->error("incrementLaunchCounter $database - current: $current result: $result");
		}
		else {
			$success = 1;
		}
	}
	else {
		$log->error("incrementLaunchCounter - database connection failed");
	}
	return $success;
}

sub _setDBRunQueueFlag { my ($execrunuid, $flag_name, $flag_value) = @_ ;
	return 1 if (isViewerRun($execrunuid));
	my $success = 0;
	if (my $dbh = job_database_connect()) {
		my ($database, $table);
		if (isAssessmentRun($execrunuid)) {
			$database = 'assessment';
			$table = 'execution_record';
		}
		elsif (isMetricRun($execrunuid)) {
			$database = 'metric';
			$table = 'metric_run';
		}
		my $query = qq{UPDATE ${database}.${table} SET $flag_name = ? WHERE ${table}_uuid = ?};
		my $sth = $dbh->prepare($query);
		$sth->bind_param(1, $flag_value ? 1 : 0);
		$sth->bind_param(2, $execrunuid);
		$sth->execute();
		if ($sth->err) {
			$log->error("_setDBRunQueueFlag $database $table $flag_name $flag_value - error: ", $sth->errstr);
		}
		else {
			$success = 1;
		}
		job_database_disconnect($dbh);
	}
	else {
		$log->error("_setDBRunQueueFlag - database connection failed");
	}
	return $success;
}

sub setLaunchFlag { my ($execrunuid, $launch) = @_ ;
	my $result = _setDBRunQueueFlag($execrunuid, 'launch_flag', $launch);
	return $result;
}

sub setCompleteFlag { my ($execrunuid, $complete) = @_ ;
	my $result = _setDBRunQueueFlag($execrunuid, 'complete_flag', $complete);
	return $result;
}

sub setSubmittedToCondorFlag { my ($execrunuid, $submitted) = @_ ;
	my $result = _setDBRunQueueFlag($execrunuid, 'submitted_to_condor_flag', $submitted);
	return $result;
}

# FIXME read this value from swamp.conf
my $LAUNCH_COUNTER_THRESHOLD = 15;
sub getLaunchExecrunuids { my ($launch_counter_begin, $launch_counter_end) = @_ ;
	my $execrunuids;
	if (my $dbh = job_database_connect()) {
		my $query = q{SELECT execution_record_uuid FROM assessment.execution_record WHERE launch_flag = 1};
		my $sth = $dbh->prepare($query);
		if (defined($launch_counter_begin) || defined($launch_counter_end)) {
			$launch_counter_begin = 0 if (! defined($launch_counter_begin));
			$launch_counter_end = $LAUNCH_COUNTER_THRESHOLD if (! defined($launch_counter_end));
			$query .= q{ AND launch_counter >= ? AND launch_counter <= ?};
			$sth = $dbh->prepare($query);
			$sth->bind_param(1, $launch_counter_begin);
			$sth->bind_param(2, $launch_counter_end);
		}
		if ($sth->err) {
			$log->error('getLaunchExecrunuids error ', $launch_counter_begin || '', $launch_counter_end ? " $launch_counter_end" : '', ": ", $sth->errstr);
		}
		else {
			$execrunuids = $dbh->selectcol_arrayref($sth);
			if ($dbh->err) {
				$log->error("getLaunchExecrunuids - select failed: ", $dbh->errstr);
				$execrunuids = undef;
			}
		}
		job_database_disconnect($dbh);
	}
	else {
		$log->error("getLaunchExecrunuids - database connection failed");
	}
	return $execrunuids;
}

sub doRun { my ($execrunuid) = @_ ;
    $tracelog->trace("doRun called with execrunuid: $execrunuid");
	timing_log_assessment_timepoint($execrunuid, 'compute bog - begin');
    my $options = _computeBOG($execrunuid);
	timing_log_assessment_timepoint($execrunuid, 'compute bog - end');
	# options is either a hash reference to the BOG
	# or an enumeration of a LAUNCHPAD_*_ERROR
	if (ref $options) {
    	$tracelog->trace("doRun - _computeBOG returned bog - calling launchPadStart");
		my $retval = launchPadStart($options);
		timing_log_assessment_timepoint($execrunuid, 'launch pad start - end');
    	$tracelog->trace("doRun - launchPadStart returned: $retval");
    	return $retval;
	}
	$tracelog->error("doRun failed to compute BOG for: $execrunuid error: $options");
	$log->error("doRun failed to compute BOG for: $execrunuid error: $options");
	return $options;
}

sub updateExecutionResults { my ($execrunid, $newrecord, $finalStatus) = @_ ;
	if (my $dbh = job_database_connect()) {
    	if ($finalStatus) {
        	$newrecord->{'completion_date'} = strftime("%Y-%m-%d %H:%M:%S", gmtime(time()));
    	}
		my $query = q{CALL assessment.update_execution_run_status(?, ?, ?, @r);};
		my $sth = $dbh->prepare($query);
		foreach my $key (keys %$newrecord) {
			# execution_record_uuid
			# field_name_in
			# field_value_in
			# return_string
			$sth->bind_param(1, $execrunid);
			$sth->bind_param(2, $key);
			$sth->bind_param(3, $newrecord->{$key});
			$sth->execute();
			if (! $sth->err) {
				my $result = $dbh->selectrow_array('SELECT @r');
				if (! $result || ($result ne 'SUCCESS')) {
        			$log->error("updateExecutionResults - error: $result");
    			}
			}
			else {
				$log->error("updateExecutionResults - error: ", $sth->errstr);
			}
		}
		job_database_disconnect($dbh);
	}
	else {
        $log->error("updateExecutionResults - database connection failed");
	}
}

sub updateRunStatus { my ($execrunid, $status, $finalStatus) = @_ ;
    $finalStatus ||= 0;
    updateExecutionResults($execrunid, {'status' => $status}, $finalStatus);
}

sub saveMetricSummary { my ($metric_results) = @_ ;
    if (!defined($metric_results->{'execrunid'})) {
        $log->error('saveMetricSummary - error: hash is missing execrunid');
		return;
    }
    if (!defined($metric_results->{'code-lines'})) {
        $log->error('saveMetricSummary - error: hash is missing code-lines');
		return;
    }
    if (!defined($metric_results->{'comment-lines'})) {
        $log->error('saveMetricSummary - error: hash is missing comment-lines');
		return;
    }
    if (!defined($metric_results->{'blank-lines'})) {
        $log->error('saveMetricSummary - error: hash is missing blank-lines');
		return;
    }
    if (!defined($metric_results->{'total-lines'})) {
        $log->error('saveMetricSummary - error: hash is missing total-lines');
		return;
    }
	if (my $dbh = job_database_connect()) {
		my $query = qq{UPDATE metric.metric_run SET pkg_code_lines = ?, pkg_comment_lines = ?, pkg_blank_lines = ?, pkg_total_lines = ? WHERE metric_run_uuid = ?};
		my $sth = $dbh->prepare($query);
		$sth->bind_param(1, $metric_results->{'code-lines'});
		$sth->bind_param(2, $metric_results->{'comment-lines'});
		$sth->bind_param(3, $metric_results->{'blank-lines'});
		$sth->bind_param(4, $metric_results->{'total-lines'});
		$sth->bind_param(5, $metric_results->{'execrunid'});
		$sth->execute();
		if ($sth->err) {
			$log->error("saveMetricSummary - error: ", $sth->errstr);
		}
		job_database_disconnect($dbh);
	}
	else {
		$log->error("saveMetricSummary - database connection failed");
	}
}

sub saveAssessmentResult { my ($bogref, $assessment_results) = @_ ;
    if (! defined($assessment_results->{'pathname'})) {
        $log->error('saveAssessmentResult - error: hash is missing pathname');
        return 0;
    }
    if (!defined($assessment_results->{'execrunid'})) {
        $log->error('saveAssessmentResult - error: hash is missing execrunid');
        return 0;
    }

	$log->debug("saveAssessmentResult - assessment_results: ", sub { use Data::Dumper; Dumper($assessment_results); });
	$log->debug("saveAssessmentResult - BOG: ", sub { use Data::Dumper; Dumper($bogref); });

	my $project_uuid = $bogref->{'projectid'};
	my $assessment_result_uuid = getUUID();

	my $result_dest_path = catdir(rootdir(), 'swamp', 'SCAProjects', $project_uuid, 'A-Results', $assessment_result_uuid);
	if (! use_make_path($result_dest_path)) {
        $log->error("Error - make_path $result_dest_path failed");
        return 0;
	}
	my $log_dest_path = catdir(rootdir(), 'swamp', 'SCAProjects', $project_uuid, 'A-Logs', $assessment_result_uuid);
	if (! use_make_path($log_dest_path)) {
        $log->error("Error - make_path $log_dest_path failed");
        return 0;
	}

	# assessment results
	if (! copy($assessment_results->{'pathname'}, $result_dest_path)) {
        $log->error('saveAssessmentResult - copy ', $assessment_results->{'pathname'}, " to $result_dest_path failed: $OS_ERROR");
        return 0;
	}
	$log->info('Copied: ', $assessment_results->{'pathname'}, " to: $result_dest_path");
	my $result_file = catfile($result_dest_path, basename($assessment_results->{'pathname'}));

	# out_archive
	# if the out_archive was already specified as the 
	# assessment result pathname do not save it twice
	if ($assessment_results->{'out_archive'} ne $assessment_results->{'pathname'}) {
		if (! copy($assessment_results->{'out_archive'}, $result_dest_path)) {
        	$log->warn('saveAssessmentResult - copy ', $assessment_results->{'out_archive'}, " to $result_dest_path failed: $OS_ERROR");
		}
		else {
			$log->info('Copied: ', $assessment_results->{'out_archive'}, " to: $result_dest_path");
		}
	}

	# source archive
	if (! copy($assessment_results->{'sourcepathname'}, $result_dest_path)) {
        $log->error('saveAssessmentResult - copy ', $assessment_results->{'sourcepathname'}, " to $result_dest_path failed: $OS_ERROR");
        return 0;
	}
	$log->info('Copied: ', $assessment_results->{'sourcepathname'}, " to: $result_dest_path");
	my $source_file = catfile($result_dest_path, basename($assessment_results->{'sourcepathname'}));

	# assessment report
	# currently does not go into database
	if (! copy($assessment_results->{'reportpath'}, $result_dest_path)) {
        $log->error('saveAssessmentResult - copy ', $assessment_results->{'reportpath'}, " to $result_dest_path failed: $OS_ERROR");
        return 0;
	}
	$log->info('Copied: ', $assessment_results->{'reportpath'}, " to: $result_dest_path");

	if (! copy($assessment_results->{'logpathname'}, $log_dest_path)) {
        $log->error('saveAssessmentResult - copy ', $assessment_results->{'logpathname'}, " to $log_dest_path failed: $OS_ERROR");
        return 0;
	}
	$log->info('Copied: ', $assessment_results->{'logpathname'}, " to: $log_dest_path");
	my $log_file = catfile($log_dest_path, basename($assessment_results->{'logpathname'}));

	if (my $dbh = job_database_connect()) {
		# execution_record_uuid_in
		# assessment_result_uuid_in
		# result_path_in
		# result_checksum_in
		# source_archive_path_in
		# source_archive_checksum_in
		# log_path_in
		# log_checksum_in
		# weakness_cnt_in
		# lines_of_code_in
		# status_out_in
		# status_out_error_msg_in
		# return_string
		my $query = q{CALL assessment.insert_results(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, @r);};
		my $sth = $dbh->prepare($query);
		$sth->bind_param(1, $assessment_results->{'execrunid'});
		$sth->bind_param(2, $assessment_result_uuid);
		$sth->bind_param(3, $result_file);
		$sth->bind_param(4, $assessment_results->{'sha512sum'});
		$sth->bind_param(5, $source_file);
		$sth->bind_param(6, $assessment_results->{'source512sum'});
		$sth->bind_param(7, $log_file);
		$sth->bind_param(8, $assessment_results->{'log512sum'});
		$sth->bind_param(9, $assessment_results->{'weaknesses'});
		$sth->bind_param(10, $assessment_results->{'locSum'});
		$sth->bind_param(11, $assessment_results->{'status_out'});
		$sth->bind_param(12, $assessment_results->{'status_out_error_msg'});
		$sth->execute();
		my $result;
		if (! $sth->err) {
			$result = $dbh->selectrow_array('SELECT @r');
		}
		else {
			$log->error("saveAssessmentResult - error: ", $sth->errstr);
		}
		job_database_disconnect($dbh);
		if (! $result || ($result ne 'SUCCESS')) {
			$log->error("saveAssessmentResult - error: $result");
			return 0;
		}
	}
	else {
        $log->error("saveAssessmentResult - database connection failed");
		return 0;
	}
    return 1;
}

sub saveMetricResult { my ($bogref, $metric_results) = @_ ;
    if (!defined($metric_results->{'pathname'})) {
        $log->error('saveMetricResult - error: hash is missing pathname');
        return 0;
    }
    if (!defined($metric_results->{'execrunid'})) {
        $log->error('saveMetricResult - error: hash is missing execrunid');
        return 0;
    }

	$log->debug("saveMetricResult - metric_results: ", sub { use Data::Dumper; Dumper($metric_results); });
	$log->debug("saveMetricResult - BOG: ", sub { use Data::Dumper; Dumper($bogref); });

	my $result_dest_path = catdir(rootdir(), 'swamp', 'store', 'SCAPackages', 'Metrics', $metric_results->{'execrunid'});
	if (! use_make_path($result_dest_path)) {
        $log->error("Error - make_path $result_dest_path failed");
        return 0;
	}

	# assessment results
	if (! copy($metric_results->{'pathname'}, $result_dest_path)) {
        $log->error('saveMetricResult - copy ', $metric_results->{'pathname'}, " to $result_dest_path failed: $OS_ERROR");
        return 0;
	}
	$log->info('Copied: ', $metric_results->{'pathname'}, " to: $result_dest_path");
	my $result_file = catfile($result_dest_path, basename($metric_results->{'pathname'}));

	# out_archive
	# if the out_archive was already specified as the 
	# metric result pathname do not save it twice
	if ($metric_results->{'out_archive'} ne $metric_results->{'pathname'}) {
		if (! copy($metric_results->{'out_archive'}, $result_dest_path)) {
        	$log->warn('saveMetricResult - copy ', $metric_results->{'out_archive'}, " to $result_dest_path failed: $OS_ERROR");
		}
		else {
			$log->info('Copied: ', $metric_results->{'out_archive'}, " to: $result_dest_path");
		}
	}

	# assessment report
	# currently does not go into database
	if (! copy($metric_results->{'reportpath'}, $result_dest_path)) {
        $log->error('saveMetricResult - copy ', $metric_results->{'reportpath'}, " to $result_dest_path failed: $OS_ERROR");
        return 0;
	}
	$log->info('Copied: ', $metric_results->{'reportpath'}, " to: $result_dest_path");

	my $result = 0;
	if (my $dbh = job_database_connect()) {
		my $query = qq{UPDATE metric.metric_run SET file_host = ?, result_path = ?, result_checksum = ?, status_out = ?, status_out_error_msg = ? WHERE metric_run_uuid = ?};
		my $sth = $dbh->prepare($query);
		$sth->bind_param(1, 'SWAMP');
		$sth->bind_param(2, $result_file);
		$sth->bind_param(3, $metric_results->{'sha512sum'});
		$sth->bind_param(4, $metric_results->{'status_out'});
		$sth->bind_param(5, $metric_results->{'status_out_error_msg'});
		$sth->bind_param(6, $metric_results->{'execrunid'});
		$sth->execute();
		if ($sth->err) {
			$log->error("saveMetricResult - error: ", $sth->errstr);
		}
		job_database_disconnect($dbh);
		$result = 1;
	}
	else {
        $log->error("saveMetricResult - database connection failed");
	}
    return $result;
}

#############################
#   CopyAssessmentInputs    #
#############################

sub copyInput { my ($inputpath, $platform_identifier, $dest, $os_dependencies) = @_ ;
    my $platform_identifier_start = $platform_identifier;
    my $inputdir = catdir($inputpath, $platform_identifier, 'in-files');
    if (! -d $inputdir) {
        $platform_identifier = 'noarch';
        $inputdir = catdir($inputpath, $platform_identifier, 'in-files');
        if (! -d $inputdir) {
            $log->error("copyInput error - neither ", $platform_identifier_start, " nor $platform_identifier found in $inputpath");
            return 0;
        }
    }
    my $inputfiles_glob = catfile($inputdir, '*');
    my $cmd = "cp $inputfiles_glob $dest";
    my ($output, $status, $error_output) = systemcall($cmd);
    if ($status) {
        $log->error("copyInput error - $cmd failed - $status $output $error_output");
        return 0;
    }
    $inputdir = catdir($inputpath, $platform_identifier, 'swamp-conf');
    if (-d $inputdir) {
        $inputfiles_glob = catfile($inputdir, '*');
        $cmd = "cp $inputfiles_glob $dest";
        ($output, $status, $error_output) = systemcall($cmd, 1);
        if ($status) {
            $log->warn("copyInput warning - $cmd failed - $status $output $error_output");
        }
		my $dependencies_files_glob = '*os-dependencies*.conf';
		my @dependencies = `find $inputdir -type f -name $dependencies_files_glob`;
		chomp @dependencies;
		foreach my $dependencies_file (@dependencies) {
			$cmd = "cat $dependencies_file >> $os_dependencies";
			($output, $status, $error_output) = systemcall($cmd, 1);
			if ($status) {
				$log->warn("copyInput warning - $cmd failed - $status $output $error_output");
			}
		}
    }
    return 1;
}

sub copyAssessmentInputs { my ($bogref, $dest) = @_ ;
    if (! defined($bogref->{'packagepath'})) {
        $log->error($bogref->{'execrunid'}, "BOG is missing packagepath specification.");
        return 0;
    }
	if (! -r $bogref->{'packagepath'}) {
        $log->error($bogref->{'execrunid'}, ' package: ', $bogref->{'packagepath'}, ' not readable.');
		return 0;
	}
    if (! defined( $bogref->{'toolpath'})) {
        $log->error($bogref->{'execrunid'}, "BOG is missing toolpath specification.");
        return 0;
    }
	if (! -r $bogref->{'toolpath'}) {
        $log->error($bogref->{'execrunid'}, ' tool: ', $bogref->{'toolpath'}, ' not readable.');
		return 0;
	}
    my $basedir = getSwampDir();
	# resultant os-dependencies file
	my $os_dependencies = catfile($dest, 'os-dependencies.conf');

	# copy assessment tool to the input destination directory
    my $toolpath = $bogref->{'toolpath'};
    $toolpath =~ s/\.gz$//;
    $toolpath =~ s/\.tar$//;
    my $platform_identifier = $bogref->{'platform_identifier'};
    my $result = copyInput($toolpath, $platform_identifier, $dest, $os_dependencies);

    # copy services.conf to the input destination directory
	my $file = catfile($basedir, 'etc', 'services.conf');
    if (! copy($file, $dest)) {
        $log->error($bogref->{'execrunid'}, "Cannot copy $file to $dest $OS_ERROR");
        return 0;
    }

	# copy the package archive to the input destination directory
	if (! copy($bogref->{'packagepath'}, $dest)) {
		$log->error($bogref->{'execrunid'}, "Cannot read packagepath $bogref->{'packagepath'} $OS_ERROR");
		return 0;
	}

	# copy package dependency list to the input destination directory
	my $user_dependencies = catfile($dest, 'user-os-dependencies.conf');
	_addUserDepends($bogref, $user_dependencies, $os_dependencies);

	# copy result parser to the input destination directory
    my $resultparserpath = catdir($basedir, 'thirdparty', 'resultparser');
    $result &&= copyInput($resultparserpath, $platform_identifier, $dest, $os_dependencies);

	# copy assessment framework to the input destination directory
    if (isJavaPackage($bogref)) {
        $file = 'java-assess';
    }        
    elsif (isRubyPackage($bogref)) {
        $file = 'ruby-assess';
    }        
    elsif (isCPackage($bogref)) {
        $file = 'c-assess';
    }        
    elsif (isScriptPackage($bogref) || isPythonPackage($bogref) || isDotNetPackage($bogref)) {
        $file = 'script-assess';
    }        
    else {
        $log->error('copyAssessmentInputs error - packagetype: ', $bogref->{'packagetype'});
        return 0;
    }
    my $frameworkpath = catdir($basedir, 'thirdparty', $file);
    $result &&= copyInput($frameworkpath, $platform_identifier, $dest, $os_dependencies);

	# remove or merge os-dependencies in the input destination directory
	if (-z $os_dependencies) {
		unlink($os_dependencies);
	}
	else {
		_mergeDependencies($os_dependencies);
	}

    return $result;
}

sub needsFloodlightAccessTool { my ($bogref) = @_ ;
    return (isParasoft9Tool($bogref) ||
            isParasoft10Tool($bogref) ||
            isGrammaTechTool($bogref) ||
            isRedLizardTool($bogref) ||
			isSynopsysTool($bogref) ||
			isOWASPDCTool($bogref)
		   );
}

sub isOWASPDCTool { my ($bogref) = @_ ;
	return ($bogref->{'toolname'} eq 'OWASP Dependency Check');
}

sub isClocTool { my ($bogref) = @_ ;
	return ($bogref->{'toolname'} eq 'cloc');
}
sub isSonatypeTool { my ($bogref) = @_ ;
	return ($bogref->{'toolname'} eq 'Sonatype Application Health Check');
}
sub isRubyTool { my ($bogref) = @_ ;
    return (
        $bogref->{'toolname'} eq 'RuboCop' ||
        $bogref->{'toolname'} eq 'ruby-lint' ||
        $bogref->{'toolname'} eq 'Reek' ||
        $bogref->{'toolname'} eq 'Brakeman' ||
        $bogref->{'toolname'} eq 'Dawn'
    );
}
sub isRubyPackage { my ($bogref) = @_ ;
    return (
        $bogref->{'packagetype'} eq $RUBY_PKG_STRING ||
        $bogref->{'packagetype'} eq $RUBY_SINATRA_PKG_STRING ||
        $bogref->{'packagetype'} eq $RUBY_ON_RAILS_PKG_STRING ||
        $bogref->{'packagetype'} eq $RUBY_PADRINO_PKG_STRING
    );
}
sub isFlake8Tool { my ($bogref) = @_ ;
    return ($bogref->{'toolname'} eq 'Flake8');
}
sub isBanditTool { my ($bogref) = @_ ;
    return ($bogref->{'toolname'} eq 'Bandit');
}
sub isAndroidTool { my ($bogref) = @_ ;
    return ($bogref->{'toolname'} eq 'Android lint');
}
sub isHRLTool { my ($bogref) = @_ ;
    return ($bogref->{'toolname'} eq 'HRL');
}
sub isParasoftC { my ($bogref) = @_ ;
    return ($bogref->{'toolname'} eq 'Parasoft C/C++test');
}
sub isParasoftJava { my ($bogref) = @_ ;
    return ($bogref->{'toolname'} eq 'Parasoft Jtest');
}
sub isParasoft9Tool { my ($bogref) = @_ ;
    return ((isParasoftC($bogref) || isParasoftJava($bogref)) && ($bogref->{'tool-version'} =~ m/^9\./));
}
sub isParasoft10Tool { my ($bogref) = @_ ;
    return ((isParasoftC($bogref) || isParasoftJava($bogref)) && ($bogref->{'tool-version'} =~ m/^10\./));
}
sub isGrammaTechCS { my ($bogref) = @_ ;
    return ($bogref->{'toolname'} eq 'GrammaTech CodeSonar');
}
sub isGrammaTechTool { my ($bogref) = @_ ;
    return (isGrammaTechCS($bogref));
}
sub isRedLizardG { my ($bogref) = @_ ;
    return ($bogref->{'toolname'} eq 'Red Lizard Goanna');
}
sub isRedLizardTool { my ($bogref) = @_ ;
    return (isRedLizardG($bogref));
}
sub isSynopsysC { my ($bogref) = @_ ;
	return ($bogref->{'toolname'} eq 'Synopsys Static Analysis (Coverity)');
}
sub isSynopsysTool { my ($bogref) = @_ ;
	return (isSynopsysC($bogref));
}
sub isJavaTool { my ($bogref) = @_ ;
    return ($bogref->{'toolname'} =~ /(Findbugs|PMD|Archie|Checkstyle|error-prone|Parasoft\ Jtest)/isxm);
}
sub isJavaPackage { my ($bogref) = @_ ;
    return (
        $bogref->{'packagetype'} eq $ANDROID_JAVASRC_PKG_STRING ||
        $bogref->{'packagetype'} eq $ANDROID_APK_PKG_STRING ||
        $bogref->{'packagetype'} eq $JAVA7SRC_PKG_STRING ||
        $bogref->{'packagetype'} eq $JAVA7BYTECODE_PKG_STRING ||
        $bogref->{'packagetype'} eq $JAVA8SRC_PKG_STRING ||
        $bogref->{'packagetype'} eq $JAVA8BYTECODE_PKG_STRING
    );
}
sub isJavaBytecodePackage { my ($bogref) = @_ ;
    return (
        $bogref->{'packagetype'} eq $JAVA7BYTECODE_PKG_STRING ||
        $bogref->{'packagetype'} eq $JAVA8BYTECODE_PKG_STRING
    );
}
sub isCTool { my ($bogref) = @_ ;
    return ($bogref->{'toolname'} =~ /(GCC|Clang Static Analyzer|cppcheck)/isxm);
}
sub isCPackage { my ($bogref) = @_ ;
    return ($bogref->{'packagetype'} eq $C_CPP_PKG_STRING);
}
sub isPythonTool { my ($bogref) = @_ ;
    return ($bogref->{'toolname'} =~ /Pylint/isxm);
}
sub isPythonPackage { my ($bogref) = @_ ;
    return ($bogref->{'packagetype'} eq $PYTHON2_PKG_STRING || $bogref->{'packagetype'} eq $PYTHON3_PKG_STRING);
}
sub isScriptPackage { my ($bogref) = @_ ;
    return ($bogref->{'packagetype'} eq $WEB_SCRIPTING_PKG_STRING);
}
sub isDotNetPackage { my ($bogref) = @_ ;
	return ($bogref->{'packagetype'} eq $DOT_NET_PKG_STRING);
}

sub createAssessmentConfigs { my ($bogref, $dest, $user, $password) = @_ ;
    my $goal = q{build+assess+parse};
	my $run_params_hash = {
        	'SWAMP_USERNAME'		=> $user,
        	'SWAMP_USERID'			=> '9999',
        	'SWAMP_GROUPNAME'		=> $user,
        	'SWAMP_GROUPID'			=> '9999',
        	'SWAMP_PASSWORD'		=> $password,
			'DELAY_SHUTDOWN_UNTIL'	=> 1,
			'CAPTURE_FILES'			=> "'/var/log/messages /var/log/boot.log'",
			'CAPTURE_ARCHIVE'		=> 'joboslog.tar.gz',
	};
	if ($bogref->{'use_docker_universe'}) {
		$run_params_hash->{'SWAMP_USERID'} = $REAL_USER_ID;
		$run_params_hash->{'SWAMP_GROUPID'} = $REAL_GROUP_ID + 0; # convert list to scalar
		$run_params_hash->{'SWAMP_EVENT_FILE'} = $HTCONDOR_JOB_EVENTS_FILE;
		$run_params_hash->{'IP_ADDR_FILE'} = $HTCONDOR_JOB_IP_ADDRESS_FILE;
	}
	else {
		$run_params_hash->{'SWAMP_EVENT_FILE'} = $HTCONDOR_JOB_EVENTS_TTY;
		$run_params_hash->{'IP_ADDR_FILE'} = $HTCONDOR_JOB_IP_ADDRESS_TTY;
	}
    if (! saveProperties("$dest/run-params.conf", $run_params_hash)) {
        $log->warn($bogref->{'execrunid'}, " Cannot save run-params.conf");
    }
    my $runprops = {'goal' => $goal};
    $global_swamp_config ||= getSwampConfig();
    my $internet_inaccessible = $global_swamp_config->get('SWAMP-in-a-Box.internet-inaccessible') || 'false';
    $runprops->{'internet-inaccessible'} = $internet_inaccessible;
    if (! saveProperties( "$dest/run.conf", $runprops)) {
        $log->warn($bogref->{'execrunid'}, " Cannot save run.conf");
        return 0;
    }
    if (! _createPackageConf($bogref, $dest)) {
        $log->warn($bogref->{'execrunid'}, " Cannot create package.conf");
        return 0;
    }
    if (! _createUserConf($bogref, $dest)) {
        $log->warn($bogref->{'execrunid'}, " Cannot create user configuration file");
        return 0;
    }
    return 1;
}

sub _getBOGValue { my ($bogref, $key) = @_ ;
    my $ret;
    if (defined($bogref->{$key})) {
        $ret = trim($bogref->{$key});
		$ret =~ s/^null$//sxm;
        if (! length($ret)) {
            $ret = undef;
        }
    }
    return $ret;
}

sub _createPackageConf { my ($bogref, $dest) = @_ ;
    my %packageConfig;
    $packageConfig{'build-sys'}    = _getBOGValue( $bogref, 'packagebuild_system' );
    if (isJavaBytecodePackage($bogref) && ! $packageConfig{'build-sys'}) {
        $packageConfig{'build-sys'} = 'java-bytecode';
    }
    $packageConfig{'build-file'}   = _getBOGValue( $bogref, 'packagebuild_file' );
    $packageConfig{'build-target'} = _getBOGValue( $bogref, 'packagebuild_target' );
    $packageConfig{'build-opt'}    = _getBOGValue( $bogref, 'packagebuild_opt' );
    $packageConfig{'build-dir'}    = _getBOGValue( $bogref, 'packagebuild_dir' );
    $packageConfig{'build-cmd'}    = _getBOGValue( $bogref, 'packagebuild_cmd' );
    $packageConfig{'config-opt'}   = _getBOGValue( $bogref, 'packageconfig_opt' );
    $packageConfig{'config-dir'}   = _getBOGValue( $bogref, 'packageconfig_dir' );
    $packageConfig{'config-cmd'}   = _getBOGValue( $bogref, 'packageconfig_cmd' );
    $packageConfig{'classpath'}    = _getBOGValue( $bogref, 'package_classpath' );

    # 2 new fields for android assess 1.08.2015
    $packageConfig{'android-sdk-target'}    = _getBOGValue( $bogref, 'android_sdk_target' );
    $packageConfig{'android-redo-build'}    = _getBOGValue( $bogref, 'android_redo_build' );

    # 2 new fields for android assess 8.18.2015
    $packageConfig{'android-lint-target'} = _getBOGValue( $bogref, 'android_lint_target' );
    $packageConfig{'gradle-wrapper'} = _getBOGValue( $bogref, 'use_gradle_wrapper' );

    # 2 new fields for android+maven assess 8.31.2015
    $packageConfig{'android-maven-plugin'} = _getBOGValue( $bogref, 'android_maven_plugin' );
    $packageConfig{'maven-version'} = _getBOGValue( $bogref, 'maven_version' );

    # 3 new fields for ruby assess 8.18.2015
    if (isRubyPackage($bogref)) {
        my $bog_package_type = _getBOGValue( $bogref, 'packagetype' );
        my $ruby_language_type = (split q{ }, $bog_package_type)[0];
        my $ruby_package_type = lc((split q{ }, $bog_package_type)[-1]);
        my $bog_language_version = _getBOGValue( $bogref, 'language_version' );
        $packageConfig{'package-language'} = $ruby_language_type;
        $packageConfig{'package-type'} = $ruby_package_type;
        if ($bog_language_version) {
            $packageConfig{'package-language-version'} = lc($ruby_language_type) . q{-} . $bog_language_version;
        }
    }

    # new field for java 8 support
    if (isJavaPackage($bogref)) {
        my $bog_package_type = _getBOGValue($bogref, 'packagetype');
        if ($bog_package_type =~ m/Java\s7/sxm) {
            $packageConfig{'package-language-version'} = 'java-7';
        }
        elsif ($bog_package_type =~ m/Java\s8/sxm) {
            $packageConfig{'package-language-version'} = 'java-8';
        }
    }

    # 3 new fields for bytecode assess 2.10.2014
    $packageConfig{'package-classpath'} = _getBOGValue($bogref, 'packageclasspath');
    $packageConfig{'package-srcdir'} = _getBOGValue($bogref, 'packagebytecodesourcepath');
    $packageConfig{'package-auxclasspath'} = _getBOGValue($bogref, 'packageauxclasspath');

    # 1 new field for script assess 12.15.2016
    if (isScriptPackage($bogref)) {
        $packageConfig{'package-language'} = _getBOGValue($bogref, 'package_language');
    }

    # 1 new field for script assess python assessments 01.20.2017
    if (isPythonPackage($bogref)) {
		my $packagetype = _getBOGValue($bogref, 'packagetype');
		my $packagelanguage = '';
		if ($packagetype eq 'Python2') {
			$packagelanguage = 'Python-2';
		}
		elsif ($packagetype eq 'Python3') {
			$packagelanguage = 'Python-3';
		}
        $packageConfig{'package-language'} = $packagelanguage;
    }

	# 1 new field for ruby assess and web packages assess 03.05.2018 CSA-2369, CSA-2889
	$packageConfig{'package-exclude-paths'} = _getBOGValue($bogref, 'exclude_paths');

	# 1 new field for script assess .NET assessments 10.10.2018
	if (isDotNetPackage($bogref)) {
		$packageConfig{'package-build-settings'} = _getBOGValue($bogref, 'packagebuild_settings');
        $packageConfig{'package-language'} = _getBOGValue($bogref, 'package_language');
	}

    foreach my $key ( keys %packageConfig ) {
        if ( !defined( $packageConfig{$key} ) ) {
            delete $packageConfig{$key};
        }
    }


    $packageConfig{'package-archive'} = basename(_getBOGValue($bogref, 'packagepath'));
    $packageConfig{'package-dir'}     = trim(_getBOGValue($bogref, 'packagesourcepath'));
    $packageConfig{'package-short-name'} = _getBOGValue($bogref, 'packagename');
	$packageConfig{'package-version'} = _getBOGValue($bogref, 'packageversion') || 'unknown';
    return saveProperties("$dest/package.conf", \%packageConfig);
}

sub _createUserConf { my ($bogref, $dest) = @_ ;
	if (isSonatypeTool($bogref)) {
		if (! $bogref->{'user_cnf'}) {
			$log->warn("$bogref->{'execrunid'} No user_cnf - cannot create sonatype-data.conf");
			return 0;
		}
		my $json = from_json_wrapper($bogref->{'user_cnf'});
		if (! defined($json)) {
			$log->warn("$bogref->{'execrunid'} Failed to parse json string: $bogref->{'user_cnf'} error: $@");
			return 0;
		}
		my $userConfig = {};
		if (! exists($json->{'name'})) {
			$log->warn("$bogref->{'execrunid'} user_cnf does not contain user\'s full name: $bogref->{'user_cnf'}");
			return 0;
		}
		if (! exists($json->{'email'})) {
			$log->warn("$bogref->{'execrunid'} user_cnf does not contain user\'s email id: $bogref->{'user_cnf'}");
			return 0;
		}
		if (! exists($json->{'organization'})) {
			$log->warn("$bogref->{'execrunid'} user_cnf does not contain user\'s company name: $bogref->{'user_cnf'}");
			return 0;
		}
    	$global_swamp_config ||= getSwampConfig();
    	my $integrator_name = $global_swamp_config->get('sonatype_integrator');
		if (! $integrator_name) {
			$log->warn("$bogref->{'execrunid'} swamp.conf does not contain sonatype integrator name");
			return 0;
		}
		$userConfig->{'full-name'} = $json->{'name'};
		$userConfig->{'email-id'} = $json->{'email'};
		$userConfig->{'company-name'} = $json->{'organization'};
		$userConfig->{'integrator-name'} = $integrator_name;
		return saveProperties("$dest/sonatype-data.conf", $userConfig);
	}
	return 1;
}

sub _mergeDependencies { my ($file) = @_ ;
    $log->info("_mergeDependencies - file: $file");
    if (open (my $fd, '<', $file)) {
        my %map;
        while (<$fd>) {
            next if (!/=/sxm); # Skip non-property looking lines
            chomp;
            my ($key, $value)=split(/=/sxm,$_);
            $map{$key} .= "$value ";
        }
        close($fd);
        if (open(my $fd, '>', $file)) {
            foreach my $key (sort keys %map) {
                print $fd "$key=$map{$key}\n";
            }
            close($fd);
        }
    }
    return;
}

sub _addUserDepends { my ($bogref, $user_dependencies, $os_dependencies) = @_ ;
    my $dep = trim($bogref->{'packagedependencylist'});
	if (! $dep || ($dep eq q{null})) {
        $log->info("addUserDepends - No packagedependencylist in BOG");
        return;
    }
    if (open(my $fh, '>', $user_dependencies)) {
        $log->info("addUserDepends - opened $user_dependencies");
		my $platform_identifier = $bogref->{'platform_identifier'};
		if ($platform_identifier =~ m/^android-/i) {
			$platform_identifier =~ s/^android-//;
		}
        print $fh "dependencies-${platform_identifier}=$bogref->{'packagedependencylist'}\n";
        if (close($fh)) {
			my $cmd = "cat $user_dependencies >> $os_dependencies";
			my ($output, $status, $error_output) = systemcall($cmd, 1);
			if ($status) {
				$log->error("addUserDepends warning - $cmd failed - $status $output $error_output");
			}
        }
		else {
            $log->error("addUserDepends - Error closing $user_dependencies $OS_ERROR");
		}
    }
    else {
        $log->error("addUserDepends - Cannot create $user_dependencies :$OS_ERROR");
    }
    return;
}

#########################
#   HTCondor ClassAd    #
#########################

sub updateClassAdAssessmentStatus { my ($execrunuid, $vmhostname, $user_uuid, $projectid, $status) = @_ ;
    $log->info("Updating Class Ad Status: $status");
	my $poolarg = q();
	$global_swamp_config ||= getSwampConfig();
	if (! isSwampInABox($global_swamp_config)) {
    	my $HTCONDOR_COLLECTOR_HOST = $global_swamp_config->get('htcondor_collector_host');
		$poolarg = qq(-pool $HTCONDOR_COLLECTOR_HOST);
	}
    my ($output, $stat) = systemcall("condor_advertise $poolarg UPDATE_AD_GENERIC - <<'EOF'
MyType=\"Generic\"
Name=\"$execrunuid\"
SWAMP_vmu_assessment_vmhostname=\"$vmhostname\"
SWAMP_vmu_assessment_status=\"$status\"
SWAMP_vmu_assessment_user_uuid=\"$user_uuid\"
SWAMP_vmu_assessment_projectid=\"$projectid\"
EOF
");
    if ($stat) {
        $log->error("Error - condor_advertise returns: $output $stat");
    }
}

#################################
#	Assessment Result Output	#
#################################

sub parse_statusOutLines { my ($statusOut_lines) = @_ ;
	my $statusOutContent = trim(join "\n", @$statusOut_lines);
	my $statusOut = {};
	my $tasks = [];
	
	# per task collected values
	my $long_message_delimiter_found = 0;
	my $long_message;
	my $long_message_task_name;

	# meta collected values
	my $first_failure_task_name;
	my $weaknesses;
	my $no_files;
	my $no_build;
	my $source_files;
	my $compilable;
	my $retry;
	my $all_pass;
	my $pass_count = 0;
	my $fail_count = 0;
	my $skip_count = 0;
	my $note_count = 0;

	foreach my $line (@$statusOut_lines) {
		# task record
		if ($line =~ m/^\s*
		(PASS|FAIL|SKIP|NOTE)\:	# status
		\s+([a-zA-Z0-9_-]+)		# task
		(?:\s+\((.*)\))?		# optional short message
		(?:\s+(-?\d+\.?\d*))?	# optional duration
		(s|ms|ns)?				# optional units		
		\s*$/x) {
			my ($status, $task_name, $short_message, $duration, $units) = ($1, $2, $3, $4, $5);
			$statusOut->{$task_name} = {
				'task'		=> $task_name,
				'status'	=> $status,
				'short'		=> $short_message,
				'duration'	=> $duration,
				'units'		=> $units,
			};
			push @$tasks, $task_name;
			if ($status eq 'PASS') {
				$pass_count += 1;
				$all_pass = 1 if ($task_name eq 'all');
			}
			elsif ($status eq 'FAIL') {
				$fail_count += 1;
				$first_failure_task_name = $task_name if (! $first_failure_task_name);
				$all_pass = 0 if ($task_name eq 'all');
			}
			elsif ($status eq 'SKIP') {
				$skip_count += 1;
				$no_files = 1 if ($task_name eq 'assess');
			}
			elsif ($status eq 'NOTE') {
				$note_count += 1;
				$retry = 1 if ($task_name eq 'retry');
			}
			if ($task_name eq 'parse-results') {
				if ($short_message =~ m/weaknesses\s*:\s*(\d+)/sxm) {
					$weaknesses = $1;
				}
			}
			elsif ($task_name eq 'no-build-setup') {
				if ($short_message =~ m/source-files\s*:\s*(\d+).*compilable\s*:\s*(\d+)/xsm) {
					$no_build = 1;
					$source_files = $1;
					$compilable = $2;
				}
			}
			$long_message_task_name = $task_name;
		}
		# long message delimiter
		elsif ($line =~ m/^\s*\-+\s*$/) {
			if (! $long_message_delimiter_found) {
				$long_message_delimiter_found = 1;
			}
			else {
				$statusOut->{$long_message_task_name}->{'long'} = $long_message;
				$long_message_delimiter_found = 0;
				$long_message = undef;
			}
		}
		# long message content
		else {
			$long_message .= $line . "\n";
		}
	}
	my $statusOutMeta = {
		'tasks'			=> $tasks,
		'first_failure'	=> $first_failure_task_name,
		'weaknesses'	=> $weaknesses,
		'no_files'		=> $no_files,
		'no_build'		=> $no_build,
		'source_files'	=> $source_files,
		'compilable'	=> $compilable,
		'retry'			=> $retry,
		'all_pass'		=> $all_pass,
		'pass_count'	=> $pass_count,
		'fail_count'	=> $fail_count,
		'skip_count'	=> $skip_count,
		'note_count'	=> $note_count,
	};
	return {
		'status'	=> $statusOut, 
		'meta'		=> $statusOutMeta, 
		'content'	=> $statusOutContent,
	};
}

sub parse_statusOut { my ($statusOut_file) = @_ ;
	if (! $statusOut_file) {
		$log->error("parse_statusOut - statusOut_file not specified");
		return;
	}
	if (! -f $statusOut_file || ! -r $statusOut_file) {
		$log->error("parse_statusOut - $statusOut_file is not a file or is not readable");
		return;
	}
	my $fh;
	if (! open($fh, '<', $statusOut_file)) {
		$log->error("parse_statusOut - open: $statusOut_file failed");
		return;
	}
	my @lines = <$fh>;
	close($fh);
	chomp @lines;
	return parse_statusOutLines(\@lines);
}

my $common_output_files = [qw(buildConf parsedResultsConf resultsConf)];
my $default_output_files = {
	'buildAssessOut'	=> 'build_assess.out',
	'buildConf'			=> 'build.conf', 			# use common
	'captureArchive'	=> 'capture.tar.gz',
	'envSh'				=> 'env.sh',
	'parsedResultsConf'	=> 'parsed_results.conf',	# use common
	'resultsConf'		=> 'results.conf',			# use common
	'runOut'			=> 'run.out',
	'statusOut'			=> 'status.out',
};

sub locate_output_files { my ($outputfolder, $output_files_config_file) = @_ ;
	# top level
	$output_files_config_file = catfile($outputfolder, $output_files_config_file);
	my $output_files = {};
	# if output file list configuration file is not present then use defaults
	# log use of defaults
	if (! -r $output_files_config_file) {
		$output_files = $default_output_files;
		$log->info("locate_output_files - no $output_files_config_file - using default values");
	}
	else {
		# if output file list configuration cannot be loaded then use defaults
		# issue a warning
		if (! loadProperties($output_files_config_file, $output_files)) {
			$output_files = $default_output_files;
			$log->warn("locate_output_files - $output_files_config_file error - using default values");
		}
	}
	foreach my $key (keys %$output_files) {
		if (! -r catfile($outputfolder, $output_files->{$key})) {
			delete $output_files->{$key};
		}
	}
	foreach my $key (@$common_output_files) {
		if (! defined($output_files->{$key}) && defined($default_output_files->{$key}) && -r catfile($outputfolder, $default_output_files->{$key})) {
			$output_files->{$key} = $default_output_files->{$key};
		}
	}
	# buildConf
	my $build_output_files = {};
	if (_loadConfig($outputfolder, $output_files, 'buildConf', $build_output_files)) {
		# preserve the file name for buildConf
		$output_files->{'buildConfFile'} = $output_files->{'buildConf'};
		$output_files->{'buildConf'} = $build_output_files;
	}
	# resultsConf
	my $results_output_files = {};
	if (_loadConfig($outputfolder, $output_files, 'resultsConf', $results_output_files)) {
		# preserve the file name for resultsConf
		$output_files->{'resultsConfFile'} = $output_files->{'resultsConf'};
		$output_files->{'resultsConf'} = $results_output_files;
	}
	# parsedResultsConf
	my $parsed_results_output_files = {};
	if (_loadConfig($outputfolder, $output_files, 'parsedResultsConf', $parsed_results_output_files)) {
		# preserve the file name for parsedResultsConf
		$output_files->{'parsedResultsConfFile'} = $output_files->{'parsedResultsConf'};
		$output_files->{'parsedResultsConf'} = $parsed_results_output_files;
	}
	return $output_files;
}

sub _loadConfig { my ($outputfolder, $output_files, $config_key, $result) = @_ ;
	if (! $config_key) {
		$log->error("_loadConfig config_key not specified");
		return;
	}
	if (! defined($output_files->{$config_key})) {
		$log->warn("_loadConfig $config_key not found in output_files");
		return;
	}
	my $configfile = catfile($outputfolder, $output_files->{$config_key});
	if (! -f $configfile || ! -r $configfile) {
		$log->error("_loadConfig - $config_key: $configfile not found");
		return;
	}
	my $config = $result;
	if (ref $config eq ref {}) {
		my $status = loadProperties($configfile, $config);
	}
	else {
		$config = loadProperties($configfile);
	}
	if (! defined($config)) {
		$log->error("_loadConfig - $config_key: failed to read $configfile");
		return;
	}
	if (! scalar(keys %$config)) {
		$log->error("_loadConfig - $config_key: $configfile is empty");
		return;
	}
	return $config;
}

1;
