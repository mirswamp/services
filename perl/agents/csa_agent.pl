#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#** @file csa_agent
#
# @brief # The CSA agent is responsible for
# 1) Watching for .bog files
# 2) creating HT Condor jobs from a BOG (Bill Of Goods) files.
# 3) Starting HTCondor jobs.
#
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 07/29/13 10:27:20
#*

#** @class main
# @brief This application handles watching for bog files in the specified folder
# ### Overview
# This class handles submitting jobs as described by .bog (Bill of Goods) files. It runs until all of the
# .bog files have been submitted as jobs.
#*

use 5.014;
use utf8;
use warnings;
use strict;
use FindBin qw($Bin);
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );

use Archive::Tar qw(COMPRESS_GZIP);
use ConfigReader::Simple;
use Carp qw(croak carp);
use Cwd qw(abs_path);
use Fcntl qw(:flock);
use English '-no_match_vars';
use File::Copy qw(move);
use File::Basename qw(basename);
use File::Path qw(make_path);
use Getopt::Long qw/GetOptions/;
use IPC::Open3 qw(open3);
use Log::Log4perl::Level;
use Log::Log4perl;
use Pod::Usage qw/pod2usage/;
use RPC::XML::Server;
use RPC::XML;

use SWAMP::Client::AgentClient qw(csaAgentFinished configureClient getSuitableMachines updateAssessmentStatus);
use SWAMP::Client::ExecuteRecordCollectorClient
  qw(configureClient updateExecutionResults updateRunStatus);
use SWAMP::Locking qw(swamplock);
use SWAMP::SWAMPUtils
  qw(diewithconfess getBuildNumber getSwampConfig trim systemcall getJobDir getJobFilename getLoggingConfigString loadProperties uname);
use SWAMP::AssessmentTools qw(isParasoftC isParasoftJava isGrammaTechCS isRedLizardG);

#
#local $SIG{'USR1'} = \&stopJob;
my $help = 0;
my $man  = 0;
our $VERSION = '1.00';
my $port;
my $host;
my $debug = 0;
my $bogDir;
my $configfile;
my $testMode = 0;
my $runnow;

GetOptions(
    'testmode' => \$testMode,
    'host=s'   => \$host,
    'port=i'   => \$port,
    'config=s' => \$configfile,
    'bog=s'    => \$bogDir,
    'debug'    => \$debug,
    'runnow=s' => \$runnow,
    'help|?'   => \$help,
    'man'      => \$man,
) or pod2usage(2);

# Unless we're invoked with runnow
if ( !defined($runnow) ) {

    # Check for an instance of ourself
    if ( !swamplock($PROGRAM_NAME) ) {
        exit 0;
    }
}

## use critic

if ($help) { pod2usage(1); }
if ($man) { pod2usage( '-verbose' => 2 ); }

Log::Log4perl->init( getLoggingConfigString() );

# No logging to screen
Log::Log4perl->get_logger(q{})->remove_appender('Screen');
my $log = Log::Log4perl->get_logger(q{});
$log->level( $debug ? $TRACE : $INFO );

# Catch anyone who calls die.
local $SIG{'__DIE__'} = \&diewithconfess;

if ( !defined($bogDir) ) {
    pod2usage('BOG file is required');
}

my $config = getSwampConfig($configfile);
if ( !defined($port) ) {
    $port = int( $config->get('agentMonitorJobPort') );
}
if ( !defined($host) ) {
    $host = $config->get('agentMonitorHost');
}
my $dispPort = $config->get('dispatcherPort');
my $dispHost = $config->get('dispatcherHost');

my $ver = "$VERSION." . getBuildNumber();
$log->info("$PROGRAM_NAME version $ver ($PID) starting. AgentMonitor:$host:$port");
if ( defined($port) && defined($host) ) {
    SWAMP::Client::AgentClient::configureClient( $host, $port );
}
SWAMP::Client::ExecuteRecordCollectorClient::configureClient( $dispHost, $dispPort );

if ( defined($runnow) ) {
    runImmediate($runnow);
    exit 0;
}

# Now read all bog files in $bogDir
my %bogFiles;

my $done = 0;
my $base = 0;
while ( !$done ) {

    # Read in list of .bog files.
    my $nToProcess = readBogFiles( $bogDir, \%bogFiles );
    if ( $nToProcess <= 0 ) {
        $done = 1;
        last;
    }
    $log->info("readBogFiles says $nToProcess left to go");
    foreach my $bogFile ( keys %bogFiles ) {
        if ( $bogFiles{$bogFile} != 0 ) {
            next;
        }
        my %bog;
        loadProperties( $bogFile, \%bog );
	    my $execrunid = $bog{'execrunid'};

		# check to see if a job with the same exec run id is currently running, or has
		# been run at some time in the past. this only applies to assessment runs.
		if (!(defined( $bog{'intent'} ) && $bog{'intent'} eq 'VRUN' )) {
	    	$log->info( "Checking assessment run $execrunid for prior attempts");
	    	if (isJobInQueue($execrunid) || isJobInHistory($execrunid)) {
				# we can delete this bog file and skip the rest of the loop
				_removeBOG($bogFile);
				$bogFiles{$bogFile} = 1;    # processed.
				$log->warn("Duplicate run $execrunid removed from job queue");
				next;
	    	}
		}
        if ( !defined( $bog{'resultsfolder'} ) ) {
            $bog{'resultsfolder'} = '/swamp/working/results';
        }
        sendUpdates( $bog{'execrunid'}, 'Waiting for resources' );
        my $nTries   = 0;
        my $machines = getSuitableMachines();
        $log->debug( "Suitable machines ($nTries): " . keys %{$machines} );

        # This loop waits for a machine to become available
        while ( keys %{$machines} < 1 ) {
            sleep 10;
            $machines = getSuitableMachines();
            $log->debug( "Suitable machines ($nTries): " . keys %{$machines} );
            $nTries++;
        }

        if ( createHTCondorJob( \%bog, $machines, $bogFile, $host, $port, $dispHost, $dispPort ) ) {
		    my ($clusterid, $start_time) = startHTCondorJob( \%bog );
            if ( $clusterid != -1 ) {
				# leave arun jobs at priority 0
				# set metric runs to priority -10
				if ($execrunid =~ m/^M-/sxm) {
            		system("condor_prio -p -10 $clusterid");
				}
                my $res = csaAgentFinished( \%bog );
                if ( !defined( $res->{'error'} ) ) {
                    # Only remove the BOG file when we have actually launched it.
                    _removeBOG($bogFile);
                    $bogFiles{$bogFile} = 1;    # processed.
                    sendUpdates( $execrunid, 'Submitted to HTCondor' );
                }
                else {
                    $log->warn(
                        "Unable to submit BOG: call to csaAgentFinished failed $res->{'error'}");
                }
            }
            else {
                $log->warn('Unable to submit BOG: cannot start HTCondor job.');
            }
        }
        else {
            $log->warn('Unable to submit BOG: cannot create HTCondor job');
        }
    }
}
$log->info("$PROGRAM_NAME version $VERSION ($PID) exiting normally.");
exit 0;

# Create the input.tgz file from the tool/package in the description.
#  bog->{'packagepath'} should contain the local URI for the package file(s)
# If packagepath is a folder, assume its contents are the package.
# The tool is specified by
# For sonatype (and possibly forever, tools and packages will be on the shared
# filesystem /everglades on the exec nodes and submit node)
sub createInputFile {
    my $jobdir  = shift;
    my $bogFile = shift;
    my @files;
    push @files, $bogFile;

    Archive::Tar->create_archive( "$jobdir/input${PID}.tgz", COMPRESS_GZIP, @files );
    return;
}

sub _removeBOG {
    my $bfile = shift;
    if ( defined( $bogFiles{$bfile} ) ) {
        $bogFiles{$bfile} = 2;    # Unlinked
    }
    else {
        $log->warn("Unlinking $bfile, but it is unknown");
    }
    unlink "$bogDir/$bfile";
    return;
}

sub testMode {
    return $testMode;
}

sub sendUpdates {
    my $execid = shift;
    my $msg    = shift;
    updateRunStatus( $execid, $msg );
    updateAssessmentStatus( $execid, $msg );
    return;
}

#** @function createHTCondorJob( \%bogref, \@machines, $bogFile)
# @brief Create the HTCondor submit file based on the BOG contents
#
# @param bogref HASH ref containing the Bill Of Goods for the exec run
# @param machines ARRAY ref containing the list of suitable machines to run on.
# @param bogFile filename of BOG file for which this job is being created.
# @return 1 on success, 0 on failure
#*
sub createHTCondorJob {
    my $bogref      = shift;
    my $machineList = shift;
    my $bogFile     = shift;
    my $execrunid   = $bogref->{'execrunid'};
    my $jobdir      = getJobDir($execrunid);
    my $ret         = 0;
    my $forVRun     = ( defined( $bogref->{'intent'} ) && $bogref->{'intent'} eq 'VRUN' );

    if ( testMode() ) {
        _removeBOG($bogFile);
        return 1;
    }

    make_path($jobdir, { 'error' => \my $err } );
    if ( @{$err} ) {
        for my $diag ( @{$err} ) {
            my ( $file, $message ) = %{$diag};
            if ( $file eq q{} ) {
                $log->error( "Cannot make working folder [$jobdir]: $message" );
            }
            else {
                $log->error( "Cannot make working folder [$jobdir]: $file $message" );
            }
        }
        return 0;
    }
    createInputFile( $jobdir, $bogFile );
    if ( !-d $jobdir ) {
        $log->error("Cannot create folder for job! $OS_ERROR");
    }

    $log->info("CreateHTCondorJob for $execrunid");
    my $filename = abs_path( getJobFilename($execrunid) );
    if ( open( my $fh, '>', $filename ) ) {
        print $fh "# HTCondor submit description file for " . $bogref->{'execrunid'} . "\n";
        print $fh "universe = vanilla\n";
        if ($forVRun) {
            print $fh "executable = /opt/swamp/bin/vrunlauncher\n";

            # pass arguments to script
            print $fh
"arguments = --vmname vswamp\$(cluster) --bog $bogFile --out out_\$(cluster).tgz --ahost $host --aport $port\n";
	    # pass the execrunid as an attribute, but not the project id (not particularly useful for v-runs)
	    print $fh "+SwampViewRunID = \"" . $execrunid . "\"\n";
        }
        else {
            print $fh "executable = /opt/swamp/bin/assessmentlauncher\n";

            # pass arguments to script
            print $fh
"arguments = --vmname swamp\$(cluster) --bog $bogFile --out out_\$(cluster).tgz --dhost $dispHost --dport $dispPort --ahost $host --aport $port\n";
	    # pass the execrunid and project id as attributes
	    print $fh "+SwampExecRunID = \"" . $execrunid . "\"\n";
	    print $fh "+SwampProjectID = \"" . $bogref->{'projectid'} ."\"\n";
        }
        print $fh "input = $jobdir/input${PID}.tgz\n";
        print $fh "output = $jobdir/out.stdout\n";
        print $fh "error = $jobdir/out.stderr\n";
        print $fh "log = $jobdir/log.\$(cluster)\n";
        if ( !$forVRun ) {
            print $fh "when_to_transfer_output = ON_EXIT\n";
            print $fh "transfer_output_files=out_\$(cluster).tgz\n";
			if (isParasoftC($bogref)) {
            	print $fh "concurrency_limits = PARASOFTC\n";
			}
			elsif (isParasoftJava($bogref)) {
            	print $fh "concurrency_limits = PARASOFTJAVA\n";
			}
			elsif (isGrammaTechCS($bogref)) {
            	print $fh "concurrency_limits = GRAMMATECHCS\n";
			}
			elsif (isRedLizardG($bogref)) {
            	print $fh "concurrency_limits = REDLIZARDG\n";
			}
        }
        print $fh "+WantIOProxy = true\n";
        print $fh "should_transfer_files = YES\n";
        print $fh "request_cpus = 2\n";
        print $fh "request_memory = 6020 Mb\n";
        print $fh 'requirements = ( ';
        my @mlist = keys %{$machineList};
        for my $idx ( 0 .. $#mlist ) {
            print $fh "Machine == \"$mlist[$idx]\"";
            if ( $idx < $#mlist ) {
               print $fh ' || ';
            }
        }
        print $fh ")\n";

        #        transfer_input_files = $bogFile
        print $fh "queue\n";
        if ( !close($fh) ) {
            $log->warn("Failed to close job file($filename): $OS_ERROR");
        }
        else {
            $ret = 1;
        }
    }
    else {
        $log->warn("Failed to open job file ($filename): $OS_ERROR");
    }

    return $ret;
}

sub startHTCondorJob {
    my $bogref     = shift;
    my $submitfile = getJobFilename( $bogref->{'execrunid'} );
    my $started    = 0;
    my $retry      = 0;
    my $output;
    my $status;
	my $start_time;

    if ( testMode() ) {
        my $id = $base + $PID;
        $bogref->{'clusterid'} = $id;
        $log->info("startHTCondorJob $id");
        $base++;
        return $id;
    }

    while ( !($started) && $retry++ < 3 ) {
		Log::Log4perl->get_logger('viewer')->trace("$bogref->{'execrunid'} Calling condor_submit");
        ( $output, $status ) = systemcall("condor_submit $submitfile");
        if ($status) {
            $log->warn("Failed to start condor job using $submitfile: $output. Trying again in 5 seconds");
            sleep 5;
        }
        else {
			$start_time = time();
            $started = 1;
            last;
        }
    }
    if ( !$started ) {
        $log->error("Failed to start condor job: $output after $retry tries");
		Log::Log4perl->get_logger('viewer')->trace("$bogref->{'execrunid'} condor_submit failed: $output after: $retry attempts");
    }
    my $clusterid = -1;
    if ( $output =~ /submitted\ to\ cluster/sxm ) {
        $clusterid = $output;
        $clusterid =~ s/^.*cluster\ //sxm;
        $clusterid =~ s/\..*$//sxm;
        $log->debug("Found cluster id <$clusterid>");
    }

    if ( $clusterid == -1 ) {
        $log->error("submit job failed");
    }

    $bogref->{'clusterid'} = $clusterid;
    $log->info("startHTCondorJob $clusterid");
    return ($clusterid, $start_time);
}

# Convert a \n delimited string to a hash map
sub stringToMap {
    my $ref = shift;
    my $str = shift;
    my @arr = split( /\n/sxm, $str );
    %{$ref} = ();
    foreach my $line (@arr) {
        my ( $key, $val ) = split( /\s=\s/sxm, $line );
        $ref->{$key} = $val;
    }
    return;
}

sub logtag {
    ( my $name = $PROGRAM_NAME ) =~ s/\.pl//sxm;
    return basename($name);
}

sub logfilename {
    ( my $name = $PROGRAM_NAME ) =~ s/\.pl//sxm;
    if ( uname() eq "Linux" ) {
        $name = basename($name);
        return "/opt/swamp/log/${name}.log";
    }
    return "${name}.log";
}

# Example signal handler
sub stopJob {
    print "@_\n";
    $log->debug("I have been asked to stop.");

    return;
}

sub readBogFiles {
    my $path   = abs_path(shift);
    my $ref    = shift;
    my $nFiles = -1;
    if ( opendir( my $dh, $path ) ) {
        $nFiles = 0;
        my @bogfiles = grep { /\.bog$/sxm && -f "$path/$_" } readdir($dh);
        foreach (@bogfiles) {
            next if (/vrun/sxim); # Do not include vrun BOG files in this loop.
            if ( !defined( $ref->{$_} ) ) {
                $ref->{$_} = 0;    # 0=>Needs processing
            }
            if ( $ref->{$_} == 0 ) {
                $nFiles++;
            }
        }
        if ( !closedir $dh ) {
            carp "Unable to closedir $path $OS_ERROR";
        }
    }
    else {
        carp "Cannot open $path $OS_ERROR";
    }
    return $nFiles;
}

sub runImmediate {
    my $bogfile = shift;

    # submit the BOG file immediately and exit.
    my %bog;
    my $ret = 1;
    loadProperties( $bogfile, \%bog );
    my $machines = getSuitableMachines('viewer');
    if ( createHTCondorJob( \%bog, $machines, $bogfile, $host, $port, $dispHost, $dispPort ) ) {
        my ($clusterid, $start_time) = startHTCondorJob( \%bog );
        if ( $clusterid != -1 ) {
			# set vrun jobs to priority 10
            system("condor_prio -p +10 $clusterid");
            my $res = csaAgentFinished( \%bog );
            # all good
            if ( !defined( $res->{'error'} ) ) {
                _removeBOG($bogfile);
                $ret = 1;
            }
        }
    }
    return $ret;
}

# Search the Condor history to see if a job with the same exec run id has
# been run before. This is for assessment runs only.
sub isJobInHistory {
    my $uuid = shift;
    my $res = 0;
    my $cmd = qq(condor_history -constraint 'SwampExecRunID == "$uuid"' -format "%s\n" SwampExecRunID);

    if (testMode()) {
	return $res;
    }

    my $childpid = open3(\*HIS_IN, \*HIS_OUT, \*HIS_ERR, $cmd);
    if (!close(HIS_IN)) {
	$log->warn("unable to close condor_history input handle");
    }
    my @outlines = <HIS_OUT>;
    my @errlines = <HIS_ERR>;

    if (!close(HIS_OUT)) {
	$log->warn("unable to close condor_history output handle");
    }
    if (!close(HIS_ERR)) {
	$log->warn("unable to close condor_hisotry error  handle");
    }
    waitpid($childpid, 1);

    my $errnum = @errlines;
    if ($errnum > 0) {
        $log->warn("error in condor_history execution\n" . @errlines);
	return $res;
    }

    my $num = @outlines;
    # there is no header line in the output when we use the -format flag, so
    # any output at all indicates that we have found the uuid.
    if ($num > 0) {
        $log->info( "found job $uuid in Condor history");
        $res = 1;
    }

    return $res;
}

# check the Condor queue to see if the job is currently running.
# this works for both assessment runs and for vruns.
sub isJobInQueue {
    my $uuid = shift;
    my $res = 0;
    my $cmd = qq(condor_q -format "%s\n" SwampExecRunID -format "%s\n" SwampViewRunID);

    if (testMode()) {
	return $res;
    }

    my $childpid = open3(\*HIS_IN, \*HIS_OUT, \*HIS_ERR, $cmd);
    if (!close(HIS_IN)) {
	$log->warn("problem closing condor_q input handle");
    }
    my @outlines = <HIS_OUT>;
    my @errlines = <HIS_ERR>;
    if (!close(HIS_OUT)) {
	$log->warn("problem closing condor_q output handle");
    }
    if (!close(HIS_ERR)) {
	$log->warn("problem closing condor_q error handle");
    }
    waitpid($childpid, 1);

    my $num = @errlines;
    if ($num > 0) {
        $log->warn("error in condor_q execution\n" . @errlines);
        return $res;
    }

    foreach my $id (@outlines) {
        if ($id =~ /$uuid/isxm) {
            $log->info("found job $uuid in Condor queue");
            $res = 1;
            last;
        }
    }
    return $res;
}


__END__
=pod

=encoding utf8

=head1 NAME

csa_agent 

=head1 SYNOPSIS

csa_agent -bog bogFile

=head1 DESCRIPTION

=head1 OPTIONS

=over 8

=item --man

Show manual page for this script

=back

=head1 EXAMPLES

=head1 SEE ALSO

=cut

## Please see file perltidy.ERR
## Please see file perltidy.ERR
