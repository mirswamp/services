#!/usr/bin/env perl
use strict;
use warnings;
use Log::Log4perl qw(:easy);

use FindBin;
use lib "$FindBin::Bin/../perl5";
use SWAMP::mongoDBUtils qw(
        mongoSaveAssessmentResult
);

Log::Log4perl->easy_init($ALL);

my $assessment_results_file = $ARGV[0];
my $execrunuid = $ARGV[1];
if ((-r $assessment_results_file) && $execrunuid) {
    my $assessment_results = {
            'execrunid'         => $execrunuid,
            'pathname'          => $assessment_results_file,
    };
    my $result = mongoSaveAssessmentResult($assessment_results);
    print "result: $result\n";
}
print "Hello World!\n";

