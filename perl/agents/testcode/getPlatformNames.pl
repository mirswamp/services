#!/usr/bin/env perl
use strict;
use warnings;
use File::Basename qw(basename);
use Log::Log4perl qw(:easy);
use DBI;
use Data::Dumper;

# use lib '/opt/swamp/perl5';
use lib '../lib';
use SWAMP::vmu_Support qw(
	database_connect 
	database_disconnect
	displaynameToMastername
	masternameToPlatform
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
    
Log::Log4perl->easy_init($INFO);
my $names = _getPlatformNames();
if (defined($names)) {
	my $i = 1;
	foreach my $name (@$names) {
		my $qcow = displaynameToMastername($name);
		my $platform = masternameToPlatform($qcow);
		$qcow = basename($qcow);
		print $i++, ') ', $name, "\n";
		print "\t", $qcow, "\n";
		print "\t", $platform, "\n";
	}
}

print "Hello World\n";
