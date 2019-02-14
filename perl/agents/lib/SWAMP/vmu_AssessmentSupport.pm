# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2019 Software Assurance Marketplace

package SWAMP::vmu_AssessmentSupport;
use strict;
use warnings;
use English '-no_match_vars';
use RPC::XML;
use RPC::XML::Client;
use Date::Parse qw(str2time);
use Log::Log4perl;
use Archive::Tar;
use File::Basename qw(basename);
use File::Copy qw(move copy);
use File::Spec::Functions;
use POSIX qw(strftime);

use SWAMP::vmu_Support qw(
	use_make_path
	getUUID
	from_json_wrapper
    trim
    systemcall
    getSwampDir
    saveProperties
	checksumFile
	launchPadStart
	database_connect
	database_disconnect
	displaynameToMastername
	masternameToPlatform
	isSwampInABox
	isAssessmentRun
	isMetricRun
	isViewerRun
	$LAUNCHPAD_SUCCESS
	$LAUNCHPAD_BOG_ERROR
	$LAUNCHPAD_FILESYSTEM_ERROR
	$LAUNCHPAD_CHECKSUM_ERROR
	$LAUNCHPAD_FORK_ERROR
	$LAUNCHPAD_FATAL_ERROR
    getSwampConfig
	$global_swamp_config
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
    $log->info("Execrunuid: $bogref->{'execrunid'}");
    $log->info("Package: $bogref->{'packagename'} $bogref->{'packagepath'}");
    $log->info("Tool: $bogref->{'toolname'} $bogref->{'toolpath'}");
    $log->info("Platform: $bogref->{'platform'}");
}

my $bogtranslator = {
	'platforms'	=> {
		'platform_path'		=> 'platform',
	},
	'tools'		=> {
		'tool_name'			=> 'toolname',
		'tool_path'			=> 'toolpath',
		'version_string'	=> 'tool-version',
	},
	'packages'	=> {
		'package_name' 		=> 'packagename', 			
		'package_version' 	=> 'packageversion', 			
		'package_build_settings'	=> 'packagebuild_settings',
		'build_target' 		=> 'packagebuild_target',		
		'build_system' 		=> 'packagebuild_system',		
		'build_dir' 		=> 'packagebuild_dir',		
		'build_opt' 		=> 'packagebuild_opt',		
		'build_cmd' 		=> 'packagebuild_cmd',		
		'config_opt' 		=> 'packageconfig_opt',		
		'config_dir' 		=> 'packageconfig_dir',		
		'config_cmd' 		=> 'packageconfig_cmd',		
		'package_path' 		=> 'packagepath',			
		'source_path' 		=> 'packagesourcepath',		
		'build_file' 		=> 'packagebuild_file',		
		'package_type' 		=> 'packagetype',			
		'bytecode_class_path'		=> 'packageclasspath',		
		'bytecode_aux_class_path'	=> 'packageauxclasspath',		
		'bytecode_source_path'		=> 'packagebytecodesourcepath',	
		'android_sdk_target'		=> 'android_sdk_target', 		
		'android_redo_build'		=> 'android_redo_build', 		# boolean converted to string
		'use_gradle_wrapper'		=> 'use_gradle_wrapper', 		# boolean converted to string
		'android_lint_target'		=> 'android_lint_target',		
		'language_version'	=> 'language_version', 		
		'maven_version'		=> 'maven_version', 			
		'android_maven_plugin'		=> 'android_maven_plugin', 		
		'package_language'	=> 'package_language', 		
		'exclude_paths'		=> 'exclude_paths',
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
    my $dbh = database_connect();
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
        database_disconnect($dbh);
	}
	else {
		$log->error("_computeBOG - database connection failed");
		return $LAUNCHPAD_BOG_ERROR;
	}
	if (! $bog_query_result) {
		return $LAUNCHPAD_BOG_ERROR;
	}

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
	if (! $bog->{'platform'}) {
		$log->error("no platform in database record");
		return $LAUNCHPAD_BOG_ERROR;
	}
	my $qcow = displaynameToMastername($bog->{'platform'});
	if (! $qcow) {
		$log->error("no qcow file for ", $bog->{'platform'});
		return $LAUNCHPAD_BOG_ERROR;
	}
	my $platform = masternameToPlatform($qcow);
	if (! $platform) {
		$log->error("no platform component in $qcow for ", $bog->{'platform'});
		return $LAUNCHPAD_BOG_ERROR;
	}
	$bog->{'platform'} = $platform;
	
    return $bog;
}
    
sub incrementLaunchCounter { my ($execrunuid, $current) = @_ ;
	my $success = 0;
	return 1 if (isViewerRun($execrunuid));
	if (my $dbh = database_connect()) {
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
		database_disconnect($dbh);
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
	if (my $dbh = database_connect()) {
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
		database_disconnect($dbh);
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
	if (my $dbh = database_connect()) {
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
		database_disconnect($dbh);
	}
	else {
		$log->error("getLaunchExecrunuids - database connection failed");
	}
	return $execrunuids;
}

sub doRun { my ($execrunuid) = @_ ;
    $tracelog->trace("doRun called with execrunuid: $execrunuid");
    my $options = _computeBOG($execrunuid);
	# options is either a hash reference to the BOG
	# or and enumeration of a LAUNCHPAD_*_ERROR
	if (ref $options) {
    	$tracelog->trace("doRun - _computeBOG returned bog - calling launchPadStart");
		my $retval = launchPadStart($options);
    	$tracelog->trace("doRun - launchPadStart returned: $retval");
    	return $retval;
	}
	$tracelog->error("doRun failed to compute BOG for: $execrunuid error: $options");
	$log->error("doRun failed to compute BOG for: $execrunuid error: $options");
	return $options;
}

sub updateExecutionResults { my ($execrunid, $newrecord, $finalStatus) = @_ ;
	if (my $dbh = database_connect()) {
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
		database_disconnect($dbh);
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
	if (my $dbh = database_connect()) {
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
		database_disconnect($dbh);
	}
	else {
		$log->error("saveMetricSummary - database connection failed");
	}
}

sub saveAssessmentResult { my ($bogref, $assessment_results) = @_ ;
    if (!defined($assessment_results->{'pathname'})) {
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
        $log->error("Error - make_path failed for: $result_dest_path");
        return 0;
	}
	my $log_dest_path = catdir(rootdir(), 'swamp', 'SCAProjects', $project_uuid, 'A-Logs', $assessment_result_uuid);
	if (! use_make_path($log_dest_path)) {
        $log->error("Error - make_path failed for: $log_dest_path");
        return 0;
	}

	if (! copy($assessment_results->{'pathname'}, $result_dest_path)) {
        $log->error('saveAssessmentResult - copy ', $assessment_results->{'pathname'}, " to $result_dest_path failed: $OS_ERROR");
        return 0;
	}
	$log->info('Copied: ', $assessment_results->{'pathname'}, " to: $result_dest_path");
	my $result_file = catfile($result_dest_path, basename($assessment_results->{'pathname'}));

	if (! copy($assessment_results->{'sourcepathname'}, $result_dest_path)) {
        $log->error('saveAssessmentResult - copy ', $assessment_results->{'sourcepathname'}, " to $result_dest_path failed: $OS_ERROR");
        return 0;
	}
	$log->info('Copied: ', $assessment_results->{'sourcepathname'}, " to: $result_dest_path");
	my $source_file = catfile($result_dest_path, basename($assessment_results->{'sourcepathname'}));

	if (! copy($assessment_results->{'logpathname'}, $log_dest_path)) {
        $log->error('saveAssessmentResult - copy ', $assessment_results->{'logpathname'}, " to $log_dest_path failed: $OS_ERROR");
        return 0;
	}
	$log->info('Copied: ', $assessment_results->{'logpathname'}, " to: $log_dest_path");
	my $log_file = catfile($log_dest_path, basename($assessment_results->{'logpathname'}));

	if (my $dbh = database_connect()) {
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
		database_disconnect($dbh);
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
        $log->error("Error - make_path failed for: $result_dest_path");
        return 0;
	}

	if (! copy($metric_results->{'pathname'}, $result_dest_path)) {
        $log->error('saveMetricResult - copy ', $metric_results->{'pathname'}, " to $result_dest_path failed: $OS_ERROR");
        return 0;
	}
	$log->info('Copied: ', $metric_results->{'pathname'}, " to: $result_dest_path");
	my $result_file = catfile($result_dest_path, basename($metric_results->{'pathname'}));

	my $result = 0;
	if (my $dbh = database_connect()) {
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
		database_disconnect($dbh);
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

# first check for files with platform in the path
# if none found
# then check for files with noarch in the path
# if symbolic links are found, pass back to caller
# and call again recursively - nested links are not handled
sub _copy_tool_files { my ($tar, $files, $platform, $dest) = @_ ;
    my $retval = [];
    my $found = 0;
    foreach my $file (@{$files}) {
        next if ($file->name =~ m/\/$/sxm);
         next if ($file->name !~ m/$platform/sxm);
         if ($file->is_symlink) {
             push @{$retval}, $file;
             next;
         }
         my $filename = basename($file->name);
        $log->debug("_copy_tool_files - extract: $file->name to $dest/$filename");
         $tar->extract_file($file->name, "$dest/$filename");
        $found = 1;
    }
    if (! $found) {
        foreach my $file (@{$files}) {
            next if ($file->name =~ m/\/$/sxm);
            next if ($file->name !~ m/noarch/sxm);
            my $filename = basename($file->name);
            $log->debug("_copy_tool_files - extract: $file->name to $dest/$filename");
            $tar->extract_file($file->name, "$dest/$filename");
        }
    }
    return $retval;
}

sub _copyInputsTools { my ($bogref, $dest) = @_ ;
    my $tar = Archive::Tar->new($bogref->{'toolpath'}, 1);
    my @files = $tar->get_files();
    # if tool bundle uses symbolic link for this platform handle that here
    my $links = _copy_tool_files($tar, \@files, $bogref->{'platform'}, $dest);
    foreach my $link (@{$links}) {
        _copy_tool_files($tar, \@files, $link->linkname, $dest);
    }
    if (-r "$dest/os-dependencies-tool.conf") {
        $log->debug("Adding $dest/os-dependencies-tool.conf");
        system("cat $dest/os-dependencies-tool.conf >> $dest/os-dependencies.conf");
    }
    # merge tool-os-dependencies.conf into os-dependencies.conf if extant
    if (-r "$dest/tool-os-dependencies.conf") {
        $log->debug("Adding $dest/tool-os-dependencies.conf");
        system("cat $dest/tool-os-dependencies.conf >> $dest/os-dependencies.conf");
    }
    return 1;
}

sub copyAssessmentInputs { my ($bogref, $dest) = @_ ;
    if (!defined($bogref->{'packagepath'})) {
        $log->error($bogref->{'execrunid'}, "BOG is missing packagepath specification.");
        return 0;
    }
	if (! -r $bogref->{'packagepath'}) {
        $log->error($bogref->{'execrunid'}, ' package: ', $bogref->{'packagepath'}, ' not readable.');
		return 0;
	}
    if (!defined( $bogref->{'toolpath'})) {
        $log->error($bogref->{'execrunid'}, "BOG is missing toolpath specification.");
        return 0;
    }
	if (! -r $bogref->{'toolpath'}) {
        $log->error($bogref->{'execrunid'}, ' tool: ', $bogref->{'toolpath'}, ' not readable.');
		return 0;
	}
	my $status;
	eval {
		$status = _copyInputsTools($bogref, $dest);
	};
	if ($@ || ! $status) {
		$log->error("_copyInputsTools failed for: ", $bogref->{'toolpath'}, ' status: ', defined($status) ? $status : 'no status',  " eval result: $@");
		return 0;
	}
	
    my $basedir = getSwampDir();
    # copy services.conf to the input destination directory
	my $servicesconf = catfile($basedir, 'etc', 'services.conf');
    if (! copy($servicesconf, $dest)) {
        $log->error($bogref->{'execrunid'}, "Cannot copy $servicesconf to $dest $OS_ERROR");
        return 0;
    }
	
    # Copy the package tarball into VM input folder from the SAN.
    if (! copy($bogref->{'packagepath'}, $dest)) {
        $log->error($bogref->{'execrunid'}, "Cannot read packagepath $bogref->{'packagepath'} $OS_ERROR");
        return 0;
    }

    _addUserDepends($bogref, "$dest/os-dependencies.conf");
    my $file = "$basedir/thirdparty/resultparser.tar";
    _deployTarball($file, $dest);
    # Add result parser's *-os-dependencies.conf to the mix, and merge for uniqueness
    if (-r "$dest/os-dependencies-parser.conf") {
        $log->debug("Adding $dest/os-dependencies-parser.conf");
        system("cat $dest/os-dependencies-parser.conf >> $dest/os-dependencies.conf");
    }

    if (! _copyFramework($bogref, $basedir, $dest)) {
        return 0;
    }

    return 1;
}

sub _deployTarByPlatform { my ($tarfile, $compressed, $dest, $platform) = @_ ;
    $log->debug("_deployTarByPlatform - tarfile: $tarfile platform: $platform dest: $dest");
    my $iter = Archive::Tar->iter($tarfile, $compressed, {'filter' => qr/$platform/sxm});
    my $member = $iter->();
    if (! $member) {
        $iter = Archive::Tar->iter($tarfile, $compressed, {'filter' => qr/noarch/sxm});
        $member = $iter->();
    }
    if (! $member) {
        $log->error("_deployTarByPlatform - $platform and noarch not found in $tarfile");
    }
    while ($member) {
        if ($member->is_dir) {
            $member = $iter->();
            next;
        }
        if ($member->is_symlink) {
            my $linkname = $member->linkname;
            $linkname =~ s/^(?:\.\.\/)*//sxm;
            my $link = Archive::Tar->iter($tarfile, $compressed, {'filter' => qr/$linkname/sxm})->();
            if ($link->is_dir) {
                $linkname = $link->name;
                my $linkiter = Archive::Tar->iter($tarfile, $compressed, {'filter' => qr/$linkname/sxm});
                while (my $linkmember = $linkiter->()) {
                    if ($linkmember->is_dir) {
                        $member = $iter;
                        next;
                    }
                    my $basename = basename($linkmember->name);
                    my $destname = $dest . qq{/}. $basename;
                    if ($linkmember->name =~ m/swamp-conf\/sys-os-dependencies.conf/sxm) {
                        $destname = $dest . qq{/os-dependencies-framework.conf};
                    }
                    $log->debug("_deployTarByPlatform - extract symlink dir: $destname to $dest");
                    $linkmember->extract($destname);
                }
            }
            else {
                my $basename = basename($link->name);
                my $destname = $dest . qq{/}. $basename;
                if ($link->name =~ m/swamp-conf\/sys-os-dependencies.conf/sxm) {
                    $destname = $dest . qq{/os-dependencies-framework.conf};
                }
                $log->debug("_deployTarByPlatform - extract symlink file: $destname to $dest");
                $link->extract($destname);
            }
        }
        else {
            my $basename = basename($member->name);
            my $destname = $dest . qq{/}. $basename;
            if ($member->name =~ m/swamp-conf\/sys-os-dependencies.conf/sxm) {
                $destname = $dest . qq{/os-dependencies-framework.conf};
            }
            $log->debug("_deployTarByPlatform - extract file: $destname to $dest");
            $member->extract($destname);
        }
        $member = $iter->();
    }
    return;
}

sub _copyFramework { my ($bogref, $basedir, $dest) = @_ ;
    my $file;
    if (isJavaPackage($bogref)) {
        $file = "$basedir/thirdparty/java-assess.tar";
    }
    elsif (isRubyPackage($bogref)) {
        $file = "$basedir/thirdparty/ruby-assess.tar";
    }
    elsif (isCPackage($bogref)) {
        $file = "$basedir/thirdparty/c-assess.tar";
    }
    elsif (isScriptPackage($bogref) || isPythonPackage($bogref) || isDotNetPackage($bogref)) {
        $file = "$basedir/thirdparty/script-assess.tar";
    }
    my $compressed = 0;
    if (! -r $file) {
		$file .= '.gz';
		$compressed = 1;
    	if (! -r $file) {
        	$log->error($bogref->{'execrunid'}, "Cannot see assessment toolchain $file");
        	return 0;
		}
    }
    my $platform = $bogref->{'platform'} . qq{/};
	$log->info("using framework: $file $compressed on platform: $platform");
    _deployTarByPlatform($file, $compressed, $dest, $platform);
    if (-r "$dest/os-dependencies-framework.conf") {
        $log->debug("Adding $dest/os-dependencies-framework.conf");
        system("cat $dest/os-dependencies-framework.conf >> $dest/os-dependencies.conf");
    }

    # remove empty os-dependencies file
    if (-z "$dest/os-dependencies.conf") {
        unlink("$dest/os-dependencies.conf");
    }
    else {
        _mergeDependencies("$dest/os-dependencies.conf");
    }

    # Preserve the provided run.sh, we'll invoke it from our run.sh
    if (-r "$dest/run.sh") {
        $log->debug("renaming $dest/run.sh");
        if (! move( "$dest/run.sh", "$dest/_run.sh")) {
            $log->error($bogref->{'execrunid'}, "Cannot move run.sh to _run.sh in $dest");
			return 0;
        }
    }
    return 1;
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
    if (! saveProperties("$dest/run-params.conf", {
        'SWAMP_USERNAME' => $user,
        'SWAMP_USERID' => '9999',
        'SWAMP_PASSWORD'=> $password}
    )) {
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
        $ret =~ s/null//sxm;
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
    $log->debug("_mergeDependencies - file: $file");
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
            foreach my $key (keys %map) {
                print $fd "$key=$map{$key}\n";
            }
            close($fd);
        }
    }
    return;
}

sub _addUserDepends { my ($bogref, $destfile) = @_ ;
    my $dep = trim($bogref->{'packagedependencylist'});
	if (! $dep || ($dep eq q{null})) {
        $log->info("addUserDepends - No packagedependencylist in BOG");
        return;
    }
    if (open(my $fh, '>>', $destfile)) {
        $log->info("addUserDepends - opened $destfile");
        print $fh "dependencies-$bogref->{'platform'}=$bogref->{'packagedependencylist'}\n";
        if (! close($fh)) {
            $log->warn("adduserDepends - Error closing $destfile: $OS_ERROR");
        }
    }
    else {
        $log->error("addUserDepends - Cannot append to $destfile :$OS_ERROR");
    }
    return;
}

sub _parserDeploy { my ($opts) = @_;
    my $member = $opts->{'member'};
    my $tar = $opts->{'archive'};
    my $dest = $opts->{'dest'};
    if ($member =~ /parser-os-dependencies.conf/sxm) {
        $log->debug("_parserDeploy - extract: $member to $dest/os-dependencies-parser.conf");
        $tar->extract_file($member, "$dest/os-dependencies-parser.conf");
    }
    if ($member =~ /in-files/sxm) {
        my $filename = basename($member);
        $log->debug("_parserDeploy - extract: $member to $dest/$filename");
        $tar->extract_file($member, "$dest/$filename");
    }
    return;
}

sub _deployTarball { my ($tarfile, $dest) = @_ ;
    my $tar = Archive::Tar->new($tarfile, 1);
    my @list = $tar->list_files();
    my %options = ('archive' => $tar, 'dest' => $dest);
    foreach my $member (@list) {
        # Skip directory
        next if ($member =~ /\/$/sxm);
        $options{'member'} = $member;
        _parserDeploy(\%options);
    }
    return 1;
}

#########################
#   HTCondor ClassAd    #
#########################

sub updateClassAdAssessmentStatus { my ($execrunuid, $vmhostname, $user_uuid, $projectid, $status) = @_ ;
    $log->info("Status: $status");
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

1;
