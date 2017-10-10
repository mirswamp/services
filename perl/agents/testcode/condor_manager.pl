#!/usr/bin/env perl
use strict;
use warnings;

my $HTCONDOR_COLLECTOR_HOST = 'swa-csacol-dt-01.cosalab.org';
my $condor_manager = $HTCONDOR_COLLECTOR_HOST;
$condor_manager =~ s/csacol/csacon/;
$condor_manager =~ s/(.*)\..*\.org$/$1\.mirsam.org/;
print "condor_manager: <$condor_manager>\n";
print "Hello World!\n";
