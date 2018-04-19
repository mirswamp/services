#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2018 Software Assurance Marketplace

use strict;
use warnings;

use lib '/opt/swamp/perl5';
use SWAMP::vmu_Support qw(database_connect);

sub storedProcedureTest { my ($execrunuid) = @_ ;
	my $result = 'Failure';
	my $dbh = database_connect();
	if ($dbh) {
		my $query = q{CALL assessment.notify_user(?, @r);};
		my $sth = $dbh->prepare($query);
		$sth->bind_param(1, $execrunuid);
		$sth->execute();
		if (! $sth->err) {
			$result = $dbh->selectrow_array('SELECT @r');
		}
		else {
			print "storedProcedureTest - error: ", $sth->errstr, "\n";
		}
	}
	else {
		print "Error - database_connect failed\n";
	}
	return $result;
}

my $execrunuid = $ARGV[0];
if ($execrunuid) {
	my $result = storedProcedureTest($execrunuid);
	print "result: <$result>\n";
}
print "Hello World\n";
