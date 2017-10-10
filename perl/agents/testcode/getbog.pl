#!/usr/bin/env perl
use strict;
use warnings;
use DBI;
use Data::Dumper;
use lib '/opt/swamp/perl5';
use SWAMP::vmu_Support qw(
	database_connect 
	database_disconnect 
	saveProperties
	checksumFile
	getSwampConfig
);

my $translate = {
	'platforms'	=> {
		'platform_path'		=> 'platform',
	},
	'tools'		=> {
		'tool_name'			=> 'toolname',
		'tool_path'			=> 'toolpath',
		'tool_arguments'	=> 'toolarguments',
		'tool_executable'	=> 'toolexecutable',
		'tool_directory'	=> 'tooldirectory',
		'version_string'	=> 'tool-version',
		'IsBuildNeeded'		=> 'buildneeded',
	},
	'packages'	=> {
		'package_name' 		=> 'packagename', 			
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
	},
	'package_dependency'	=> {
    	'packagedependencylist'		=> 'packagedependencylist',
	},
};

sub translateToBOG { my ($merge, $title, $hashref, $keepnulls) = @_ ;
	foreach my $key (keys %$hashref) {
		if (exists($translate->{$title}->{$key})) {
			my $newkey = $translate->{$title}->{$key};
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

sub writeBOG { my ($execrun_uuid) = @_ ;
	my $execution_record;
	my ($platform_version, $tool_version, $package_version, $package_dependency);
	my ($tool_path, $package_path);
	my ($tool_version_checksum, $package_version_checksum);
    my $dbh = database_connect();
    if ($dbh) {
		# execution_record_uuid_in
    	my $query = q{CALL assessment.select_execution_record(?);};
		my $sth = $dbh->prepare($query);
		$sth->bind_param(1, $execrun_uuid);
		$sth->execute();
		if ($sth->err) {
			print "Error - select_execution_record - error: $sth->errstr\n";
			$sth->finish();
			database_disconnect();
			return 0;
		}
		$execution_record = $sth->fetchrow_hashref();
		$sth->finish();
		print "select_execution_record\n";
		print Dumper($execution_record);
		my $platform_version_uuid = $execution_record->{'platform_version_uuid'};
		my $tool_version_uuid = $execution_record->{'tool_version_uuid'};
		my $package_version_uuid = $execution_record->{'package_version_uuid'};
		if ($platform_version_uuid) {
			# platform_version_uuid_in
    		$query = q{CALL platform_store.select_platform_version(?);};
			$sth = $dbh->prepare($query);
			$sth->bind_param(1, $platform_version_uuid);
			$sth->execute();
			if ($sth->err) {
				print "Error - select_platform_version - error: $sth->errstr\n";
				$sth->finish();
				database_disconnect();
				return 0;
			}
			$platform_version = $sth->fetchrow_hashref();
			$sth->finish();
			if (! $platform_version) {
				print "Error - select_platform_version - no platform_version record\n";
				database_disconnect();
				return 0;
			}
			print "select_platform_version\n";
			print Dumper($platform_version);
		}
		else {
			print "Error - select_platform_version - no platform_version_uuid\n";
			database_disconnect();
			return 0;
		}
		if ($tool_version_uuid && $package_version_uuid) {
			# tool_version_uuid_in
			# platform_version_uuid_in
			# package_version_uuid_in
    		$query = q{CALL tool_shed.select_tool_version(?, ?, ?);};
			$sth = $dbh->prepare($query);
			$sth->bind_param(1, $tool_version_uuid);
			$sth->bind_param(2, $platform_version_uuid);
			$sth->bind_param(3, $package_version_uuid);
			$sth->execute();
			if ($sth->err) {
				print "Error - select_tool_version - error: $sth->errstr\n";
				$sth->finish();
				database_disconnect();
				return 0;
			}
			$tool_version = $sth->fetchrow_hashref();
			$sth->finish();
			if (! $tool_version) {
				print "Error - select_tool_version - no tool_version record\n";
				database_disconnect();
				return 0;
			}
			print "select_tool_version\n";
			print Dumper($tool_version);
			$tool_path = $tool_version->{'tool_path'};
			$tool_version_checksum = $tool_version->{'checksum'};
		}
		else {
			print "Error - select_tool_version - no tool_version_uuid or no package_version_uuid\n";
			database_disconnect();
			return 0;
		}
		if ($package_version_uuid) {
			# package_version_uuid_in
    		$query = q{CALL package_store.select_pkg_version(?);};
			$sth = $dbh->prepare($query);
			$sth->bind_param(1, $package_version_uuid);
			$sth->execute();
			if ($sth->err) {
				print "Error - select_pkg_version - error: $sth->errstr\n";
				$sth->finish();
				database_disconnect();
				return 0;
			}
			$package_version = $sth->fetchrow_hashref();
			$sth->finish();
			if (! $package_version) {
				print "Error - select_pkg_version - no package_version record\n";
				database_disconnect();
				return 0;
			}
			print "select_pkg_version\n";
			print Dumper($package_version);
			$package_path = $package_version->{'package_path'};
			$package_version_checksum = $package_version->{'checksum'};
		}
		else {
			print "Error - select_pkg_version - no package_version_uuid\n";
			database_disconnect();
			return 0;
		}
		if ($package_version_uuid && $platform_version_uuid) {
			# package_version_uuid_in
			# platform_version_uuid_in
			# dependency_found_flag
			# dependency_list_out
    		$query = q{CALL package_store.fetch_pkg_dependency(?, ?, @r1, @r2);};
			$sth = $dbh->prepare($query);
			$sth->bind_param(1, $package_version_uuid);
			$sth->bind_param(1, $platform_version_uuid);
			$sth->execute();
			if ($sth->err) {
				print "Error - fetch_pkg_dependency - error: $sth->errstr\n";
				$sth->finish();
				database_disconnect();
				return 0;
			}
			$sth->finish();
			my $dependency_found_flag = $dbh->selectrow_array('SELECT @r1');
			my $dependency_list_out = $dbh->selectrow_array('SELECT @r2');
			if ($dependency_found_flag && $dependency_found_flag eq 'Y' && $dependency_list_out) {
				$package_dependency->{'packagedependencylist'} = $dependency_list_out;
				print "fetch_pkg_dependency\n";
				print Dumper($package_dependency);
			}
			else {
				$package_dependency->{'packagedependencylist'} = undef;
			}
		}
		else {
			print "Error - fetch_pkg_dependency - no package_version_uuid or no platform_version_uuid\n";
			database_disconnect();
			return 0;
		}
    	database_disconnect($dbh);
    }   
	# Other stuff - not from the database
	my $merge = {};
	$merge->{'execrunid'} = $execrun_uuid;
	$merge->{'projectid'} = $execution_record->{'project_uuid'};
	$merge->{'userid'} = $execution_record->{'user_uuid'};
	$merge->{'version'} = '2';
	my $config = getSwampConfig();
	my $results_folder = $config->get('resultsFolder');
	$merge->{'resultsfolder'} = $results_folder;
	if (! -d $results_folder) {
		print "Error - no results folder\n";
		return 0;
	}
	translateToBOG($merge, 'platforms', $platform_version, 1);
	translateToBOG($merge, 'tools', $tool_version, 1);
	translateToBOG($merge, 'packages', $package_version, 1);
	translateToBOG($merge, 'package_dependency', $package_dependency, 1);
	if ($tool_path && -r $tool_path && $tool_version_checksum) {
		if (my $checksum = checksumFile($tool_path) ne $tool_version_checksum) {
			print "Error - checksum mismatch for: $tool_path\n";
			print "Found: $checksum - expected: $tool_version_checksum\n";
			return 0;
		}
	}
	else {
		print "Error - no tool_path or tool_version_checksum\n";
		return 0;
	}
	if ($package_path && -r $package_path && $package_version_checksum) {
		if (my $checksum = checksumFile($package_path) ne $package_version_checksum) {
			print "Error - checksum mismatch for: $package_path\n";
			print "Found: $checksum - expected: $package_version_checksum\n";
			return 0;
		}
	}
	else {
		print "Error - no package_path or package_version_checksum\n";
		return 0;
	}
	saveProperties($execrun_uuid . '_A.bog', $merge, 'merged bog file');
    return 1;
}
    
my $execrun_uuid = $ARGV[0];
if (defined($execrun_uuid)) {
	my $result = writeBOG($execrun_uuid);
	print "result: <$result>\n";
}
else {
	print "Error - no execrun_uuid\n";
}

print "Hello World\n";
