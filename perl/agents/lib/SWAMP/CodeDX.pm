# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2019 Software Assurance Marketplace

package SWAMP::CodeDX;
use 5.014;
use utf8;
use strict;
use warnings;
use English '-no_match_vars';
use Log::Log4perl;
use Log::Log4perl::Level;
use SWAMP::vmu_Support qw(
	from_json_wrapper
	systemcall
);

use parent qw(Exporter);
our (@EXPORT_OK);
BEGIN {
    require Exporter;
    @EXPORT_OK = qw(
      listprojects
      createproject
      deleteproject
      uploadanalysisrun
	);
}

my $log = Log::Log4perl->get_logger(q{});

sub _getAPIReturn { my ($output) = @_ ;
	my $retval = {};
	if (length($output)) {
		my $ref = from_json_wrapper($output);
		$retval = $ref;
		if (! defined($ref)) {
			$retval = {'error' => "Error in json conversion: $_"};
		}
	}
	return $retval;
}

sub _checkAPIReturn { my ($output) = @_ ;
	my $retval = _getAPIReturn($output);
	if ($retval->{'error'}) {
		return $retval->{'error'};
	}
    return q{SUCCESS};
}

sub listprojects { my ($host, $apikey, $project) = @_ ;
    my $projects = {};
    my $curl    = qq{curl -ks -H "AUTHORIZATION: System-Key $apikey"  -X GET https://$host/$project/api/projects};
    my ( $output, $status ) = systemcall($curl);
    if ($status) {    # error
        $projects->{'error'} = $output;
        $log->error("Error - listprojects - curl: [$curl] output: [$output] status: ($status)");
    }
    else {
		my $ref = _getAPIReturn($output);
        if ($ref->{'error'}) {
            $projects->{'error'} = $ref->{'error'};
            $log->error("Error - listprojects - curl: [$curl] output: [$output] apiResult: ", $ref);
        }
        else {
            my $aref = $ref->{'projects'};
            foreach my $proj (@{$aref}) {
                $projects->{$proj->{'id'}} = $proj->{'name'};
            }
        }
    }
    return $projects;
}

sub createproject { my ($host, $apikey, $project, $package) = @_ ;
    my $ret       = -1;
    my $projectID = _getprojectid( $host, $apikey, $project, $package );
    if ( $projectID != -1 ) {
        return $projectID;
    }
    my $curl = qq{curl -ks -H "Content-type: application/json" -d '{ "name" : "$package" }' -H "AUTHORIZATION: System-Key $apikey"  -X PUT https://${host}/$project/api/projects};
    my ( $output, $status ) = systemcall($curl);
    if ( $status == 0 ) {
        $ret = _getprojectid( $host, $apikey, $project, $package );
    }
    else {
        $log->error("Error - createproject - curl: [$curl] output: [$output] status: ($status)");
    }
    return $ret;
}

sub _getprojectid { my ($host, $apikey, $project, $package) = @_ ;
    my $currentProjects = listprojects( $host, $apikey, $project );
    my $projectID       = -1;
    if ( !defined( $currentProjects->{'error'} ) ) {
        foreach my $id ( keys %{$currentProjects} ) {
            if ( $currentProjects->{$id} eq $package ) {
                $projectID = $id;
                last;
            }
        }
    }
    return $projectID;
}

sub deleteproject { my ($host, $apikey, $project, $package) = @_ ;
    my $projectID = _getprojectid( $host, $apikey, $project, $package );
    my $ret       = 0;
    if ( $projectID != -1 ) {
        my $curl = qq{curl -ks -H "Authorization: System-Key $apikey"  -X DELETE https://$host/$project/api/projects/$projectID};
        my ( $output, $status ) = systemcall($curl);
        if ( $status == 0 ) {
			my $apiResult = _checkAPIReturn($output);
            if ($apiResult ne q{SUCCESS}) {
                $log->error("Error - deleteproject - curl: [$curl] output: [$output] apiResult: ", $apiResult);
            }
            else {
                $ret = 1;
            }
        }
        else {
            $log->error("Error - deleteproject - curl: [$curl] output: [$output] status: ($status)");
        }
    }
    return $ret;
}

sub uploadanalysisrun { my ($host, $apikey, $project, $package, $files) = @_ ;
	my $ret       = 0;
	my $projectID = createproject( $host, $apikey, $project, $package );
	if ( $projectID != -1 ) {
		my $curl = qq{curl -ks -H "Authorization: System-Key $apikey" https://$host/$project/api/projects/$projectID/analysis};
		my $nn = 1;
		for my $file ( @{$files} ) {
			$curl .= " -F \"file${nn}=\@$file\"";
			$nn++;
		}
		my ( $output, $status ) = systemcall($curl);
		if ( $status == 0 ) {
			my $apiResult = _checkAPIReturn($output);
			if ($apiResult eq q{SUCCESS}) {
				$log->info("uploading project: $package curl: [$curl] output: [$output]");
				$ret = 1;
			}
			else {
				$log->error("Error - uploadanalysisrun - curl: [$curl] output: [$output] apiResult: ", $apiResult);
			}
		}
		else {
			$log->error("Error - uploadanalysisrun - curl: [$curl] output: [$output] status: ($status)");
		}
	}
	else {
		$log->error("Error uploadanalysisrun - cannot find projectID: <$host,$apikey, $project,$package>");
	}
	return $ret;
}

1;
