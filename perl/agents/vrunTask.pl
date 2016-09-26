#!/opt/perl5/perls/perl-5.18.1/bin/perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#** @file vrunTask.pl
#
# @brief ViewRun task. Similar to assessmentTask, but for launching viewer runs.
# This code runs on a hypervisor.
# @verbatim
# When started via condor, the command line will contain the inputs
# This script needs access to libvirt, so it should be sudo'd.
# Create the input folder for the VM image.
# Create the 'run.sh' from the BOG specifications with commands to manipulate mysql.
# Communicate with the AgentMonitor.
# Start the VM.
# @end verbatim
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 01/02/2014 09:23:48
#*

use 5.014;
use utf8;
use warnings;
use strict;
use FindBin qw($Bin);
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );
use sigtrap 'handler', \&taskShutdown, 'normal-signals';

use Carp qw(carp croak);
use ConfigReader::Simple;
use Cwd qw(getcwd abs_path);
use File::Basename qw(basename dirname);
use English '-no_match_vars';
use File::Copy qw(move cp);
use File::Path qw(make_path remove_tree);
use File::Spec qw(catfile);
use Getopt::Long qw/GetOptions/;
use Log::Log4perl::Level;
use Log::Log4perl;
use Pod::Usage qw/pod2usage/;
use Storable qw(lock_retrieve);

our $VERSION = '1.00';

use SWAMP::Client::AgentClient qw(configureClient removeVmID addVmID createVmID setViewerState storeviewer);
use SWAMP::VRunTools qw(createrunscript copyvruninputs parseRunOut);
use SWAMP::SWAMPUtils qw(
  diewithconfess
  checksumFile
  createDomainPIDFile
  getBuildNumber
  getDomainStateFilename
  getLoggingConfigString
  getSWAMPDir
  getSwampConfig
  loadProperties
  removeDomainPIDFile
  systemcall
  condor_chirp
  trim
);

my $help       = 0;
my $man        = 0;
my $debug      = 0;               #** @var $debug If true, increase log level to DEBUG
my $basedir    = getSWAMPDir();
my $startupdir = getcwd;

#** @var $agentHost The hostname on which agentMonitor is listening
my $agentHost;

#** @var $agentPort The agentMonitor port
my $agentPort;

#** @var $bogfile The name of our Bill Of Goods file
my $bogfile;

#** @var $uri of our libvirt, currently using 'undef'
my $uri;

#** @var $vmname Name of the Virtual Machine this script will create.
my $vmname = "swamp${PID}";

#** @var $vmid Opaque id of the Virtual Machine this script will create.
my $vmid;

#** @var $ok Flag indicating this script should continue
my $ok = 1;

#** @var %bog The map that will contain our Bill Of Goods for this assessment run.
my %bog;

#** @var $appname Textual name for this process's logger
my $appname = "vruntask_$PID";

#** @var $log Global Log::Log4perl object
my $log;
my $outfile;

use constant {
    'MAX_RESTARTS'  => 3,      # number of times to allow a VM to restart before giving up.
    'MAX_WAITSTUCK' => 600,    # number of seconds to wait for a VM to start running the assessment.
};

GetOptions(
    'bog=s'      => \$bogfile,
    'out=s'      => \$outfile,
    'debug'      => \$debug,
    'vmname=s'   => \$vmname,
    'ahost=s'    => \$agentHost,
    'aport=s'    => \$agentPort,
    'libvirturi' => \$uri,
    'help|?'     => \$help,
    'man'        => \$man,
) or pod2usage(2);

if ($help)                { pod2usage(1); }
if ($man)                 { pod2usage( '-verbose' => 2 ); }
if ( !defined($bogfile) ) { pod2usage('--bog parameter required'); }

$appname = "vruntask_$vmname";
$appname =~ s/vswamp//sxm;

Log::Log4perl->init( getLoggingConfigString() );
if ( !$debug ) {
    Log::Log4perl->get_logger(q{})->remove_appender('Screen');
}

$log = Log::Log4perl->get_logger(q{});
$log->level( $debug ? $TRACE : $INFO );

# Catch anyone who calls die.
local $SIG{'__DIE__'} = \&diewithconfess;
configureClients( $agentHost, $agentPort );

my $ver = "$VERSION." . getBuildNumber();
$log->info( "#### $appname v$ver running on " . `hostname -f` );

# 1. read the BOG file
# 2. Create the Input disk from the DB image
# 3. Create the run.sh
# 4. start the VM
# 4.5 inform agentmonitor that the VM has been launched
# 5. wait for the run.sh to indicate success/failure
# 6. report  to agentmonitor that the viewer is running

if ( !setupWorkingSpace($vmname) ) {
    $ok = 0;
    $log->error('Unable to set up working space.');

    # TODO report to the AgentMonitor that things have failed.
    exit 1;
}
if ( loadProperties( $bogfile, \%bog ) == 0 ) {
    $ok = 0;
    $log->error("Unable to load BOG $bogfile");

    # TODO report to the AgentMonitor that things have failed.
    exit 1;
}

# just for completeness, let's log the contents of the BOG
$log->info("BOG contents from file: $bogfile");
foreach my $bogkey (keys %bog) {
    $log->info("\t$bogkey = $bog{$bogkey}");
}

condor_chirp($bog{'intent'}, "NAME", "vmname", $vmname);
condor_chirp($bog{'intent'}, "ID", "execution_record_uuid", $bog{'execrunid'});
condor_chirp($bog{'intent'}, "TIME", "vrunTask_start", time());
condor_chirp($bog{'intent'}, "NAME", "urluuid", $bog{'urluuid'});
createDomainPIDFile($PID, $vmname);
my $inputfolder = 'input';
if (copyvruninputs(\%bog, $inputfolder)) {
    condor_chirp($bog{'intent'}, "TIME", "vrunTask_copyvruninputs_complete", time());
    if (createrunscript(\%bog, $inputfolder)) {
        condor_chirp($bog{'intent'}, "TIME", "vrunTask_createrunscript_complete", time());
        $vmid = createVmID();
        addVmID( $vmid, $bog{'execrunid'}, $vmname );

        #updateRunStatus( $bog{'execrunid'}, 'Starting virtual machine' );

		condor_chirp($bog{'intent'}, "TIME", "vrunTask_start_vm", time());
		condor_chirp($bog{'intent'}, "NAME", "vrunTask_start_vm_image_name", $bog{'platform'});
		Log::Log4perl->get_logger('viewer')->trace("$bog{'execrunid'} $vmname Calling start_vm");
        my ( $output, $status ) =
          systemcall(
            "PERL5LIB=$basedir/perl5 $basedir/bin/start_vm --outsize 6144 --name $vmname input $bog{'platform'}" );

		condor_chirp($bog{'intent'}, "TIME", "vrunTask_start_vm_return", time());
        if ($status) {
            $log->error("start_vm returned: $output");
            removeVmID( \$vmid );
            $log->error("Unable to startVM $status");
        }
        else {
            setDeadman();
            setStarts(0);    # Clean slate.

			condor_chirp($bog{'intent'}, "TIME", "vrunTask_watchVM_start", time());
		    Log::Log4perl->get_logger('viewer')->trace("$bog{'execrunid'} $vmname Starting watchVM");
            watchVM( \%bog );

            removeVmID( \$vmid );
			condor_chirp($bog{'intent'}, "TIME", "vrunTask_vm_cleanup", time());
		    Log::Log4perl->get_logger('viewer')->trace("$bog{'execrunid'} $vmname Calling vm_cleanup");
            ( $output, $status ) =
              systemcall("PERL5LIB=$basedir/perl5 $basedir/bin/vm_cleanup --force  $vmname 2>&1");
            if ($status) {
                $log->warn("Unable to cleanup from $vmname: $output");
            }
        }
    }
    else {
        $log->error("Error creating scripts inputs");
    }
}
else {
    $log->error("Error copying inputs");
}

removeStateFile($vmname);
# condor_chirp requires WorkingSpace
condor_chirp($bog{'intent'}, "TIME", "vrunTask_exit", time());
cleanupWorkingSpace();
removeDomainPIDFile($PID, $vmname);
exit $ok ? 0 : 1;

#** @function watchVM( )
# @brief Block until our VM shuts down or the deadman timer goes off.
#
# @return 1 if all is well, 0 if the VM is stuck.
#*
sub watchVM {
    my $bogref = shift;

    my $quitLoop   = 0;
    my $lastPoll   = 0;
    my $ret        = 0;
    my $needUpdate = 1;
	condor_chirp($bog{'intent'}, "TIME", "watchVM_start", time());
    while ( !$quitLoop ) {
		# add query to session management component on web server to ask whether or not it is OK to
		# use virsh shutdown <vmname> to cause a shutdown of the vm due to inactivity
        if ( !checkDeadman() ) {
            $quitLoop = 1;
            $log->info("Exiting loop because of deadMan");
            $ret = 0;
            last;
        }

        my $rootref      = localGetDomainStatus($vmname);
        my $currentState = $rootref->{'domainstate'};

        if ( !checkState($currentState) ) {
            $log->warn("domain state for $vmname has been UNKNOWN for too long");
        }
        if ( $currentState eq 'started' ) {

            # NB increasing the frequency of this poll will likely not
            # have the desired effect, the overhead of guestfish too great.
            #
            # If it's been more than 10 seconds and the VM is
            # running
            if ( time - $lastPoll > 10 ) {
                if ($needUpdate) {
                    $needUpdate = sendUpdate( $currentState, $rootref, $bogref );
                }
                else {
                    setDeadman(); # We have communicated, all is well.
                }
                $lastPoll = time;
            }

        }
        elsif ( $currentState eq 'shutdown' || $currentState eq 'stopped' ) {
            # Tell AgentMonitor that this viewer is shutdown.
            setViewerState(
                'domain' => $vmname, 
                'viewer'  => $bogref->{'viewer'},
                'vieweruuid' => $bogref->{'viewer_uuid'},
                'urluuid' => $bogref->{'urluuid'},
                'project' => $bogref->{'project'},
                'state'   => 'shutdown'
            );
			condor_chirp($bog{'intent'}, "TIME", "watchVM_saveViewerDatabase", time());
            saveViewerDatabase($bogref, $vmname);
            $quitLoop = 1;
            $ret      = 1;
            last;
        }
        sleep 5;
    }
	condor_chirp($bog{'intent'}, "TIME", "watchVM_return", time());
    return $ret;
}

#** @function saveViewerDatabase( \%bogref )
# @brief persist the SQL database from the VM to /swamp and then invoke storeviewer method.
#
# @param bogref reference to this run's Bill Of Goods
# @return  0 on failure, 1 on success.
#*
sub saveViewerDatabase { my ($bogref, $vmname) = @_ ;
    my $savefile = q{codedx_viewerdb.tar.gz};
	if ($bogref->{'viewer'} eq q{ThreadFix}) {
		$savefile = q{threadfix_viewerdb.tar.gz};
	}
    my $runoutfile = q{run.out};

    my ( $output, $status ) = systemcall("virt-copy-out -d $vmname -m /dev/sdc:/mnt/out /mnt/out/$savefile .");
    if ($status) {
        $log->error("Cannot extract: $savefile from: $vmname - $output");
    }
    ( $output, $status ) = systemcall("virt-copy-out -d $vmname -m /dev/sdc:/mnt/out /mnt/out/$runoutfile .");
    if ($status) {
        $log->error("Cannot extract: $runoutfile from: $vmname - $output");
    }
    if (-r $runoutfile && !cp($runoutfile, abs_path("$basedir/log/$vmname-$runoutfile"))) {
        $log->error("Cannot copy $runoutfile to $$basedir/log/$vmname-$runoutfile : $OS_ERROR");
    }

	if (! -r $savefile) {
		return 0;
	}
    my $sharedfolder = File::Spec->catfile( $bogref->{'resultsfolder'}, $bogref->{'viewer_uuid'} );
    make_path($sharedfolder);
    my %results;
    $results{'viewerdbchecksum'} = checksumFile( $savefile );
    if (!cp($savefile, $sharedfolder)) {
        $log->error("Cannot copy $savefile to $sharedfolder : $OS_ERROR");
        return 0;
    }
	$log->info("Copied: $savefile to: $sharedfolder");
	Log::Log4perl->get_logger('viewer')->trace("$bog{'execrunid'} $vmname copied: $savefile to: $sharedfolder");
    $results{'vieweruuid'} = $bogref->{'viewer_uuid'};
    $results{'viewerdbpath'} = abs_path(File::Spec->catfile($sharedfolder, $savefile));
    # MYSQL needs to own our result files folders so they can be cleaned up.
    my ( $uid, $gid ) = ( getpwnam('mysql') )[ 2, 3 ];
    if ( chown( $uid, $gid, $sharedfolder ) != 1 ) {
        $log->warning("Cannot chown folder $sharedfolder to mysql user. $OS_ERROR" );
    }
    if ( chown( $uid, $gid, $results{'viewerdbpath'} ) != 1 ) {
        $log->warning("Cannot chown file $results{'viewerdbpath'} to mysql user. $OS_ERROR" );
    }
    my $result = storeviewer(%results);
	$log->info("storeviewer result: ", $result);
	Log::Log4perl->get_logger('viewer')->trace("$bog{'execrunid'} $vmname storeviewer result: ", $result);

    return 1;
}

sub sendUpdate {
    my $state  = shift;
    my $ref    = shift;
    my $bogref = shift;
    my $output;
    my $status;
    my $ret = 1;

    ( $output, $status ) = systemcall("guestfish --ro --mount /dev/sdc:/mnt/out -d $vmname -i cat /mnt/out/run.out 2>&1");
    if ( !$status ) {
        setStarts(0);    # Clean slate.
        haveCommunicated();
        setDeadman();    # Reset the timer, we have communications.
                         # The scalar $output will have all of the stuff in it from the VM run.out
        if ($output =~/ERROR:\sNO\sIP/sxm) {
            setViewerState(
                'domain' => $vmname,
                'viewer'    => $bogref->{'viewer'},
                'project'   => $bogref->{'project'},
                'vieweruuid' => $bogref->{'viewer_uuid'},
                'apikey'    => $bogref->{'apikey'},
                'urluuid'    => $bogref->{'urluuid'},
                'state'     => 'shutdown'
            );
            $log->error("VM detected no IP address and has shutdown");
            return 0;
        }
        my %values = parseRunOut( $bogref, $output );
        setViewerState(
            'domain' => $vmname,
            'viewer'    => $bogref->{'viewer'},
            'project'   => $values{'project'},
            'vieweruuid' => $bogref->{'viewer_uuid'},
            'ipaddress' => $values{'ipaddr'},
            'apikey'    => $bogref->{'apikey'},
            'urluuid'    => $bogref->{'urluuid'},
            'state'     => $values{'state'}
        );
        if ( defined( $values{'ipaddr'} ) ) {
            $ret = 0;    # no need to send further updates
        }
    }
    else {
        $log->info("Cannot get run.out from $vmname: $status ($state) output: $output");
    }
    return $ret;
}

{
    my $_haveCommunicated = 0;

    sub forgetCommunicated {
        $_haveCommunicated = 0;
        return;
    }

    sub haveCommunicated {
        $_haveCommunicated = 1;
        return;
    }

    sub getHaveCommunicated {
        return $_haveCommunicated;
    }
}

sub removeStateFile {
    my $domname = shift;
    my $statefile = getDomainStateFilename( $basedir, $domname );
    if ( unlink($statefile) != 1 ) {
        $log->warn("Unable to remove state file $statefile: $OS_ERROR");
    }
    return;
}

sub localGetDomainStatus {
    my $domname   = shift;
    my $statefile = abs_path("$basedir/run/$domname.state");

    # There should be a state file, but there is not.
    if ( !-r $statefile ) {
        return { 'domainstate' => 'UNKNOWN' };
    }
    my $root = lock_retrieve($statefile);
    return $root;

}

#** @function checkState( )
# @brief Examine current VM state. Return 1 if the loop should continue, 0 if the wait loop should exit.
# This is intended to be called only from the doWaitLoop.
# If we are in UNKNOWN state for more than 1 minute, something
# has gone wrong and we need to just exit.
#
# @param state Current state as reported by libvirt
# @return 0 or 1
#*
sub checkState {
    my $state = shift;
    state $inUnknown = time;

    if ( $state eq 'UNKNOWN' ) {
        if ( ( time - $inUnknown ) > 60 ) {
            return 0;
        }
    }
    else {    # Any state other than UNKNOWN resets the counter
        $inUnknown = time;
    }
    return 1;
}

#** @function checkDeadman( )
# @brief Check the deadman timer on the VM and if it has expired,
# try to restart N times. If after N failures, give up.
#
# @return
# @see
#*
sub checkDeadman {
    my $now = time;
    my $ret = 0;
    if ( numberStarts() < main->MAX_RESTARTS ) {

        # If we get no response, kick the VM over.
        if ( abs( $now - getDeadman() ) > main->MAX_WAITSTUCK ) {
            $ret = restartVM(1);
            $log->info("Restarting VM");
        }
        else {
            $ret = 1;
        }
    }
    return $ret;
}

{
    #** @var $numberStarts The number of times we've had to start our VM.
    my $nRestarts = 0;

    sub setStarts {
        $nRestarts = shift;
        return;
    }

    sub numberStarts {
        return $nRestarts;
    }
}

sub restartVM {
    my $needDestroy = shift;
    my $ret         = 0;
    setStarts( numberStarts() + 1 );

    # Let's make a VM
    my $output;
    my $status = 0;
    if ($needDestroy) {
        ( $output, $status ) = systemcall("virsh destroy $vmname");
    }
    if ( !$status ) {
        ( $output, $status ) = systemcall("virsh start $vmname");
        if ($status) {
            $log->error("Unable to start stuck VM $vmname");
        }
        else {
            $ret = 1;
            forgetCommunicated();
            setDeadman();
            $log->info( "Restarted stuck VM $vmname " . numberStarts() . " times." );
        }
    }
    else {
        $log->error("Unable to destroy stuck VM $vmname $status: ($output)");
    }
    return $ret;
}

{
    #** @var $vmDeadman the timer started when we launch our VM. This is part of a
    # deadman timer watching for feedback from the VM. No feedback is assumed to be a
    # failure to launch.
    my $vmDeadman;

    sub getDeadman {
        return $vmDeadman;
    }

    sub setDeadman {
        $vmDeadman = time;
        return;
    }
}

sub configureClients {
    my $aHost  = shift;
    my $aPort  = shift;
    my $config = getSwampConfig();
    if ( !defined($aPort) ) {
        $aPort = int( $config->get('agentMonitorJobPort') );
    }
    if ( !defined($aHost) ) {
        $aHost = $config->get('agentMonitorHost');
    }

    if ( defined($aPort) && defined($aHost) ) {
        SWAMP::Client::AgentClient::configureClient( $aHost, $aPort );
    }
    return;
}

{
    my $workingspace;

#** @function setupWorkingSpace( $suffix )
# @brief Based on the desired resultsFolder in the swamp.conf, build and chdir to a temp space in the resultsFolder tree.
#
# @param suffix The folder we should  use. This should be unique in a SWAMP instance.
# @return 1 if we succeeded, 0 otherwise. The assessment will fail if we return 0.
#*
    sub setupWorkingSpace {
        my $suffix = shift;
        my $config = getSwampConfig();
        $workingspace = $config->get("resultsFolder") // q{.};
        $workingspace = File::Spec->catfile( $workingspace, q{temp}, $suffix );
        make_path( $workingspace, { 'error' => \my $err } );
        if ( @{$err} ) {
            for my $diag ( @{$err} ) {
                my ( $file, $message ) = %{$diag};
                if ( $file eq q{} ) {
                    $log->error("Cannot make working folder [$workingspace]: $message");
                }
                else {
                    $log->error("Cannot make working folder [$workingspace]: $file $message");
                }
            }
            return 0;
        }
        my ( $output, $status ) = systemcall("tar -C $workingspace -xf input*.tgz");
        if ($status) {
            $log->error("Cannot extract input to $workingspace  : $status $OS_ERROR $output");
            return 0;
        }
		if (-r '.chirp.config') {
            cp('.chirp.config', $workingspace);
		}
        chdir $workingspace;
        if ( getcwd() ne abs_path($workingspace) ) {
            $log->error("Cannot chdir to input to $workingspace  : $OS_ERROR");
            return 0;
        }
        return 1;
    }

    #** @function cleanupWorkingSpace( )
    # @brief Remove the working space set up by #setupWorkingSpace()
    #*
    sub cleanupWorkingSpace {
        if ($workingspace) {
            $log->info("Cleaning up $workingspace");
            remove_tree($workingspace);
        }
        return;
    }
}

sub taskShutdown {
    if ( defined($vmid) ) {    # If vmid is still defined our VM is viable.
        systemcall("PERL5LIB=$basedir/perl5 $basedir/bin/vm_cleanup --force  $vmname 2>&1");
        removeDomainPIDFile($PID, $vmname);
        my $statefile = getDomainStateFilename( $basedir, $vmname ) . q{died};
        if ( open( my $fh, '>', $statefile ) ) {
            print $fh "Caught signal @_, shutting down\n";
            if ( !close($fh) ) {

                # nothing to do, we're shutting down.
            }
        }
    }

    # Try and clean up.
    cleanupWorkingSpace();
    croak "Caught signal @_, shutting down";
}

sub logtag {
    ( my $name = $PROGRAM_NAME ) =~ s/\.pl//sxm;
    return basename($name);
}

sub logfilename {
    ( my $name = $appname ) =~ s/\.pl//sxm;
    $name = basename($name);
    return "$basedir/log/${name}.log";
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


