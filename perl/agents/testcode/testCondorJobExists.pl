#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2018 Software Assurance Marketplace

use strict;
use warnings;
use Log::Log4perl qw(:easy);
use lib '/opt/swamp/perl5';
use SWAMP::vmu_Support qw(
	systemcall
);

Log::Log4perl->easy_init($ALL);
my $log = Log::Log4perl->get_logger(q{});

sub isJobInHistory { my ($execrunuid) = @_ ;
	my $cmd  = qq(condor_history); 
	   $cmd .= qq( -constraint ');
	   $cmd .= qq(SWAMP_arun_execrunuid == "$execrunuid");
	   $cmd .= qq( || SWAMP_mrun_execrunuid == "$execrunuid");
	   $cmd .= qq( || SWAMP_vrun_execrunuid == "$execrunuid");
	   $cmd .= qq(');
	   $cmd .= qq( -format "%s\n" SWAMP_arun_execrunuid); 
	   $cmd .= qq( -format "%s\n" SWAMP_mrun_execrunuid); 
	   $cmd .= qq( -format "%s\n" SWAMP_vrun_execrunuid); 
	   $cmd .= qq( -limit 1);
    my ($output, $status) = systemcall($cmd);
    if ($status) {
        $log->error("isJobInHistory condor_history failed - $status output: $output");
        return 0;
    }
	if ($output =~ m/^$execrunuid$/) {
		$log->info("$execrunuid found from condor_history");
		return 1;
	}
    return 0;
}

sub isJobInQueue { my ($execrunuid) = @_ ;
	my $cmd  = qq(condor_q);
	   $cmd .= qq( -format "%s\n" SWAMP_arun_execrunuid);
	   $cmd .= qq( -format "%s\n" SWAMP_vrun_execrunuid);
	   $cmd .= qq( -format "%s\n" SWAMP_mrun_execrunuid);
    my ($output, $status) = systemcall($cmd);
    if ($status) {
        $log->error("isJobInQueue condor_q failed - $status output: $output");
        return 0;
    }
	if ($output =~ m/$execrunuid/) {
		$log->info("$execrunuid found from condor_q");
    	return 1;
	}
	return 0;
}

sub condorJobExists { my ($execrunuid) = @_ ;
	return isJobInQueue($execrunuid) || isJobInHistory($execrunuid);
}

my $execrunuid = $ARGV[0];
if ($execrunuid) {
	print "$execrunuid: ";
	if (isJobInQueue($execrunuid)) {
		print "found in HTCondor queue\n";
	}
	elsif (isJobInHistory($execrunuid)) {
		print "found in HTCondor history\n";
	}
	else {
		print "not found in HTCondor\n";
	}
}
else {
	print "Error - no execrunuid\n";
}
print "Hello World!\n";
