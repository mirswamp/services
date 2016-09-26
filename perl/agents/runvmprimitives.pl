#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#** @file runvmprimitives.pl
#
# @brief A test driver for VMPrimitives
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 09/24/2013 10:57:02
#*

use 5.010;
use utf8;
use warnings;
use strict;
use FindBin qw($Bin);
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );

use Getopt::Long qw/GetOptions/;
use Pod::Usage qw/pod2usage/;
use English '-no_match_vars';
use Carp qw(carp croak);
use Log::Log4perl::Level;
use Log::Log4perl;
use Data::Dumper qw(Dumper);

use SWAMP::Client::AgentClient qw(configureClient serverVersion);
use SWAMP::VMPrimitives qw(
  configure
  vmGetOutputDir
  vmPutInputDir
  vmRegister
  vmStart
  vmStatus
  vmUnregister
);
use SWAMP::SWAMPUtils qw(getLoggingConfigString getSwampConfig);

my $help = 0;
my $man  = 0;
our $VERSION = '0.00';
my $platform;
my $hostname = "vmtest_$PID";
my $outSize  = 512;
my $nCPU     = 2;
my $inpath = 'input';
my $outpath = 'output';
my $ramMB = 4096;
my $debug = 0;

GetOptions(
    'help|?'     => \$help,
    'platform=s' => \$platform,
    'outsize=i'  => \$outSize,
    'host=s'     => \$hostname,
    'input=s'    => \$inpath,
    'ouput=s'    => \$outpath,
    'ncpu=i'     => \$nCPU,
    'memMB=i'    => \$ramMB,
    'debug' => \$debug,
    'man'        => \$man,
) or pod2usage(2);

if ($help) { pod2usage(1); }
if ($man) { pod2usage( '-verbose' => 2 ); }
if (!$inpath) {
    pod2usage( 'input parameter is not optional');
}
Log::Log4perl->init( getLoggingConfigString() );
my $config   = getSwampConfig();
my $port     = int( $config->get('agentMonitorJobPort') );
my $host     = $config->get('agentMonitorHost');
if ( defined($port) && defined($host) ) {
    SWAMP::Client::AgentClient::configureClient( $host, $port);
}

my $log = Log::Log4perl->get_logger(q{});
$log->remove_appender('Screen');
my $stdout_appender =  Log::Log4perl::Appender->new( "Log::Log4perl::Appender::Screen",
name      => "screenlog", stderr    => 0);

my $layout = Log::Log4perl::Layout::PatternLayout->new( "%d{ISO8601} %p %P %F{1} %M %L> %m %n");
$stdout_appender->layout($layout);
$log->add_appender($stdout_appender);
$log->level( $debug ? $TRACE : $INFO );


my %config = ( 'hostname' => \$hostname, 'ncpu' => \$nCPU, 'memMB' => \$ramMB );

my $id = serverVersion();
$log->info("Server version says: $id");
# Test VM Primitives library
my ( $vmid, $errCode ) = vmRegister( $platform, $outSize, \%config );
if ($errCode ne SWAMP::VMPrimitives->noError) {
    $log->error("Error getting vmid $errCode");
    croak;
}
configure('testmode' => 1);
$errCode = vmPutInputDir( $vmid, $inpath );
$errCode = vmStart($vmid);
my $statusref;
($statusref, $errCode) = vmStatus($vmid);

# Now we wait for a while
while ( $statusref->{'executionstatus'} ne 'stopped' ) {
    $log->info("Current status: $statusref->{'executionstatus'}");
    sleep 1;
    ($statusref, $errCode) = vmStatus($vmid);
}
$errCode = vmGetOutputDir( $vmid, $outpath );
configure('testmode' => 0);
$errCode = vmUnregister($vmid);


sub logtag {
    return "runvmprimitives";
}
sub logfilename {
    return logtag().".log";
}
__END__
=pod

=encoding utf8

=head1 NAME

runvmprimitives.pl - Exercise the VM primitives library

=head1 SYNOPSIS

runvmprimitives.pl --platform platform --input ipath  --output opath --ncpu N --memMB MB --man --help

=head1 DESCRIPTION

Use runvmprimitives to create and run a VM using the VMPrimitives library.

=head1 OPTIONS

=over 8

=item --platform B<platform>

Provide the name of a platform on which to base the VM

=item --outsize B<MB>

Size of the output disk in MB

=item --host B<hostname> 

Specify the hostname for the VM

=item --input B<input directory>

Specify the input directory for the VM

=item --output B<output directory>

Specify the output directory for the VM

=item --memMB B<memory in MB>

Specify the amount of memory in MB the VM should have. Default is 4096MB.

=item --ncpu B<number CPU>

Specify the number of CPUs the VM should have. Default is 2.

=item --man

Show this manual page

=item --help 

Show command line options

=back

=head1 AUTHOR

Dave Boulineau <dboulineau@continuousassurance.org>

=cut


