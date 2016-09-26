#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#** @file dumphist.pl
#
# @brief
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 09/04/2013 12:57:33
#*

use 5.010;
use utf8;
use warnings;
use strict;
use FindBin qw($Bin);
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );

use Getopt::Long qw/GetOptions/;
use Data::Dumper;
use Cwd qw(abs_path);
use Pod::Usage qw/pod2usage/;
use English '-no_match_vars';
use Carp qw/croak carp/;
use Storable qw(lock_retrieve);
use Log::Log4perl qw(:easy);
use Log::Log4perl::Level;

use SWAMP::Client::AgentClient qw(configureClient fetchHistoryFile);
use SWAMP::SWAMPUtils qw(getSwampConfig getLoggingConfigString uname);

my $help = 0;
my $man  = 0;
my $host;
my $historyfile;
my $majikmode = 0;
my $since = 0;    # in minutes
our $VERSION = '0.00';

GetOptions(
    'f=s'     => \$historyfile,
    'majik' => \$majikmode,
    'help|?'  => \$help,
    'host=s' => \$host,
    'last=i' => \$since,
    'man'     => \$man,
) or pod2usage(2);
Log::Log4perl->easy_init($TRACE);

if ($help) { pod2usage(1); }
if ($man) { pod2usage( '-verbose' => 2 ); }
my $jobIdx      = 0;
my $averageTime = 0;
my $startTime   = 0;
my $endTime     = 0;
my $minTime     = time;
my $minT        = 10_000;
my $maxT        = 0;
if ( $since == 0 ) {
    $minTime = 0;
}
else {
    $minTime -= 60*$since;
}
if ( !defined($historyfile) ) {
    $historyfile = 'swamp.history';
    if ( setupClient($host) ) {
        my $results = fetchHistoryFile();
        open( my $fh, '>', $historyfile );
        binmode $fh;
        print $fh $results;
        close($fh);
    }
}

my $histref = lock_retrieve( abs_path($historyfile) );
my %projuuids;
foreach my $key ( keys %{$histref} ) {
    my $runref = $histref->{$key};
    my @arr = sort keys %{$runref};
    $projuuids{$arr[0]} = $key;
}
foreach my $key ( sort keys %projuuids) {
        if ($majikmode) {
            print "KEY: <$projuuids{$key}>\n";
            }
    my $runref = $histref->{$projuuids{$key}};
    my $start  = 0;
    my $end    = 0;
    # These keys are times and sorted accordingly
    foreach my $runkey ( sort keys %{$runref} ) {
        # Skip ones before our filter time;
        if ( $runkey < $minTime ) {
            if ($majikmode) {
                print "Start is too soon: ", scalar localtime $runkey,"\n";
            }
                last;
        }
        if ($majikmode) {
            print scalar localtime $runkey," ($runkey)\n";
            next;
        }

        if ( $startTime == 0 ) {
            $startTime = $runkey;
        }
        if ( $runkey < $startTime ) {
            $startTime = $runkey;
        }
        if ( $start == 0 ) {
            $start = $runkey;
        }
        my $evtref = $runref->{$runkey};
        foreach my $evtkey ( keys %{$evtref} ) {
            my $evt = $evtref->{$evtkey} // q{};
            my $timestr = scalar localtime $runkey;
            printf "$timestr:$jobIdx:%-20s = %-24s (%s)\n", $evtkey, $evt, $projuuids{$key};
        }
        $end = $runkey;
        if ( $end > $endTime ) {
            $endTime = $end;
        }
    }
    $end = int( $end - $start + 0.5 );
    if ( $end != 0 ) {
        print "Total time(seconds): $end\n";
        if ( $end > $maxT ) {
            $maxT = $end;
        }
        if ( $end < $minT ) {
            $minT = $end;
        }
        $averageTime += $end;
        $jobIdx++;
    }
}
if ($jobIdx) {
    $averageTime = int( $averageTime / $jobIdx );
    print "Avg time(seconds): $averageTime for $jobIdx jobs\n";
}
print "Max time(seconds): $maxT\n";
print "Min time(seconds): $minT\n";
my $stime = scalar localtime( int($startTime) );
my $etime = scalar localtime( int($endTime) );
print "Log start: $stime\n  Log end: $etime\n";

#** @function setupClient( )
# @brief Configure XML::RPC clients
#
# @return 0 if clients couldn't be correctly configured, 1 otherwise
#*
sub setupClient {
    my $userHost = shift;
    my $config = getSwampConfig();
    my $port   = int( $config->get('agentMonitorJobPort') );
    my $host   = $userHost // $config->get('agentMonitorHost');

    if ( defined($port) && defined($host) ) {
        SWAMP::Client::AgentClient::configureClient( $host, $port, $PROGRAM_NAME );
    }
    else {
        carp "Unable to discern host and port of agentMonitor";
        return 0;
    }
    return 1;
}
__END__
=pod

=encoding utf8

=head1 NAME


=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 OPTIONS

=over 8

=item --man

Show manual page for this script

=back

=head1 EXAMPLES

=head1 SEE ALSO

=cut


