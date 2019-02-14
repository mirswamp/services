#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2019 Software Assurance Marketplace

use strict;
use warnings;
use DBI;
use lib '/opt/swamp/perl5';
use SWAMP::vmu_Support qw(database_connect database_disconnect);

sub doit {
    my $dbh = database_connect();
	my $result;
    if ($dbh) {
    	my $query = q{CALL assessment.set_system_status(?, ?, @r);};
		my $sth = $dbh->prepare($query);
		$sth->bind_param(1, 'Tom_mood');
		$sth->bind_param(2, 'mood five');
		my $status = $sth->execute();
		$result = $dbh->selectrow_array('SELECT @r');
		print "result: <$result>\n";
    	database_disconnect($dbh);
    }   
    if (! $result || ($result eq 'error')) {
    	return 0;
    }   
    return 1;
}
    
my $result = doit();
print "result: <$result>\n";

print "Hello World\n";
