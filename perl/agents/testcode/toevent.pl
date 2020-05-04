#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

#** @file toevent.pl 
# 
# @brief Add events from csa_agent.log to execution_event table.
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
use EventCommon qw(fakeInsert realInsert timeToSecs);

my $help = 0;
my $man  = 0;
our $VERSION = '0.00';
my $eventlog = q{.agentevents};
my $logfile;
my $qmPort = 8084;
my $qmHost;
my $testmode = 0;
#** @var $pdtime If true, the expected log file date/time format is 'Month day hh:mm:ss'
# if false the expected format is 'YYYY/MM/DD hh:mm:ss'
my $pdtime = 0;

GetOptions(
    'test' => \$testmode,
    'pdtime' => \$pdtime,
    'event=s' => \$eventlog,
    'log=s' => \$logfile,
    'help|?' => \$help,
    'man'    => \$man,
) or pod2usage(2);

if ($help) { pod2usage(1); }
if ($man) { pod2usage( '-verbose' => 2 ); }
Log::Log4perl->easy_init($DEBUG);

my $log = Log::Log4perl->get_logger(q{});
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
my %mon2num = qw(
  jan 1  feb 2  mar 3  apr 4  may 5  jun 6
    jul 7  aug 8  sep 9  oct 10 nov 11 dec 12
    );
my $fh;
my %events;
#2013/09/13 12:29:24: INFO 5789 csa_agent.pl-346 startHTCondorJob 17291
if ( open( $fh, '<', $logfile ) ) {
    while (<$fh>) {
        if (/startHTCondorJob/) {
            chomp;
            my $seconds = 0;
            my $condorID;
            if ($pdtime) { 
                $_ =~s/\s\s/ /gsxm;
                my @line=split(/ /,$_);
                #$log->debug("PDTime: [$line[0]] [$line[1]] [$line[2]]");
                $line[2] =~ s/:$//;
                my $monNum = $mon2num{lc $line[0]};
                $seconds = timeToSecs("2014/$monNum/$line[1]", $line[2]);
                $condorID = $line[-1];
            }
            else {
                my @line=split(/ /,$_);
                $line[1] =~ s/:$//;
                $seconds = timeToSecs($line[0], $line[1]);
                $condorID = $line[-1];
            }
            next if ($seconds < 1391303556); # Feb 1, 2014 the day we burned down the dataservers.
            if (!defined($events{$condorID})) { 
                $events{$condorID} = $seconds;
            }
        }
    }
}
my %record;
my %lastStatus;
if ( open( $fh, '<', $eventlog ) ) {
    my %lastStatus;
    while (<$fh>) {
        next if (/^[a,v]run/);
        chomp;
        my @list = split(/,/);
        next if ($list[1] < 1391303556); # Feb 1, 2014 the day we burned down the dataservers.
        next if ($list[2] ne q{setvmid});
        my $payload = $list[3] // q{null};
        $payload =~s/ swamp//;
        if (defined($events{$payload})) {
            next if ($events{$payload} == 0);
            $record{'execrecorduuid'} = $list[0];
            $record{'eventtime'}      = $events{$payload};
            $record{'eventname'}      = q{assessmentStatus};
            $record{'eventpayload'}     = qq{Submitted to HTCondor};
            $action->(\%record);
            $events{$payload} = 0;
        }
        else {
            $log->warn("No such job: [$payload]");
        }
    }
    close($fh);
}
__END__
=pod

=encoding utf8

=head1 NAME
toevent.pl - Add HTCondor start events from csa_agent.log to execution_event table.

=head1 SYNOPSIS

toevent.pl --event eventlog --logfile csa_agent.log

=head1 DESCRIPTION

=head1 OPTIONS

=over 8

=item --man

Show manual page for this script

=back

=head1 EXAMPLES

=head1 SEE ALSO

=cut


