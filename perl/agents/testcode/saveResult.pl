#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

use strict;
use warnings;
use lib '/opt/swamp/perl5';
use lib '../lib';
use SWAMP::vmu_AssessmentSupport qw(saveResult);

my $results = 
{
          'sha512sum' => '62e4aa6c0ebff7d6983db8f99b74173efbe1e914dc8d3ade0d5aa5050ca3a549d09229d9cf9e3e257c7a753a3b3b25c5b0bf39c6a6cb1440f8effbcb3d428c89',
		            'locSum' => 21149,
					          'status_out' => 'NOTE: begin                                                                    
							  PASS: install-os-dependencies                                         44.009176s
							  PASS: install-strace (/opt/strace-4.10/bin/strace)                     0.044379s
							  PASS: tool-unarchive                                                  80.702548s
							  PASS: package-unarchive                                                8.509689s
							  PASS: build                                                            2.041519s
							  PASS: build-trace-decode                                               0.835905s
							  PASS: assess (pass: 1, fail: 0)                                       33.276864s
							  PASS: buildbug                                                        40.502306s
							  PASS: build-archive                                                    0.055234s
							  PASS: results-archive                                                  0.237981s
							  PASS: resultparser-unarchive                                           0.020721s
							  PASS: parse-results (weaknesses: 0)                                    0.537745s
							  PASS: parsed_results-archive                                           0.003712s
							  PASS: all                                                            174.631061s
							  NOTE: end
							  ',
							            'sourcepathname' => '/swamp/working/results/cc68f33e-8761-11e7-bdbd-0025b51000fd/snappy-c-master.zip',
										          'log512sum' => '5fce5131a647bf30791ad3b53553a502b2d98068ef29e70994416fa27aaf2e899a33129ec7f3fcf6c7f3f124f6c0e3140c815a384de4ed20099fd1288bf23d68',
												            'pathname' => '/swamp/working/results/cc68f33e-8761-11e7-bdbd-0025b51000fd/parsed_results.xml',
															          'execrunid' => 'cc68f33e-8761-11e7-bdbd-0025b51000fd',
																	            'logpathname' => '/swamp/working/results/cc68f33e-8761-11e7-bdbd-0025b51000fd/swamp_run.out',
																				          'source512sum' => 'b9e8f016ead62707f1cacc490b79e64d9810191f9439709dab198223311ad4fea219a0596bd3e0f6b0c4561ee9e04623839bccc3ae358ec448cbf7b8ade6c6be',
																						            'weaknesses' => '0'
																									        };

my $status = saveResult($results);
print "status: <$status>\n";
print "Hello World\n";
