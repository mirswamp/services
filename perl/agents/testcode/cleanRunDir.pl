#!/usr/bin/env perl
use strict;
use warnings;
use English '-no_match_vars';
use File::Basename qw(basename);
use File::Spec::Functions;
use Log::Log4perl;

use FindBin qw($Bin);
use lib ("$FindBin::Bin/../lib", "$FindBin::Bin/../perl5");
use SWAMP::vmu_Support qw(
	getSwampDir
	getLoggingConfigString
	cleanRunDir
);

sub logfilename {
	my $name = basename($PROGRAM_NAME, ('.pl'));
	chomp $name;
	return catfile(getSwampDir(), 'log', $name . '.log');
}

Log::Log4perl->init(getLoggingConfigString());
cleanRunDir();
print "Hello World!\n";
