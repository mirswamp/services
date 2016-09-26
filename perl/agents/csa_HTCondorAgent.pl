#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

use 5.014;
use utf8;
use warnings;
use strict;
use FindBin qw($Bin);
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );

use Carp qw(croak carp);
use ConfigReader::Simple;
use Cwd qw(abs_path getcwd);
use English '-no_match_vars';
use Fcntl qw(:flock);
use File::Basename qw(basename);
use File::Copy qw(move);
use File::Path qw(remove_tree);
use File::Spec qw(catfile);
use Getopt::Long qw/GetOptions/;
use List::MoreUtils qw(any);
use Log::Log4perl::Level;
use Log::Log4perl;
use Pod::Usage qw/pod2usage/;

use SWAMP::Client::AgentClient qw(listJobs configureClient clusterJobStatus resultsProcessed);
use SWAMP::HTCondorDefines;
use SWAMP::SWAMPUtils qw(diewithconfess getBuildNumber getSwampConfig trim systemcall uname getJobDir getLoggingConfigString);

my $help     = 0;
my $testMode = 0;
my %testMap;
my %lastStatus;    # Map of line numbers in the event log where job status{clusterid} was last read
my $man   = 0;
my $debug = 0;
my $port;
my $host;
our $VERSION = '1.00';

#** @var %codeDXIndexes this is the map of project name to codeDX project number. Unfortunately this is hard coded.
my %codeDXIndexes = (
    'Camel'             => 1,
    'Clojure'           => 2,
    'ElasticSearch'     => 3,
    'Felix'             => 4,
    'Fitness'           => 5,
    'Gremlin'           => 6,
    'Hadoop'            => 7,
    'Hazelcast'         => 8,
    'Java Websocket'    => 9,
    'Jedis'             => 10,
    'Jenkins'           => 11,
    'JUnit'             => 12,
    'K-9'               => 13,
    'Minecraft API'     => 14,
    'Mongo Java Driver' => 15,
    'Netty'             => 16,
    'Pegasus'           => 17,
    'Scarab'            => 18,
    'Scribe'            => 19,
    'Sling'             => 20,
    'Solandra'          => 21,
    'Storm'             => 22,
    'Titan'             => 23,
    'Twitter4j'         => 24,
    'Velocity'          => 25,
    'Voldemort'         => 26,
);

## no critic (ProhibitCallsToUndeclaredSubs)
# Check for an instance of ourself
open my $self, '<', $PROGRAM_NAME or croak "Couldn't open self: $OS_ERROR";
flock $self, ( LOCK_EX | LOCK_NB ) or exit 0;

## use critic

GetOptions(
    'testmode' => \$testMode,
    'debug'    => \$debug,
    'help|?'   => \$help,
    'man'      => \$man,
) or pod2usage(2);

if ($help) { pod2usage(1); }
if ($man) { pod2usage( '-verbose' => 2 ); }
srand(time);
Log::Log4perl->init( getLoggingConfigString() );

# No logging to screen
Log::Log4perl->get_logger(q{})->remove_appender('Screen');

my $log = Log::Log4perl->get_logger(q{});
$log->level( $debug ? $TRACE : $INFO );

my $startupdir = getcwd;

# Catch anyone who calls die.
local $SIG{'__DIE__'} = \&diewithconfess;

my $config = getSwampConfig();
if ( !defined($port) ) {
    $port = int( $config->get('agentMonitorJobPort') );
}
if ( !defined($host) ) {
    $host = $config->get('agentMonitorHost');
}

my $ver = "$VERSION.".getBuildNumber();
$log->info("${PROGRAM_NAME} version $ver starting. AgentMonitor:$host:$port");

if ( defined($port) && defined($host) ) {
    configureClient( $host, $port );
}
my $done = 0;
while ( !$done ) {
    my $jobmap = listJobs();
    if ( scalar keys %{$jobmap} <= 0 ) {
        $done = 1;
        last;
    }

    # Need to loop over each job's log and keep track of it.
    my %jobStatus;
    my $more = 0;
    foreach my $eid ( keys %{$jobmap} ) {
        my $clusterid = $jobmap->{$eid}->{'id'};
        next if ($clusterid eq q{swampPENDING}); # Don't remove pending jobs!
        my $status;
        my $extra;
        ( $status, $extra, $more ) =
          getJobStatus( $eid, $clusterid, $jobmap->{$eid}->{'status'} );
        $jobStatus{$eid}->{'status'} = $status;
        if ( defined($extra) ) {
            $jobStatus{$eid}->{'extra'} = $extra;
        }
        $log->debug("Job $jobmap->{$eid} = $status");
        if ( $status eq SWAMP::HTCondorDefines->Job_terminated || $status eq SWAMP::HTCondorDefines->Job_evicted ) {
            # TODO for VRun VMs, there will be no 'output' file(s) and the jobdir can be
            # reaped on terminate. However the job may run for a very very long time.
            if ($eid =~ /vrun/sxm) {
                remove_tree( getJobDir($eid) );
            }
            else {
                move( "out_${clusterid}.tgz", getJobDir($eid) . "/out.tgz" );
            }
            remove_tree( getJobDir($eid) );
        }
    }
    clusterJobStatus( time, \%jobStatus );
    undef %jobStatus;
    if ( $more == 0 ) {    # Don't sleep at all if there's more waiting to be done.
        sleep(2);
    }
}
$log->info("$PROGRAM_NAME version $VERSION ($PID) exiting normally.");
exit 0;

#** @function getJobStatus($eid, $clusterid )
# @brief parses HTCondor job logs, establishing the job's state
#
# @param eid the execrunid associated with the HTCondor job $clusterid
# @param clusterid the HTCondor job id
# @return job's event id  or -1 on failure
# @see {@link SWAMP::HTCondorDefines}
#*
sub getJobStatus {
    my $eid         = shift;
    my $clusterid   = shift;
    my $currStatus  = shift;
    my $logfilename = getJobDir($eid) . "/log.$clusterid";
    my $more        = 0;
    if ( testMode() ) {
        nextState( \%testMap, $eid );
        my $status = $testMap{$eid}->{'status'};
        my $extra  = $testMap{$eid}->{'extra'};
        return ( $status, $extra, $more );
    }

    # Pad clusterid in case it's small
    if ( $clusterid < 10 ) {
        $clusterid = "0" . $clusterid;
    }
    if ( $clusterid < 100 ) {
        $clusterid = "0" . $clusterid;
    }
    if ( open( my $fd, '<', abs_path($logfilename) ) ) {
        my $status = -1;
        my $extra;
        my $lineAt = -1;
        my $found  = 0;
        $log->debug("reading log file: " . abs_path($logfilename));
        while (<$fd>) {
            if (/^(0..)\ \($clusterid/sxm) {

                if ( !$found ) {
                    $status = int($1);
                    if ( $status eq $currStatus ) {
                        next;    # Skip it if we're already in this state
                    }
                }
                else {
                    # Found a state, but we've already got one,
                    # Tell the caller to come back for more.
                    $more = 1;
                    last;
                }

                if ( $status eq SWAMP::HTCondorDefines->Execute ) {

                    # Set extra to host executing the job
                    $extra = $_;
                    $extra =~ s/^.*Job\ executing\ on\ host:\ <//sxm;
                    $extra =~ s/:.*$//sxm;

                    #$log->info("Found the hypervisor at <$extra> from [$_]");
                }
                else {
                    undef $extra;
                }

                # take advantage of the fact that status is time ordered
                # Don't care when, but don't want to miss a state transition.
                if ( defined( $lastStatus{$clusterid} ) ) {
                    if ( $INPUT_LINE_NUMBER > $lastStatus{$clusterid} ) {
                        $lineAt = $INPUT_LINE_NUMBER;
                        $found  = 1;
                    }
                }
                else {
                    $lineAt = $INPUT_LINE_NUMBER;
                    $found  = 1;
                }
            }
        }
        if ( !close($fd) ) {
            $log->warn("Cannot close log file $logfilename: $OS_ERROR");
        }
        if ( $lineAt != -1 ) {    # Remember the position, if we found one.
            $lastStatus{$clusterid} = $lineAt;
            $log->info("Set $clusterid lastStatus to $lineAt");
        }
        return ( $status, $extra, $more );
    }
    else {
        $log->error("Cannot open log file $logfilename: $OS_ERROR");
    }
    # If we get here, we cannot even access the HTCondor job log, so assume it is gone,
    # mark this job as done so we stop processing it. 
    return ( SWAMP::HTCondorDefines->Job_terminated, 'error', $more );
}

#** @function testMode( )
# @brief Getter for testMode behaviour
#
# @return 1 if the app should behave in test mode (e.g. no HTCondor), 0 otherwise
#*
sub testMode {
    return $testMode;
}

#** @function nextState( \%refmap , $eid)
# @brief This method is used only in testMode, running w/out HTCondor so that
# the correct cluster job states can be observed.
#
# @param refmap reference to a hash of job states, keyed by execute run ids
# @param eid the execute run id on which to operate.
#*

sub nextState {
    my $refmap = shift;
    my $eid    = shift;

    # Initialize test state
    if ( !defined( $refmap->{$eid} ) ) {
        $refmap->{$eid}->{'status'} = SWAMP::HTCondorDefines->Submit;
        return;
    }
    if ( $refmap->{$eid}->{'status'} eq SWAMP::HTCondorDefines->Submit ) {
        $refmap->{$eid}->{'status'} = SWAMP::HTCondorDefines->Execute;
        $refmap->{$eid}->{'extra'}  = '127.0.0.1';
    }
    elsif ( $refmap->{$eid}->{'status'} eq SWAMP::HTCondorDefines->Execute ) {
        if ( int( rand(10) ) > 5 ) {
            $refmap->{$eid}->{'status'} = SWAMP::HTCondorDefines->Image_size;
            undef $refmap->{$eid}->{'extra'};
        }
    }
    elsif ( $refmap->{$eid}->{'status'} eq SWAMP::HTCondorDefines->Image_size ) {
        if ( int( rand(10) ) > 8 ) {
            $refmap->{$eid}->{'status'} = SWAMP::HTCondorDefines->Job_terminated;
            undef $refmap->{$eid}->{'extra'};
        }
    }
    return;
}

sub makeZip {
    my $oldname = shift;
    my $newname;
    my $output;
    my $status;
    my $tmpdir = "tmp$PID";    #original
    mkdir $tmpdir;
    chdir $tmpdir;
    if ( $oldname =~ /\.tar$/sxm ) {
        $newname = $oldname;
        $newname =~ s/\.tar$/.zip/sxm;
        ( $output, $status ) = systemcall("tar xf ../$oldname");
        if ($status) {
            $log->error(
                "Unable to extract tarfile $oldname: ($status) " . defined($output)
                ? $output
                : q{}
            );
        }
    }
    elsif ( $oldname =~ /\.tar\.gz$/sxm ) {
        $newname = $oldname;
        $newname =~ s/\.tar\.gz$/.zip/sxm;
        ( $output, $status ) = systemcall("tar xzf ../$oldname");
        if ($status) {
            $log->error(
                "Unable to extract compressed tarfile $oldname: ($status) " . defined($output)
                ? $output
                : q{}
            );
        }

    }
    elsif ( $oldname =~ /\.jar$/sxm ) {
        $newname = $oldname;
        $newname =~ s/\.jar$/.zip/sxm;
        ( $output, $status ) = system("jar xf ../$oldname");
        if ($status) {
            $log->error(
                "Unable to extract jarfile $oldname: ($status) " . defined($output)
                ? $output
                : q{}
            );
        }
    }
    else {
        $log->error("Unable to process $oldname");
    }
    ( $output, $status ) = systemcall("zip ../$newname -r .");
    if ($status) {
        $log->error(
            "Unable to create zipfile ../$newname ($status) " . defined($output)
            ? $output
            : q{}
        );
        $newname = q{};
    }
    chdir q{..};
    remove_tree($tmpdir);
    return $newname;
}
#** @function checkForHooks( $fh )
# @brief Look for any hooks placed in the Bill Of Goods file.
#
# @param fh filehandle to an open bog file. Do not close and leave seek where it is at.
# @return 0 if there are no hooks, otherwise non-zero meaning do not process further.
# @see 
#*
sub checkForHooks {
    my $fh = shift;
    seek( $fh, 0, 0 );
    if ( any { /^testmode/sxm } <$fh> ) {
        return 3;
    }
    seek( $fh, 0, 0 );
        # If this is a sonatype special, just bail out.
    if ( any { /^gav/sxm } <$fh> ) {
        return 2;
    }
    seek( $fh, 0, 0 );
    return 0;
}
#** @function postProcessResults( $eid )
# @brief Perform any post run activities necessary for the assessment
# run. This functio should be called at the end of an assessment run
# after the HTCondor job has finished.
#
# @param eid the execute run id of this assessment
# @return 0 on failure, 1 on success
#*
sub postProcessResults {
    my $eid = shift;
    my $dir = getJobDir($eid);
    chdir $dir;
    my $resfile;
    my $name;
    my $packagename;
    my $val;
    my $zipname;
    my $url;
    my $otherresults;
    my $sendIt = 0;
    my $ret    = 0;
    my ( $output, $status ) = systemcall('tar xf out.tgz');

    if ($status) {
        $log->error("Unable to extract output $status: $output");
    }
    ( $output, $status ) = systemcall('tar xf out/results.tar.gz');
    if ($status) {
        $log->error("Unable to extract output results $status: $output");
    }

    if ( open( my $bogfh, '<', "${eid}.bog" ) ) {

        if ((my $check = checkForHooks($bogfh)) != 0) {
            if ( close($bogfh) ) {
                carp "Unable to close bog $OS_ERROR";
            }
            chdir q{..};
            return $check;
        }
        while (<$bogfh>) {
            chomp;
            if (/toolname/sxm) {
                if (/PMD/sxm) {
                    $resfile = "PMD.xml";
                }
                elsif (/Findbugs/sxm) {
                    $resfile = "Findbugs.xml";
                }
                else {
                    $log->error("Don't know how to process this tool: $_");
                }
            }
            if (/packagepath/sxm) {
                $_ =~ s/\ //sxmg;
                ( $name, $val ) = split( /=/sxm, $_ );
                $val =~ s/^\///sxm;
                if ( $val !~ /\.zip$/sxm ) {
                    $zipname = makeZip($val);
                }
                else {
                    $zipname = $val;
                }
            }
            if (/packagename/sxm) {
                ( $name, $packagename ) = split( /=/sxm, $_ );
                $packagename =~ s/^\ *//sxm;
                $packagename =~ s/\ *$//sxm;
            }
            if (/codedxurl/sxm) {
                ( $name, $url ) = split( /=/sxm, $_ );
                $url =~ s/^\ *//sxm;
                $url =~ s/\ *$//sxm;
                $sendIt = 1;
            }
            if (/siblings/sxm) {
                my ( $junk, $siblings ) = split( /=/sxm, $_ );
                $siblings =~ s/\ //sxm;
                ( $otherresults, $sendIt ) = checkSiblings($siblings);
                if ( $sendIt == 0 ) {
                    $ret = -1;    # pending
                }
            }
        }
        if ( !close($bogfh) ) {
            carp "Cannot close ${eid}.bog $OS_ERROR";
        }

        # If the codedxurl is in the bog, send it.
        if ( $sendIt && -r $zipname && -r $resfile ) {
            if ( -z $resfile ) {
                $log->error("The result file: $resfile is empty, assessment failed.");
            }
            else {
                my $proj = $codeDXIndexes{$packagename};
                my $curlcmd =
"curl -F username=admin -F password='PA\$\$w0rd123' -F file1=\@$resfile $otherresults -F srcfile=\@$zipname https://viewer.cosalab.org/upload/project/$proj";
                $log->info("Sending results to CodeDX: < $curlcmd >");
                ( $output, $status ) = systemcall($curlcmd);
                if ($status) {
                    $log->error("Unable to upload results to CodeDX: ($status) : $output");
                }
                else {
                    $ret = 1;
                    $log->info("Results uploaded to CodeDX: $output");
                }
            }
        }
        #else {
        #    if ($sendIt) {
        #        $log->warn("Cannot find files ($zipname, $resfile) for $packagename");
        #    }
        #}
        if (!$sendIt && $ret == 0) {
            $ret = 1;
        }

    }
    else {
        $log->error("Cannot open BOG file $eid");
    }

    chdir q{..};
    return $ret;
}

# if this BOG has siblings, then at this point we need to look and see if the siblings
# are done by going to ../siblingID folder and looking for extracted results. If the results are there, add
# them to the curl results, if the results aren't there, skip the curl command and just leave (result code is -1 =waiting).
# if we just leave the LAST job in the sibling chain will handle uploading results for all of them since they are processed
# sequentially.
sub checkSiblings {
    my @siblist = split( /,/sxm, shift );

    # if any of the siblings are not done, return empty string
    my $allDone = 1;
    my @resultfiles;
    foreach my $sibling (@siblist) {
        my $sibdir = getJobDir($sibling);
        if ( !-r "../$sibdir/out.tgz" ) {
            $log->info("Sibling <$sibling> is not done.");
            $allDone = 0;
            last;
        }
        else {    # Done, add it's results to our list.
            if ( -r "../$sibdir/PMD.xml" ) {
                push @resultfiles, "../$sibdir/PMD.xml";
            }
            elsif ( -r "../$sibdir/Findbugs.xml" ) {
                push @resultfiles, "../$sibdir/Findbugs.xml";
            }
        }
    }
    if ($allDone) {
        my $idx = 2;
        my $res = join( q{ }, map { "-F file" . $idx++ . "=\@$_" } @resultfiles );
        $log->info('All siblings done.');
        return ( $res, 1 );
    }
    else {
        return ( q{}, 0 );
    }
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
