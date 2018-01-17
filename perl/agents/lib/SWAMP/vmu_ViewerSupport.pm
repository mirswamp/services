# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2018 Software Assurance Marketplace

package SWAMP::vmu_ViewerSupport;
use strict;
use warnings;
use English '-no_match_vars';
use RPC::XML;
use RPC::XML::Client;
use Log::Log4perl;
use File::Path qw(make_path);
use File::Copy qw(cp);
use SWAMP::vmu_Support qw(
	systemcall 
	getSwampDir 
	getSwampConfig 
	checksumFile 
	rpccall
	database_connect
	database_disconnect
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
		$VIEWER_STATE_JOBDIR_FAILED
		$VIEWER_STATE_SHUTDOWN
		$VIEWER_STATE_TERMINATING
		$VIEWER_STATE_TERMINATED
		$VIEWER_STATE_TERMINATE_FAILED
		createrunscript
		copyvruninputs
		saveViewerDatabase
		updateClassAdViewerStatus
		getViewerStateFromClassAd
		launchViewer
    );
}

my $global_swamp_config;
my $log = Log::Log4perl->get_logger(q{});
my $tracelog = Log::Log4perl->get_logger('runtrace');

#########################
#	HTCondor ClassAd	#
#########################

our $VIEWER_STATE_NO_RECORD			= 0;
our $VIEWER_STATE_LAUNCHING 		= 1;
our $VIEWER_STATE_READY				= 2;
our $VIEWER_STATE_STOPPING			= -1;
our $VIEWER_STATE_JOBDIR_FAILED		= -2;
our $VIEWER_STATE_SHUTDOWN			= -3;
our $VIEWER_STATE_TERMINATING		= -4;
our $VIEWER_STATE_TERMINATED		= -5;
our $VIEWER_STATE_TERMINATE_FAILED	= -6;

sub updateClassAdViewerStatus { my ($execrunuid, $state, $status, $options) = @_ ;
	$global_swamp_config ||= getSwampConfig();
	my $HTCONDOR_COLLECTOR_HOST = $global_swamp_config->get('htcondor_collector_host');
	$log->info("updateClassAdViewerStatus - collector: $HTCONDOR_COLLECTOR_HOST execrunuid: $execrunuid state: $state status: $status");
	$log->debug("updateClassAdViewerStatus - options: ", sub { use Data::Dumper; Dumper($options); });
	my $vmhostname = $options->{'vmhostname'} || 'null';
	my $viewer = $options->{'viewer'} || 'null';
	my $vmip = $options->{'vmip'} || 'null';
	my $apikey = $options->{'apikey'} || 'null';
	my $user_uuid = $options->{'userid'} || 'null';
	my $projectid = $options->{'projectid'} || 'null';
	my $viewer_instance_uuid = $options->{'viewer_uuid'} || 'null';
	my $viewer_url_uuid = $options->{'urluuid'} || 'null';
    my ($output, $stat) = systemcall("condor_advertise -pool $HTCONDOR_COLLECTOR_HOST UPDATE_AD_GENERIC - <<'EOF'
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

sub getViewerStateFromClassAd { my ($project_name, $viewer_name) = @_ ;
	$global_swamp_config ||= getSwampConfig();
    my $HTCONDOR_COLLECTOR_HOST = $global_swamp_config->get('htcondor_collector_host');
    my $command = qq{condor_status -pool $HTCONDOR_COLLECTOR_HOST -any -af:V, Name SWAMP_vmu_viewer_state SWAMP_vmu_viewer_status SWAMP_vmu_viewer_name SWAMP_vmu_viewer_vmip SWAMP_vmu_viewer_apikey SWAMP_vmu_user_uuid SWAMP_vmu_viewer_projectid SWAMP_vmu_viewer_instance_uuid SWAMP_vmu_viewer_url_uuid -constraint \"isString(SWAMP_vmu_viewer_status)\"};
    my ($output, $status) = systemcall($command);
    if ($status) { 
        my $error_message = "condor_status $HTCONDOR_COLLECTOR_HOST failed - status: $status output: $output";
        $log->error($error_message);
        return {'error' => $error_message};
    }
    if (! $output) {
        return {'state' => $VIEWER_STATE_NO_RECORD};
    }
	$log->debug("project_name: $project_name viewer_name: $viewer_name output: $output");
	my @lines = split "\n", $output;
	foreach my $line (@lines) {
    	my @parts = split ',', $line;
    	s/\"//g for @parts;
    	s/^\s+//g for @parts;
    	s/\s+$//g for @parts;
    	my ($execrunuid, $state, $vstatus, $viewer, $vmip, $apikey, $user_uuid, $projectid, $viewer_instance_uuid, $viewer_url_uuid) = @parts;
    	if (($projectid eq $project_name) && ($viewer eq $viewer_name)) {
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
    my ($output, $status) = systemcall("echo $name=$value >> $file");
	if ($status) {
        $log->error("Cannot set $name=$value in: $file $OS_ERROR");
		return 0;
	}
	return 1;
}

#	Common Files
#	vrunchecktimeout
#	checktimeout.pl
#	swamp-shutdown-service

sub createrunscript { my ($bogref, $dest) = @_ ;
    my $ret    = 1;

    my $basedir = getSwampDir();

	# set CHECKTIMEOUT_FREQUENCY in run.sh
	# set PROJECT in run.sh
	# set APIKEY in run.sh
	# cat vrun.sh into run.sh
	my $vrunsh = "$basedir/thirdparty/codedx/swamp/vrun.sh";
	if ($bogref->{'viewer'} eq 'ThreadFix') {
		$vrunsh = "$basedir/thirdparty/threadfix/swamp/vrun.sh";
	}
	my $inputvrunsh = "${dest}/run.sh";
	my $checktimeout_frequency = getSwampConfig()->get('vruntimeout_frequency') // '10';
	$ret = 0 if (! _set_var('CHECKTIMEOUT_FREQUENCY', $checktimeout_frequency, $inputvrunsh));
	$ret = 0 if (! _set_var('PROJECT', $bogref->{'urluuid'}, $inputvrunsh));
	if ($bogref->{'viewer'} eq 'ThreadFix') {
		$ret = 0 if (! _set_var('APIKEY', $bogref->{'apikey'}, $inputvrunsh));
	}
    my ($output, $status) = systemcall("cat $vrunsh >> $inputvrunsh");
	if ($status) {
        $log->error("Cannot add: $vrunsh to: $inputvrunsh $OS_ERROR");
		$ret = 0;
	}

	# set VIEWER in checktimeout
	# set CHECKTIMEOUT_DURATION in checktimeout
	# set CHECKTIMEOUT_LASTLOG in checktimeout
	# copy checktimeout to vm input directory
	my $checktimeout = "$basedir/thirdparty/common/vrunchecktimeout";
	my $inputchecktimeout = "${dest}/checktimeout";
	$ret = 0 if (! _set_var('VIEWER', $bogref->{'viewer'}, $inputchecktimeout));
	my $checktimeout_duration = getSwampConfig()->get('vruntimeout_duration') // '28800';
	$ret = 0 if (! _set_var('CHECKTIMEOUT_DURATION', $checktimeout_duration, $inputchecktimeout));
	my $checktimeout_lastlog = getSwampConfig()->get('vruntimeout_lastlog') // '3600';
	$ret = 0 if (! _set_var('CHECKTIMEOUT_LASTLOG', $checktimeout_lastlog, $inputchecktimeout));
    ($output, $status) = systemcall("cat $checktimeout >> $inputchecktimeout");
	if ($status) {
        $log->error("Cannot add: $checktimeout to: $inputchecktimeout $OS_ERROR");
		$ret = 0;
	}

	# copy checktimeout.pl to vm input directory
	my $file = "$basedir/thirdparty/common/checktimeout.pl";
	if (! cp($file, $dest)) {
		$log->error("Cannot copy $file to $dest $OS_ERROR");
		$ret = 0;
	}
	
	# copy swamp-shutdown-service to vm input directory
	$file = "$basedir/thirdparty/common/swamp-shutdown-service";
	if (! cp($file, $dest)) {
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
#	resetdb-threadfix.sql
#	emptydb-mysql-codedx.sql
#	swamp-codedx-service
#	checktimeout.pl
#	logback.xml
#	codedx.props
#	codedx_viewerdb.tar.gz

sub _copyvruninputs_codedx { my ($bogref, $dest) = @_ ;
	my $ret = 1;
	my $basedir = getSwampDir();
	# copy codedx.war to vm input directory
	my $file = "$basedir/thirdparty/codedx/vendor/codedx.war";
	if (! cp($file, $dest)) {
		$log->error("Cannot copy $file to $dest $OS_ERROR");
		$ret = 0;
	}
	# copy empty codedx database sql script to vm input directory
	$file = "$basedir/thirdparty/codedx/swamp/emptydb-codedx.sql";
	if (! cp($file, $dest)) {
		$log->error("Cannot copy $file to $dest $OS_ERROR");
		$ret = 0;
	}
	# copy empty mysql database sql script to vm input directory
	$file = "$basedir/thirdparty/codedx/swamp/emptydb-mysql-codedx.sql";
	if (! cp($file, $dest)) {
		$log->error("Cannot copy $file to $dest $OS_ERROR");
		$ret = 0;
	}
	# copy flushprivs.sql to vm input directory
	$file = "$basedir/thirdparty/common/flushprivs.sql";
	if (! cp($file, $dest)) {
		$log->error("Cannot copy $file to $dest $OS_ERROR");
		$ret = 0;
	}
	# copy resetdb-codedx.sql to vm input directory
	$file = "$basedir/thirdparty/codedx/swamp/resetdb-codedx.sql";
	if (! cp($file, $dest)) {
		$log->error("Cannot copy $file to $dest $OS_ERROR");
		$ret = 0;
	}
	
	# set PROJECT in backup_viewerdb.sh
	# cat codedx_viewerdb.sh into backup_viewerdb.sh
	my $codedx_viewerdbsh = "$basedir/thirdparty/codedx/swamp/codedx_viewerdb.sh";
	my $inputbackup_viewerdbsh = "${dest}/backup_viewerdb.sh";
	$ret = 0 if (! _set_var('PROJECT', $bogref->{'urluuid'}, $inputbackup_viewerdbsh));
    my ($output, $status) = systemcall("cat $codedx_viewerdbsh >> $inputbackup_viewerdbsh");
	if ($status) {
        $log->error("Cannot add: $codedx_viewerdbsh to: $inputbackup_viewerdbsh $OS_ERROR");
		$ret = 0;
	}
	
	# copy logback.xml to vm input directory
	$file = "$basedir/thirdparty/codedx/swamp/logback.xml";
	if (! cp($file, $dest)) {
		$log->error("Cannot copy $file to $dest $OS_ERROR");
		$ret = 0;
	}
	# copy codedx.props to vm input directory
	# set swa.admin.system-key in codedx.props
	my $codedxprops = "$basedir/thirdparty/codedx/swamp/codedx.props";
	my $inputcodedxprops = "${dest}/codedx.props";
	if (! cp($codedxprops, $inputcodedxprops)) {
		$log->error("Cannot copy $codedxprops to $inputcodedxprops $OS_ERROR");
		$ret = 0;
	}
	$ret = 0 if (! _set_var('swa.admin.system-key', $bogref->{'apikey'}, $inputcodedxprops));
	
    # It is OK to not specify a db_path, this just means it has never been persisted
    if (defined($bogref->{'db_path'}) && length($bogref->{'db_path'}) > 2) {
		if (! -r $bogref->{'db_path'}) {
			$log->error("file: $bogref->{'db_path'} not found");
		}
		else {
        	if (cp($bogref->{'db_path'}, $dest)) {
				$log->info("$bogref->{'db_path'} to $dest");
        	}
			else {
            	# Error, but non-fatal.
				$log->error("copy failed: $bogref->{'db_path'} to $dest $OS_ERROR");
			}
		}
    }
    return $ret;
}

#	ThreadFix Files
#	threadfix_viewerdb.sh
#	threadfix.war
#	emptydb-threadfix.sql
#	emptydb-mysql-threadfix.sql
#	flushprivs.sql
#	resetdb-threadfix.sql
#	threadfix.jdbc.properties
#	threadfix_viewerdb.tar.gz

sub _copyvruninputs_threadfix { my ($bogref, $dest) = @_ ;
	my $ret = 1;
	my $basedir = getSwampDir();
	# copy threadfix.war to vm input directory
	my $file = "$basedir/thirdparty/threadfix/vendor/threadfix.war";
	if (! cp($file, $dest)) {
		$log->error("Cannot copy $file to $dest $OS_ERROR");
		$ret = 0;
	}
	# copy empty threadfix database sql script to vm input directory
	$file = "$basedir/thirdparty/threadfix/swamp/emptydb-threadfix.sql";
	if (! cp($file, $dest)) {
		$log->error("Cannot copy $file to $dest $OS_ERROR");
		$ret = 0;
	}
	# copy empty mysql database sql script to vm input directory
	$file = "$basedir/thirdparty/threadfix/swamp/emptydb-mysql-threadfix.sql";
	if (! cp($file, $dest)) {
		$log->error("Cannot copy $file to $dest $OS_ERROR");
		$ret = 0;
	}
	# copy flushprivs.sql to vm input directory
	$file = "$basedir/thirdparty/common/flushprivs.sql";
	if (! cp($file, $dest)) {
		$log->error("Cannot copy $file to $dest $OS_ERROR");
		$ret = 0;
	}
	# copy resetdb-threadfix.sql to vm input directory
	$file = "$basedir/thirdparty/threadfix/swamp/resetdb-threadfix.sql";
	if (! cp($file, $dest)) {
		$log->error("Cannot copy $file to $dest $OS_ERROR");
		$ret = 0;
	}
	
	# set PROJECT in backup_viewerdb.sh
	# cat threadfix_viewerdb.sh into backup_viewerdb.sh
	my $threadfix_viewerdbsh = "$basedir/thirdparty/threadfix/swamp/threadfix_viewerdb.sh";
	my $inputbackup_viewerdbsh = "${dest}/backup_viewerdb.sh";
	$ret = 0 if (! _set_var('PROJECT', $bogref->{'urluuid'}, $inputbackup_viewerdbsh));
    my ($output, $status) = systemcall("cat $threadfix_viewerdbsh >> $inputbackup_viewerdbsh");
	if ($status) {
        $log->error("Cannot add: $threadfix_viewerdbsh to: $inputbackup_viewerdbsh $OS_ERROR");
		$ret = 0;
	}
	
	# copy threadfix.jdbc.properties to vm input directory
	$file = "$basedir/thirdparty/threadfix/swamp/threadfix.jdbc.properties";
	if (! cp($file, $dest)) {
		$log->error("Cannot copy $file to $dest $OS_ERROR");
		$ret = 0;
	}
    # It is OK to not specify a db_path, this just means it has never been persisted
    if (defined($bogref->{'db_path'}) && length($bogref->{'db_path'}) > 2) {
		if (! -r $bogref->{'db_path'}) {
			$log->error("file: $bogref->{'db_path'} not found");
		}
		else {
			my ($output, $status) = systemcall("tar -C $dest -xzf $bogref->{'db_path'}");
			if ($status) {
            	# Error, but non-fatal.
				$log->warn("untar failed: $bogref->{'db_path'} to $dest error: <$output>");
			}
			else {
				$log->info("untar: $bogref->{'db_path'} to $dest");
        	}
		}
    }
    return $ret;
}

sub copyvruninputs { my ($bogref, $dest) = @_ ;
	my $retval = 0;
	if ($bogref->{'viewer'} eq 'CodeDX') {
		$retval = _copyvruninputs_codedx($bogref, $dest);
	}
	elsif ($bogref->{'viewer'} eq 'ThreadFix') {
		$retval = _copyvruninputs_threadfix($bogref, $dest);
	}
	return $retval;
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

#############################
#	Save Viewer Database	#
#############################

sub saveViewerDatabase { my ($bogref, $vmhostname, $outputfolder, $saverunname) = @_ ;
	my $basedir = getSwampDir();

	my $savedbname = q{codedx_viewerdb.tar.gz};
	if ($bogref->{'viewer'} eq q{ThreadFix}) {
		$savedbname = q{threadfix_viewerdb.tar.gz};
	}
    my $savedbfile = "$outputfolder/$savedbname";

	if ($saverunname) {
		my $saverunfile = "$outputfolder/$saverunname";
    	if (-r $saverunfile && ! cp($saverunfile, "$basedir/log/${vmhostname}_${saverunname}")) {
        	$log->error("Cannot copy $saverunfile to $$basedir/log/${vmhostname}_${saverunname} : $OS_ERROR");
    	}
	}

	if (! -r $savedbfile) {
		return 0;
	}
    my $sharedfolder = $bogref->{'resultsfolder'} . '/' . $bogref->{'viewer_uuid'};
    make_path($sharedfolder);
    if (! cp($savedbfile, $sharedfolder)) {
        $log->error("Cannot copy $savedbfile to $sharedfolder : $OS_ERROR");
        return 0;
    }
	$log->info("Copied: $savedbfile to: $sharedfolder");
    # MYSQL needs to own our result files folders so they can be cleaned up.
    my ($uid, $gid) = (getpwnam('mysql'))[2, 3];
    if (chown($uid, $gid, $sharedfolder) != 1) {
        $log->warn("Cannot chown folder $sharedfolder to mysql user. $OS_ERROR");
    }
	my $viewerdbpath = $sharedfolder . '/' . $savedbname;
    if (chown($uid, $gid, $viewerdbpath) != 1) {
        $log->warn("Cannot chown file $viewerdbpath to mysql user. $OS_ERROR");
    }
	if (my $dbh = database_connect()) {
		# viewer_instance_uuid_in
		# viewer_db_path_in
		# viewer_db_checksum_in
		# return_string
		my $query = q{CALL viewer_store.store_viewer(?, ?, ?, @r);};
		my $sth = $dbh->prepare($query);
		my $viewerinstanceuuid = $bogref->{'viewer_uuid'};
		my $viewerdbchecksum = checksumFile($savedbfile);
		$log->info("saveViewerDatabase - calling store_viewer with: $viewerinstanceuuid $viewerdbpath $viewerdbchecksum");
		$sth->bind_param(1, $viewerinstanceuuid);
		$sth->bind_param(2, $viewerdbpath);
		$sth->bind_param(3, $viewerdbchecksum);
		$sth->execute();
		my $result;
		if (! $sth->err) {
			$result = $dbh->selectrow_array('SELECT @r');
		}
		database_disconnect($dbh);
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
