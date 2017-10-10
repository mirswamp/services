#!/usr/bin/env perl
use strict;
use warnings;
use DBI;
use Data::Dumper;

use lib '/opt/swamp/perl5';
use SWAMP::vmu_Support qw(database_connect database_disconnect);

sub _computeBOG { my ($execrunuid) = @_ ;
    my $dbh = database_connect();
	my $result;
    if ($dbh) {
    	my $query = q{SELECT * FROM assessment.exec_run_view WHERE execution_record_uuid = ?};
		my $sth = $dbh->prepare($query);
		$sth->bind_param(1, $execrunuid);
		$sth->execute();
		if ($sth->err) {
			print "select assessment.exec_run_view - error: $sth->errstr", "\n";
		}
		else {
			$result = $sth->fetchrow_hashref();
			print 'result: ', Dumper($result);
		}
		$sth->finish();
    	database_disconnect($dbh);
    }   
    if (! $result || ($result eq 'error')) {
    	return 0;
    }   
    return 1;
}
    
my $execrunuid = $ARGV[0];
my $result = _computeBOG($execrunuid);
print "result: <$result>\n";

print "Hello World\n";
