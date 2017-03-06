# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2017 Software Assurance Marketplace

package SWAMP::CodeDX;
use 5.014;
use utf8;
use strict;
use warnings;
use English '-no_match_vars';
use Log::Log4perl;
use Log::Log4perl::Level;
use Try::Tiny qw(try catch);
use JSON qw(from_json);
use SWAMP::vmu_Support qw(systemcall);

use parent qw(Exporter);
our (@EXPORT_OK);
BEGIN {
    require Exporter;
    @EXPORT_OK = qw(
      listprojects
      createproject
      deleteproject
      uploadanalysisrun);
}

my $log = Log::Log4perl->get_logger(q{});

# Pre-1.5.1 Code Dx API needs uri_escape
# use URI::Escape qw(uri_escape);

sub _getAPIReturn { my ($output) = @_ ;
	my $retval = {};
	if (length($output)) {
		try {
        	my $ref = from_json($output);
			if ($ref->{'error'}) {
				$retval = $ref->{'error'};
			}
			$retval = $ref;
		}
		catch {
			$retval = {'error' => "Error in json conversion: $_"};
		};
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

#** @function listprojects( $host, $apikey, $project, $package)
# @brief Create a CodeDX project (SWAMP package) if it does not already exist
#
# @param $host The IP address of the VM running the CodeDX instance
# @param $apikey The API Key used to authenticate with the CodeDX instance
# @param $project The name of the SWAMP project which is also the folder containing the CodeDX files
# @return A HASH of project(SWAMP package)  names indexed by CodeDX ids on success, { 'error' => 'reason'} on failure.
#
#*
sub listprojects {
    my $host    = shift;
    my $apikey  = shift;
    my $project = shift;
    # Code Dx 1.5 and beyond API
    my $curl    = qq{curl -ks -H "AUTHORIZATION: System-Key $apikey"  -X GET https://$host/$project/api/projects};
    
    # Code Dx pre-1.5 API
    # my $curl    = qq{curl -ks -H "API-Key: $apikey"  -X GET https://$host/$project/api/project};

    my $projects = {};
    my ( $output, $status ) = systemcall($curl);
    if ($status) {    # error
        $projects->{'error'} = $output;
        $log->error("Error listing projects: $output");
    }
    else {
		my $ref = _getAPIReturn($output);
        if ($ref->{'error'}) {
            $projects->{'error'} = $ref->{'error'};
            $log->warn("Error listing projects: [$ref->{'error'}]");
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

#** @function createproject( $host, $apikey, $project, $package)
# @brief Create a CodeDX project (SWAMP package) if it does not already exist
#
# @param $host The IP address of the VM running the CodeDX instance
# @param $apikey The API Key used to authenticate with the CodeDX instance
# @param $project The name of the SWAMP project which is also the folder containing the CodeDX .htaccess file
# @param $package the SWAMP package, CodeDX project, to create.
# @return -1 on failure, ProjectID on success
#*
sub createproject {
    my $host      = shift;
    my $apikey    = shift;
    my $project   = shift;
    my $package   = shift;
    my $ret       = -1;
    my $projectID = _getprojectid( $host, $apikey, $project, $package );

    if ( $projectID != -1 ) {
        return $projectID;    # Found it.
    }
    # N.B. ONLY Here do we use the uri_escaped form of the package name, hence forth the 
    # unescaped version will work AND must be the unescaped version.
    # New API for 1.5 doesn't require escaped
    # my $escaped = uri_escape($package);

    my $curl =
    # New API for Code Dx 1.5 and beyond
     qq{curl -ks -H "Content-type: application/json" -d '{ "name" : "$package" }' -H "AUTHORIZATION: System-Key $apikey"  -X PUT https://${host}/$project/api/projects};

    # Pre Code Dx 1.5 API
    # qq{curl -ks -H "API-Key: $apikey"  -X PUT https://${host}/$project/api/project?project_name="$escaped"};

    my ( $output, $status ) = systemcall($curl);
    if ( $status == 0 ) {
        $ret = _getprojectid( $host, $apikey, $project, $package );
    }
    else {
        $log->error("Error creating project <$host,$project,$package>: $output ($status) [$curl]");
    }
    return $ret;
}

sub _getprojectid {
    my $host            = shift;
    my $apikey          = shift;
    my $project         = shift;
    my $package         = shift;                                      # The sought package
    my $currentProjects = listprojects( $host, $apikey, $project );
    my $projectID       = -1;
    if ( !defined( $currentProjects->{'error'} ) ) {
        foreach my $id ( keys %{$currentProjects} ) {
            # SWAMP packages are CodeDX projects
            if ( $currentProjects->{$id} eq $package ) {
                $projectID = $id;
                last;
            }
        }
    }
    return $projectID;
}

#** @function deleteproject( $host, $apikey, $project, $package)
# @brief Delete a CodeDX project (SWAMP package)
#
# @param $host The IP address of the VM running the CodeDX instance
# @param $apikey The API Key used to authenticate with the CodeDX instance
# @param $project The name of the SWAMP project which is also the folder containing the CodeDX .htaccess
# @param $package the SWAMP package, CodeDX project, to delete.
# @return 0 on failure, 1 on success
# @see
#*
sub deleteproject {
    my $host      = shift;
    my $apikey    = shift;
    my $project   = shift;
    my $package   = shift;
    my $projectID = _getprojectid( $host, $apikey, $project, $package );
    my $ret       = 0;
    if ( $projectID != -1 ) {
        my $curl =
        # Code Dx 1.5 and beyond API
        qq{curl -ks -H "Authorization: System-Key $apikey"  -X DELETE https://$host/$project/api/projects/$projectID};
        # Code Dx pre-1.5 API
        # qq{curl -ks -H "API-Key: $apikey" -X DELETE https://$host/$project/api/project/$projectID};

        my ( $output, $status ) = systemcall($curl);
        if ( $status == 0 ) {
            if (_checkAPIReturn($output) ne q{SUCCESS})  {
                $log->error("Error deleting project <$host,$project,$package>:[$curl} $output");
                
            }
            else {
                $ret = 1;
            }
        }
        else {
            $log->error("Error deleting project <$host,$project,$package>:[$curl} $output");
        }
    }
    return $ret;
}

sub uploadanalysisrun {
	my $host      = shift;
	my $apikey    = shift;
	my $project   = shift;
	my $package   = shift;
	my $files     = shift;                                              # This is an array reference
		my $ret       = 0;
	my $projectID = createproject( $host, $apikey, $project, $package );
	if ( $projectID != -1 ) {
		my $curl =
# Code Dx 1.5 and beyond API
			qq{curl -ks -H "Authorization: System-Key $apikey" https://$host/$project/api/projects/$projectID/analysis};
# Code Dx pre-1.5 API
# qq{curl -ks -H "API-Key: $apikey" https://$host/$project/api/project/$projectID/analysis};
		my $nn = 1;
		for my $file ( @{$files} ) {
			$curl .= " -F \"file${nn}=\@$file\"";
			$nn++;
		}
		my ( $output, $status ) = systemcall($curl);
		if ( $status == 0 ) {
			my $apiResult = _checkAPIReturn($output);
			if ($apiResult eq q{SUCCESS}) {
				$ret = 1;
			}
			else {
				$log->warn("uploading project failed $apiResult");
			}
			$log->info("uploading project <$host,$project,$package>: $output [$curl]");
		}
		else {
			$log->error("Error uploading project <$host,$project,$package>: $output ($status) [ $curl ]");
		}
	}
	else {
		$log->error("Error uploading project cannot find ID.<$host,$project,$package>");
	}
	return $ret;
}

1;
