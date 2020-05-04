#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

use strict;
use warnings;
use Log::Log4perl qw(:easy);
use FindBin;
use lib "../lib";
use SWAMP::vmu_Support qw(
	database_connect 
	database_disconnect
	displaynameToMastername
);
use SWAMP::vmu_AssessmentSupport qw(
	copyAssessmentInputs
);

sub _getPlatformNames {
    my $dbh = database_connect();
    if ($dbh) {
    	my $query = q{SELECT platform_path FROM platform_store.platform_version};
		my $names = $dbh->selectcol_arrayref($query);
    	database_disconnect($dbh);
		return $names if (scalar(@$names));
    }   
    return;
}

sub _getToolPaths {
    my $dbh = database_connect();
    if ($dbh) {
    	my $query = q{SELECT tool_path FROM tool_shed.tool_version};
		my $names = $dbh->selectcol_arrayref($query);
    	database_disconnect($dbh);
		return $names if (scalar(@$names));
    }   
    return;
}

Log::Log4perl->easy_init($DEBUG);
my $dest = 'outputfolder';
if (! -d $dest) {
	mkdir $dest;
}
if (! -d $dest) {
	print "Error - $dest not found\n";
	exit(0);
}

my $platform_names = _getPlatformNames();
my $tool_paths = _getToolPaths();

my $toolpath = 'testtoolpath';
my $platform = 'testplatform';

my $bogref = {
	'execrunid'		=> 'testexecrunuuid',
	'packagepath'	=> 'testpackagepath',
	'toolpath'		=> $toolpath,
	'platform'		=> $platform,
};
my $result = copyAssessmentInputs($bogref, $dest);
print "copyAssessmentInputs returns: $result\n";
print "Hello World!\n";
