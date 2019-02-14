#!/usr/bin/env perl
use strict;
use warnings;
use Log::Log4perl qw(:easy);
use lib '../lib';
use SWAMP::vmu_Support qw(
	getSwampConfig
	$global_swamp_config
	database_connect
	database_disconnect
);
use SWAMP::vmu_AssessmentSupport qw(
	needsLicenseServerAccessTool
	getLicenseServerData
);

Log::Log4perl->easy_init($ALL);
$global_swamp_config ||= getSwampConfig('swamp.conf');
my $toolnames;
my $dbh = database_connect('root', 'swampinabox');
if ($dbh) {
	my $query = q{SELECT name from tool_shed.tool};
	my $sth = $dbh->prepare($query);
	$sth->execute();
	if ($sth->err) {
		print "$query failed - error: ", $sth->errstr, "\n";
	}
	else {
		$toolnames = $sth->fetchall_arrayref({});
	}
	database_disconnect($dbh);
}
foreach my $toolname (@$toolnames) {
	my $bogref = {
		'toolname'	=> $toolname->{'name'},
		'tool-version'	=> '10.',
	};
	if (needsLicenseServerAccessTool($bogref)) {
		print 'toolname: ', $bogref->{'toolname'}, "\n";
		my (undef, $port, $aux_port, $ip) = getLicenseServerData($bogref);
		print '  ip: ', $ip || '', ' port: ', $port || '', ' aux_port: ', $aux_port || '', "\n";
	}
}
print "Hello World!\n";
