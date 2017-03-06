#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2017 Software Assurance Marketplace

use 5.014;
use utf8;
use warnings;
use strict;
use English '-no_match_vars';
use File::Basename qw(basename);
use File::Spec::Functions;
use Getopt::Long qw(GetOptions);
use Cwd qw(getcwd);
use Log::Log4perl::Level;
use Log::Log4perl;

use FindBin qw($Bin);
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );

# use SWAMP::Client::AgentClient qw(configureClient csaAgentStop);
use SWAMP::vmu_Support qw(
	getLoggingConfigString 
	getSwampConfig 
	getSwampDir 
);

my $startupdir = getcwd;
my $asdaemon   = 1;
my $debug      = 0;
my $execution_record_uuid;

GetOptions(
    'execution_record_uuid=s' => \$execution_record_uuid,
);
chdir($startupdir);

Log::Log4perl->init( getLoggingConfigString() );
my $log = Log::Log4perl->get_logger(q{});
$log->level( $debug ? $TRACE : $INFO );
Log::Log4perl->get_logger(q{})->remove_appender('Screen');

$log->info("$PROGRAM_NAME killrun");

my $config     = getSwampConfig();
my $serverPort = $config->get('agentMonitorJobPort');
my $serverHost = $config->get('agentMonitorHost');
# SWAMP::Client::AgentClient::configureClient( $serverHost, $serverPort );

if ($execution_record_uuid) {
    # csaAgentStop( { 'execrunid' => $execution_record_uuid } );
}

sub logfilename {
    ( my $name = $PROGRAM_NAME ) =~ s/\.pl//sxm;
    $name = basename($name);
    return catfile(getSwampDir(), 'log', $name . '.log');
}
