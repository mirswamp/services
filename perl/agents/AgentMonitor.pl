#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#** @file AgentMonitor
# @brief AgentMonitor is the Server that provides virtual machine ID information to CSA Agents, as well as
#  forwards logging and results information to the Java collectors. It also provides launchPad services
#
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
#*

#** @class main
# @brief This application is the XMLRPC server that maintains SWAMP status for all jobs running.
#*

use 5.014;
use utf8;
use warnings;
use strict;
use FindBin qw($Bin);
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );

use Carp qw(croak carp);
use ConfigReader::Simple;
use Cwd qw(getcwd);
use English '-no_match_vars';
use Fcntl qw(:flock);
use File::Spec qw(devnull catfile);
use File::Basename qw(basename);
use Getopt::Long qw/GetOptions/;
use Log::Log4perl;
use Log::Log4perl::Level;
use POSIX qw(:sys_wait_h WNOHANG);    # for nonblocking read
use POSIX qw(setsid waitpid);
use Pod::Usage qw/pod2usage/;
use RPC::XML::Server;
use RPC::XML;
use URI::Escape qw(uri_escape);

use SWAMP::HTCondorDefines;
use SWAMP::Client::LogCollectorClient qw(logLog configureClient); 
use SWAMP::Client::LaunchPadClient qw(launchPadStart configureClient); 
use SWAMP::Client::ExecuteRecordCollectorClient qw(configureClient updateRunStatus );
#use SWAMP::Client::ViewerMonitorClient qw(configureClient viewerMonitorSetup viewerMonitorTeardown);
use SWAMP::Client::GatorClient qw(configureClient storeviewer updateviewerinstance);
use SWAMP::Locking qw(swamplock swampunlock);
use SWAMP::RPCUtils qw(rpccall okReturn);

# There's is a tag (:common) in AgentMonitorCommon, but perlcritic doesn't quite grok tags, so explicitly
# list methods used .
use SWAMP::AgentMonitorCommon qw(
  cleanupDomain
  clearViewerCount
  deleteVMID
  eventLog
  getClusterHypervisor
  getClusterID
  getClusterStatus
  getCurrentStatus
  getDomainID
  getDomainMap
  getDomainState
  getExecrunIDs
  getExecuteID
  getHypervisorList
  getVMIDfromDomain
  getViewerAddress
  getViewerByDomain
  getViewerCount
  getViewerapikey
  getViewerURLuuid
  getViewerUUID
  getViewerState
  grabLaunchToken
  incViewerCount
  isClusterID
  isValidVMID
  jobFinished
  jobLaunched
  numberJobsLaunched
  releaseLaunchToken
  removeClusterID
  initAppState
  restoreAppState
  restoreHypervisorState
  saveAppState
  setClusterHypervisor
  setClusterInfo
  setDomainState
  saveViewerState
  setHypervisorViability
  setVMID
  );

use SWAMP::SWAMPUtils qw(
  diewithconfess
  getHostname
  getJobDir
  getLoggingConfigString
  getMethodName
  getSwampConfig
  getSWAMPDir
  getBuildNumber
  getUUID
  systemcall
  safecsvstring
  start_process
  stop_process
  uname
  );

our $VERSION = '1.00';

## no critic (ProhibitCallsToUndeclaredSubs)
# Check for an instance of ourself
open my $self, '<', $PROGRAM_NAME or croak "Couldn't open self: $OS_ERROR";
flock $self, ( LOCK_EX | LOCK_NB ) or exit 0;
## use critic

my $serverhost;
my $port;
my $debug = 0;

#** @var $asdaemon If true, daemonize ourselves at launchtime, else run in the foreground.
my $asdaemon = 0;

my $configfile;

my $help       = 0;
my $doinit     = 0;
my $man        = 0;
my $startupdir = getcwd;
my $testharness = 0;

#** @var %children this is a map of execrunid's indexed by process ID. if defined, the process ID is the associated csa_agent.
my %children;

local $SIG{'CHLD'} = sub {

    # don't change $! and $? outside handler
    local $OS_ERROR    = $OS_ERROR;
    local $CHILD_ERROR = $CHILD_ERROR;
    my $pid = 1;
    while ( $pid > 0 ) {
        $pid = waitpid( -1, WNOHANG );
    }
    return if $pid == -1;
    if ( !defined( $children{$pid} ) ) {
        return;
    }
    delete $children{$pid};
    cleanup_child( $pid, $CHILD_ERROR );
};

GetOptions(
    'host=s'   => \$serverhost,
    'port=i'   => \$port,
    'init'     => \$doinit,
    'config=s' => \$configfile,
    'debug'    => \$debug,
    'daemon'   => \$asdaemon,
    'testharness' => \$testharness,
    'help|?'   => \$help,
    'man'      => \$man,
) or pod2usage(2);

if ($help) { pod2usage(1); }
if ($man) { pod2usage( '-verbose' => 2 ); }

my $uname = uname();

if ($asdaemon) {
    chdir(q{/});
    open( STDIN, '<', File::Spec->devnull )
      || croak "can't read /dev/null: $OS_ERROR";
    open( STDOUT, '>', File::Spec->devnull )
      || croak "can't write to /dev/null: $OS_ERROR";
    defined( my $pid = fork() ) || croak "can't fork: $OS_ERROR";
    exit if $pid;    # non-zero now means I am the parent
    ( setsid() != -1 ) || croak "Can't start a new session: $OS_ERROR";
    open( STDERR, ">&STDOUT" ) || carp "Can't open STDERR $OS_ERROR";
#    if ( open( my $pidfile, '>', '/tmp/swamp.pid' ) ) {
#        print $pidfile "$PID\n";
#        if ( !close $pidfile ) {
#            carp "Cannot close $pidfile $OS_ERROR";
#        }
#    }
#    else {
#        carp "Cannot open $pidfile $OS_ERROR";
#    }
}
chdir($startupdir);
Log::Log4perl->init( getLoggingConfigString() );
if ($asdaemon) {
    # Turn off logging to Screen appender
    Log::Log4perl->get_logger(q{})->remove_appender('Screen');
}
$SWAMP::AgentMonitorCommon::TEST_MODE = $testharness;

my $log = Log::Log4perl->get_logger(q{});
$log->level( $debug ? $TRACE : $INFO );

# Catch anyone who calls die.
local $SIG{'__DIE__'} = \&diewithconfess;

my $config;

$config = getSwampConfig($configfile);

if ( !defined($port) ) {
    $port = $config->get('agentMonitorJobPort');
	$port = int($port) ;
}
if ( !defined($serverhost) ) {
    $serverhost = $config->get('agentMonitorHost');
}

$log->debug( "Current directory is " . getcwd );
$log->debug("Running on $uname");
my $daemon = RPC::XML::Server->new( 'host' => $serverhost, 'port' => $port );

{
    my $logport = $config->get('dispatcherPort');
    my $loghost = $config->get('dispatcherHost');
    SWAMP::Client::LogCollectorClient::configureClient( $loghost, $logport );
    # Added so that updateRunStatus can be called
    SWAMP::Client::ExecuteRecordCollectorClient::configureClient( $loghost, $logport);
    # Added so that launchPadStart can be called for VRuns
    my $launchPadPort = int($config->get('agentMonitorPort'));
    my $launchPadHost = $config->get('agentMonitorHost');
    SWAMP::Client::LaunchPadClient::configureClient( $launchPadHost, $launchPadPort);
#    my $viewerPort = int($config->get('viewerMonitorPort'));
#    my $viewerHost = $config->get('viewerMonitorHost');
#    SWAMP::Client::ViewerMonitorClient::configureClient( $viewerHost, $viewerPort);
    my $qmPort = int( $config->get('quartermasterPort') );
    my $qmHost = $config->get('quartermasterHost');
    SWAMP::Client::GatorClient::configureClient( $qmHost, $qmPort);
}


# Add methods to our server
my @sig = ( 'struct', 'struct string' );
$daemon->add_method(
    {
        'name'      => getMethodName('AGENT_MONITOR_QUERYVMID'),
        'signature' => \@sig,
        'code'      => \&_queryVmID
    }
);
@sig = ('struct');
$daemon->add_method(
    {
        'name'      => getMethodName('AGENT_MONITOR_LISTVMID'),
        'signature' => \@sig,
        'code'      => \&_listVmID
    }
);
@sig = ( 'struct', 'struct string string string' );
$daemon->add_method(
    {
        'name'      => getMethodName('AGENT_MONITOR_ADDVMID'),
        'signature' => \@sig,
        'code'      => \&_addVmID
    }
);
@sig = ( 'int', 'int string' );
$daemon->add_method(
    {
        'name'      => getMethodName('AGENT_MONITOR_REMOVEVMID'),
        'signature' => \@sig,
        'code'      => \&_removeVmID
    }
);
@sig = ('string');
$daemon->add_method(
    {
        'name'      => getMethodName('AGENT_MONITOR_CREATEVMID'),
        'signature' => \@sig,
        'code'      => \&_createVmID
    }
);

@sig = ( 'int', 'int struct' );
$daemon->add_method(
    {
        'name'      => getMethodName('AGENT_MONITOR_LOGSTATE'),
        'signature' => \@sig,
        'code'      => \&_agentLogState
    }
);
#@sig = ( 'string', 'string string' );
#$daemon->add_method(
#    {
#        'name'      => getMethodName('AGENT_MONITOR_DOMAINSTATE'),
#        'signature' => \@sig,
#        'code'      => \&_getDomainState
#    }
#);
#@sig = ( 'int', 'int string' );
#$daemon->add_method(
#    {
#        'name'      => getMethodName('AGENT_MONITOR_JOBCOUNTBYIP'),
#        'signature' => \@sig,
#        'code'      => \&_getJobCountByIP
#    }
#);

@sig = ( 'int', 'int struct' );
$daemon->add_method(
    {
        'name'      => getMethodName('AGENT_MONITOR_LOGLOG'),
        'signature' => \@sig,
        'code'      => \&_logLog
    }
);

@sig = ( 'struct', 'struct struct' );
$daemon->add_method(
    {
        'name'      => getMethodName('CSAAGENT_STOP'),
        'signature' => \@sig,
        'code'      => \&_csaAgentStop
    }
);
@sig = ( 'struct', 'struct struct' );
$daemon->add_method(
    {
        'name'      => getMethodName('CSAAGENT_FINISHED'),
        'signature' => \@sig,
        'code'      => \&_csaAgentFinished
    }
);
@sig = ( 'struct', 'struct struct' );
$daemon->add_method(
    {
        'name'      => getMethodName('AGENT_MONITOR_LISTJOBS'),
        'signature' => \@sig,
        'code'      => \&_listJobs
    }
);

@sig = ( 'struct', 'struct string struct' );
$daemon->add_method(
    {
        'name'      => getMethodName('AGENT_MONITOR_JOBSTATUS'),
        'signature' => \@sig,
        'code'      => \&_clusterJobStatus
    }
);

@sig = ('struct', 'struct string');
$daemon->add_method(
    {
        'name'      => getMethodName('CSAAGENT_GETMACHINELIST'),
        'signature' => \@sig,
        'code'      => \&_getSuitableMachines 
    }
);
@sig = ( 'int', 'int string' );
$daemon->add_method(
    {
        'name'      => getMethodName('CSAAGENT_OKTOLAUNCH'),
        'signature' => \@sig,
        'code'      => \&_okToLaunch
    }
);
@sig = ( 'string', 'string string' );
$daemon->add_method(
    {
        'name'      => 'agentMonitor.setLogLevel',
        'signature' => \@sig,
        'code'      => \&_setLogLevel
    }
);
@sig = ( 'struct' );
$daemon->add_method(
    {
        'name'      => 'agentMonitor.status',
        'signature' => \@sig,
        'code'      => \&_generateStatus
    }
);
@sig = ( 'base64' );
$daemon->add_method(
    {
        'name'      => 'agentMonitor.fetchHistoryFile',
        'signature' => \@sig,
        'code'      => \&_fetchHistoryFile
    }
);
@sig = ( 'base64', 'base64 string' );
$daemon->add_method(
    {
        'name'      => 'agentMonitor.fetchRawResults',
        'signature' => \@sig,
        'code'      => \&_fetchRawResults
    }
);
@sig = ( 'struct', 'struct string string' );
$daemon->add_method(
    {
        'name'      => 'agentMonitor.updateAssessmentStatus',
        'signature' => \@sig,
        'code'      => \&_updateAssessmentStatus
    }
);

@sig = ( 'struct', 'struct string string' );
$daemon->add_method(
    {
        'name'      => 'agentMonitor.resultsProcessed',
        'signature' => \@sig,
        'code'      => \&_resultsProcessed
    }
);
@sig = ( 'string');
$daemon->add_method(
    {
        'name'      => 'server.version',
        'signature' => \@sig,
        'code'      => sub { 
            return "$VERSION.".getBuildNumber();
        }
    }
);
@sig = ( 'int', 'int string string string string' );
$daemon->add_method(
    {
        'name'      => 'agentMonitor.execNodePing',
        'signature' => \@sig,
        'code'      => \&_execNodePing
    }
);
@sig = ( 'struct', 'struct string string' );
$daemon->add_method(
    {
        'name'      => 'agentMonitor.isViewerAvailable',
        'signature' => \@sig,
        'code'      => \&_isViewerAvailable
    }
);
@sig = ( 'int', 'int struct ' );
$daemon->add_method(
    {
        'name'      => 'agentMonitor.setViewerState',
        'signature' => \@sig,
        'code'      => \&_setViewerState
    }
);
@sig = ( 'int', 'int struct ' );
$daemon->add_method(
    {
        'name'      => 'agentMonitor.launchViewer',
        'signature' => \@sig,
        'code'      => \&_launchViewer
    }
);
@sig = ( 'int', 'int struct ' );
$daemon->add_method(
    {
        'name'      => 'agentMonitor.abortViewer',
        'signature' => \@sig,
        'code'      => \&_abortViewer
    }
);
@sig = ( 'int', 'int struct ' );
$daemon->add_method(
    {
        'name'      => 'agentMonitor.storeviewer',
        'signature' => \@sig,
        'code'      => \&_storeviewer
    }
);

restoreHypervisorState();

if ($doinit) {
    initAppState();
}
else {
    restoreAppState();
    # Launch the HTCondor agent when we restore state, in case
    # jobs need processing.
    start_process( $config->get('csaHTCondorAgent') );
}
# Here we go!
# Pass in a list of signals to gracefully exit on.
my @signals = qw/TERM HUP INT/;
my %map = ( 'signal' => \@signals );
my $pv = sprintf "%vd", $PERL_VERSION;
my $ver = "$VERSION.".getBuildNumber();
$log->info(
    "$PROGRAM_NAME: v$ver under Perl $pv entering listen loop at $serverhost on port: $port");
my $res = $daemon->server_loop(%map);
for my $child (keys %children) {
    $log->debug("Stopping child process $child");
    my $pid = waitpid( $child, WNOHANG );
    if ($pid != -1) {
        stop_process($child);
    }
}
# This is our chance to cleanup
$log->debug("Good bye");
exit 0;

#** @function logtag( )
# @brief Get this application's tag for calls to syslog
#
# @return the text tag to use in calls to syslog
# @see #logfilename
#*
sub logtag {
    ( my $name = $PROGRAM_NAME ) =~ s/\.pl//sxm;
    return basename($name);
}
#** @function logfilename( )
# @brief Get this application's logfile name.
#
# @return the abs_path to this application's log file.
# @see #logtag
#*
sub logfilename {
    (my $name = $PROGRAM_NAME ) =~ s/\.pl//sxm;
    if ($uname eq "Linux") {
        $name=basename($name);
        return getSWAMPDir()."/log/${name}.log";
    }
    return "${name}.log";
}


#################
# XML RPC methods

#** @function _generateStatus( $server )
# @brief Get this AgentMonitor's current status including number of jobs and hypervisors in use.
# This method should not be called directly, but should be invoked through
# the client interface SWAMP::Client::AgentClient::status()
# Implements `agentMonitor.status`
#
# @param server Reference to this XMLRPC server
# @return Hash reference to the current status of this AgentMonitor
# @see SWAMP::Client::AgentClient::status()
#*
sub _generateStatus {
    my $server = shift;
    my %status;
    $status{'pid'} = $PID;
    getCurrentStatus(\%status);

    return \%status;
}
#** @function _setLogLevel( $server, $level)
# @brief Set this application's log level
# This method should not be called directly, but should be invoked through
# the client interface setLoggingLevel
# Implements  `agentMonitor.setLogLevel`
#
# @param server Reference to this XMLRPC server
# @param level The desired logging level
# @return The current logging level
# @see {@link SWAMP::Client::AgentClient::setLoggingLevel}
#
#*
sub _setLogLevel {
    my $server = shift;
    my $level = shift;
    my $current;
    if (defined($log)) {
## no critic (ProhibitCallsToUnexportedSubs)
        $current = Log::Log4perl::Level::to_level($log->level());
        $log->debug("_setLogLevel was $current is: $level");
        $log->level(Log::Log4perl::Level::to_priority($level));   
## use critic
    }
    return $current;
}
#** @function _logLog( $server, \%hashref )
# @brief Make a call to the LogCollector::logLog method
# Implements `AGENT_MONITOR_LOGLOG`
#
# @param server Reference to this XMLRPC server
# @param Reference to a hash map containing the log file and run id to send.
# @return The result of the call on success or undef on failure.
# @see {@link SWAMP::Client::LogCollectorClient::logLog}
#*
sub _logLog {
    my $server   = shift;
    my $hashref  = shift;
    my $vmid     = ${$hashref}{'execrunid'};
    my $pathname = ${$hashref}{'pathname'};
    my $checksum = ${$hashref}{'sha512sum'};

    # Look up the execute run bound to this VM
    if ( isValidVMID($vmid) ) {

        # Make call to actual collector
        my $result = logLog( getExecuteID($vmid), $pathname, $checksum );
        return $result;
    }
    else {
        $log->warn("logLog cannot find a vmid $vmid");
    }
    return;
}
#** @function _getJobCountByIP( \%server, $ipaddr)
# @brief Return the number of jobs running on `$ipaddr`
#
# @param server Reference to this XMLRPC server
# @param ipaddr The ip address of the host being sought
# @return number of jobs running on a given host.
# @see 
#*
#sub _getJobCountByIP {
#    my $server = shift;
#    my $ipaddr = shift;
#    my $njobs = numberJobs($ipaddr);
#    $log->debug("_getJobCountByIP($ipaddr) = $njobs");
#    return $njobs;
#
#}
#sub _getDomainState {
#    my $server = shift;
#    my $vmid = shift;
#    my $state = getDomainState($vmid);
#    $log->debug("_getDomainState($vmid) = $state");
#    return $state;
#
#}
#        'name'      => getMethodName('AGENT_MONITOR_LOGSTATE'),


#** @function _agentLogState( )
# @brief 
#
# @param 
# @return 
# @see 
#*
sub _agentLogState {
    my $server    = shift;
    my $hashref   = shift;
    my $timestamp = ${$hashref}{'timestamp'};
    my $domain    = ${$hashref}{'execrunid'};
    my $state     = ${$hashref}{'state'};
    my $reason    = ${$hashref}{'reason'};

    $log->info("_agentLogState($timestamp, $domain, $state, $reason)");
    # If a VRunVM becomes undefined, we might need to clean up after it.
    if ($domain =~ /^vswamp/sxm && $state eq 'undefined') {
        my ($project, $viewer, $currstate) = getViewerByDomain($domain);
        if ($project && $viewer && $currstate && $currstate ne 'stopped') {
                my %current;
                $current{'project'} = $project;
                $current{'viewer'} = $viewer;
                $current{'domain'} = $domain;
                $current{'urluuid'}  = getViewerURLuuid($viewer,$project);
                $current{'vieweruuid'}  = getViewerUUID($viewer,$project);
                $current{'state'} = q{shutdown};
                _setViewerState(q{server}, \%current);
                $log->info("_agentLogState informed viewer of shutdown: $domain");
        }
    }
    # When a SWAMP assessment VM shutsdown, cleanup
    if ($domain =~/^swamp/sxm && $state eq 'shutdown') {
        my $cfg = getSwampConfig($configfile);
        my $floodlight;
        if ($cfg) {
            $floodlight = $cfg->get('floodlight');
        }
        cleanupDomain($domain, $floodlight);
    }

    my $vmid = getVMIDfromDomain($domain);

    # Look up the assessment run bound to this VM
    if ( isValidVMID($vmid) ) {
        setDomainState($vmid, $state);
        return {};
    }
    else {
        $log->warn("_agentLogState cannot find a vmid for $domain");
    }
    return { 'error', 'vmid no longer valid' } ;
}

#** @function _createVmID( \%server )
# @brief Return a unique ID 
# Implements `AGENT_MONITOR_CREATEVMID`
# @param server A reference to this XMLRPC server
# @return a unique opaque ID
# @see #_removeVmID
#*
sub _createVmID {
    return getUUID();
}

#        'name'      => getMethodName('AGENT_MONITOR_REMOVEVMID'),

sub _removeVmID {
    my $server = shift;
    my $vmid   = shift;
    my $ret    = 0;
    if ( deleteVMID($vmid) ) {
        saveAppState();
        $ret = 1;
    }
    return $ret;
}

#        'name'      => getMethodName('AGENT_MONITOR_LISTVMID'),
sub _listVmID {
    return getDomainMap();    #\%domainMap;
}

#        'name'      => getMethodName('AGENT_MONITOR_ADDVMID'),
sub _addVmID {
    my $server = shift;

    my $vmid      = shift;
    my $execrunid = shift;
    my $domain    = shift;
    if ( setVMID( $vmid, $execrunid, $domain ) ) {
        saveAppState();
        $log->debug("addVmID($execrunid, $vmid, $domain)");
        return { 'return' => '1' };
    }
    else {
        return { 'error' => "Failed to add $vmid, it exists" };
    }
}

#       'name'      => getMethodName('AGENT_MONITOR_QUERYVMID'),
sub _queryVmID {
    my $server = shift;
    my $vmid   = shift;
    $log->debug("queryVmID($vmid)");
    if ( isValidVMID($vmid) ) {
        return { 'domain', getDomainID($vmid) };
    }
    return { 'error', "no such id $vmid" };
}


#        'name'      => getMethodName('AGENT_MONITOR_LISTJOBS'),
sub _listJobs {
    my $server = shift;
    my %newAgentmap;
    my $nActive = 0;
    foreach my $id ( getExecrunIDs() ) {
        $newAgentmap{$id}->{'id'}         = getClusterID($id);
        $newAgentmap{$id}->{'status'}     = getClusterStatus($id);
        $newAgentmap{$id}->{'hypervisor'} = getClusterHypervisor($id);
        $nActive++;
    }
    $log->debug("launchpadListJobs #active : $nActive");
    return \%newAgentmap;
}

#        'name'      => 'agentMonitor.updateAssessmentStatus',
sub _updateAssessmentStatus {
    my $server = shift;
    my $execrunid = shift;
    my $status = shift;
    eventLog($execrunid, 'assessmentStatus', $status);
    return {};
}
#        'name'      => 'agentMonitor.resultsProcessed',
sub _resultsProcessed {
    my $server = shift;
    my $execrunid = shift;
    my $status = shift;
    eventLog($execrunid, 'resultsprocessed', $status);
    return {};
}
#        'name'      => 'agentMonitor.fetchHistoryFile',
sub _fetchHistoryFile {
    my $server = shift;
    if (open(my $fh, '<' , File::Spec->catfile("$FindBin::Bin/../run", '.agentevents'))) {
        binmode $fh;
        local ($INPUT_RECORD_SEPARATOR)=undef; #SLURP mode
        my $bits=<$fh>;
        if (!close($fh)) {
            $log->warn("Error closing histfile $OS_ERROR");
        }
## no critic (RequireExplicitInclusion)
        return RPC::XML::base64->new($bits,0);
## use critic
    }
    return;
}
#        'name'      => 'agentMonitor.fetchRawResults',
sub _fetchRawResults {
    my $server = shift;
    my $execrunid = shift;
    my $dir = getJobDir($execrunid);
    if (open(my $fh, '<' , File::Spec->catfile($dir, 'out.tgz'))) {
## no critic (RequireExplicitInclusion)
        return RPC::XML::base64->new($fh);  
## use critic
    }
    return;
}
#** @method _clusterJobStatus($server, $timestamp, \%map )
# @brief This method updates the internal state of all HTCondor jobs
# Implements `AGENT_MONITOR_JOBSTATUS`
#
# @param server this RPCXML server object
# @param timestamp the time the status was gathered.
# @param map reference to a hash of execrunid => HTCondor job event state
# @return empty hash
#*
sub _clusterJobStatus {
    my $server    = shift;
    my $timestamp = shift;
    my $map       = shift;
    my $nChanged = 0;
    foreach my $execrunid ( keys %{$map} ) {
        if ( isClusterID($execrunid) ) {
            my $status = $map->{$execrunid}->{'status'};
            if ( getClusterStatus($execrunid) != $status ) {
                $log->debug( "clusterJobStatus "
                      . getClusterID($execrunid)
                      . " status was:"
                      . getClusterStatus($execrunid)
                      . " is now $status" );
                $log->debug("clusterJobStatus $execrunid : $status ");
                setClusterInfo( $execrunid, getClusterID($execrunid), $status );
                $nChanged++;
            }
            if ( $status == SWAMP::HTCondorDefines->Execute ) {
                # Look like an IP address?
                if ($map->{$execrunid}->{'extra'} =~ /\./sxm) {
                    setClusterHypervisor( $execrunid,
                        $map->{$execrunid}->{'extra'} );
                    $nChanged++;
                }
                else {
                    $log->debug("clusterJobStatus Execute state, but no hypervisor");
                }
            }
            if (   $status == SWAMP::HTCondorDefines->Job_terminated
                || $status eq SWAMP::HTCondorDefines->Job_aborted
                || $status eq SWAMP::HTCondorDefines->Job_held )
            {
                if ($status eq SWAMP::HTCondorDefines->Job_held ) {
                    updateRunStatus($execrunid, 'HTCondor job held');
                    eventLog($execrunid, 'assessmentStatus', 'HTCondor job held');
                }
                $nChanged += removeClusterID($execrunid);
            }
        }
        else {
            $log->warn("clusterJobStatus no such $execrunid");
        }
    }
    if ( $nChanged > 0 ) {
        $log->debug("clusterJobStatus $nChanged jobs changed, saving");
        saveAppState();
    }
    return {};
}
#        'name'      => getMethodName('CSAAGENT_FINISHED'),
sub _csaAgentFinished {
    my $server    = shift;
    my $ref       = shift;
    my $execrunid = $ref->{'execrunid'};
    my $clusterid = $ref->{'clusterid'};
    $log->debug("csaAgentFinished($execrunid) = $clusterid");

    jobLaunched();

    # Check to see if the total jobs running is less than minimum of { jobs per node over all nodes }
    # If so, go ahead and let some more launch
    if ( numberJobsLaunched() < 6 ) {
        releaseLaunchToken($execrunid);
    }

    setClusterInfo( $execrunid, $clusterid, 0 );
    saveAppState();

    # if we haven't done so yet, we need to fork the csa_HTCondorAgent now
    start_process( $config->get('csaHTCondorAgent') );

    return {};
}

#        'name'      => getMethodName('CSAAGENT_GETMACHINELIST'),
sub _getSuitableMachines {
    my $server = shift;
    my $mode = shift;
    $log->debug("_getSuitableMachines from $server->{'peerhost'}:$server->{'peerport'} $server->{'request'}");
    my @machineList = getHypervisorList();
    $log->debug("Number hypervisors ".($#machineList+1));
    my %results;
    foreach my $machine (@machineList) {
        my $host = getHostname($machine);
        $results{$host}  = 1;
    }

    return \%results;
}
# This is just a wrapper to call the storeviewer in the quartermaster (aka GatorClient)
sub _storeviewer {
    my $server = shift;
    my $opts = shift;
    $log->info("storeviewer " . safecsvstring($opts->{'viewerdbpath'}, $opts->{'vieweruuid'}));
    storeviewer($opts);
    return 1;
}
sub _setViewerState {
    my $server = shift;
    my $ref = shift; # Reference to map of options
    $log->info("setViewerState:" . safecsvstring($ref->{'viewer'}, $ref->{'project'}, $ref->{'domain'},
        $ref->{'state'}, $ref->{'ipaddress'}, $ref->{'apikey'}, $ref->{'urluuid'}));
    my $prevState = saveViewerState($ref);
    if (defined($ref->{'state'})) {
        if ($ref->{'state'} eq 'shutdown' && $prevState ne 'shutdown') {
            clearViewerCount($ref->{'project'}, $ref->{'viewer'});
            updateviewerinstance({'vieweruuid' => $ref->{'vieweruuid'}, 
                'viewerstatus' => q{Viewer has shutdown},
                'vieweraddress' => q{},
                'viewerproxyurl' => q{} });
        }
        else {
            $log->warn("_setViewerState: $ref->{'state'} <$prevState>");
        }
    }
    else {
        $log->warn("_setViewerState: not defined");
    }
    return 1;
}
sub _abortViewer {
    my $server = shift;
    my $options = shift;
    $log->info("_abortViewer " . safecsvstring($options->{'viewer'}, $options->{'project'}));
    # This will UNDEFINE all of the values associated with this viewer
    saveViewerState($options);
    clearViewerCount($options->{'project'}, $options->{'viewer'});
    return 1;
}
sub _getThreadFixVM {
	return 'universal-rhel-6.7-64-viewer';
}
sub _getCodeDXVM {
    my $default = 'codedx1.0.5-rhel-6.5-64-viewer';
    my $cfg = getSwampConfig($configfile);
    if ($cfg) {
        my $current= $cfg->get('master.codedx') // $default;
        my $prev= $cfg->get('previous.codedx') // $default;
        return ($current, $prev);
    }
    return ($default, $default);
}
sub _launchViewer {
    my $server = shift;
    my $options = shift;
    my $key = "$options->{'project'}.$options->{'viewer'}";
    $key =~s/\s//sxmg;
    # If this is the first user of this viewer.project pair
    if (getViewerCount($options->{'project'}, $options->{'viewer'}) == 0) {
        incViewerCount($options->{'project'}, $options->{'viewer'});
        # EVERYTHING needs an execrunid.
        $options->{'execrunid'} = "vrun.$key";
        $options->{'intent'} = 'VRUN'; # New field.
        $options->{'apikey'} = getUUID();
        # This is now the URL for the VM instead of project.
        # It needs to persist for THIS VM, but be unique next time.
        $options->{'urluuid'} = qq{proxy-}.uri_escape(getUUID()); 
		$options->{'platform'} = _getThreadFixVM();
		if ($options->{'viewer'} eq 'CodeDX') {
        	($options->{'platform'}, $options->{'pred_platform'}) = _getCodeDXVM();
		}
        $log->info("_launchViewer: invoking launchPadStart for [$key] $options->{'apikey'}");
        return okReturn(launchPadStart($options));
    }
    else {
        # TODO: Note that we had a pending lauch. If the VM is shutting down right now,
        # ViewerCount will be non-zero and we will think we don't need to launch. but when the VM 
        # shuts down, we need to see if we told anyone we were pending and RE-launch.
        $log->info("_launchViewer: pending launchPadStart for [$key] $options->{'apikey'}");
        return 1; # pending
    }
}
sub _isViewerAvailable {
    my $server = shift;
    my $viewer = shift;
    my $project = shift;
    my $ret = getViewerState($viewer, $project);
    $log->info("_isViewerAvailable $viewer $project says $ret");
    my %res ;
    # Map boolean to 0/1
    $res{ 'ready' }=  (0+($ret eq q{ready}));
    $res{ 'address' }  = getViewerAddress($viewer,$project);
    $res{ 'apikey' }  = getViewerapikey($viewer,$project);
    $res{ 'urluuid' }  = getViewerURLuuid($viewer,$project);
    return \%res;
}

sub _execNodePing {
    my $server = shift;
    my $execIP = shift;
    my $viability = shift;
    my $ncpu = shift;
    my $nGB = shift;
    $log->debug("_execNodePing $execIP $viability, $ncpu, $nGB");
    setHypervisorViability($execIP, $viability, $ncpu, $nGB);
    return 1;
}
#        'name'      => getMethodName('CSAAGENT_OKTOLAUNCH'),
sub _okToLaunch {
    my $server    = shift;
    my $execrunid = shift;
    return grabLaunchToken($execrunid);
}

# Tell a CSA Agent server to stop
sub _csaAgentStop {

    my $server = shift;
    my $ref    = shift;
    # If there is an execrunid, do this
    if ( defined( ${$ref}{'execrunid'} ) ) {
        my $execrunid = ${$ref}{'execrunid'};
        $log->info("csaAgentStop($execrunid)");
        if ( isClusterID($execrunid) ) {
            my $condorID = getClusterID($execrunid);
            if ( defined($condorID) ) {
                $log->info("csaAgentStop($execrunid) is at cluster id $condorID");
                my ($output, $status) = systemcall("condor_rm $condorID");
                if ($status) {
                    $log->warn("Failed to remove condor job: $output.");
                }
                else {
                    updateRunStatus($execrunid, 'terminated');
                    eventLog($execrunid, 'assessmentStatus', 'terminated');
                }
            }
            else {
                $log->warn("Cannot find a cluster ID associated with $execrunid");
            }

            return {};
        }
        else {
                $log->warn("ID $execrunid is not a valid cluster ID ");
            return { 'error', q{no such id $execrunid} };
        }
    }
    if ( defined( ${$ref}{'vrunid'} ) ) {
        # it's a viewer, kill it differently
    }
    return {};
}

sub cleanup_child {
    my $pid   = shift;
    my $state = shift;
    $log->debug("Child $pid has $state");
    return;
}
__END__
=pod

=encoding utf8

=head1 NAME

AgentMonitor 

=head1 SYNOPSIS

AgentMonitor [--port #] [--host host] [--help] [--man]

=head1 DESCRIPTION


=head1 OPTIONS

=over 8

=item --man

Show manual page

=back

=over 8

=item --help

Show this help message

=back

=over 8

=item --port

Specify port number this server will listen on.

=back

=over 8

=item --host

Specify host this server will bind to.

=back

=head1 METHODS IMPLEMENTED BY THIS SERVER

=over 8

=item swamp.agentMonitor.createVmID

=item swamp.agentMonitor.removeVmID

=item swamp.agentMonitor.listVmID

=item swamp.agentMonitor.queryVmID

=item swamp.agentMonitor.addVmID

=item swamp.agentMonitor.logStatus

=item swamp.agentMonitor.logState

=item swamp.agentMonitor.logLog

=item swamp.agentMonitor.saveResult

=item swamp.agentMonitor.updateResult

=item swamp.agentMonitor.listJobs

=item swamp.agentMonitor.clusterJobStatus

=item swamp.agentMonitor.clusterJobLog

=item swamp.agentMonitor.getDomainState

=item swamp.agentMonitor.getJobCount

=item swamp.csaAgent.stop

=item swamp.csaAgent.finished

=item swamp.csaAgent.getMachineList

=item swamp.csaAgent.okToLaunch

=back

=cut
