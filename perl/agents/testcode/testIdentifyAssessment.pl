#!/usr/bin/env perl
use strict;
use warnings;
use Log::Log4perl qw(:easy);
use lib '../lib';
use SWAMP::vmu_AssessmentSupport qw(
	identifyAssessment
);

Log::Log4perl->easy_init($ALL);
my $execrunuid = '899c0325-30df-11ea-a09b-0025b51000ed';
my $bogref = {
	'execrunid'			=> $execrunuid,
	'packagename'			=> 'packagename',
	'packagepath'			=> 'packagepath',
	'toolname'				=> 'toolname',
	'toolpath'				=> 'toolpath',
	'platform_identifier'	=> 'platform_identifier',
	'platform_type'			=> 'platform_type',
	'platform_image'		=> 'platform_image',
};
identifyAssessment($bogref);
