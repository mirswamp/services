#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2017 Software Assurance Marketplace

#** @file toevent.pl
# 
# @brief  Add events from calldorun.log to execution_event log.
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 05/21/2014 13:53:36
#*

use 5.014;
use utf8;
use warnings;
use strict;
use FindBin qw($Bin);
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );

use Getopt::Long qw/GetOptions/;
use Pod::Usage qw/pod2usage/;
use English '-no_match_vars';
use Carp qw(carp croak);
use Log::Log4perl qw(:easy);
use SWAMP::SWAMPUtils qw(getSwampConfig);
use SWAMP::Client::GatorClient qw(configureClient);
use EventCommon qw(realInsert fakeInsert timeToSecs);

my $help = 0;
my $man  = 0;
our $VERSION = '0.00';
my $logfile;
my $qmPort = 8084;
my $qmHost;
my $testmode = 0;

GetOptions(
    'test' => \$testmode,
    'log=s' => \$logfile,
    'help|?' => \$help,
    'man'    => \$man,
) or pod2usage(2);

if ($help) { pod2usage(1); }
if ($man) { pod2usage( '-verbose' => 2 ); }
Log::Log4perl->easy_init($DEBUG);

my $action;
if ($testmode) {
    $action = \&fakeInsert;
}
else {
    my $config = getSwampConfig();
    if ( !$qmHost ) {
        $qmHost = $config->get('quartermasterHost');
    }
    configureClient( $qmHost, $qmPort );
    $action = \&realInsert;
}

my $fh;
my %events;
#2014/05/22 19:21:10: DEBUG 29395 RunControllerClient.pm-82 RunControllerClient::launchPadStart on http://swa-csasub-dt-01:8083 execid is 1a17f67a-e1e6-11e3-8775-001a4a81450b
if ( open( $fh, '<', $logfile ) ) {
    while (<$fh>) {
        if (/RunControllerClient::launchPadStart/) {
            chomp;
            my @line=split(/ /,$_);
            $line[1] =~ s/:$//;
            my $secs = timeToSecs($line[0], $line[1]);
            next if ($secs < 1391303556); # Feb 1, 2014 the day we burned down the dataservers.
            $events{$line[-1]} = $secs;
#            $action->({'execrecorduuid' => $line[-1], 'eventtime' => $secs, 'eventname' => q{launchpadstart} });
        }
    }
    close($fh);
    foreach my $execid (keys %events) {
        $action->({'execrecorduuid' => $execid, 'eventtime' => $events{$execid},  'eventname' => q{launchpadstart}, 'eventpayload' => q{} });
    }
}
