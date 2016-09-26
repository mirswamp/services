#/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

# Test the assessmentTools package methods

use strict;
use warnings;

use Cwd qw(abs_path getcwd);
use Carp qw(croak);
use Archive::Tar;
use English '-no_match_vars';
use File::Spec;
use File::Basename qw(basename);
use File::Path qw(rmtree);
use Getopt::Long;
use Log::Log4perl::Level;
use Log::Log4perl;
use Test::More;

BEGIN {
    use_ok('SWAMP::SWAMPUtils');
    use_ok('SWAMP::Client::ResultCollectorClient');
    use_ok('SWAMP::AssessmentTools');
    use_ok('SWAMP::PackageTypes');
}

use SWAMP::AssessmentTools qw( copyInputs createRundotsh invokeResultCollector parseStatusOut getBOGValue isJavaTool deployTarball addUserDepends packageType);
use SWAMP::SWAMPUtils qw(getHostAndPort getLoggingConfigString);
use SWAMP::Client::ResultCollectorClient qw(configureClient);
use SWAMP::PackageTypes qw(
  $C_CPP_PKG_STRING 
  $JAVA7SRC_PKG_STRING 
  $JAVA7BYTECODE_PKG_STRING 
  $JAVA8SRC_PKG_STRING 
  $JAVA8BYTECODE_PKG_STRING 
  $PYTHON2_PKG_STRING 
  $PYTHON3_PKG_STRING 
  $ANDROID_JAVASRC_PKG_STRING 
  $RUBY_PKG_STRING 
  $RUBY_SINATRA_PKG_STRING
  $RUBY_ON_RAILS_PKG_STRING
  $RUBY_PADRINO_PKG_STRING
  $ANDROID_APK_PKG_STRING 

  $CPP_TYPE 
  $PYTHON_TYPE 
  $JAVA_TYPE 
  $RUBY_TYPE
);

use subs qw(start_server stop_server callOK callFAIL);
my ( $vol, $dir, undef ) =
  File::Spec->splitpath( File::Spec->rel2abs($PROGRAM_NAME) );
$dir = File::Spec->catpath( $vol, $dir, q{} );
require File::Spec->catfile( $dir, 'util.pl' );

my $configfile    = 'test.conf';
my $useTestServer = 1;
my $host;
my $port;
my $debug = 0;
GetOptions(
    'config=s' => \$configfile,
    'server!'  => \$useTestServer,
    'debug'    => \$debug
);

# Set this in the environment, all subprocesses and their children will inherit
$ENV{'SWAMP_CONFIG'} = File::Spec->catfile($dir, $configfile);

sub logtag {
    return $PROGRAM_NAME;
}
sub logfilename {
    return "${PROGRAM_NAME}.log";
}

Log::Log4perl->init( getLoggingConfigString() );

my $cwd = getcwd();
chdir($dir);
my $canonname =
  File::Spec->rel2abs( basename($PROGRAM_NAME) );    # This file should exist.

my $log = Log::Log4perl->get_logger(q{});
$log->level( $debug ? $TRACE : $INFO );
#local $SIG{'__DIE__'} = sub { Log::Log4perl->get_logger(q{})->logconfess() };
$log->remove_appender('Screen');

my $childA;
my $childB;
if ($useTestServer) {
    my $cmdA = "perl -I${cwd}/lib ${cwd}/TestDispatchServer.pl "
      . ( $debug ? q{--debug} : q{} );
    my $cmdB = "perl -I${cwd}/lib ${cwd}/AgentMonitor.pl --testharness "
      . ( $debug ? q{--debug} : q{} );
    $log->info("starting server: [$cmdA]");
    $childA = start_server($cmdA);
    $log->info("starting server: [$cmdB]");
    $childB = start_server($cmdB);
}
my ( $tempport, $temphost ) = getHostAndPort( 'dispatcher', $configfile );
if ( !defined($port) ) {
    $port = int($tempport);
}
if ( !defined($host) ) {
    $host = $temphost;
}
is( defined($port) && defined($host), 1, "Read configuration" );
configureClient( $host, $port );
my $tooltar = 'testtool.tar.gz';
my $jarfile = 'testfile.jar'; `touch $jarfile`;
system("/bin/tar -cvzf $tooltar $canonname");
my %bog = ( 'toolname' => 'Foobaz', 'toolpath' => $tooltar, 'packagepath' => $configfile, 'execrunid' => 'testID' );

# Start with a clean slate
my $testfolder = "junk$PID";
my $resultsfolder="resultsToTest$PID";
rmtree($testfolder);

#Test the copyInputs method
# ok( copyInputs( \%bog, $testfolder, 1 ), 'call copyInputs' );
# ok( -d $testfolder, 'input folder created' );
# ok( -r File::Spec->catfile( $testfolder, basename($tooltar) ), 'tool copied' );
# ok( -r File::Spec->catfile( $testfolder, basename($configfile) ), 'package copied' );
# $bog{'packagepath'} = $jarfile;
# ok( copyInputs( \%bog, $testfolder, 1 ), 'call copyInputs' );
# %bog = ( 'toolname' => q{none}, 'toolpath' => '______', 'packagepath' => $configfile, 'execrunid' => 'testID' );
# is( copyInputs( \%bog, $testfolder ), 0, 'copyInputs fail call 1st version' );
# %bog = ( 'toolname' => q{none}, 'toolpath' => $configfile, 'packagepath' => '_______', 'execrunid' => 'testID' );
# is( copyInputs( \%bog, $testfolder ), 0, 'copyInputs fail call 2nd version' );
# %bog = ( 'toolname' => q{none}, 'toolpath' => $configfile, 'pckagepath' => $configfile, 'execrunid' => 'testID' );
# is( copyInputs( \%bog, $testfolder ), 0, 'copyInputs fail invalid BOG 1st version' );
# %bog = ( 'toolname' => q{none}, 'tolpath' => $configfile, 'packagepath' => $configfile, 'execrunid' => 'testID' );
# is( copyInputs( \%bog, $testfolder ), 0, 'copyInputs fail invalid BOG 2nd version' );
%bog = (
    'toolexecutable'  => 'toolpath packageinvoke',
    'toolname'    => 'FindBugs.1.2.3.4',
    'packagename' => 'guice-3.0.0.jar',

    # Package path is needed by invokeResultCollector
    'packagepath'   => 'guice-3.0.0.jar',
    'toolpath'      => '/opt/findbugs.tar.gz',
    'toolname'      => 'findbugs',
    'tooldirectory' => 'findbugs',
    'toolarguments' => 'null',
    'gav'           => 'com.jolira:guice:3.0.0',
    'execrunid'     => '330BF716-FAB6-11E2-8D8F-2C59B0C62179',
    'packagebuild'  => 'null',
    'packagedeploy' => 'null',
    'tooldeploy'    => ' tar xvf toolpath ',
    'platform'      => 'rhel-6.4-64',
    'resultsfolder' => $resultsfolder,
    'packagesourcepath' => 'guice-3.0.0',
    'packagebuildfile' => 'test.xml',
    'packagebuildtool' => 'gradle'
);
is (!defined(getBOGValue(\%bog, 'toolarguments')),1, 'Check getBOGValue for null value'); 
is (!defined(getBOGValue(\%bog, 'thispropertydoesntexits')),1, 'Check getBOGValue for nonexistent value'); 
is (getBOGValue(\%bog, 'packagebuildtool'),'gradle', 'Check getBOGValue for actual value'); 
is (getBOGValue(\%bog, 'tooldeploy'),'tar xvf toolpath', 'Check getBOGValue for trimmed value'); 
my $success;
# $success = createRundotsh( \%bog, $testfolder );
# is( $success, 1, 'Create run.sh happy path' );

# Check parsing of status.out
my $why;
my $retry = 1;
my $statusOut=qq{PASS: step 1\nPASS: step 2\nNOTE: end};
($success, $why) = parseStatusOut($statusOut, \$retry);
is ($success, 1, 'Parse successful status.out');
is ($retry, 0, 'No retry in status.out');
$statusOut=qq{PASS: step 1\nFAIL: step 2\nFAIL: dang\nNOTE: end};
($success, $why) = parseStatusOut($statusOut);
is ($success, 0, 'Parse failed status.out');
$statusOut=qq{PASS: step 1\nFAIL: step 2\nFAIL: dang\nNOTE: end};
my @res=split(/\n/sxm, $why);
is (@res, 2, 'Correct number of failures from parseStatusOut');
$statusOut=qq{PASS: step 1\nNOTE:retry\n};
($success, $why) = parseStatusOut($statusOut, \$retry);
is ($success, 0, 'Parse ok status.out');
is ($retry, 1, 'Retry with no space set in status.out');
$statusOut=qq{PASS: step 1\nNOTE: retry\n};
($success, $why) = parseStatusOut($statusOut, \$retry);
is ($retry, 1, 'Retry with a space set in status.out');
$statusOut=qq{PASS: step 1\nNOTE:   retry\n};
($success, $why) = parseStatusOut($statusOut, \$retry);
is ($retry, 1, 'Retry with a tab set in status.out');
$statusOut=qq{PASS: step 1\nNOTE:  retry\nNOTE:end};
($success, $why) = parseStatusOut($statusOut, \$retry);
is ($retry, 1, 'Retry with multiple space set in status.out');

# Test the tarball deploy methods
is (deployTarball(q{foo}),0, 'deployTarball with invalid mode'); 
# Create test tarballs containing known files.
`mkdir in-files swamp-conf skip`;
`touch in-files/{a,b,c,d,e,f};touch swamp-conf/{sys,parser,tool}-os-dependencies.conf;touch skip/{x,y,z}`;
`/bin/tar -cf testframe.tar in-files/a in-files/b in-files/c swamp-conf/sys-os-dependencies.conf skip *.log`;
`/bin/tar -cf testparser.tar in-files/d in-files/e swamp-conf/parser-os-dependencies.conf skip`;
`mkdir noarch;mv in-files skip swamp-conf noarch`;
`/bin/tar -cf testtool.tar noarch/in-files/f noarch/swamp-conf/tool-os-dependencies.conf noarch/skip`;
is (deployTarball(SWAMP::AssessmentTools::FRAMEWORKID, q{testframe.tar}, 'input'),1,  'deployTarball with framework'); 
ok (-r 'input/os-dependencies-framework.conf', 'Framework os-dependencies deployed');
ok (-r 'input/a', 'Framework test file a deployed');
ok (-r 'input/b', 'Framework test file b deployed');
ok (-r 'input/c', 'Framework test file c deployed');
is (deployTarball(SWAMP::AssessmentTools::PARSERID, q{testparser.tar}, 'input'),1,  'deployTarball with parser'); 
ok (-r 'input/os-dependencies-parser.conf', 'Parser os-dependencies deployed');
ok (-r 'input/d', 'Parser test file d deployed');
ok (-r 'input/e', 'Parser test file e deployed');
# is (deployTarball(SWAMP::AssessmentTools::TOOLID, q{testtool.tar}, 'input', q{noarch}),1,  'deployTarball with tool'); 
# ok (-r 'input/f', 'Tool test file f deployed');
# ok (-r 'input/os-dependencies-tool.conf', 'Tool os-dependencies deployed');

# ok ( -r 'input/x', 'test file x deployed');
# ok ( -r 'input/y', 'test file y deployed');
# ok ( -r 'input/z', 'test file z deployed');


my $results = "testfile${PID}.xml";

open( my $fd, '>', $results ) || croak "Cannot open $results : $OS_ERROR";
print $fd "I am results!\n";
close $fd;
ok( -r $results, 'Create sample results' );
my $tarball = 'results.tar.gz';
Archive::Tar->create_archive( $tarball, COMPRESS_GZIP, ($results) );
ok( -r $tarball, 'Create sample results tarball' );

invokeResultCollector( 'bogref'=> \%bog, 'tarball' => 'results.tar.gz', 'soughtfile' => $results, 'logfile' => $results);
unlink($tarball);
unlink($results);
ok(-d "$resultsfolder/$bog{'execrunid'}", "results moved to shared area named results/$bog{'execrunid'}");
is( isJavaTool( { 'toolname' => q{Findbugs} } ),    1,   q{Findbugs is a Java tool} );
is( isJavaTool( { 'toolname' => q{findbugs} } ),    1,   q{findbugs is a Java tool} );
is( isJavaTool( { 'toolname' => q{Findbug} } ),     q{}, q{Findbug is not a Java tool} );
is( isJavaTool( { 'toolname' => q{cppcheck} } ),    q{}, q{cppcheck is not a Java tool} );
is( isJavaTool( { 'toolname' => q{gcc} } ),         q{}, q{gcc is not a Java tool} );
is( isJavaTool( { 'toolname' => q{clang} } ),       q{}, q{clang is not a Java tool} );
is( isJavaTool( { 'toolname' => q{PMD} } ),         1,   q{PMD is a Java tool} );
is( isJavaTool( { 'toolname' => q{Archie} } ),      1,   q{Archie is a Java tool} );
is( isJavaTool( { 'toolname' => q{archie} } ),      1,   q{archie is a Java tool} );
is( isJavaTool( { 'toolname' => q{error-prone} } ), 1,   q{error-prone is a Java tool} );
is( isJavaTool( { 'toolname' => q{checkstyle} } ),  1,   q{checkstyle is a Java tool} );
is( isJavaTool( { 'toolname' => q{Checkstyle} } ),  1,   q{checkstyle is a Java tool} );
is( packageType({'packagetype' => $C_CPP_PKG_STRING} ), $CPP_TYPE, qq{$C_CPP_PKG_STRING package is type $CPP_TYPE});
is( packageType({'packagetype' => $JAVA7BYTECODE_PKG_STRING } ), $JAVA_TYPE, qq{$JAVA7BYTECODE_PKG_STRING package is type $JAVA_TYPE});
is( packageType({'packagetype' => $JAVA7SRC_PKG_STRING } ), $JAVA_TYPE, qq{$JAVA7SRC_PKG_STRING package is type $JAVA_TYPE});
is( packageType({'packagetype' => $JAVA8BYTECODE_PKG_STRING } ), $JAVA_TYPE, qq{$JAVA8BYTECODE_PKG_STRING package is type $JAVA_TYPE});
is( packageType({'packagetype' => $JAVA8SRC_PKG_STRING } ), $JAVA_TYPE, qq{$JAVA8SRC_PKG_STRING package is type $JAVA_TYPE});
is( packageType({'packagetype' => $PYTHON2_PKG_STRING } ), $PYTHON_TYPE, qq{$PYTHON2_PKG_STRING package is type $PYTHON_TYPE});
is( packageType({'packagetype' => $PYTHON3_PKG_STRING } ), $PYTHON_TYPE, qq{$PYTHON3_PKG_STRING package is type $PYTHON_TYPE});
is( packageType({'packagetype' => q{burgertime} } ), undef, q{burgertime package is type undef});

%bog = (
    'platform'      => 'rhel-6.4-64',
    'packagedependencylist' => 'package-a-1 package-b-2 anotherpackage',

);
my $depfile=qq{$resultsfolder/pkg-os-dependencies.conf};
addUserDepends(\%bog, $depfile);
ok(-r $depfile, 'created dependency file');
my $ans = `cat $depfile`;
chomp $ans;
is($ans, q{dependencies-rhel-6.4-64=package-a-1 package-b-2 anotherpackage}, 'dependency contents ok');

rmtree($testfolder);
rmtree($resultsfolder);
rmtree(q{input});
rmtree(q{noarch});
unlink $tooltar;
unlink q{testframe.tar};
unlink q{testtool.tar};
unlink q{testparser.tar};

if ($useTestServer) { 
    stop_server($childA); 
    stop_server($childB); 
}

done_testing();
