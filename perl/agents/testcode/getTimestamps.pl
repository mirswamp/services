#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

use strict;
use warnings;
use Log::Log4perl qw(:easy);
use DBI;
use Data::Dumper;

# use lib '/opt/swamp/perl5';
use lib '../lib';
use SWAMP::vmu_Support qw(
	database_connect 
	database_disconnect
);

sub _getTimestamps { my ($execrunuid) = @_ ;
	my $timestamps = {};
    my $dbh = database_connect();
    if ($dbh) {
    	my $query = q{SELECT UNIX_TIMESTAMP(run_date), UNIX_TIMESTAMP(completion_date), UNIX_TIMESTAMP(create_date), UNIX_TIMESTAMP(update_date), UNIX_TIMESTAMP(delete_date) FROM assessment.execution_record where execution_record_uuid = ?};
		my $sth = $dbh->prepare($query);
		$sth->bind_param(1, $execrunuid);
		$sth->execute();
		if ($sth->err) {
			print "Error - SELECT timestamps - execute error: ", $sth->errstr, "\n";
		}
		else {
			$timestamps = $sth->fetchrow_hashref();
			if ($sth->err) {
				print "Error - SELECT timestamps - fetch error: ", $sth->errstr, "\n";
				$timestamps = {};
			}
			$timestamps = {} if (! defined($timestamps));
		}
		$sth->finish();
    	database_disconnect($dbh);
    }   
    return $timestamps;
}
    
Log::Log4perl->easy_init($ALL);
my $execrunuid = $ARGV[0];
if (! $execrunuid) {
	print "Error - no execrunuid\n";
	exit;
}
my $timestamps = _getTimestamps($execrunuid);
foreach my $key (sort keys %$timestamps) {
	print $key, ' => ', $timestamps->{$key} || 'undefined', "\n";
}
print "Hello World\n";
