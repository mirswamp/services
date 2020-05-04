#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

#** @file dump_event.pl
#
# @brief Examine the event log in the assessment table and dump it to STDOUT
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 5/2/2014
#*

use 5.014;
use utf8;
use warnings;
use strict;
use FindBin qw($Bin);
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );

use DBI;
use Getopt::Long qw/GetOptions/;
use Pod::Usage qw/pod2usage/;
use English '-no_match_vars';
use Carp qw(carp croak);

my $help = 0;
my $man  = 0;
my $file;
## Name of dataserver to query
my $host = "swa-csaper-dt-01.mirsam.org";
# @var $tolog if true emit log formatted output suitable for Splunk to grok, otherwise csv
my $tolog = 1; 
my %state;
my %events;
my %log;    # store events in a log map so we can emit it in time order.
my $since;
our $VERSION = '1.00';

GetOptions(
    'dataserver=s' => \$host,
    'since=s' => \$since,
    'file=s'       => \$file,
    'log!'          => \$tolog,
    'help|?'       => \$help,
    'man'          => \$man,
) or pod2usage(2);

if ($help) { pod2usage(1); }
if ($man) { pod2usage( '-verbose' => 2 ); }
if (defined($since)) {
    $since = time - $since*3600;
}
if ($file) {
    fromFile($file);
}
else {
    fromDB();
}
#$foreach my $id ( keys %events ) {
#    say "$id $events{$id}";
#}
# Process all of the state information
# The time a job spent
foreach my $execid ( keys %state ) {
    my $launchTime=0;
    my $submitTime=0;
    my $runTime=0;
    my $vmStart=0;
    my $vmEnd=0;
    my $arunEnd=0;
    my $assessTime=0;
    my $ref = $state{$execid};
    my $nvmid=0;
    my $keep = 1;
    foreach my $ts ( sort keys $ref ) {
        if ($ref->{$ts}->{payload} eq q{Failed to start VM.}) {
            $keep = 0;
            last;
        }
        if ($ref->{$ts}->{event} eq q{setvmid}) {
            $nvmid++;
            if ($nvmid > 1) {
                $keep = 0;
                last;
            }
        }
        if ( $ref->{$ts}->{event} eq q{launchpadstart} ) {
            $launchTime = $ts;
        }
        if ( $ref->{$ts}->{payload} eq q{Submitted to HTCondor} ) {
            $submitTime = $ts;
        }
        elsif ( $ref->{$ts}->{event} eq q{htcondorstatus1} && $runTime == 0 ) {
            $runTime = $ts;
        }
        elsif ( $ref->{$ts}->{payload} eq q{Performing assessment} && $assessTime == 0) {
            $assessTime = $ts;
        }
        elsif ( $ref->{$ts}->{event} eq q{domainstate}) {
            if ($ref->{$ts}->{payload} eq q{started} && $vmStart == 0) {
                $vmStart = $ts;
            }
            elsif ($ref->{$ts}->{payload} eq q{stopped}) {
                $vmEnd = $ts;
            }
        }
        elsif ( $ref->{$ts}->{payload} =~ /Finished/) {
            $arunEnd = $ts;    
        }
        # we should skip assessments that 'Failed to start VM'
    }
    if ($keep && $launchTime && $runTime && $submitTime && $vmEnd && $vmStart && $arunEnd && $assessTime) {
        $log{$execid}->{basetime} = $launchTime;
        $log{$execid}->{launch} = $submitTime - $launchTime;
        $log{$execid}->{submit} = $runTime - $submitTime;
        $log{$execid}->{vmbuild} = $vmStart - $runTime;
        $log{$execid}->{vmlife} = $vmEnd - $vmStart;
        $log{$execid}->{assess} = $vmEnd - $assessTime;
        $log{$execid}->{post} = $arunEnd - $vmEnd;
        $log{$execid}->{total} = $arunEnd - $launchTime;
        $log{$execid}->{end} = $arunEnd ;
    }
}

sub byval {
    $log{$a}->{basetime} <=> $log{$b}->{basetime};
}
if ( $tolog ) {
    foreach my $id ( sort byval keys %log ) {
        printf "%s execid=$id,launchwait=%4.2f,submitwait=%4.2f,vmbuildtime=%4.2f,assesstime=%4.2f,vmtime=%4.2f,posttime=%4.2f,totaltime=%4.2f\n",
          scalar localtime( int( $log{$id}->{basetime} ) ), $log{$id}->{launch},
          $log{$id}->{submit}, $log{$id}->{vmbuild}, $log{$id}->{assess}, $log{$id}->{vmlife}, $log{$id}->{post}, $log{$id}->{total};
    }
}
else {
    say "execrunid,launch time,time queued, HTCondor queue,VM build,arun total,VM lifetime,post processing,total, end";
    foreach my $id ( sort byval keys %log ) {
        printf "$id,\"%s\",%4.2f,%4.2f,%4.2f,%4.2f,%4.2f,%4.2f,%4.2f,\"%s\"\n",
          scalar localtime( int( $log{$id}->{basetime} ) ), $log{$id}->{launch},
          $log{$id}->{submit}, $log{$id}->{vmbuild}, $log{$id}->{assess}, $log{$id}->{vmlife}, $log{$id}->{post},$log{$id}->{total}, scalar localtime(int($log{$id}->{end}));
    }
   
}
exit(0);

sub fromFile {
    my $dbfile = shift;
    if ( open( my $fh, '<', $dbfile ) ) {
        while (<$fh>) {
            chomp;
            my @row        = split( /,/, $_ );
            my $execid     = $row[0];
            my $event_time = $row[1];
            my $event      = $row[2];
            my $payload    = $row[3] // q{};
            if ( $event eq q{htcondorstatus} ) {
                $event .= $payload;
            }
            $state{$execid}->{$event_time}->{event}   = $event;
            $state{$execid}->{$event_time}->{payload} = $payload;
            if ( $event eq q{setvmid} ) {
                $payload = q{swamp};
            }
            $events{"$event,$payload"}++;
        }
        if (!close($fh)) {
            carp "Unable to close $dbfile: $OS_ERROR";
        }
    }
    else {
        carp "Unable to open $dbfile: $OS_ERROR";
    }
    return;
}

sub fromDB {
## mysql user database name
    my $db = "assessment";
## mysql database user name
    my $user = "web";

## mysql database password
    my $pass = 'MNH$f4xP7vWQ$64d';


## SQL query
    my $query = "show tables";
    $query = qq{describe assessment.execution_event;};

    my $dbh = DBI->connect( "DBI:mysql:$db:$host", $user, $pass );
    my $sqlQuery = $dbh->prepare($query)
      or croak "Can't prepare $query: $dbh->errstr\n";

    my $rv = $sqlQuery->execute
      or croak "can't execute the query: $sqlQuery->errstr";

    my $row0;
    my %index;
    my $ii = 0;
    while ( my @row = $sqlQuery->fetchrow_array() ) {
        $row0 .= qq{"$row[0]"|};
#        say "$row[0] = $ii";
        $index{ $row[0] } = $ii++;
    }
    my $rc = $sqlQuery->finish;

    $query = q{SELECT * FROM assessment.execution_event};
    if (defined($since)) {
        $query .= qq{ where event_time > $since};
    }
    $query .= q{;};

    #$dbh = DBI->connect( "DBI:mysqlPP:$db:$host", $user, $pass );
    $sqlQuery = $dbh->prepare($query)
      or croak "Can't prepare $query: $dbh->errstr\n";

    $rv = $sqlQuery->execute
      or croak "can't execute the query: $sqlQuery->errstr";

# "execution_event_id"|"execution_record_uuid"|"event_time"|"event"|"payload"|"create_user"|"create_date"|"update_user"|"update_date"|

    #my $ref = $sqlQuery->fetchall_arrayref();
    while ( my @row = $sqlQuery->fetchrow_array() ) {
        my $execid     = $row[ $index{execution_record_uuid} ];
        my $event_time = $row[ $index{event_time} ];
        my $event      = $row[ $index{event} ];
        my $payload    = $row[ $index{payload} ];
        if ( $event eq q{htcondorstatus} ) {
            $event .= $payload;
        }
        $state{$execid}->{$event_time}->{event}   = $event;
        $state{$execid}->{$event_time}->{payload} = $payload;
        if ( $event eq q{setvmid} ) {
            $payload = q{swamp};
        }
        $events{"$event,$payload"}++;
    }
    $rc = $sqlQuery->finish;
    return;
}

__END__
=pod

=encoding utf8

=head1 NAME

dump_event

=head1 SYNOPSIS

dump_event [--dataserver HOST] [--nolog]

=head1 DESCRIPTION

dump_event queries a SWAMP dataserver for events from the assessment.execution_event table and converts those events into a log file (or CSV if --nolog is provided)

=head1 OPTIONS

=over 8

=item --man

Show manual page for this script

=item --dataserver HOST

Specify the SWAMP dataserver host to which the script should connect, host can be IP address or hostname.

=item --log

Output format is that of a log file sorted by event time. DEFAULT

=item --nolog

Output format is CSV

=back

=head1 EXAMPLES

dump_event --dataserver swa-csadata-it-01 > integration.log


=cut


