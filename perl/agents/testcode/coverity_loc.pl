#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2019 Software Assurance Marketplace

use strict;
use warnings;
use English '-no_match_vars';
use File::Spec::Functions;
use XML::XPath;

use SWAMP::vmu_Support qw(
	systemcall
	loadProperties
);

sub copy_results { my ($outputfolder) = @_ ;
    my $configfile = catfile($outputfolder, "results.conf");
    if (! -r $configfile) {
        print("copy_results - $configfile not found");
        return(0, '', '');
    }   
    my $config = loadProperties($configfile);
    if (! defined($config)) {
        print("copy_results - failed to read $configfile");
        return(0, '', '');
    }   
    my $results_archive = catfile($outputfolder, $config->get('results-archive'));
    my ($output, $status) = systemcall("tar xf $results_archive --directory=$outputfolder");
    if ($status) {
        print("copy_results - tar of $results_archive to $outputfolder failed: $output $status");
        return (0, '', '');
    }
	my $results_dir = $config->get('results-dir');
	my $assessment_summary_name = $config->get('assessment-summary-file');
	my $assessment_summary_file = catfile($outputfolder, $results_dir, $assessment_summary_name);
	if (! -r $assessment_summary_file) {
        return (0, '', '');
	}
	my $xp = XML::XPath->new(filename => $assessment_summary_file);
	my $nodeset = $xp->find('/assessment-summary/assessment-artifacts/assessment/stdout');
	my $locSum = 0;
	foreach my $node ($nodeset->get_nodelist) {
		my $file = $node->string_value();
		my $locfile = catfile($outputfolder, $results_dir, $file);
		if (open(my $fh, '<', $locfile)) {
			while (my $line = <$fh>) {
				if ($line =~ m/Total LoC input to cov-analyze\s*:\s*(\d+)/) {
					$locSum += $1;
					print "$locfile: $1\n";
					last;
				}
			}
		}
	}
	print "locSum: $locSum\n";
}

my $outputfolder = 'output';
copy_results($outputfolder);
print "Hello World!\n";
