#Host/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

# Test Utility methods
use strict;
use warnings;

use Test::More;
use File::Spec;
use Cwd qw(getcwd abs_path);
use English '-no_match_vars';
use Getopt::Long;
use Cwd;
use Log::Log4perl;
use Log::Log4perl::Level;
use File::Spec qw(catpath catfile);
use File::Path qw(make_path remove_tree);

BEGIN {
    use_ok('SWAMP::SWAMPUtils');
}

use SWAMP::SWAMPUtils qw( systemcall getSWAMPDir checksumFile loadProperties
saveProperties getLoggingConfigString removehtaccess createhtaccess makeoption
readDomainPIDFile makePIDFilename createDomainPIDFile removeDomainPIDFile);

my ( $vol, $dir, undef ) =
  File::Spec->splitpath( File::Spec->rel2abs($PROGRAM_NAME) );
$dir = File::Spec->catpath( $vol, $dir, q{} );
require File::Spec->catfile( $dir, 'util.pl' );

my $debug = 0;
GetOptions( 'debug' => \$debug );

sub logtag {
    return $PROGRAM_NAME;
}

sub logfilename {
    return "${PROGRAM_NAME}.log";
}
Log::Log4perl->init( getLoggingConfigString() );
my $log = Log::Log4perl->get_logger(q{});
$log->level( $debug ? $TRACE : $INFO );
my $cwd = getcwd();
$log->debug("process started in $cwd");
chdir($dir);
$log->debug( "process now in in " . getcwd() );

my %map = ( 'foo' => 'bar', 'execrunid' => 'br549', 'gav' => 'this is not a gav' );
is( saveProperties( 'temp.props', \%map ), 1, 'Save property file' );
my %othermap;
is( loadProperties( 'temp.props', \%othermap ), 3, 'Load property file' );
my $checksum = checksumFile('temp.props');
my ( $output, $status ) = systemcall("sha512sum temp.props");
$output =~ s/\ .*$//sxm;
is( $checksum, $output, 'Checksum calculate' );

my $webroot='/tmp/foo/bar/subdir';
($output, $status) = createhtaccess( $webroot, 'oicu812', '127.0.0.1', 'abcdef' );
is( $status, 1, 'Create .htaccess file' );
($output, $status) = createhtaccess( $webroot, 'oicu812', '127.0.0.1', 'abcdef' );
is( $status, 1, 'Create .htaccess file with existing project name' );
$output=qx{grep ^RequestHeader $webroot/oicu812/.htaccess};
chomp $output;
is ($output, qq{RequestHeader set AUTHORIZATION "SWAMP abcdef"}, 'Check header auth');
$output=qx{grep ^RewriteRule $webroot/oicu812/.htaccess};
chomp $output;
is ($output, q{RewriteRule ^/?(.*) https://127.0.0.1/oicu812/$1 [P]}, 'Check header rewrite');
($output, $status) = removehtaccess( $webroot, 'oicu812', '127.0.0.1', 'abcdef' );
is( $status, 1, 'Remove .htaccess file');
($output, $status) = createhtaccess( '/foo', 'oicu812', '127.0.0.1', 'abcdef' );
is( $status, 0, 'Fail to create .htaccess file with illegal path' );
my $junk;
($output, $status) = removehtaccess( $webroot, $junk, '127.0.0.1', 'abcdef' );
is( $status, 0, 'DO NOT Remove webroot v1');
($output, $status) = removehtaccess( $webroot, '', '127.0.0.1', 'abcdef' );
is( $status, 0, 'DO NOT Remove webroot v2');
($output, $status) = createhtaccess( '/foo', 'oicu812', '127.0.0.1', 'abcdef' );
my $rundir = File::Spec->catfile( getSWAMPDir(), 'run');
make_path( abs_path($rundir)) ;
my $pidfile = makePIDFilename('1234', 'myvmname');
is( createDomainPIDFile(1234, 'myvmname'), 1, 'Create Domain/PID file');
is( -r "$rundir/$pidfile", 1, 'Check for Domain/PID file');
my ($pid, $domain) = readDomainPIDFile("$rundir/$pidfile");
is ($pid, 1234, 'Read correct PID from file');
is ($domain, 'myvmname', 'Read correct domain from file');
is( removeDomainPIDFile(1234, 'myvmname'), 1, 'Remove Domain/PID file');
is( -r "$rundir/$pidfile", undef, 'Check for removed Domain/PID file');
my $param;
$param=makeoption($param, 'aparam');
is ($param, q{}, 'Undefined param returns blank');
$param=makeoption('value', 'aparam');
is ($param, q{--aparam value}, 'Defined param returns option');
system('/bin/rm -rf /tmp/foo'); # Clean up after ourselves
done_testing();
