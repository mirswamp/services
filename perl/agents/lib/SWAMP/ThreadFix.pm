# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#** @file ThreadFix.pm
#
# @brief Interface to ThreadFix
# @author Thomas Jay Anthony Bricker, tbricker@continuousassurance.org
# @date 12/02/2015
#*
#
package SWAMP::ThreadFix;

use 5.014;
use utf8;
use strict;
use warnings;
use parent qw(Exporter);
use URI::Escape qw(uri_escape);

BEGIN {
    our $VERSION = '1.00';
}
our (@EXPORT_OK);

BEGIN {
    require Exporter;
    @EXPORT_OK = qw(
      threadfix_uploadanalysisrun
    );
}

use English '-no_match_vars';
use Log::Log4perl;
use Log::Log4perl::Level;
use SWAMP::SWAMPUtils qw(systemcall);
use JSON qw(from_json);

sub _create_team { my ($host, $project, $apikey, $teamname) = @_ ;
    # lookup team first to attempt to get existing team id
    my $curl = qq{curl --silent --insecure -H 'Accept: application/json' -X GET https://$host/$project/rest/teams/lookup?name=$teamname\\&apiKey=$apikey};
    my ($output, $status) = systemcall($curl);
    if ($status) {
		Log::Log4perl->get_logger('viewer')->trace("_create_team Lookup failed for: $project $apikey $teamname output: <$output>");
    	return;
    }
    my $teamid;
    my $object_result = from_json($output);
    if ($object_result->{'success'}) {
		$teamid = $object_result->{'object'}->{'id'};
		Log::Log4perl->get_logger('viewer')->trace("_create_team Lookup for: $project $apikey $teamname teamid: $teamid");
    }
    # if lookup did not return team id then create new team
    if (! $teamid) {
        $curl = qq{curl --silent --insecure -H 'Accept: application/json' -X POST --data 'name=$teamname' https://$host/$project/rest/teams/new?apiKey=$apikey};
    	($output, $status) = systemcall($curl);
    	if ($status) {
	    Log::Log4perl->get_logger('viewer')->trace("_create_team New Team failed for: $project $apikey $teamname output: <$output>");
    	    return;
    	}
    	$object_result = from_json($output);
    	if ($object_result->{'success'}) {
	    $teamid = $object_result->{'object'}->{'id'};
    	}
	else {
	    Log::Log4perl->get_logger('viewer')->trace("_create_team New Team failed for: $project $apikey $teamname output: <$output>");
    	    return;
	}
    }
    return $teamid;
}

sub _create_application { my ($host, $project, $apikey, $uri_package, $teamname, $teamid) = @_ ; ## no critic (ProhibitManyArgs)
    # lookup application first to attempt to get existing application id
    my $curl = qq{curl --silent --insecure -H 'Accept: application/json' -X GET https://$host/$project/rest/applications/$teamname/lookup?apiKey=$apikey\\&name=$uri_package};
	my ($output, $status) = systemcall($curl);
	if ($status) {
		Log::Log4perl->get_logger('viewer')->trace("_create_application Lookup failed for: $project $apikey $uri_package $teamname $teamid output: <$output>");
		return;
	}
	my $applicationid;
	my $object_result = from_json($output);
	if ($object_result->{'success'}) {
		$applicationid = $object_result->{'object'}->{'id'};
		Log::Log4perl->get_logger('viewer')->trace("_create_application Lookup for: $project $apikey $uri_package $teamname $teamid applicationid: $applicationid");
	}
	# if lookup did not return application id then create new application
    if (! $applicationid) {
    	$curl = qq{curl --silent --insecure -H 'Accept: application/json' -X POST --data name='$uri_package&url=https://continuousassurance.org/' https://$host/$project/rest/teams/$teamid/applications/new?apiKey=$apikey};
    	($output, $status) = systemcall($curl);
    	if ($status) {
			Log::Log4perl->get_logger('viewer')->trace("_create_application Create Application failed for: $project $apikey $uri_package $teamname $teamid output: <$output>");
    		return;
    	}
    	$object_result = from_json($output);
    	if ($object_result->{'success'}) {
			my $applicationteamid = $object_result->{'object'}->{'organization'}->{'id'};
			if ($applicationteamid == $teamid) {
	    		$applicationid = $object_result->{'object'}->{'id'};
	    	}
    	}
    	else {
	    	Log::Log4perl->get_logger('viewer')->trace("_create_application Create Application failed for: $project $apikey $uri_package $teamname $teamid output: <$output>");
    	    return;
    	}
    }
	return $applicationid;
}

sub _upload_result { my ($host, $project, $apikey, $applicationid, $files) = @_ ;
	foreach my $file (@{$files}) {
    	my $curl = qq{curl --silent --insecure -H 'Accept: application/json' -X POST --form "file=\@$file" https://$host/$project/rest/applications/$applicationid/upload?apiKey=$apikey};
    	my ($output, $status) = systemcall($curl);
    	if ($status) {
		Log::Log4perl->get_logger('viewer')->trace("_upload_result failed for: $project $apikey $applicationid - file: ", $file, " output: <$output>");
    		return 0;
    	}
	}
    return 1;
}

sub threadfix_uploadanalysisrun { my ($host, $apikey, $project, $package, $files) = @_ ;
    my $ret       = 0;
	my $teamname = $project;
	my $uri_package = uri_escape($package);
    my $teamid = _create_team($host, $project, $apikey, $teamname);
    if ($teamid) {
    	my $applicationid = _create_application($host, $project, $apikey, $uri_package, $teamname, $teamid);
		if ($applicationid) {
	    	$ret = _upload_result($host, $project, $apikey, $applicationid, $files);
		}
    }
    return $ret;
}

1;
