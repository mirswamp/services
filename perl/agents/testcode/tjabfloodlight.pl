#!/usr/bin/env perl 
use utf8;
use warnings;
use strict;
use Getopt::Long qw/GetOptions GetOptionsFromString/;
use JSON qw(to_json from_json);
use Log::Log4perl qw(:easy);
use FindBin qw($Bin);
use lib ("/opt/swamp/perl5", "$FindBin::Bin/../perl5", "$FindBin::Bin/lib", "$FindBin::Bin/../lib");
use SWAMP::ToolLicense;
use SWAMP::SWAMPUtils qw(systemcall);

my $DEFINED_ALL_FLOW_PREFIXES = 'ps-|parasoft|swamp|admin|vpn|bastion';
my $DEFINED_PARASOFT_FLOW_PREFIXES = 'ps-|parasoft';

my $env_params = {
	'dt' => {
		'floodlight_url' => 'http://swa-flood-dt-01.mirsam.org:8080',
		'floodlight_port' => '2002',
		'floodlight_flowprefix' => $DEFINED_ALL_FLOW_PREFIXES,
		'parasoft_server_ip' => '128.104.7.8',
		'parasoft_server_mac' => '00:50:56:AC:AC:77',
		'parasoft_server' => 'lic-ps-dt-01.cosalab.org',
		'vmdomain' => 'vm.cosalab.org',
		'nameserver' => '128.104.7.5',
	},

	'it' => {
		'floodlight_url' => 'http://swa-flood-it-01.mirsam.org:8080',
		'floodlight_port' => '2002',
		'floodlight_flowprefix' => $DEFINED_ALL_FLOW_PREFIXES,
		'parasoft_server_ip' => '128.104.7.7',
		'parasoft_server_mac' => '00:50:56:AC:9B:FD',
		'parasoft_server' => 'lic-ps-it-01.cosalab.org',
		'vmdomain' => 'vm.cosalab.org',
		'nameserver' => '128.104.7.5',
	},

	'pd' => {
		'floodlight_url' => 'http://swa-flood-pd-01.mirsam.org:8080',
		'floodlight_port' => '2002',
		'floodlight_flowprefix' => $DEFINED_ALL_FLOW_PREFIXES,
		'parasoft_server_ip' => '128.105.64.7',
		'parasoft_server_mac' => '00:50:56:AC:0D:2A',
		'parasoft_server' => 'lic-ps-pd-01.mir-swamp.org',
		'vmdomain' => 'vm.mir-swamp.org',
		'nameserver' => '128.105.64.5',
	}
};

sub command_options {
	print "q/Q - quit\n";
	print "h - print help\n";
	print "env - show environment\n";
	print "params - show params\n";
	print "init - init params\n";
	print "dt|it|pd - set environment\n";
	print "switches - show switches\n";
	print "flows - show flows\n";
	print "vmon - flow on for vname\n";
	print "vmoff - flow on for vname\n";
	print "poff - flow off for prefix\n";
	print "psopen - parasoft generic flow rules on\n";
	print "psclose - parasoft generic flow rules off\n";
	print "all|- - show rules for all live/live+dead switches\n";
	print "dead - toggle show dead switches\n";
	print "noport|<port number> - clear/set floodlight_port\n";
	print "nodpid|<switch dpid suffix> - clear/set switch_dpid\n";
	print "noprefix|defined-all|defined-parasoft|<flow rulename prefix> - clear/set floodlight_flowprefix\n";
}

sub usage {
	print "usage: $0 -help -verbose -vname <string> -env <dt|it|pd> -url <floodlight server url> -flow_prefix <string> -port <string> -switch <dpid> -dead\n"; 
	command_options();
	exit;
}

my $help = 0;
my $verbose = 0;
my $vmname;
my $environment = 'dt';
my $floodlight_url;
my $floodlight_flowprefix;
my $floodlight_port;
my $switch_dpid = '';
my $vmip = '';
my $show_dead_switches = 0;

my $result = GetOptions(
    'help|?'    => \$help,
    'verbose' 	=> \$verbose,
    'vmname=s'  => \$vmname,
    'env=s' 	=> \$environment,
	'url=s'		=> \$floodlight_url,
	'flow_prefix=s'	=> \$floodlight_flowprefix,
	'port=s'	=> \$floodlight_port,
	'switch=s'	=> \$switch_dpid,
	'dead'		=> \$show_dead_switches,
);

usage() if (! $result || $help);

sub show_switches { my ($floodlight_url) = @_ ;
	my ($sstatus, $switches) = SWAMP::ToolLicense::fetch_switches($floodlight_url);
	print "Switches ($environment):\n";
	foreach my $switch (@$switches) {
		print '  dpid: ', $switch->{dpid};
		print ' ', $switch->{inetAddress};
		print ' [', (join ',', map{$_->{portNumber}} @{$switch->{ports}}), "]\n";
	}
}

sub dpid_member { my ($dpid, $switches) = @_ ;
	foreach my $switch (@$switches) {
		return 1 if ($dpid eq $switch->{dpid});
	}
	return 0;
}

sub show_switch_flows { my ($dpid, $switch_flows, $floodlight_flowprefix, $floodlight_port, $switch_dpid, $vmip) = @_ ;
	my $total_count = 0;
	my $name_count = 0;
	my $port_count = 0;
	next if ($dpid !~ m/$switch_dpid$/);
	print "  dpid: $dpid\n";
	foreach my $name (keys %$switch_flows) {
		$total_count += 1;
		next if ($name !~ m/^$floodlight_flowprefix/);
		$name_count += 1;
		my $match = $switch_flows->{$name}->{'match'};

		my $src = $match->{'networkSource'};
		my $dst = $match->{'networkDestination'};
		next if ((($src !~ m/^$vmip/) && ($dst !~ m/^$vmip/)) && (($src !~ m/$vmip$/) && ($dst !~ m/$vmip$/)));

		$src .= '/' . $match->{'networkSourceMaskLen'};
		$dst .= '/' . $match->{'networkDestinationMaskLen'};

		my $src_port = $match->{'transportSource'};
		my $dst_port = $match->{'transportDestination'};
		next if (($src_port !~ m/^$floodlight_port/) && ($dst_port !~ m/^$floodlight_port/));

		print "    $name $src($src_port) -> $dst($dst_port)\n";
		$port_count += 1;
	}
	print "    Total: $total_count Name: $name_count Port: $port_count\n";
}

sub show_flows { my ($floodlight_url, $floodlight_flowprefix, $floodlight_port, $switch_dpid, $vmip) = @_ ;
	my ($sstatus, $switches) = SWAMP::ToolLicense::fetch_switches($floodlight_url);
	my ($fstatus, $all_flows) = SWAMP::ToolLicense::fetch_flows($floodlight_url);
	print "Live Switch " if ($show_dead_switches);
	print "Flows ($environment):\n";
	foreach my $dpid (map {$_->{dpid}} @$switches) {
		my $switch_flows = $all_flows->{$dpid};
		show_switch_flows($dpid, $switch_flows, $floodlight_flowprefix, $floodlight_port, $switch_dpid, $vmip);
	}
	return if (! $show_dead_switches);
	print "Dead Switch Flows ($environment):\n";
	while (my ($dpid, $switch_flows) = each(%$all_flows)) {
		next if (dpid_member($dpid, $switches));
		my $switch_flows = $all_flows->{$dpid};
		show_switch_flows($dpid, $switch_flows, $floodlight_flowprefix, $floodlight_port, $switch_dpid, $vmip);
	}
}

sub parasoft_open { my ($floodlight_url, $floodlight_port, $parasoft_server_ip) = @_ ;
	my ($sstatus, $switches) = SWAMP::ToolLicense::fetch_switches($floodlight_url);
	my $idx = 1;
	my $address = "$floodlight_url/wm/staticflowentrypusher/json";
	my $vmip = $parasoft_server_ip;
	$vmip =~ s/\.\d+$/\.0/;
	my $netmask = 24;
	$netmask = 22 if ($environment eq 'pd');
	foreach my $switch (@$switches) {
		my $rulename = "parasoft-$idx";
    	my %flow = (
        	"switch"     => $switch->{'dpid'},
        	"name"       => $rulename,
        	"priority"   => 65,
        	'dst-port'   => $floodlight_port,
        	'protocol'   => '6',
        	'ether-type' => '2048',
        	'active'     => 'true',
        	'actions'    => 'output=flood',
    		'src-ip'	 => $vmip . "/$netmask",
        	'dst-ip' 	 => $parasoft_server_ip . '/32',
    	);
    	my $flow_data = to_json( \%flow );
		if ($verbose) {
			print "curl forward: $flow_data at: $address\n";
		}
		my ($output, $status) = systemcall(qq{curl -q -s -X POST -d '$flow_data' $address});
		$idx += 1;
		$rulename = "parasoft-$idx";
    	delete $flow{'dst-port'};
    	$flow{'name'} = $rulename;
		$flow{'src-port'} = $floodlight_port;
		$flow{'src-ip'} = $parasoft_server_ip . '/32';
		$flow{'dst-ip'} = $vmip . "/$netmask";
    	$flow_data = to_json( \%flow );
		if ($verbose) {
			print "curl backward: $flow_data at: $address\n\n";
		}
		($output, $status) = systemcall(qq{curl -q -s -X POST -d '$flow_data' $address});
		$idx += 1;
	}
}

sub parasoft_close { my ($floodlight_url) = @_ ;
	my $nRemoved = SWAMP::ToolLicense::all_off($floodlight_url, 'parasoft-\d');
	print "Removed: $nRemoved\n";
}

sub vm_flow_on { my ($vmname, $params) = @_ ;
	my $vmip = SWAMP::ToolLicense::getvmipaddr($vmname, $params->{'vmdomain'}, $params->{'nameserver'});
	my $floodlight_params = [$params->{'floodlight_flowprefix'}, $vmip, $params->{'parasoft_server_ip'}, $params->{'floodlight_port'}, $vmname];
	my $rulenames = SWAMP::ToolLicense::floodlight_flows_on($params->{'floodlight_url'}, $floodlight_params);
	return $rulenames;
}

sub vm_flow_off { my ($floodlight_url, $rulenames) = @_ ;
	foreach my $rulename (@$rulenames) {
    	SWAMP::ToolLicense::flow_off_by_rulename($floodlight_url, $rulename);
	}
}

sub prefix_flow_off { my ($floodlight_url, $floodlight_flowprefix) = @_ ;
	my $nRemoved = SWAMP::ToolLicense::all_off($floodlight_url, $floodlight_flowprefix);
	print "Removed: $nRemoved\n";
}

sub show_environment {
	print "Environment: $environment\n";
	print '  Floodlight url: ', $env_params->{$environment}->{'floodlight_url'}, "\n";
	print '  Floodlight port: ', $env_params->{$environment}->{'floodlight_port'}, "\n";
	print '  Floodlight flowprefix: ', $env_params->{$environment}->{'floodlight_flowprefix'}, "\n";
	print '  Parasoft server ip: ', $env_params->{$environment}->{'parasoft_server_ip'}, "\n";
	print '  Parasoft server mac: ', $env_params->{$environment}->{'parasoft_server_mac'}, "\n";
	print '  Parasoft server: ', $env_params->{$environment}->{'parasoft_server'}, "\n";
	print "VM name: $vmname\n" if ($vmname);
	print '  VM domain: ', $env_params->{$environment}->{'vmdomain'}, "\n";
	print '  VM nameserver: ', $env_params->{$environment}->{'nameserver'}, "\n";
}

sub show_params {
	print "Params:\n";
	print "  Floodlight url: $floodlight_url\n";
	print "  Floodlight port: $floodlight_port\n";
	print "  Floodlight flowprefix: $floodlight_flowprefix\n";
	print "  Switch dpid: $switch_dpid\n";
	print "  VM IP: $vmip\n";
	print "  Show dead switches: ", $show_dead_switches ? 'yes' : 'no', "\n";
}

sub init_params {
	$floodlight_url = $env_params->{$environment}->{'floodlight_url'} if (! defined($floodlight_url));
	$floodlight_flowprefix = $env_params->{$environment}->{'floodlight_flowprefix'} if (! defined($floodlight_flowprefix));
	$floodlight_port = '' if (! defined($floodlight_port));
	$switch_dpid = '';
	$vmip = '';
}

sub set_params_from_env { my ($env) = @_ ;
	# set params to specified environment defaults
	$environment = $env;
	$floodlight_url = $env_params->{$environment}->{'floodlight_url'};
	$floodlight_flowprefix = $env_params->{$environment}->{'floodlight_flowprefix'};
	$floodlight_port = '';
	$switch_dpid = '';
	$vmip = '';
}

Log::Log4perl::easy_init($TRACE);
my $rulenames;

init_params();
show_environment();
show_params();
while (1) {
	print "Command (h|?|q ...): ";
	my $answer = <STDIN>;
	chomp $answer;
	print "\n";
	last if ($answer =~ m/q/i);

	if ($answer eq 'h' || $answer eq '?') {
		command_options();
		next;
	}
	elsif ($answer eq 'env') {
		show_environment();
		next;
	}
	elsif ($answer eq 'params') {
		show_params();
		next;
	}
	elsif ($answer eq 'init') {
		init_params();
		show_params();
		next;
	}
	elsif ($answer eq 'dt' || $answer eq 'it' || $answer eq 'pd') {
		set_params_from_env($answer);
		show_environment();
		show_params();
		next;
	}

	# switches or flows
	elsif ($answer eq 'switches') {
		show_switches($floodlight_url);
		next;
	}
	elsif ($answer eq 'flows') {
		show_flows($floodlight_url, $floodlight_flowprefix, $floodlight_port, $switch_dpid, $vmip);
		next;
	}

	elsif ($answer eq 'vmon') {
		$rulenames = vm_flow_on($vmname, $env_params->{$environment}) if ($vmname);
	}

	elsif ($answer eq 'vmoff') {
		vm_flow_off($floodlight_url, $rulenames) if ($rulenames);
	}

	elsif ($answer eq 'tcon') {
		if ($vmname) {
	      	my $floodlight_params = ['tomcat', '10.129.65.61', '128.104.7.107', 443, $vmname];
	      	$rulenames = SWAMP::ToolLicense::floodlight_flows_on($env_params->{$environment}->{'floodlight_url'}, $floodlight_params);
	  	}
	}

	elsif ($answer eq 'tcoff') {
		vm_flow_off($floodlight_url, $rulenames) if ($rulenames);
	}

	elsif ($answer eq 'poff') {
		prefix_flow_off($floodlight_url, $floodlight_flowprefix) if ($floodlight_flowprefix);
	}

	elsif ($answer eq 'psopen') {
		# set parasoft generic open rules
		parasoft_open($env_params->{$environment}->{'floodlight_url'}, $env_params->{$environment}->{'floodlight_port'}, $env_params->{$environment}->{'parasoft_server_ip'});
	}

	elsif ($answer eq 'psclose') {
		# clear parasoft generic open rules
		parasoft_close($env_params->{$environment}->{'floodlight_url'});
	}

	elsif ($answer eq 'all' || $answer eq '-') {
		# show all flows on all live/live+dead switches
		$floodlight_flowprefix = '';
		$floodlight_port = '';
		$switch_dpid = '';
		$vmip = '';
		if ($answer eq 'all') {
			$show_dead_switches = 1;
		}
		else {
			$show_dead_switches = 0;
		}
	}

	# dead switches
	elsif ($answer eq 'dead') {
		# toggle dead switches
		$show_dead_switches = ! $show_dead_switches;
	}

	# floodlight_port
	elsif ($answer eq 'noport') {
		# clear floodlight port
		$floodlight_port = '';
	}
	elsif ($answer =~ m/^\d+$/) {
		# set floodlight port
		$floodlight_port = $answer;
	}

	# switch_dpid
	elsif ($answer eq 'nodpid') {
		# clear switch dpid suffix
		$switch_dpid = '';
	}
	elsif ($answer =~ m/(?:\:[[:xdigit:]]{2}){1,8}/) {
		# set switch dpid suffix
		$switch_dpid = $answer;
	}

	# vmip
	elsif ($answer eq 'novmip') {
		$vmip = '';
	}
	elsif ($answer =~ m/^ip\s+\d+/) {
		$vmip = $answer;
		$vmip =~ s/^ip\s*//;
	}

	# floodlight_flowprefix
	elsif ($answer eq 'noprefix') {
		# clear floodlight flowprefix
		$floodlight_flowprefix = '';
	}
	elsif ($answer eq 'defined-all') {
		# set default all defined flow prefixes
		$floodlight_flowprefix = $DEFINED_ALL_FLOW_PREFIXES;
	}
	elsif ($answer eq 'defined-parasoft') {
		# set default parasoft defined flow prefixes
		$floodlight_flowprefix = $DEFINED_PARASOFT_FLOW_PREFIXES;
	}
	# this must be last clause - tests non empty answer
	elsif ($answer =~ m/\S+/) {
		# set floodlight flowprefix
		$floodlight_flowprefix = $answer;
	}

	show_switches($floodlight_url);
	show_flows($floodlight_url, $floodlight_flowprefix, $floodlight_port, $switch_dpid, $vmip);

}
print "Hello World!\n";
