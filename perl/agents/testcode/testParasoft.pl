#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

use strict;
use warnings;
use English '-no_match_vars';
use File::Basename;
use File::Spec::Functions;
use Time::Local;
use POSIX qw(strftime);
use Log::Log4perl::Level;
use Log::Log4perl;

use FindBin qw($Bin);
use lib ("$FindBin::Bin/../perl5", "$FindBin::Bin/lib");

use SWAMP::vmu_Support qw(
        getSwampDir
        getSwampConfig
        isSwampInABox
        getLoggingConfigString
        loadProperties
);
use SWAMP::vmu_AssessmentSupport qw(
        isLicensedTool
        isParasoft9Tool
        isParasoft10Tool
);

my $bogfile = $ARGV[0];
if ($bogfile) {
        my %bog;
        loadProperties($bogfile, \%bog);
        my $bogref = \%bog;
        if (isLicensedTool($bogref)) {
                print "isLicensedTool\n";
                if (isParasoft9Tool($bogref)) {
                        print "isParasoft9Tool\n";
                }
                elsif (isParasoft10Tool($bogref)) {
                        print "isParasoft10Tool\n";
                }
        }
}
print "Hello World!\n";

