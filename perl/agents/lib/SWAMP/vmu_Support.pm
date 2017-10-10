# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2017 Software Assurance Marketplace

package SWAMP::vmu_Support;
use strict;
use warnings;
use English '-no_match_vars';
use Cwd;
use ConfigReader::Simple;
use Data::UUID;
use Digest::SHA;
use Log::Log4perl;
use File::Basename qw(basename);
use File::Path qw(remove_tree);
use File::Spec::Functions;
use RPC::XML;
use RPC::XML::Client;
use DBI;

use parent qw(Exporter);
our (@EXPORT_OK);
BEGIN {
    require Exporter;
    @EXPORT_OK = qw(
	  getStandardParameters
	  identifyScript
	  listDirectoryContents
	  trim
      systemcall
	  getSwampDir
      getSwampConfig
	  isSwampInABox
      getLoggingConfigString
	  buildExecRunAppenderLogFileName
      switchExecRunAppenderLogFile
      loadProperties
	  saveProperties
	  insertIntoInit
	  displaynameToMastername
	  masternameToPlatform
	  checksumFile
	  rpccall
	  getJobDir
	  makezip
	  getUUID
	  HTCondorJobStatus
	  getHTCondorJobId
	  start_process
	  stop_process
	  launchPadStart
	  launchPadKill
	  deleteJobDir
	  createBOGfileName
	  construct_vmhostname
	  construct_vmdomainname
	  create_empty_file
	  isAssessmentRun
	  isMetricRun
	  isViewerRun
	  database_connect
	  database_disconnect

	  $LAUNCHPAD_SUCCESS
	  $LAUNCHPAD_BOG_ERROR
	  $LAUNCHPAD_FILESYSTEM_ERROR
	  $LAUNCHPAD_CHECKSUM_ERROR
	  $LAUNCHPAD_FORK_ERROR
	  $LAUNCHPAD_FATAL_ERROR

	  runType
	  $RUNTYPE_ARUN
	  $RUNTYPE_VRUN
	  $RUNTYPE_MRUN
    );
}

our $LAUNCHPAD_SUCCESS			= 0;
our $LAUNCHPAD_BOG_ERROR		= 1;
our $LAUNCHPAD_FILESYSTEM_ERROR	= 2;
our $LAUNCHPAD_CHECKSUM_ERROR	= 3;
our $LAUNCHPAD_FORK_ERROR		= 4;
our $LAUNCHPAD_FATAL_ERROR		= 5;

our $RUNTYPE_ARUN	= 1;
our $RUNTYPE_VRUN	= 2;
our $RUNTYPE_MRUN	= 3;

my $DEFAULT_CONFIG = getSwampDir() . '/etc/swamp.conf';
# my $MASTER_IMAGE_PATH = '/var/lib/libvirt/images/';
my $MASTER_IMAGE_PATH = '/swamp/platforms/images/';

my $global_swamp_config;
my $log = Log::Log4perl->get_logger(q{});
my $tracelog = Log::Log4perl->get_logger('runtrace');

sub getSwampDir {
	return "/opt/swamp";
}

sub getStandardParameters { my ($argv, $execrunuidref, $clusteridref) = @_ ;
	# execrunuid owner uiddomain clusterid procid [debug]
	my $argc = scalar(@$argv);
	return if ($argc < 5 || $argc > 6);
	$$execrunuidref = $argv->[0];
	my $owner = $argv->[1];
	my $uiddomain = $argv->[2];
	$$clusteridref = $argv->[3];
	my $procid = $argv->[4];
	# debug is optional
	my $debug = $argv->[5];
	# execrunuid is returned via reference because it is global
	# clusterid is returned via reference because it is global
	return($owner, $uiddomain, $procid, $debug);
}

sub identifyScript { my ($argv) = @_ ;
	my $cwd = getcwd();
	$log->info("$PROGRAM_NAME ($PID) argv: <", (join ' ', @$argv), ">");
	$log->info("uid: $REAL_USER_ID euid: $EFFECTIVE_USER_ID gid: $REAL_GROUP_ID egid: $EFFECTIVE_GROUP_ID");
	$log->info("cwd: $cwd");
	$log->info("executable: $EXECUTABLE_NAME");
}

sub listDirectoryContents { my ($dir) = @_ ;
	if ($log->is_debug()) {
		if (! $dir) {
			$dir = getcwd();
		}
		my ($output, $status) = systemcall("ls -lart $dir");
		if ($status) {
			$log->error("unable to list $dir");
		}
		$log->debug("Contents of $dir:\n", $output);
	}
}

sub isAssessmentRun { my ($execrunuid) = @_ ;
	if ($execrunuid =~ m/^M-/sxm) {
		return 0;
	}
	if ($execrunuid =~ m/^vrun_/sxim) {
		return 0;
	}
	return 1;
}

sub isMetricRun { my ($execrunuid) = @_ ;
	if ($execrunuid =~ m/^M-/sxm) {
		return 1;
	}
	return 0;
}

sub isViewerRun { my ($execrunuid) = @_ ;
	if ($execrunuid =~ m/^vrun_/sxim) {
		return 1;
	}
	return 0;
}

sub runType { my ($execrunuid) = @_ ;
	if ($execrunuid =~ m/^M-/sxm) {
		return $RUNTYPE_MRUN;
	}
	if ($execrunuid =~ m/^vrun_/sxim) {
		return $RUNTYPE_VRUN;
	}
	return $RUNTYPE_ARUN;
}

sub trim { my ($string) = @_ ;
    $string =~ s/^\s+//sxm;
    $string =~ s/\s+$//sxm;
    return $string;
}

my $condor_manager;
my $submit_node;

sub _getHTCondorManager {
	$global_swamp_config ||= getSwampConfig();
	if (! isSwampInABox($global_swamp_config)) {
		if (! $condor_manager) {
			$condor_manager = $global_swamp_config->get('htcondor_condor_manager');
			if (! $condor_manager) {
				my $HTCONDOR_COLLECTOR_HOST = $global_swamp_config->get('htcondor_collector_host');
				if ($HTCONDOR_COLLECTOR_HOST) {
					$condor_manager = $HTCONDOR_COLLECTOR_HOST;
					$condor_manager =~ s/csacol/csacon/;
					$condor_manager =~ s/(.*)\..*\.org$/$1\.mirsam.org/;
				}
			}
		}
	}
	return $condor_manager;
}

sub _getHTCondorSubmitNode { my ($condor_manager) = @_ ;
    $global_swamp_config ||= getSwampConfig();
	if (! isSwampInABox($global_swamp_config)) {
		$submit_node = $global_swamp_config->get('htcondor_submit_node');
		if (! $submit_node) {
			my $cmd = qq(condor_status -pool $condor_manager -schedd -af Name);
			my ($output, $status) = systemcall($cmd);
			if (! $status) {
				if ($output) {
					$submit_node = $output;
					chomp $submit_node;
				}
			}
		}
	}
	return $submit_node;
}

sub getHTCondorJobId { my ($execrunuid) = @_ ;
    my $cmd = q(condor_q);
	$condor_manager ||= _getHTCondorManager();
	$submit_node ||= _getHTCondorSubmitNode($condor_manager);
	if ($condor_manager && $submit_node) {
		$cmd .= qq( -name $submit_node -pool $condor_manager);
	}
	$cmd .= qq( -constraint \'SWAMP_arun_execrunuid==\"$execrunuid\" || SWAMP_mrun_execrunuid==\"$execrunuid\" || SWAMP_vrun_execrunuid==\"$execrunuid\"\' -af CLUSTERID PROCID);                       
	my ($output, $status) = systemcall($cmd);
	if ($status) {
		$log->error("getHTCondorJobId condor_q failed for $execrunuid: $status $output");
		return;
	}
	if ($output !~ m/^\d+\s+\d+$/) {
		$log->error("getHTCondorJobId condor_q failed for $execrunuid: $output");
		return;
	}
	my ($clusterid, $procid) = split ' ', $output;
	my $jobid = $clusterid . '.' . $procid;
	return $jobid;
}

sub HTCondorJobStatus { my ($jobid) = @_ ;
	my $cmd = q(condor_q);
	$condor_manager ||= _getHTCondorManager();
	$submit_node ||= _getHTCondorSubmitNode($condor_manager);
	if ($condor_manager && $submit_node) {
		$cmd .= qq( -name $submit_node -pool $condor_manager);
	}
	$cmd .= qq( -f \"%s\" JobStatus $jobid);
	my ($output, $status) = systemcall($cmd);
	if (! $status) {
		if (! $output) {
			return $output;
		}
	}
	return;
}

sub construct_vmdomainname { my ($owner, $uiddomain, $clusterid, $procid) = @_ ;
	my $vmdomainname = $owner . '_' . $uiddomain . '_' . $clusterid . '_' . $procid;
	return $vmdomainname;
}

sub _execrunuidToHostname { my ($execrunuid) = @_ ;
	my $name = 'aswamp';
	if (isMetricRun($execrunuid)) {
		$name = 'mswamp';
	}
	elsif (isViewerRun($execrunuid)) {
		$name = 'vswamp';
	}
	return $name;
}

sub construct_vmhostname { my ($execrunuid, $clusterid, $procid) = @_ ;
	my $name = _execrunuidToHostname($execrunuid);
	my $vmhostname = $name . '-' . $clusterid . '-' . $procid;
	return $vmhostname;
}

sub getJobDir { my ($execrunuid, $vmhostname) = @_ ;
	if (! defined($vmhostname)) {
		$vmhostname = _execrunuidToHostname($execrunuid);
	}
    return $vmhostname . '_' . $execrunuid;
}

sub create_empty_file { my ($filename) = @_ ;
	if (open(my $fh, '>', $filename)) {
		close($fh);
		return 1;
	}
	return 0;
}

sub createBOGfileName { my ($execrunid) = @_ ;
    return "${execrunid}.bog";
}

sub getUUID {
	return Data::UUID->new()->create_str();
}

sub start_process { my ($server) = @_ ;
    my $pid;
    if ($OSNAME eq "MSWin32") {
        $log->warn("About to call fork() on a Win32 system.");
    }
    if (! defined( $pid = fork())) {
        $tracelog->trace("start_process: $server - fork error: $OS_ERROR");
        return;
    }
    elsif ($pid) {
        $tracelog->trace("start_process: $server - returns pid: $pid");
        return $pid;
    }
    else {
        $tracelog->trace("start_process: $server - calling exec");
        exec($server);    # Need a better way to tell if this failed.
                          # If we return from the exec call, bad bad things have happened.
        exit 6;
    }
	$tracelog->trace("start_process: $server - error - returns undef");
    return;
}

sub stop_process { my ($pid) = @_ ;
    my $SIGNAL = ($OSNAME eq "MSWin32") ? 'KILL' : 'TERM';
    my $ret = kill $SIGNAL, $pid;
    sleep 1;    # give any old sockets time to go away
    if ($ret != 1) {
        $log->warn("kill of $pid failed, trying again");
        $ret = kill $SIGNAL, $pid;
        sleep 1;    # give any old sockets time to go away
        if ($ret != 1) {
            $log->warn("kill of $pid failed again, -9 time.");
            $ret = kill -9, $pid;
        }
    }
    return $ret;
}

sub makezip { my ($oldname) = @_ ;
    my $newname = basename($oldname);
    my $output;
    my $status;
    my $tmpdir = "tmp$PID";
    mkdir($tmpdir);
    chdir($tmpdir);

	# fix for other archive extensions
    if ( $newname =~ /(\.tar)/isxm || $newname =~ /(\.tgz)/isxm ) {
        $newname =~ s/$1.*$/.zip/sxm;

        # This will extract normal and compressed tarballs
        ( $output, $status ) = systemcall("/bin/tar xf $oldname");
        if ($status) {
            $log->error("Unable to extract tarfile $oldname: ($status) " . (defined($output) ? $output : q{}));
            $newname = $oldname;
        }
    }
    elsif ( $newname =~ /(\.jar$)/isxm ) {
        $newname =~ s/$1.*$/.zip/sxm;
        ( $output, $status ) = systemcall("jar xf $oldname");
        if ($status) {
            $log->error("Unable to extract jarfile $oldname: ($status) " . (defined($output) ? $output : q{}));
            $newname = $oldname;
        }
    }

    elsif ( $newname =~ /(\.gem$)/isxm ) {
        $newname =~ s/$1.*$/.zip/sxm;
        ( $output, $status ) = systemcall("gem unpack $oldname");
        if ($status) {
            $log->error("Unable to unpack gem $oldname: ($status) " . (defined($output) ? $output : q{}));
            $newname = $oldname;
        }
    }
    elsif ( $newname =~ /(\.whl$)/isxm ) {
        $newname =~ s/$1.*$/.zip/sxm;
        ( $output, $status ) = systemcall("wheel unpack $oldname");
        if ($status) {
            $log->error("Unable to unpack whl $oldname: ($status) " . (defined($output) ? $output : q{}));
            $newname = $oldname;
        }
    }

    else {
        $log->error("Do not understand how to re-zip $oldname");

    }
	# silent failure should be fixed here
    if ( $newname ne $oldname ) {
        ( $output, $status ) = systemcall("zip ../$newname -qr .");
        if ($status) {
            $log->error("Unable to create zipfile ../$newname ($status) " . (defined($output) ? $output : q{}));

            # revert
            $newname = $oldname;
        }
    }
    chdir(q{..});
    remove_tree($tmpdir);
    return $newname;
}

sub checksumFile { my ($filename, $algorithm) = @_ ;
	$algorithm ||= 512;
    my $sha = Digest::SHA->new(512);
	eval {
		$sha->addfile($filename, "pb");
	};
	if ($@) {
		$log->error("checksumFile - $filename $algorithm error - $@");
        return 'ERROR';
    }
    else {
        return $sha->hexdigest;
    }
}

sub rpccall { my ($client, $req) = @_ ;
    if (defined($req)) {
        my $res = $client->send_request($req);
        if (ref $res) {
            if ($res->is_fault()) {
				my $str = $res->value()->as_string();
				$log->error("rpccall is_fault - error: $str");
                return {'error' => $str, 'fault' => 1};
            }
            else {
                return {'value' => $res->value()};
            }
        }
        else {
			$log->error("rpccall did not get a ref back - error: $res");
            return {'error' => 'did not get a ref back', 'text' => $res};
        }
    }
    else {
		$log->error('rpccall - XMLRequest undefined');
        return {'error' => 'XMLRequest undefined'};
    }
}

sub loadProperties { my ($file, $hashref) = @_ ;
    my $config;
    $config = ConfigReader::Simple->new($file);
    if (defined($hashref) && ref($hashref) eq "HASH") {
        my $nItems = 0;
        foreach my $key ($config->directives()) {
            $hashref->{$key} = $config->get($key);
            $nItems++;
        }
        return $nItems;
    }
    else {
        return $config;
    }
}

sub _getPropString { my ($key, $value) = @_ ;
	my $propstring = q{};
	my $nlcount = ($value =~ tr/\n//);
	if ($nlcount > 0) {
		$nlcount += 1;
		$propstring = "$key:${nlcount}L=$value";
	}
	elsif ($value =~ m/^\s+|\s+$/sxm) {
		$propstring = "$key:=$value";
	}
	else {
		$propstring = "$key=$value";
	}
	return $propstring;
}

sub saveProperties { my ($file, $hashref, $comment) = @_ ;
    my $ret     = 0;
    if (open(my $fh, '>', $file)) {
        if (defined($comment)) {
            print $fh "# $comment\n";
        }
        foreach my $key (sort keys %{$hashref}) {
			my $propstring = _getPropString($key, $hashref->{$key});
            print $fh "$propstring\n";
        }
		close($fh);
		$ret = 1;
    }
    else {
        $log->error("unable to open $file $OS_ERROR");
    }
    return $ret;
}

sub _findConfig {
    if (defined( $ENV{'SWAMP_CONFIG'})) {
        return $ENV{'SWAMP_CONFIG'};
    }
    elsif (-r 'swamp.conf') {
        return 'swamp.conf';
    }
    elsif ($DEFAULT_CONFIG && -r $DEFAULT_CONFIG) {
        return $DEFAULT_CONFIG;
    }
    elsif (-r getSwampDir() . '/etc/swamp.conf') {
        return getSwampDir() . '/etc/swamp.conf';
    }
    elsif (-r '../../deployment/swamp/config/swamp.conf') {
        return '../../deployment/swamp/config/swamp.conf';
    }
    return;
}

sub isSwampInABox { my ($config) = @_ ;
	return 0 if (! $config);
	if ($config->get('SWAMP-in-a-Box') || '' =~ m/yes/sxmi) {
		return 1;
	}
    return 0;
}

sub getSwampConfig { my ($configfile) = @_ ;
	$configfile ||= _findConfig();
    if (defined($configfile)) {
        return loadProperties($configfile);
    }
	$log->error('getSwampConfig - config file: ', $configfile || '', ' not found');
    return;
}

sub _findLog4perlConfig {
    if ( -r 'log4perl.conf' ) {
        return 'log4perl.conf';
    }
    elsif ( -r '/opt/swamp/etc/log4perl.conf' ) {
        return '/opt/swamp/etc/log4perl.conf';
    }
    elsif ( -r '../../deployment/swamp/config/log4perl.conf' ) {
        return '../../deployment/swamp/config/log4perl.conf';
    }
    return;
}

sub getLoggingConfigString {

    #
    # Load from a config file, if we can find one.
    #
    my $configFile = _findLog4perlConfig();

    if (defined $configFile) {
        return $configFile;
    }

    #
    # Otherwise, return a hard-coded configuration.
    #
    my $config = {
    	'log4perl.rootLogger'   => 'ERROR, LOGFILE',
    	'log4perl.appender.LOGFILE' => 'Log::Log4perl::Appender::File',
    	'log4perl.appender.LOGFILE.filename' => catfile(getSwampDir(), 'log', 'noconfig.log'),
    	'log4perl.appender.LOGFILE.layout' => 'Log::Log4perl::Layout::SimpleLayout',
	};
    return $config;
}

sub buildExecRunAppenderLogFileName { my ($execrunuid) = @_ ;
	my $name = catfile(getSwampDir(), 'log', $execrunuid . '.log');
	return $name;
}

sub switchExecRunAppenderLogFile { my ($execrunuid) = @_ ;
    $global_swamp_config ||= getSwampConfig();
    # A unified a-run log isn't helpful with multi-server setups.
    # For example, it will clutter the log directory on the data server.
	if (isSwampInABox($global_swamp_config)) {
		my $file_appender = Log::Log4perl::appender_by_name('Logfile');
		my $name = buildExecRunAppenderLogFileName($execrunuid);
		$file_appender->file_switch($name);
	}
}

sub systemcall { my ($command, $silent) = @_;
    my $handler = $SIG{'CHLD'};
    local $SIG{'CHLD'} = 'DEFAULT';
    my ($output, $status) = ($_ = qx{$command 2>&1}, $CHILD_ERROR >> 8);
    local $SIG{'CHLD'} = $handler;
    if ($status) {
		if (! $silent) {
        	my $msg = "$command failed with status $status";
        	if (defined($output)) {
            	$msg .= " output: ($output)";
        	}
			$log->error("systemcall - error: $msg");
		}
    }
	$output = '' if (! defined($output));
    return ($output, $status);
}

sub masternameToPlatform { my ($qcow_name) = @_ ;
	if (! $qcow_name) {
		$log->error("No qcow file name specified");
		return '';
	}
	my $platform = basename($qcow_name);
	$platform =~ s/^condor-//;
	$platform =~ s/-master-\d+.qcow2$//;
	# my ($vendor, $release, $bits) = split /\-/, $platform;
	# my ($major, $minor) = split /\./, $release;
	# $platform = $vendor || '';
	# $platform .= '-' . $major if ($major);
	# $platform .= '.' . $minor if ($minor);
	# $platform .= '-' . $bits if ($bits);
	if (! $platform) {
		$log->error("Could not translate $qcow_name to platform");
		return '';
	}
	return $platform;
}

sub displaynameToMastername { my ($platform) = @_ ;
	if (! $platform) {
		$log->error("No platform specified");
		return '';
	}
	$log->trace("displaynameToMastername - platform: $platform");
	$platform =~ s/\.minorversion\-/\.\*\-/;
	my $findcmd = "find $MASTER_IMAGE_PATH -maxdepth 1 -name \"*$platform*\"";
	$log->trace("displaynameToMastername - find command: $findcmd");
    my ($output, $status) = systemcall($findcmd);
    if ($status) {
        $log->error("Cannot find images in: $MASTER_IMAGE_PATH for: $platform");
        return '';
    }
    my @files = split "\n", $output;
    my $latest_timestamp = 0;
    my $imagename = '';
    foreach my $file (@files) {
        if ($file =~ m/^${MASTER_IMAGE_PATH}condor-$platform-master-(.*).qcow2$/mxs) {
            my $timestamp = $1;
            if ($timestamp > $latest_timestamp) {
                $imagename = $file;
                $latest_timestamp = $timestamp;
            }
        }
    }
	if (! $imagename) {
		$log->error("Cannot find image for: $platform");
		return '';
	}
    return $imagename;
}

sub _handleRHEL6 { my ($opts) = @_;
    my $osimage  = $opts->{'osimage'};
    my $script   = $opts->{'script'};
    my $runshcmd = $opts->{'runcmd'};
    my $vmhostname   = $opts->{'vmhostname'};
    my $ostype   = 'unknown';
    if ( $osimage =~ /rhel.*-6..-32/mxs ) {
        $ostype = 'RHEL6.4 32 bit';
    }
    elsif ( $osimage =~ /rhel.*-6..-64/mxs || $osimage =~ /centos/mxs ) {
        $ostype = 'RHEL6.4 64 bit';
    }
    print $script "write /etc/sysconfig/network \"HOSTNAME=$vmhostname\\nNETWORKING=yes\\n\"\n";
    print $script
"write /etc/sysconfig/network-scripts/ifcfg-eth0 \"DHCP_HOSTNAME=$vmhostname\\nBOOTPROTO=dhcp\\nONBOOT=yes\\nDEVICE=eth0\\nTYPE=Ethernet\\n\"\n";
    print $script "rm-rf /etc/udev/rules.d/70-persistent-net.rules\n";
    print $script "write /etc/rc3.d/S99runsh $runshcmd\n";
    print $script "chmod 0777 /etc/rc3.d/S99runsh\n";
    return $ostype;
}

sub _handleDebian { my ($opts) = @_;
    my $osimage  = $opts->{'osimage'};
    my $script   = $opts->{'script'};
    my $runshcmd = $opts->{'runcmd'};
    my $vmhostname   = $opts->{'vmhostname'};
    my $ostype   = 'Debian';

    # Debian hostname should not have FQDN
    print $script "write /etc/hostname \"${vmhostname}\\n\"\n";

    # Debian has the funky script order .files that need to be modified
    # so for now, just stuff this in rc.local
    print $script "write /etc/rc.local $runshcmd\n";
    return $ostype;
}

sub _handleUbuntu { my ($opts) = @_;
    my $osimage  = $opts->{'osimage'};
    my $script   = $opts->{'script'};
    my $runshcmd = $opts->{'runcmd'};
    my $vmhostname   = $opts->{'vmhostname'};
    my $ostype   = 'Ubuntu';

    #Ubuntu hostname should not have FQDN
    print $script "write /etc/hostname \"${vmhostname}\\n\"\n";
    print $script "write /etc/rc2.d/S99runsh $runshcmd\n";
    print $script "chmod 0777 /etc/rc2.d/S99runsh\n";
    return $ostype;
}

sub _handleScientific { my ($opts) = @_;
    my $osimage  = $opts->{'osimage'};
    my $script   = $opts->{'script'};
    my $runshcmd = $opts->{'runcmd'};
    my $vmhostname   = $opts->{'vmhostname'};
    my $ostype   = 'Scientific';
    if ( $osimage =~ /scientific-5/mxs ) {
        $ostype = 'Scientific 5.9';
    }
    elsif ( $osimage =~ /scientific-6/mxs ) {
        $ostype = 'Scientific 6.4';
    }
    print $script "write /etc/sysconfig/network \"HOSTNAME=$vmhostname\\nNETWORKING=yes\\n\"\n";
    print $script
"write /etc/sysconfig/network-scripts/ifcfg-eth0 \"DHCP_HOSTNAME=$vmhostname\\nBOOTPROTO=dhcp\\nONBOOT=yes\\nDEVICE=eth0\\nTYPE=Ethernet\\n\"\n";
    print $script "rm-rf /etc/udev/rules.d/70-persistent-net.rules\n";
    print $script "write /etc/rc3.d/S99runsh $runshcmd\n";
    print $script "chmod 0777 /etc/rc3.d/S99runsh\n";

    return $ostype;
}

sub _handleFedora { my ($opts) = @_;
    my $osimage  = $opts->{'osimage'};
    my $script   = $opts->{'script'};
    my $runshcmd = $opts->{'runcmd'};
    my $vmhostname   = $opts->{'vmhostname'};
    my $ostype   = 'Fedora';
    print $script "write /etc/hostname \"${vmhostname}.vm.cosalab.org\\n\"\n";
    print $script "write /etc/rc.d/rc.local $runshcmd\n";
    print $script "chmod 0777 /etc/rc.d/rc.local\n";

    return $ostype;
}

sub _handleWindows {
    return 'Windows7';
}

my %os_init = (
    'rhel'			=> \&_handleRHEL6,
    'centos'     	=> \&_handleRHEL6,
    'ubuntu'     	=> \&_handleUbuntu,
    'debian'     	=> \&_handleDebian,
    'fedora'     	=> \&_handleFedora,
    'scientific' 	=> \&_handleScientific,
    'windows-7'  	=> \&_handleWindows,
);

sub insertIntoInit { my ($osimage, $script, $runshcmd, $vmhostname, $imagename) = @_ ;
    my $ostype    = 'unknown';
    my $ret       = 1;
    foreach my $key (keys %os_init) {
        if (lc $osimage =~ /$key/sxm) {
            $ostype = $os_init{$key}->( { 'osimage' => $osimage, 'script'  => $script, 'runcmd'  => $runshcmd, 'vmhostname'  => $vmhostname });
            $ret = 0;
            last;
        }
    }
    if ($ret == 1) {
        $log->error("insertIntoInit - Unrecognized image platform type using \"$imagename\"");
    }
    return ($ostype, $ret);
}

#########################
#	Launch Pad Client	#
#########################

my $launchpadUri;
my $launchpadClient;

sub _configureLaunchPadClient {
	$global_swamp_config ||= getSwampConfig();
	my $host = $global_swamp_config->get('agentMonitorHost');
	my $port = $global_swamp_config->get('agentMonitorPort');
    my $uri = "http://$host:$port";
    undef $launchpadClient;
    return $uri;
}

#########################
#	Launch Pad Start	#
#########################

sub launchPadStart { my ($options)    = @_ ;
    my $req = RPC::XML::request->new('swamp.launchPad.start', RPC::XML::struct->new($options));
	$launchpadUri ||= _configureLaunchPadClient();
	$launchpadClient ||= RPC::XML::Client->new($launchpadUri);
    my $result = rpccall($launchpadClient, $req);
	if ($result->{'error'}) {
		$log->error("launchPadStart failed - error: ", sub { use Data::Dumper; Dumper($result->{'error'}); });
		return $LAUNCHPAD_FATAL_ERROR;
	}
	my $status = $LAUNCHPAD_FATAL_ERROR;
	$status = $result->{'value'} if (defined($result->{'value'}));
	return $status;
}

#########################
#	Launch Pad Kill		#
#########################

sub launchPadKill { my ($execrunuid, $jobid)    = @_ ;
    my $req = RPC::XML::request->new('swamp.launchPad.kill', RPC::XML::string->new($execrunuid), RPC::XML::string->new($jobid));
	$launchpadUri ||= _configureLaunchPadClient();
	$launchpadClient ||= RPC::XML::Client->new($launchpadUri);
    my $result = rpccall($launchpadClient, $req);
	if ($result->{'error'}) {
		$log->error("launchPadKill failed - error: ", sub { use Data::Dumper; Dumper($result->{'error'}); });
		return $LAUNCHPAD_FATAL_ERROR;
	}
	my $status = $LAUNCHPAD_FATAL_ERROR;
	$status = $result->{'value'} if (defined($result->{'value'}));
	return $status;
}

#####################
#	Agent Client	#
#####################

my $agentUri;
my $agentClient;

sub _configureAgentClient {
	$global_swamp_config ||= getSwampConfig();
	my $host = $global_swamp_config->get('agentMonitorHost');
	my $port = $global_swamp_config->get('agentMonitorJobPort');
    my $uri = "http://$host:$port";
    undef $agentClient;
    return $uri;
}

#############################
#	Database Connectivity	#
#############################

sub database_connect {
	$global_swamp_config ||= getSwampConfig();
	my $dsnHost = $global_swamp_config->get('dbPerlDsnHost');
	my $dsnPort = $global_swamp_config->get('dbPerlDsnPort');
	my $dsn = "DBI:mysql:host=$dsnHost;port=$dsnPort";
	my $user = $global_swamp_config->get('dbPerlUser');
	my $password = $global_swamp_config->get('dbPerlPass');
	my $dbh = DBI->connect($dsn, $user, $password, {PrintError => 0, RaiseError => 0});
	if ($DBI::err) {
		$log->error("database_connect failed: $DBI::err error: ", $DBI::errstr);
	}
	return $dbh;
}

sub database_disconnect { my ($dbh) = @_ ;
	$dbh->disconnect();
}

#####################
#	Delete Job Dir	#
#####################

sub deleteJobDir { my ($execrunuid, $clusterid, $procid) = @_ ;
	my $options = {};
	$options->{'execrunuid'} = $execrunuid;
	$options->{'clusterid'} = $clusterid;
	$options->{'procid'} = $procid;
    my $req = RPC::XML::request->new('agentMonitor.deleteJobDir', RPC::XML::struct->new($options));
	$agentUri ||= _configureAgentClient();
	$agentClient ||= RPC::XML::Client->new($agentUri);
	my $result = rpccall($agentClient, $req);
    if ($result->{'error'}) {
        $log->error("deleteJobDir with $execrunuid error: $result->{'error'}");
        return 0;
    }
	my $delete_count = $result->{'value'} || 0;
	return $delete_count;
}

1;
