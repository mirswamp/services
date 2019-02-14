#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2019 Software Assurance Marketplace

#** @file add_event.pl
#
# @brief Add an event to the execution_event table or add all events from .agentevent file to the execution_event table.
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 05/02/2014 14:05:37
#*

use 5.014;
use utf8;
use warnings;
use strict;
use FindBin qw($Bin);
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );

use Data::Dumper;
use Getopt::Long qw/GetOptions/;
use Pod::Usage qw/pod2usage/;
use English '-no_match_vars';
use Carp qw(carp croak);
use Log::Log4perl qw(:easy);
use SWAMP::SWAMPUtils qw(getSwampConfig);
use SWAMP::Client::GatorClient qw(configureClient);
use EventCommon qw(realInsert fakeInsert);

my $help = 0;
my $man  = 0;
our $VERSION = '0.00';
my $file;
my $euid;
my $event;
my $timestamp;
my $payload;
my %record;
my $qmPort = 8084;
my $qmHost;
my $testmode = 0;
my $csv = 0;

GetOptions(
    'host=s' => \$qmHost,
    'port=i' => \$qmPort,
    'file=s' => \$file,
    'csv'    => \$csv,
    'test'   => \$testmode,
    'e=s'    => \$record{'execrecorduuid'},
    'v=s'    => \$record{'eventname'},
    't=s'    => \$record{'eventtime'},
    'p=s'    => \$record{'eventpayload'},
    'help|?' => \$help,
    'man'    => \$man,
) or pod2usage(2);

if ($help) { pod2usage(1); }
if ($man) { pod2usage( '-verbose' => 2 ); }
if ( !$file ) {
    if ( !$record{'execrecorduuid'} ) { pod2usage('exec record uid is required'); }
    if ( !$record{'eventname'} )      { pod2usage('event type is required'); }
    if ( !$record{'eventtime'} )      { pod2usage('timestamp is required'); }
}
Log::Log4perl->easy_init($DEBUG);
my $config = getSwampConfig();
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
if ($file) {
    my $fh;
    if ( open( $fh, '<', $file ) ) {
        my %lastStatus;
        while (<$fh>) {
            next if (/^[a,v]run/);
            next if (/resultsprocessed/);
            chomp;
            my @list = split(/,/);
            next if ($list[1] < 1391303556); # Feb 1, 2014 the day we burned down the dataservers.
            my $payload = $list[3] // q{null};

            # Map known changed statuses to current production settings.
            if ( $payload eq q{ Finished with errors.} ) {
                $payload = q{ Finished with errors};
            }
            if ( $payload eq q{ performing assessment} ) {
                $payload = q{ Performing assessment};
            }
            my $index = $list[2] . $payload;
            $payload =~s/^ //;

            # if this event is the same as the previous event for this uuid, then skip it.
            if ( defined( $lastStatus{ $list[0] } ) && $lastStatus{ $list[0] } ne $index ) {
                $record{'execrecorduuid'} = $list[0];
                $record{'eventtime'}      = $list[1];
                $record{'eventname'}      = $list[2];
                if ( defined($payload) ) {
                    $record{'eventpayload'} = $payload;
                }
                else {
                    $record{'eventpayload'} = q{};
                }
                $action->(\%record);
            }
            $lastStatus{ $list[0] } = $index;
        }
        close($fh);
    }
}
else {
    insertExecEvent( \%record );
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


