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
use Getopt::Long qw(GetOptions);
use File::Basename qw(basename);
use File::Spec::Functions;
use Log::Log4perl;
use Log::Log4perl::Level;
use POSIX qw(setsid);

use FindBin qw($Bin);
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );

use SWAMP::vmu_Notification qw(getNotifier);
use SWAMP::vmu_Support qw(
	getLoggingConfigString
  	getSwampConfig
  	getSwampDir
  	systemcall
);

my %options = (
    'debug'  => 0,
    'transmission_medium'  => q{EMAIL},
    'daemon' => 1
);
my @optionNames = qw(
  daemon!
  debug
  notification_uuid=s
  transmission_medium=s
  user_uuid=s
  notification_impetus=s
  success_or_failure=s
  project_name=s
  package_name=s
  package_version=s
  tool_name=s
  tool_version=s
  platform_name=s
  platform_version=s
  completion_date=s
);
GetOptions( \%options, @optionNames );

Log::Log4perl->init(getLoggingConfigString());
my $log = Log::Log4perl->get_logger(q{});
$log->level( $options{'debug'} ? $TRACE : $INFO );

if ( $options{'daemon'} ) {
    chdir(q{/});
    if (! open(STDIN, '<', File::Spec->devnull)) {
        $log->error("prefork - open STDIN to /dev/null failed: $OS_ERROR");
        exit;
    }
    if (! open(STDOUT, '>', File::Spec->devnull)) {
        $log->error("prefork - open STDOUT to /dev/null failed: $OS_ERROR");
        exit;
    }
    my $pid = fork();
    if (! defined($pid)) {
        $log->error("fork failed: $OS_ERROR");
        exit;
    }
    if ($pid) {
        # parent
        exit(0);
    }
    # child
    if (setsid() == -1) {
    	$log->error("child - setsid failed: $OS_ERROR");
        exit;
    }
    if (! open(STDERR, ">&STDOUT")) {
    	$log->error("child - open STDERR to STDOUT failed:$OS_ERROR");
        exit;
    }
}

my $notifier = getNotifier($options{'transmission_medium'});
if ($notifier->(%options)) {
    $log->info("Notifier succeeded");
}
else {
    $log->error("Notifier failed");
}

sub logfilename {
    ( my $name = $PROGRAM_NAME ) =~ s/\.pl//sxm;
    $name = basename($name);
    return catfile(getSwampDir(), 'log', $name . '.log');
}
