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
use RPC::XML;
use RPC::XML::Client;

use parent qw(Exporter);
our (@EXPORT_OK);
BEGIN {
    require Exporter;
    @EXPORT_OK = qw(
	  getStandardParameters
	  identifyScript
	  listDirectoryContents
	  HTCondorJobStatus
	  $HTCondor_No_Status
	  $HTCondor_Unexpanded
	  $HTCondor_Idle
	  $HTCondor_Running
	  $HTCondor_Removed
	  $HTCondor_Completed
	  $HTCondor_Held
	  $HTCondor_Submission_Error
	  trim
      systemcall
	  getSwampDir
      getSwampConfig
      getLoggingConfigString
      addExecRunLogAppender
      removeExecRunLogAppender
      loadProperties
	  saveProperties
	  insertIntoInit
	  displaynameToMastername
	  checksumFile
	  rpccall
	  getJobDir
	  makezip
	  getUUID
	  start_process
	  stop_process
	  deleteJobDir
	  createBOGfileName
	  construct_vmhostname
	  construct_vmdomainname
	  create_empty_file
	  isMetricRun
	  isViewerRun
    );
}

our $HTCondor_No_Status			= -1;
our $HTCondor_Unexpanded		= 0;
our $HTCondor_Idle				= 1;
our $HTCondor_Running			= 2;
our $HTCondor_Removed			= 3;
our $HTCondor_Completed			= 4;
our $HTCondor_Held				= 5;
our $HTCondor_Submission_Error	= 6;

my $DEFAULT_CONFIG = getSwampDir() . '/etc/swamp.conf';
my $MASTER_IMAGE_PATH = '/var/lib/libvirt/images/';
my $EXEC_RUN_APPENDER_NAME = 'ExecRunUUID';
my $EXEC_RUN_APPENDER_LAYOUT = Log::Log4perl::Layout::PatternLayout->new('%d: %p %P %F{1}-%L %m%n');

my $log = Log::Log4perl->get_logger(q{});
my $global_swamp_config;

sub getSwampDir {
	return "/opt/swamp";
}

sub getStandardParameters { my ($argv, $clusteridref) = @_ ;
	# execrunuid owner uiddomain clusterid procid [debug]
	my $argc = scalar(@$argv);
	return if ($argc < 5 || $argc > 6);
	my $execrunuid = $argv->[0];
	my $owner = $argv->[1];
	my $uiddomain = $argv->[2];
	$$clusteridref = $argv->[3];
	my $procid = $argv->[4];
	# debug is optional
	my $debug = $argv->[5];
	# clusterid is returned via reference because it is global
	return($execrunuid, $owner, $uiddomain, $procid, $debug);
}

sub identifyScript { my ($argv) = @_ ;
	my $cwd = getcwd();
	$log->info("$PROGRAM_NAME ($PID) argv: <", (join ',', @$argv), ">");
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

# HTCondor JobStatus
#	0	Unexpanded	U
#	1	Idle	I
#	2	Running	R
#	3	Removed	X
#	4	Completed	C
#	5	Held	H
#	6	Submission_err	E

sub HTCondorJobStatus { my ($execrunuid, $clusterid, $procid) = @_ ;
	return $HTCondor_No_Status if (! defined($clusterid));
	$procid = 0 if (! defined($procid));

	# first check condor_q for current job
	my $command = qq{condor_q $clusterid . '.' . $procid -af JobStatus};
	my ($output, $status) = systemcall($command);
	if ($status) {
		$log->error("Error - condor_q failed: $output");
		return $HTCondor_No_Status;
	}
	# test output for positive integer in range
	if ($output =~ m/^\d+$/) {
		if ($output >= $HTCondor_Unexpanded && $output <= $HTCondor_Submission_Error) {
			return $output;
		}
	}
	# test output non empty string
	$output = trim($output);
	if (length($output)) {
		$log->error("Error - condor_q failed: $output");
		return $HTCondor_No_Status;
	}

	# second check condor_history for terminated job
	$command = qq{condor_history $clusterid . '.' . $procid -af JobStatus};
	($output, $status) = systemcall($command);
	if ($status) {
		$log->error("Error - condor_history failed: $output");
		return $HTCondor_No_Status;
	}
	# test output for positive integer in range
	if ($output =~ m/^\d+$/) {
		if ($output >= $HTCondor_Unexpanded && $output <= $HTCondor_Submission_Error) {
			return $output;
		}
	}
	# status not found from condor_q nor condor_history
	return $HTCondor_No_Status;
}

sub isMetricRun { my ($execrunuid) = @_ ;
	if ($execrunuid =~ m/^M-/sxm) {
		return 1;
	}
	return 0;
}

sub isViewerRun { my ($execrunuid) = @_ ;
	if ($execrunuid =~ m/^vrun\./sxim) {
		return 1;
	}
	return 0;
}

sub trim { my ($string) = @_ ;
    $string =~ s/^\s+//sxm;
    $string =~ s/\s+$//sxm;
    return $string;
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
    if (!defined( $pid = fork())) {
        $log->warn("Unable to fork process $server: $OS_ERROR");
        return;
    }
    elsif ($pid) {
        return $pid;
    }
    else {
        exec($server);    # Need a better way to tell if this failed.
                          # If we return from the exec call, bad bad things have happened.
        exit 6;
    }
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
    if (defined(eval {$sha->addfile($filename, "pb");})) {
        return $sha->hexdigest;
    }
    else {
		$log->error("checksumFile - $filename $algorithm error");
        return 'ERROR';
    }
}

sub rpccall { my ($client, $req) = @_ ;
    if (defined($req)) {
        my $res = $client->send_request($req);
        if (ref $res) {
            if ($res->is_fault) {
                my $str = $req->as_string();
				$log->error('rpccall - error: ', sub{use Data::Dumper; Dumper($res->value);});
                return {'error' => $res->value, 'fault' => 1};
            }
            else {
                return {'value' => $res->value};
            }
        }
        else {
            my $str = $req->as_string();
			$log->error("rpccall - error: $str");
            return {'error' => 'did not get a ref back', 'text' => $str};
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
    my $config = <<'END_LOGGING_CONFIG';
log4perl.logger            = TRACE, Logfile, Screen
log4perl.category.runtrace = TRACE, RTLogfile

log4perl.appender.Logfile          = Log::Log4perl::Appender::File
log4perl.appender.Logfile.umask    = sub { 0000 };
log4perl.appender.Logfile.filename = sub { logfilename(); };
log4perl.appender.Logfile.mode     = append
log4perl.appender.Logfile.layout   = Log::Log4perl::Layout::PatternLayout
log4perl.appender.Logfile.layout.ConversionPattern = %d: %p %P %F{1}-%L %m%n

log4perl.appender.Screen           = Log::Log4perl::Appender::Screen
log4perl.appender.Screen.stderr    = 0
log4perl.appender.Screen.Threshold = TRACE
log4perl.appender.Screen.layout    = Log::Log4perl::Layout::PatternLayout
log4perl.appender.Screen.layout.ConversionPattern = %r %p %P %F{1} %M %L> %m %n

log4perl.appender.RTLogfile          = Log::Log4perl::Appender::File
log4perl.appender.RTLogfile.umask    = sub { 0000 };
log4perl.appender.RTLogfile.filename = /opt/swamp/log/runtrace.log
log4perl.appender.RTLogfile.mode     = append
log4perl.appender.RTLogfile.layout   = Log::Log4perl::Layout::PatternLayout
log4perl.appender.RTLogfile.layout.ConversionPattern = %d: %p %P %F{1}-%L %m%n
END_LOGGING_CONFIG

    return \$config;
}

sub addExecRunLogAppender { my ($exec_run_uuid) = @_;
    $global_swamp_config ||= getSwampConfig();

    # A unified a-run log isn't helpful with multi-server setups.
    # For example, it will clutter the log directory on the data server.
    if ($global_swamp_config->exists('SWAMP-in-a-Box')) {
        if ($global_swamp_config->get('SWAMP-in-a-Box') =~ /yes/sxmi) {

            # Remove an existing appender, if any.
            removeExecRunLogAppender();

            # Add the new appender.
            my $exec_run_log_file = getSwampDir() . '/log/' . $exec_run_uuid . '.log';
            my $file_appender = Log::Log4perl::Appender->new('Log::Log4perl::Appender::File',
                    name     => $EXEC_RUN_APPENDER_NAME,
                    filename => $exec_run_log_file,
                    umask    => 0000,
                    mode     => 'append');
            $file_appender->layout($EXEC_RUN_APPENDER_LAYOUT);
            $log->add_appender($file_appender);
        }
    }
}

sub removeExecRunLogAppender {
    Log::Log4perl->eradicate_appender($EXEC_RUN_APPENDER_NAME);
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

sub displaynameToMastername { my ($platform) = @_ ;
    my ($output, $status) = systemcall("find $MASTER_IMAGE_PATH -name \"*$platform*\"");
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
