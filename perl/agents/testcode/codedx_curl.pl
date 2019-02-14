#!/usr/bin/env perl
use strict;
use warnings;
use Log::Log4perl qw(:easy);
use lib '/opt/swamp/perl5';
use lib '../lib';
use SWAMP::vmu_Support qw(
	systemcall
	from_json_wrapper
	makezip
);

Log::Log4perl->easy_init($ALL);

my $codedx_host = 'codedx.mirsam.org';
my $api_key = '7c882499-f824-49f4-9615-cd0bb9c1115c';
$api_key = '';
my $user = 'tbricker';
my $password = 'swamp';

sub build_authentication { my ($api_key, $user, $password) = @_ ;
	my $api_key_header = '';
	my $authentication = '';
	if ($api_key) {
		$api_key_header = qq{-H "API-Key: $api_key"};
	}
	elsif ($user && $password) {
		$authentication = qq{$user:$password@};
	}
	return ($api_key_header, $authentication);
}

sub list_projects { my ($api_key, $user, $password) = @_ ;
	my ($api_key_header, $authentication) = build_authentication($api_key, $user, $password);
	if (! $api_key_header && ! $authentication) {
		print "error - no authentication\n";
		return;
	}
	my $curl = qq{curl --silent --insecure $api_key_header -H "accept: application/json" -H "Content-Type: application/json" -X GET "https://${authentication}${codedx_host}/codedx/api/projects"};
	my ($output, $status) = systemcall($curl);
	if ($status) {
		print "error - curl:\n$curl\nstatus: $status output: $output\n";
		return;
	}
	print "$curl\noutput\n$output\n\n";
	my $result = from_json_wrapper($output);
	if (! $result) {
		print "error - json - curl:\n$curl\nstatus: $status output: $output\n";
	}
	return $result;
}

sub get_project_id { my ($project_name, $api_key, $user, $password) = @_ ;
	my $projects = list_projects($api_key, $user, $password);
	return if (! $projects);
	$projects = $projects->{'projects'};
	return if (! $projects);
	foreach my $project (@$projects) {
		if ($project->{'name'} eq $project_name) {
			return $project->{'id'};
		}
	}
	return;
}

sub create_project { my ($project_name, $api_key, $user, $password) = @_ ;
	my ($api_key_header, $authentication) = build_authentication($api_key, $user, $password);
	if (! $api_key_header && ! $authentication) {
		print "error - no authentication\n";
		return;
	}
	if (! $project_name) {
		print "error - no project_name\n";
		return;
	}
  	my $curl = qq{curl --silent --insecure $api_key_header -H "accept: application/json" -H "Content-Type: application/json" -X PUT "https://${authentication}${codedx_host}/codedx/api/projects" -d "{\\"name\\":\\"$project_name\\"}"};
	my ($output, $status) = systemcall($curl);
	if ($status) {
		print "error - curl:\n$curl\nstatus: $status output: $output\n";
		return;
	}
	print "$curl\noutput\n$output\n\n";
	my $result = from_json_wrapper($output);
	if (! $result) {
		print "error - json - curl:\n$curl\nstatus: $status output: $output\n";
	}
	my $project_id;
	if (defined($result->{'id'})) {
		$project_id = $result->{'id'};
	}
	return $project_id;
}

sub prepare_analysis { my ($project_id, $api_key, $user, $password) = @_ ;
	my ($api_key_header, $authentication) = build_authentication($api_key, $user, $password);
	if (! $api_key_header && ! $authentication) {
		print "error - no authentication\n";
		return;
	}
	if (! $project_id) {
		print "error - no project_id\n";
		return;
	}
  	my $curl = qq{curl --silent --insecure $api_key_header -H "accept: application/json" -H "Content-Type: application/json" -X POST "https://${authentication}${codedx_host}/codedx/api/analysis-prep" -d "{\\"projectId\\":\\"$project_id\\"}"};
	my ($output, $status) = systemcall($curl);
	if ($status) {
		print "error - curl:\n$curl\nstatus: $status output: $output\n";
		return;
	}
	print "$curl\noutput\n$output\n\n";
	my $result = from_json_wrapper($output);
	if (! $result) {
		print "error - json - curl:\n$curl\nstatus: $status output: $output\n";
	}
	my $prep_id;
	if (defined($result->{'prepId'})) {
		$prep_id = $result->{'prepId'};
	}
	return $prep_id;
}
	
sub upload_analysis { my ($project_name, $files, $api_key, $user, $password) = @_;
	my $project_id = get_project_id($project_name, $api_key, $user, $password);
	if (! $project_id) {
		print "error - could not get projectId for $project_name\n";
		return;
	}
	my $prep_id = prepare_analysis($project_id, $api_key, $user, $password);
	if (! $prep_id) {
		print "error - could not get prepId for $project_name\n";
		return;
	}
	my ($api_key_header, $authentication) = build_authentication($api_key, $user, $password);
	if (! $api_key_header && ! $authentication) {
		print "error - no authentication\n";
		return;
	}
	foreach my $file (@$files) {
		my $removeZip = 0;
		if (($file !~ m/\.zip$/) && ($file !~ m/\.xml/)) {
			$file = makezip($file);
			$removeZip = ($file =~ m/\.zip$/);
		}
		my $curl = qq{curl --silent --insecure $api_key_header -H "accept: application/json" -H "Content-Type: multipart/form-data" -X POST "https://${authentication}${codedx_host}/codedx/api/analysis-prep/$prep_id/upload" -F "file=\@${file};type=text/xml"};
		my ($output, $status) = systemcall($curl);
		unlink $file if ($removeZip);
		if ($status) {
			print "error - curl:\n$curl\nstatus: $status output: $output\n";
			return;
		}
		print "$curl\noutput\n$output\n\n";
		my $result = from_json_wrapper($output);
		if (! $result) {
			print "error - json - curl:\n$curl\nstatus: $status output: $output\n";
		}
		my $input_id;
		if (defined($result->{'inputId'})) {
			$input_id = $result->{'inputId'};
			my $curl = qq{curl --silent --insecure $api_key_header -H "accept: application/json" -H "Content-Type: application/json" -X GET "https://${authentication}${codedx_host}/codedx/api/analysis-prep/$prep_id/$input_id"};
			my ($output, $status) = systemcall($curl);
			if ($status) {
				print "error - curl:\n$curl\nstatus: $status output: $output\n";
				return;
			}
			print "$curl\noutput\n$output\n\n";
		}
	}
	my $curl = qq{curl --silent --insecure $api_key_header -H "accept: application/json" -H "Content-Type: application/json" -X POST "https://${authentication}${codedx_host}/codedx/api/analysis-prep/$prep_id/analyze"};
	my ($output, $status) = systemcall($curl);
	if ($status) {
		print "error - curl:\n$curl\nstatus: $status output: $output\n";
		return;
	}
	print "$curl\noutput\n$output\n\n";
}

sub upload_files { my ($project_name, $files, $api_key, $user, $password) = @_;
	my $project_id = get_project_id($project_name, $api_key, $user, $password);
	if (! $project_id) {
		print "error - could not get projectId for $project_name\n";
		return;
	}
	my ($api_key_header, $authentication) = build_authentication($api_key, $user, $password);
	if (! $api_key_header && ! $authentication) {
		print "error - no authentication\n";
		return;
	}
	my $curl = qq{curl --silent --insecure $api_key_header -H "accept: application/json" -H "Content-Type: multipart/form-data" -X POST "https://${authentication}${codedx_host}/codedx/api/projects/$project_id/analysis"};
	my $i = 1;
	my $archive;
	foreach my $file (@$files) {
		if (($file !~ m/\.zip$/) && ($file !~ m/\.xml/)) {
			$file = makezip($file);
			$archive = $file if ($file =~ m/\.zip$/);
		}
		$curl .= qq{ -F "file${i}=\@${file};type-text/xml"};
		$i += 1;
	}
	my ($output, $status) = systemcall($curl);
	unlink $archive if (-f $archive);
	if ($status) {
		print "error - curl:\n$curl\nstatus: $status output: $output\n";
		return;
	}
	print "$curl\noutput\n$output\n\n";
}

my $project_name = shift @ARGV;
my $project_id = create_project($project_name, $api_key);
print 'project_id: ', $project_id || 'undefined', "\n";
# upload_analysis($project_name, \@ARGV, $api_key);
upload_files($project_name, \@ARGV, $api_key);
print "Hello World!\n";
