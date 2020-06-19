# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

package SWAMP::vmu_ViewerSupport;
use strict;
use warnings;
use English '-no_match_vars';
use RPC::XML;
use RPC::XML::Client;
use Log::Log4perl;
use File::Copy qw(move copy);
use File::Basename qw(basename);
use File::Spec::Functions;
use POSIX qw(strftime);
use SWAMP::vmu_Support qw(
	use_make_path
	isSwampInABox
	systemcall 
	getSwampDir 
	checksumFile 
	rpccall
	job_database_connect
	job_database_disconnect
	getSwampConfig 
	$global_swamp_config
	$HTCONDOR_JOB_INPUT_DIR
	$HTCONDOR_JOB_OUTPUT_DIR
	$HTCONDOR_JOB_INPUT_MOUNT
	$HTCONDOR_JOB_OUTPUT_MOUNT
	$HTCONDOR_JOB_IP_ADDRESS_FILE
	$HTCONDOR_JOB_EVENTS_FILE
	$HTCONDOR_JOB_IP_ADDRESS_TTY
	$HTCONDOR_JOB_EVENTS_TTY
);

use parent qw(Exporter);
our (@EXPORT_OK);
BEGIN {
    require Exporter;
    @EXPORT_OK = qw(
		$VIEWER_STATE_NO_RECORD
		$VIEWER_STATE_LAUNCHING
		$VIEWER_STATE_READY
		$VIEWER_STATE_STOPPING
		$VIEWER_STATE_SHUTDOWN
		$VIEWER_STATE_ERROR
		$VIEWER_STATE_TERMINATING
		$VIEWER_STATE_TERMINATED
		$VIEWER_STATE_TERMINATE_FAILED
		createvrunscript
		copyvruninputs
		copyuserdatabase
		getViewerVersion
		saveViewerDatabase
		updateClassAdViewerStatus
		getViewerStateFromClassAd
		launchViewer
		identifyViewer
    );
}

my $log = Log::Log4perl->get_logger(q{});
my $tracelog = Log::Log4perl->get_logger('runtrace');

sub identifyViewer { my ($bogref) = @_ ;
	$log->info('Execrunuid: ', $bogref->{'execrunid'}, "\n",
		'  Platform: ', $bogref->{'platform_identifier'}, "\n",
		'  Type: ', $bogref->{'platform_type'}, "\n",
		'  Image: ', $bogref->{'platform_image'}
	);
}

#########################
#	HTCondor ClassAd	#
#########################

# terminal states
our $VIEWER_STATE_NO_RECORD			= 0;
our $VIEWER_STATE_READY				= 2;
our $VIEWER_STATE_SHUTDOWN			= -3;
our $VIEWER_STATE_ERROR				= -5;
our $VIEWER_STATE_TERMINATED		= -7;
our $VIEWER_STATE_TERMINATE_FAILED	= -8;

# progress states
our $VIEWER_STATE_LAUNCHING 		= 1;
our $VIEWER_STATE_STOPPING			= -1;
our $VIEWER_STATE_TERMINATING		= -6;

sub updateClassAdViewerStatus { my ($execrunuid, $state, $status, $options) = @_ ;
	my $vmhostname = $options->{'vmhostname'} || 'null';
	my $viewer = $options->{'viewer'} || 'null';
	my $vmip = $options->{'vmip'} || 'null';
	my $apikey = $options->{'apikey'} || 'null';
	my $user_uuid = $options->{'userid'} || 'null';
	my $projectid = $options->{'projectid'} || 'null';
	my $viewer_instance_uuid = $options->{'viewer_uuid'} || 'null';
	my $viewer_url_uuid = $options->{'urluuid'} || 'null';
	my $poolarg = q();
	$global_swamp_config ||= getSwampConfig();
	if (! isSwampInABox($global_swamp_config)) {
		my $HTCONDOR_COLLECTOR_HOST = $global_swamp_config->get('htcondor_collector_host');
		$poolarg = qq(-pool $HTCONDOR_COLLECTOR_HOST);
	}
	$log->info("updateClassAdViewerStatus - $poolarg execrunuid: $execrunuid state: $state status: $status");
	$log->debug("updateClassAdViewerStatus - options: ", sub { use Data::Dumper; Dumper($options); });
    my ($output, $stat) = systemcall("condor_advertise $poolarg UPDATE_AD_GENERIC - <<'EOF'
MyType=\"Generic\"
Name=\"$execrunuid\"
SWAMP_vmu_viewer_vmhostname=\"$vmhostname\"
SWAMP_vmu_viewer_state=\"$state\"
SWAMP_vmu_viewer_status=\"$status\"
SWAMP_vmu_viewer_name=\"$viewer\"
SWAMP_vmu_viewer_vmip=\"$vmip\"
SWAMP_vmu_viewer_apikey=\"$apikey\"
SWAMP_vmu_viewer_user_uuid=\"$user_uuid\"
SWAMP_vmu_viewer_projectid=\"$projectid\"
SWAMP_vmu_viewer_instance_uuid=\"$viewer_instance_uuid\"
SWAMP_vmu_viewer_url_uuid=\"$viewer_url_uuid\"
EOF
");
	if ($stat) {
		$log->error("Error - condor_advertise returns: $stat [$output]");
	}
}

sub getViewerStateFromClassAd { my ($project_uuid, $viewer_name) = @_ ;
	my $poolarg = q();
	$global_swamp_config ||= getSwampConfig();
	if (! isSwampInABox($global_swamp_config)) {
    	my $HTCONDOR_COLLECTOR_HOST = $global_swamp_config->get('htcondor_collector_host');
		$poolarg = qq(-pool $HTCONDOR_COLLECTOR_HOST);
	}
    my $command = qq{condor_status $poolarg -any -af:V, Name SWAMP_vmu_viewer_state SWAMP_vmu_viewer_status SWAMP_vmu_viewer_name SWAMP_vmu_viewer_vmip SWAMP_vmu_viewer_apikey SWAMP_vmu_user_uuid SWAMP_vmu_viewer_projectid SWAMP_vmu_viewer_instance_uuid SWAMP_vmu_viewer_url_uuid -constraint \"isString(SWAMP_vmu_viewer_status)\"};
    my ($output, $status) = systemcall($command);
    if ($status) { 
        my $error_message = "<$command> failed - $status $output";
        $log->error($error_message);
        return {'error' => $error_message};
    }
    if (! $output) {
        return {'state' => $VIEWER_STATE_NO_RECORD};
    }
	$log->debug("project_uuid: $project_uuid viewer_name: $viewer_name output: $output");
	my @lines = split "\n", $output;
	foreach my $line (@lines) {
    	my @parts = split ',', $line;
    	s/\"//g for @parts;
    	s/^\s+//g for @parts;
    	s/\s+$//g for @parts;
    	my ($execrunuid, $state, $vstatus, $viewer, $vmip, $apikey, $user_uuid, $projectid, $viewer_instance_uuid, $viewer_url_uuid) = @parts;
    	if (($projectid eq $project_uuid) && ($viewer eq $viewer_name)) {
			if ($vstatus eq 'Viewer is up') {
        		return {
            		'state'     => $state,
            		'address'   => $vmip,
            		'apikey'    => $apikey,
            		'urluuid'   => $viewer_url_uuid,
        		};
    		}
			return {'state' => $state};
		}
	}
	return {'state' => $VIEWER_STATE_NO_RECORD};
}

#############################
#	Create Run.sh Script	#
#############################

sub _set_var { my ($name, $value, $file) = @_ ;
    my ($output, $status) = systemcall("echo $name=\"$value\" >> $file");
	if ($status) {
        $log->error("Cannot set $name=\"$value\" in: $file $OS_ERROR");
		return 0;
	}
	return 1;
}

sub _set_env_var { my ($name, $value, $file) = @_ ;
	my $retval = _set_var('export ' . $name, $value, $file);
	return $retval;
}

#	Common Files
#	vrunchecktimeout
#	checktimeout.pl
#	swamp-shutdown-service

sub createvrunscript { my ($bogref, $dest) = @_ ;
    my $ret    = 1;
	$global_swamp_config ||= getSwampConfig();
    my $basedir = getSwampDir();

	my $CHECKTIMEOUT_FREQUENCY = $global_swamp_config->get('vruntimeout_frequency') // '10';
	my $CHECKTIMEOUT_DURATION = $global_swamp_config->get('vruntimeout_duration') // '28800';
	my $CHECKTIMEOUT_LASTLOG = $global_swamp_config->get('vruntimeout_lastlog') // '3600'; 

	# initialize values for vm universe
	# specify the run.sh template for vm universe
	my $vrunsh = "$basedir/thirdparty/codedx/swamp/vmu_vrun_nobake.sh";
	if ($bogref->{'use_baked_viewer'}) {
		$vrunsh = "$basedir/thirdparty/codedx/swamp/vmu_vrun.sh";
	}
	# specify the run-params.sh script location for setting up environment
	my $runparamssh = catfile($dest, 'run-params.sh');
	my $JOB_INPUT_DIR = $HTCONDOR_JOB_INPUT_MOUNT;
	my $JOB_OUTPUT_DIR = $HTCONDOR_JOB_OUTPUT_MOUNT;
	my $SWAMP_EVENT_FILE = $HTCONDOR_JOB_EVENTS_TTY;
	my $IP_ADDR_FILE = $HTCONDOR_JOB_IP_ADDRESS_TTY;
	my $MACHINE_SHUTDOWN_COMMAND = "'/sbin/shutdown -h now'";

	# initialize for docker universe
	if ($bogref->{'use_docker_universe'}) {
		# specify the run.sh template for docker universe
		$vrunsh = "$basedir/thirdparty/codedx/swamp/docker_vrun_nobake.sh";
		if ($bogref->{'use_baked_viewer'}) {
			$vrunsh = "$basedir/thirdparty/codedx/swamp/docker_vrun.sh";
		}
		# specify the run-params.sh script location for setting up environment
		$runparamssh = 'run-params.sh';
		$JOB_INPUT_DIR = catfile('$_CONDOR_SCRATCH_DIR', $HTCONDOR_JOB_INPUT_DIR);
		$JOB_OUTPUT_DIR = catfile('$_CONDOR_SCRATCH_DIR', $HTCONDOR_JOB_OUTPUT_DIR);
		$SWAMP_EVENT_FILE = catfile($JOB_OUTPUT_DIR, $HTCONDOR_JOB_EVENTS_FILE);
		$IP_ADDR_FILE = catfile($JOB_OUTPUT_DIR, $HTCONDOR_JOB_IP_ADDRESS_FILE);
		$MACHINE_SHUTDOWN_COMMAND = "'supervisorctl shutdown'";
	}

	# generic values
	my $SWAMP_LOG_FILE = catfile($JOB_OUTPUT_DIR, 'run.out');
	my $TOMCAT_LOG_DIR = '/opt/tomcat/logs';
	my $SKIPPED_BUNDLE = catfile($JOB_OUTPUT_DIR, 'skippedbundle');
	my $VIEWER_STARTEPOCH_FILE = catfile($JOB_OUTPUT_DIR, 'run.epoch');

	# set environment variables in $runparamssh
	$ret = 0 if (! _set_env_var('PROJECT', $bogref->{'urluuid'}, $runparamssh));
	$ret = 0 if (! _set_env_var('APIKEY', $bogref->{'apikey'}, $runparamssh));
	$ret = 0 if (! _set_env_var('JOB_INPUT_DIR', $JOB_INPUT_DIR, $runparamssh));
	$ret = 0 if (! _set_env_var('JOB_OUTPUT_DIR', $JOB_OUTPUT_DIR, $runparamssh));
	$ret = 0 if (! _set_env_var('SWAMP_EVENT_FILE', $SWAMP_EVENT_FILE, $runparamssh));
	$ret = 0 if (! _set_env_var('IP_ADDR_FILE', $IP_ADDR_FILE, $runparamssh));

	$ret = 0 if (! _set_env_var('SWAMP_LOG_FILE', $SWAMP_LOG_FILE, $runparamssh));
	$ret = 0 if (! _set_env_var('TOMCAT_LOG_DIR', $TOMCAT_LOG_DIR, $runparamssh));
	$ret = 0 if (! _set_env_var('SKIPPED_BUNDLE', $SKIPPED_BUNDLE, $runparamssh));

    $ret = 0 if (! _set_env_var('VIEWER', $bogref->{'viewer'}, $runparamssh));

    $ret = 0 if (! _set_env_var('VIEWER_STARTEPOCH_FILE', $VIEWER_STARTEPOCH_FILE, $runparamssh));
	$ret = 0 if (! _set_env_var('CHECKTIMEOUT_FREQUENCY', $CHECKTIMEOUT_FREQUENCY, $runparamssh));
    $ret = 0 if (! _set_env_var('CHECKTIMEOUT_DURATION', $CHECKTIMEOUT_DURATION, $runparamssh));
    $ret = 0 if (! _set_env_var('CHECKTIMEOUT_LASTLOG', $CHECKTIMEOUT_LASTLOG, $runparamssh));
    $ret = 0 if (! _set_env_var('MACHINE_SHUTDOWN_COMMAND', $MACHINE_SHUTDOWN_COMMAND, $runparamssh));

	# run.sh, checketimeout* and docker-viewer-management-service are already in the baked viewer
	return $ret if ($bogref->{'use_baked_viewer'});

	# copy run.sh to input directory run.sh
	my $inputvrunsh = catfile($dest, "run.sh");
	if (! copy($vrunsh, $inputvrunsh)) {
		$log->error("Cannot add $vrunsh to $inputvrunsh $OS_ERROR");
		$ret = 0;
	}
	chmod 0755, $inputvrunsh;

	# copy vrunchecktimeout to input directory
	my $file = "$basedir/thirdparty/common/checktimeout";
	if (! copy($file, $dest)) {
		$log->error("Cannot copy $file to $dest $OS_ERROR");
		$ret = 0;
	}

	# copy checktimeout.pl to input directory
	$file = "$basedir/thirdparty/common/checktimeout.pl";
	if (! copy($file, $dest)) {
		$log->error("Cannot copy $file to $dest $OS_ERROR");
		$ret = 0;
	}
	
	# copy swamp-shutdown-service to input directory
	$file = "$basedir/thirdparty/common/swamp-shutdown-service";
	if (! copy($file, $dest)) {
		$log->error("Cannot copy $file to $dest $OS_ERROR");
		$ret = 0;
	}

    return $ret;
}

#########################
#	Copy Vrun Inputs	#
#########################

#	CodeDX Files
#	codedx.war
#	emptydb-codedx.sql
#	flushprivs.sql
#	resetdb-codedx.sql
#	emptydb-mysql-codedx.sql
#	swamp-codedx-service
#	checktimeout.pl
#	logback.xml
#	codedx.props

sub copyvruninputs { my ($bogref, $dest) = @_ ;
	my $ret = 1;
	my $basedir = getSwampDir();
	# copy codedx.war to input directory
	my $file = "$basedir/thirdparty/codedx/vendor/codedx.war";
	if (! copy($file, $dest)) {
		$log->error("Cannot copy $file to $dest $OS_ERROR");
		$ret = 0;
	}
	# copy empty codedx database sql script to input directory
	$file = "$basedir/thirdparty/codedx/swamp/emptydb-codedx.sql";
	if (! copy($file, $dest)) {
		$log->error("Cannot copy $file to $dest $OS_ERROR");
		$ret = 0;
	}
	# copy empty mysql database sql script to input directory
	$file = "$basedir/thirdparty/codedx/swamp/emptydb-mysql-codedx.sql";
	if (! copy($file, $dest)) {
		$log->error("Cannot copy $file to $dest $OS_ERROR");
		$ret = 0;
	}
	# copy flushprivs.sql to input directory
	$file = "$basedir/thirdparty/common/flushprivs.sql";
	if (! copy($file, $dest)) {
		$log->error("Cannot copy $file to $dest $OS_ERROR");
		$ret = 0;
	}
	# copy resetdb-codedx.sql to input directory
	$file = "$basedir/thirdparty/codedx/swamp/resetdb-codedx.sql";
	if (! copy($file, $dest)) {
		$log->error("Cannot copy $file to $dest $OS_ERROR");
		$ret = 0;
	}
	
	# copy codedx_backup_viewerdb.sh to backup_viewerdb.sh
	my $codedx_viewerdbsh = "$basedir/thirdparty/codedx/swamp/codedx_viewerdb.sh";
	my $inputbackup_viewerdbsh = "${dest}/backup_viewerdb.sh";
	if (! copy($codedx_viewerdbsh, $inputbackup_viewerdbsh)) {
		$log->error("Cannot copy $codedx_viewerdbsh to $inputbackup_viewerdbsh $OS_ERROR");
		$ret = 0;
	}
	
	# copy logback.xml to input directory
	$file = "$basedir/thirdparty/codedx/swamp/logback.xml";
	if (! copy($file, $dest)) {
		$log->error("Cannot copy $file to $dest $OS_ERROR");
		$ret = 0;
	}
	# copy codedx.props to input directory
	# set swa.admin.system-key in codedx.props
	my $codedxprops = "$basedir/thirdparty/codedx/swamp/codedx.props";
	my $inputcodedxprops = "${dest}/codedx.props";
	if (! copy($codedxprops, $inputcodedxprops)) {
		$log->error("Cannot copy $codedxprops to $inputcodedxprops $OS_ERROR");
		$ret = 0;
	}
	$ret = 0 if (! _set_var('swa.admin.system-key', $bogref->{'apikey'}, $inputcodedxprops));
	
    return $ret;
}

#	codedx_viewerdb.tar.gz

sub copyuserdatabase { my ($bogref, $dest) = @_ ;
    # It is OK to not specify a db_path, this just means it has never been persisted
	my $ret = 1;
	my $db_path = $bogref->{'db_path'};
    if (defined($db_path)) {
		$log->info("copyuserdatabase - user database: $db_path");
		if (! -r $db_path) {
			$log->error("copyuserdatabase - file: $db_path not found or not readable");
			$ret = 0;
		}
		else {
			my ($output, $status, $error_output) = systemcall("tar -C $dest -xzf $db_path");
			if ($status) {
				$log->error("copyuserdatabase - untar failed: $db_path to $dest output: <$output> error: <$error_output>");
				$ret = 0;
			}
			else {
				$log->info("copyuserdatabase - untar succeeded: $db_path to $dest");
			}
		}
    }
	else {
		$log->info("copyuserdatabase - no user database specified");
	}
	return $ret;
}

#####################
#	Agent Client	#
#####################

my $agentUri;
my $agentClient;

sub _configureAgentClient {
	$global_swamp_config ||= getSwampConfig();
	my $host = $global_swamp_config->get('agentMonitorHost');
	my $port = $global_swamp_config->get('agentMonitorPort');
    my $uri = "http://$host:$port";
    undef $agentClient;
    return $uri;
}

#####################
#	Launch Viewer	#
#####################

sub launchViewer { my ($options) = @_ ;
    my $req = RPC::XML::request->new('agentMonitor.launchViewer', RPC::XML::struct->new($options));
	$agentUri ||= _configureAgentClient();
	$agentClient ||= RPC::XML::Client->new($agentUri);
    my $result = rpccall($agentClient, $req);
	if ($result->{'error'}) {
		$log->error("launchViewer failed - error: ", sub { use Data::Dumper; Dumper($result->{'error'}); });
	}
    return $result->{'value'};
}

sub getViewerVersion { my ($bogref) = @_ ;
	my $viewerversion = 'unknown';
	my $codedx_properties = 'WEB-INF/classes/version.properties';
	my $basedir = getSwampDir();
	my $war_file;
	if ($bogref->{'viewer'} eq 'CodeDX') {
		$war_file = "$basedir/thirdparty/codedx/vendor/codedx.war";
	}
	return $viewerversion if (! $war_file || ! -r $war_file);
	my $command = "unzip -p $war_file $codedx_properties | grep 'version'";
    my ($output, $status) = systemcall($command);
	if ($status) {
		$log->error("getViewerVersion <$command> failed - $status $output");
		return $viewerversion;
	}
	$viewerversion = $output;
	chomp $viewerversion;
	$viewerversion =~ s/\s*version\s*=\s*//;
	$viewerversion = 'codedx-' . $viewerversion . '.war';
	return $viewerversion;
}

#############################
#	Save Viewer Database	#
#############################

sub saveViewerDatabase { my ($bogref, $vmhostname, $outputfolder) = @_ ;
	my $basedir = getSwampDir();

	my $datestamp = sprintf(strftime('%Y%m%d%H%M%S', localtime(time())));
	my $savedbname = q{codedx_viewerdb.tar.gz};
	my $stampeddbname = qq{codedx_viewerdb_$datestamp.tar.gz};
    my $savedbfile = "$outputfolder/$savedbname";
	if (! -r $savedbfile) {
		$log->error("File: $savedbfile not found");
		return 0;
	}
	my $viewerdbfolder = catdir(rootdir(), 'swamp', 'SCAProjects', $bogref->{'projectid'}, 'V-Runs', $bogref->{'viewer_uuid'});
	my $viewerdbpath = catfile($viewerdbfolder, $stampeddbname);
	if (! use_make_path($viewerdbfolder)) {
        $log->error("Error - make_path $viewerdbfolder failed");
		# this is a fatal error and store_viewer is not invoked
		return 0;
	}
    if (! copy($savedbfile, $viewerdbpath)) {
        $log->error("Error - Copy $savedbfile to $viewerdbpath failed: $OS_ERROR");
		# this is a fatal error and store_viewer is not invoked
		return 0;
    }
	$log->info("Copied: $savedbfile to: $viewerdbpath");
	$log->debug("saveViewerDatabase - BOG: ", sub { use Data::Dumper; Dumper($bogref); });
	my $viewerdbchecksum = checksumFile($viewerdbpath);
	my $viewerinstanceuuid = $bogref->{'viewer_uuid'};
	my $viewerplatform = $bogref->{'viewerplatform'};
	my $viewerversion = $bogref->{'viewerversion'};
	$log->info("saveViewerDatabase - calling store_viewer with: $viewerinstanceuuid $viewerdbpath $viewerdbchecksum $viewerplatform $viewerversion");
	if (my $dbh = job_database_connect()) {
		# viewer_instance_uuid_in
		# viewer_db_path_in
		# viewer_db_checksum_in
		# platform_image_in
		# viewer_version_in
		# return_string
		my $query = q{CALL viewer_store.store_viewer(?, ?, ?, ?, ?, @r);};
		my $sth = $dbh->prepare($query);
		$sth->bind_param(1, $viewerinstanceuuid);
		$sth->bind_param(2, $viewerdbpath);
		$sth->bind_param(3, $viewerdbchecksum);
		$sth->bind_param(4, $viewerplatform);
		$sth->bind_param(5, $viewerversion);
		$sth->execute();
		my $result;
		if (! $sth->err) {
			$result = $dbh->selectrow_array('SELECT @r');
		}
		job_database_disconnect($dbh);
		if (! $result || ($result ne 'SUCCESS')) {
			$log->error("saveViewerDatabase - error: $result");
			return 0;
		}
		$log->info("saveViewerDatabase - store_viewer returns: $result");
	}
	else {
        $log->error("saveViewerDatabase - database connection failed");
		return 0;
	}
    return 1;
}

1;
