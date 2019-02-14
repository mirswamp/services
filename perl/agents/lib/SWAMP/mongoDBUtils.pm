# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2019 Software Assurance Marketplace

package SWAMP::mongoDBUtils;
use strict;
use warnings;

use English '-no_match_vars';
use Log::Log4perl;
use MongoDB;
use parent qw(Exporter);
use SWAMP::ScarfXmlReader;
use SWAMP::vmu_Support qw(
	getSwampConfig
	$global_swamp_config
);
use SWAMP::FrameworkUtils qw(
	generateMongoJson
);
our (@EXPORT_OK);
BEGIN {
    require Exporter;
    @EXPORT_OK = qw(
	  mongoSaveAssessmentResult
    );
}

my $log = Log::Log4perl->get_logger(q{});

sub mongoSaveAssessmentResult { my ($assessment_results) = @_ ;
    $global_swamp_config ||= getSwampConfig();
    my $use_mongodb = $global_swamp_config->get('useMongoDB') || '';
	if ($use_mongodb eq 'yes') {
		my $db_name = $global_swamp_config->get('mongoDBName') || 'scarf-db';
		$log->info("mongoSaveAssessmentResult - saving assessment results to MongoDB: $db_name");
    	if (! _mongoSaveAssessmentResult($db_name, $assessment_results)) {
			return 0;
		}
	}
	return 1;
}

sub _mongoSaveAssessmentResult { my ($db_name, $assessment_results) = @_ ;
    my $retCode;
    if (my $dbh = openDatabase($db_name)) {
        my $file = $assessment_results->{'pathname'};
        my $uuid = $assessment_results->{'execrunid'};
        # process SCARF results and insert it into MongoDB
        if ($file =~ m/\.xml$/sxmi) {
            $retCode = insertScarfToDB($dbh, $file, $uuid);
            if ($retCode == 0) {
                $log->error("mongoSaveAssessmentResult - Fail inserting $file into MongoDB");
            }
        }
        # process SONATYPE results, skip MongoDB inserting
        elsif ($file =~ m/\.zip$/sxmi) {
            $log->info("mongoSaveAssessmentResult - skip inserting $file into MongoDB");
            $retCode = 1;
        }
        # process ERROR results and insert it into MongoDB
        elsif ($file =~ m/\.tar\.gz$/sxmi) {
            $retCode = insertErrorReportToDB($dbh, $file, $uuid);
            if ($retCode == 0) {
                $log->error("mongoSaveAssessmentResult - Fail inserting $file into MongoDB");
            }
        }
        else {
            $log->error("mongoSaveAssessmentResult - cannot insert $file into MongoDB");
            $retCode = 0;
        }
    } else {
        $log->error("mongoSaveAssessmentResult - MongoDB connection failed");
        $retCode = 0;
    }
    return $retCode;
}

sub openDatabase { my ($db_name, $user, $password) = @_;
	$global_swamp_config ||= getSwampConfig();
	my $host = $global_swamp_config->get('mongoDBPerlHost') || 'localhost';
	my $port = $global_swamp_config->get('mongoDBPerlPort') || '27017';
	$db_name ||= $global_swamp_config->get('mongoDBName');
	$user ||= $global_swamp_config->get('mongoDBPerlUser');
	$password ||= $global_swamp_config->get('mongoDBPerlPass');
	my $commits = 1500;
	my $url = 'mongodb://';
	if ($user && $password) {
		$url .= "$user:$password@";
	}
	# default to 'admin' database for authentication
	$url .= $host . ":$port";
	my $client;
	eval {
		$client = MongoDB->connect($url);
	};
	if ($@) {
		$log->error("openDatabase - MongoDB connect failed: $@");
		return;
	}
	my $dbh;
	eval {
		$dbh = $client->get_database("$db_name");
	};
	if ($@) {
		$log->error("openDatabase - get_database failed: $@");
		return;
	}
	return $dbh
}

sub insertScarfToDB { my ($dbh, $scarf_file, $uuid) = @_;
	if (-r $scarf_file && $dbh && $uuid) {
		eval {
			parse_file($dbh, $scarf_file, $uuid);
		};
		if ($@) {
			$log->error("insertScarfToDB - error: $@");
			return 0;
		}
		return 1;
	}
	return 0;
}

sub insertErrorReportToDB { my ($dbh, $error_file, $uuid) = @_ ;
	my $topdir = 'out';
	$topdir = 'output' if ($error_file =~ m/outputdisk.tar.gz$/);
	if (-r $error_file && $dbh) {
		eval {
			my $report = generateMongoJson($error_file, $topdir);
			my $coll = $dbh->get_collection($uuid);
			$coll->insert_one($report);
		};
		if ($@) {
			$log->error("insertErrorReportToDB - error: $@");
			return 0;
		}
		return 1;
	}
	return 0;
}

sub parse_file { my ($dbh, $scarf_file, $uuid) = @_ ;
    my %data = (
		db_count			=> 0,
		db_commits			=> 1500,
		assessReportFile	=> 1,
		buildid				=> 1,
		instanceLocation	=> 1,
    );
	my $reader = new SWAMP::ScarfXmlReader($scarf_file);
	$reader->SetEncoding('UTF-8');

	$data{assess} = $dbh->get_collection($uuid);
	
	$reader->SetInitialCallback(\&initMongo);
	$reader->SetBugCallback(\&bugMongo);
	$reader->SetMetricCallback(\&metricMongo);
	$reader->SetFinalCallback(\&finish);
	$reader->SetCallbackData(\%data);
    $reader->Parse();
}

sub initMongo { my ($details, $data) = @_ ;
    $data->{init} = 1;
    $data->{assessUuid} = $details->{uuid};
    $data->{toolName} = $details->{tool_name};
    $data->{toolVersion}  = $details->{tool_version};
    if (defined $details->{package_name}) {
		$data->{pkgName} = $details->{package_name};
    }
    if (defined $details->{platform_name}) {
		$data->{plat} = $details->{platform_name};
    }
    if (defined $details->{package_version}) {
		$data->{pkgVer} = $details->{package_version};
    }

    # Insert an entry of metadata information into MongoDB under assessment collection
	my %metaData = (    assessUuid   	=> $data->{assessUuid},
		pkgShortName 	=> $data->{pkgName},
		pkgVersion   	=> $data->{pkgVer},
		toolType     	=> $data->{toolName},
		toolVersion  	=> $data->{toolVersion},
		plat         	=> $data->{plat}
	);
	push @{$data->{scarf}}, \%metaData;
	my $res = $data->{assess}->insert_many(\@{$data->{scarf}});
	delete $data->{scarf};
    return;
}

sub metricMongo { my ($metric, $data) = @_ ;
    $data->{bug} = 1;
    my $classname = undef;
    if (exists $metric->{Class})  {
        $classname = $metric->{Class};
    }
    my $method_name = undef;
    if (exists $metric->{Method})  {
        $method_name = $metric->{Method};
    }
    if ($metric->{Value} =~ /^[0-9]+$/)  {
        $metric->{Value} = int($metric->{Value})
    }
    my %metricInstance = (  assessUuid   	=> $data->{assessUuid},
		pkgShortName 	=> $data->{pkgName},
		pkgVersion   	=> $data->{pkgVer},
		toolType     	=> $data->{toolName},
		toolVersion  	=> $data->{toolVersion},
		plat         	=> $data->{plat}, 
		Value 		=> $metric->{Value},
		Type 		=> $metric->{Type},
		Method 		=> $method_name, 
		Class 		=> $classname,
		SourceFile	 	=> $metric->{SourceFile},
		MetricId 		=> int($metric->{MetricId})
	);

	push @{$data->{scarf}}, \%metricInstance;
	$data->{db_count}++;
	if ($data->{db_commits} != 'INF' && $data->{db_commits} == $data->{db_count}) {
		# change the collection name to assessUuid
		my $res = $data->{assess}->insert_many(\@{$data->{scarf}});
		$data->{db_count} = 0;
		delete $data->{scarf};
	}
    return;
}

sub bugMongo { my ($bug, $data) = @_ ;
    my ($assessReportFile, $buildid, $instanceLocation) = (undef, undef, undef);
    if (defined $data->{assessReportFile}) {
		$assessReportFile = $bug->{AssessmentReportFile};
    }
    if (defined $data->{buildid}) {
		$buildid = $bug->{BuildId};
    }
    if (defined $data->{instanceLocation}) {
		if (exists $bug->{InstanceLocation}) {
	    	$instanceLocation = $bug->{InstanceLocation};
		}
    }
    $data->{bug} = 1;
    my $bug_code = undef;
    if (exists $bug->{BugCode})  {
        $bug_code = $bug->{BugCode};
    }

    my $bug_group = undef;
    if (exists $bug->{BugGroup})  {
        $bug_group = $bug->{BugGroup};
    }

    my $bug_rank = undef;
    if (exists $bug->{BugRank})  {
		$bug_rank = $bug->{BugRank};
    }

    my $bug_sev = undef;
    if (exists $bug->{BugSeverity})  {
		$bug_sev = $bug->{BugSeverity};
    }
    
    my $res_sug = undef;
    if (exists $bug->{ResolutionSuggestion})  {
		$res_sug = $bug->{ResolutionSuggestion};
    }

    my $classname = undef;
    if (exists $bug->{ClassName})  {
		$classname = $bug->{ClassName};
    }
 
    my $length = scalar @{$bug->{Methods}};
    if (exists $bug->{Methods} && $length != 0)  {
        foreach my $method (@{$bug->{Methods}}) {
            $method->{MethodId} = int($method->{MethodId});
	    	if ( $method->{primary} == 1)  {
                $method->{primary} = JSON->true;
            } else  {
                $method->{primary} = JSON->false;	
	    	}
		}
    }

    $length = scalar @{$bug->{BugLocations}};
    if (exists $bug->{BugLocations} && $length != 0)  {
        foreach my $location (@{$bug->{BugLocations}}) {
            $location->{LocationId} = int($location->{LocationId});
            
	    	if ( $location->{primary} == 1)  {
                $location->{primary} = JSON->true;
            } else  {
                $location->{primary} = JSON->false;	
	    	}
    
	    	if (exists $location->{StartLine})  {
				$location->{StartLine} = int($location->{StartLine});
	    	}
    
	    	if (exists $location->{EndLine})  {
	        	$location->{EndLine} = int($location->{EndLine});
	    	}

	    	if (exists $location->{EndColumn})  {
	        	$location->{EndColumn} = int($location->{EndColumn});
	    	}

	    	if (exists $location->{StartColumn})  {
				$location->{StartColumn} = int($location->{StartColumn});
	    	}	
		}
    }

    my %bugInstance = ( assessUuid   		=> $data->{assessUuid},
		    # comment redundant attribute	
            #pkgShortName 		=> $data->{pkgName},
			#pkgVersion   		=> $data->{pkgVer},
			#toolType     		=> $data->{toolName},
			#toolVersion  		=> $data->{toolVersion},
			#plat         		=> $data->{plat},
			BugMessage   		=> $bug->{BugMessage},
			BugGroup     		=> $bug_group,
			Location     		=> $bug->{BugLocations},
			Methods      		=> $bug->{Methods},
			BugId 	        	=> int($bug->{BugId}),
			BugCode          	=> $bug_code,
			BugRank          	=> $bug_rank,
			BugSeverity      	=> $bug_sev,
			BugResolutionMsg 	=> $res_sug,
			classname        	=> $classname,		
			BugCwe           	=> $bug->{CweIds},
			AssessmentReportFile	=> $assessReportFile,
			BuildId			=> $buildid,
			InstanceLocation	=> $instanceLocation,
    );
 
	push @{$data->{scarf}}, \%bugInstance;

	$data->{db_count}++;
	if ($data->{db_commits} != 'INF' && $data->{db_commits} == $data->{db_count}) {
		# change the collection name to assessUuid
		my $res = $data->{assess}->insert_many(\@{$data->{scarf}});
		$data->{db_count} = 0;
		delete $data->{scarf};
	}
    return;
}

sub finish { my ($returnVal, $data) = @_ ;
    # Executing the remaining instances 
	if (($data->{db_count} != 0 && exists $data->{bug}) || $data->{db_commits} eq 'INF') {
		# change the collection name to assessUuid
		my $res = $data->{assess}->insert_many(\@{$data->{scarf}});
		delete $data->{scarf};
	}  
	elsif (($data->{db_count} != 0 && exists $data->{init}) || $data->{db_commits} eq 'INF')  {
		# change the collection name to assessUuid
		$data->{assess}->insert({      	'assessUuid'    => $data->{assessUuid},
			'pkgShortName'  => $data->{pkgName},
			'pkgVersion'    => $data->{pkgVer},
			'toolType'      => $data->{toolName},
			'toolVersion'   => $data->{toolVersion},
			'plat'          => $data->{plat},
		});	
	}
}

1;
