#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

use strict;
use warnings;
use lib '../lib';
use SWAMP::ScarfXmlReader;

sub metricSummaryFunction { my ($href, $execrunuid) = @_ ;
	print "In metricSummaryFunction\n";
	my $metricSummaries = $href->{'MetricSummaries'};
	foreach my $metricSummary (@$metricSummaries) {
		my $type = $metricSummary->{'Type'};
		my $sum = $metricSummary->{'Sum'};
		print "$type: $sum\n";
	}
}

sub parse_metric_loc { my ($execrunuid, $parsed_results_file) = @_ ;
	return if (! $parsed_results_file || ! -r $parsed_results_file);
	my $reader = new SWAMP::ScarfXmlReader($parsed_results_file);
	$reader->SetEncoding('UTF-8');
	$reader->SetMetricSummaryCallback(\&metricSummaryFunction);
	my $data = $execrunuid;
	$reader->SetCallbackData(\$data);
	$reader->Parse();
}

my $parsed_results_file = $ARGV[0];
my $execrunuid = $ARGV[1];
parse_metric_loc($execrunuid, $parsed_results_file);

print "Hello World!\n";
