#!/usr/bin/env perl
use strict;
use warnings;
use File::Basename;
use Log::Log4perl qw(:easy);
use DBI;
use lib '/opt/swamp/perl5';
use SWAMP::vmu_Support qw(
	systemcall
	database_connect 
	database_disconnect
);

my $swamplogdir = '/opt/swamp/log';
my $username = 'web';
my $password = 'swampinabox';

sub fetch_assessment_result { my ($execution_record_uuid) = @_ ;
    my $dbh = database_connect($username, $password);
	my $assessment_result;
    if ($dbh) {
    	my $query = qq{SELECT file_path from assessment.assessment_result WHERE execution_record_uuid = '$execution_record_uuid'};
		my $data = $dbh->selectrow_array($query);
		if ($dbh->err) {
			print "$query failed - error: ", $dbh->errstr, "\n";
		}
		else {
			$assessment_result = $data;
		}
    	database_disconnect($dbh);
    }   
	return $assessment_result;
}

sub fetch_execution_records { my ($complete_flag) = @_ ;
    my $dbh = database_connect($username, $password);
	my $execution_record_uuids = [];
    if ($dbh) {
    	my $query = q{SELECT execution_record_uuid, launch_flag, submitted_to_condor_flag, complete_flag from assessment.execution_record};
    	if (defined($complete_flag)) {
    		$query .= qq{ WHERE complete_flag = $complete_flag};
		}
		my $data = $dbh->selectall_hashref($query, 'execution_record_uuid');
		if ($dbh->err) {
			print "$query failed - error: ", $dbh->errstr, "\n";
		}
		else {
			$execution_record_uuids = $data;
		}
    	database_disconnect($dbh);
    }   
	return $execution_record_uuids;
}

sub fetch_condor { my ($where) = @_ ;
	my $command = qq{$where -format "%s\n" SWAMP_arun_execrunuid};
	my ($output, $status) = systemcall($command);
	if ($status) {
		return;
	}
	my @execrunuids = split /\n/, $output;
	my $hash = {};
	foreach my $execrunuid (@execrunuids) {
		$hash->{$execrunuid} = 1;
	}
	return $hash;
}

Log::Log4perl->easy_init($ERROR);
my $execution_record_uuids = fetch_execution_records(0);
print 'execution record count: ', scalar(keys(%$execution_record_uuids)), "\n";
my $condor_queue = fetch_condor('condor_q');
print 'condor queue count: ', scalar(keys(%$condor_queue)), "\n";
my $condor_history = fetch_condor('condor_history');
print 'condor history count: ', scalar(keys(%$condor_history)), "\n";

print "execution record uuid                L S C result  condor\n";
foreach my $execution_record_uuid (keys %$execution_record_uuids) {
	next if (exists($condor_queue->{$execution_record_uuid}));
	my $logfileregex = ${execution_record_uuid} . '_*.log';
	print "$execution_record_uuid ";
	print $execution_record_uuids->{$execution_record_uuid}->{'launch_flag'}, ' ';
	print $execution_record_uuids->{$execution_record_uuid}->{'submitted_to_condor_flag'}, ' ';
	print $execution_record_uuids->{$execution_record_uuid}->{'complete_flag'}, ' ';
	my $file_path = fetch_assessment_result($execution_record_uuid);
	if ($file_path) {
		if ($file_path =~ m/\.xml$/) {
			print 'success ';
		}
		elsif ($file_path =~ m/\.tar\.gz$/) {
			print 'failure ';
		}
		else {
			print $file_path, ' ';
		}
	}
	else {
		print 'nopath  ';
	}
	# my $logfilename = `find $swamplogdir -name $logfileregex`;
	# if ($logfilename) {
		# chomp $logfilename;
		# print basename($logfilename), ' ';
	# }
	# else {
		# print 'nologfile ';
	# }
	if (exists($condor_queue->{$execution_record_uuid})) {
		print 'queue ';
	}
	elsif (exists($condor_history->{$execution_record_uuid})) {
		print 'history ';
	}
	else {
		print 'nocondor ';
	}
	print "\n";
}

print "Hello World!\n";
