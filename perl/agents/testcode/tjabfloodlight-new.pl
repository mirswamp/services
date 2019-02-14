#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2019 Software Assurance Marketplace

use 5.010;
use utf8;
use warnings;
use strict;
use FindBin qw($Bin);
use lib ("/opt/swamp/perl5", "$FindBin::Bin/../perl5", "$FindBin::Bin/lib", "$FindBin::Bin/../lib");

use Getopt::Long qw/GetOptions/;
use SWAMP::ToolLicense;
use SWAMP::SWAMPUtils qw(getSwampConfig);
use Log::Log4perl qw(:easy);

my $env_params = {
	'dt' => {
		'floodlight_url' => 'http://swa-flood-dt-01.mirsam.org:8080',
		'floodlight_port' => '2002',
		'floodlight_flowprefix' => 'ps-dt-license',
		'parasoft_server_ip' => '128.104.7.8',
		'parasoft_server_mac' => '00:50:56:AC:AC:77',
		'parasoft_server' => 'lic-ps-dt-01.cosalab.org',
		'vmdomain' => 'vm.cosalab.org',
		'nameserver' => '128.104.7.5',
	},

	'it' => {
		'floodlight_url' => 'http://swa-flood-it-01.mirsam.org:8080',
		'floodlight_port' => '2002',
		'floodlight_flowprefix' => 'ps-it-license',
		'parasoft_server_ip' => '128.104.7.7',
		'parasoft_server_mac' => '00:50:56:AC:9B:FD',
		'parasoft_server' => 'lic-ps-it-01.cosalab.org',
		'vmdomain' => 'vm.cosalab.org',
		'nameserver' => '128.104.7.5',
	},

	'pd' => {
		'floodlight_url' => 'http://swa-flood-pd-01.mirsam.org:8080',
		'floodlight_port' => '2002',
		'floodlight_flowprefix' => 'ps-pd-license',
		'parasoft_server_ip' => '128.105.64.7',
		'parasoft_server_mac' => '00:50:56:AC:0D:2A',
		'parasoft_server' => 'lic-ps-pd-01.cosalab.org',
		'vmdomain' => 'vm.mir-swamp.org',
		'nameserver' => '128.105.64.5',
	}
};

my $help = 0;
my $verbose    = 0;
my $vmname;
my $environment = 'it';

GetOptions(
    'help|?'    => \$help,
    'vmname=s'  => \$vmname,
    'verbose!' 	=> \$verbose,
    'env=s' 	=> \$environment,
);

sub show_params {
	print 'Floodlight url: ', $env_params->{$environment}->{'floodlight_url'}, "\n";
	print 'Floodlight port: ', $env_params->{$environment}->{'floodlight_port'}, "\n";
	print 'Floodlight flowprefix: ', $env_params->{$environment}->{'floodlight_flowprefix'}, "\n";
	print 'Parasoft server ip: ', $env_params->{$environment}->{'parasoft_server_ip'}, "\n";
	print 'Parasoft server mac: ', $env_params->{$environment}->{'parasoft_server_mac'}, "\n";
	print 'Parasoft server: ', $env_params->{$environment}->{'parasoft_server'}, "\n";
	print "VM name: $vmname\n" if ($vmname);
	print 'VM domain: ', $env_params->{$environment}->{'vmdomain'}, "\n";
	print 'VM nameserver: ', $env_params->{$environment}->{'nameserver'}, "\n";
}

sub show_switches { my ($floodlight_url) = @_ ;
	my ($status, $switches) = SWAMP::ToolLicense::fetch_switches($floodlight_url);
	print "Switches:\n";
	foreach my $switch (@$switches) {
		print '  dpid: ', $switch->{switchDPID};
		print ' ', $switch->{inetAddress};
		print ' [', (join ',', map{$_->{portNumber}} @{$switch->{ports}}), "]\n";
	}
}

sub show_flows { my ($floodlight_url, $floodlight_flowprefix) = @_ ;
	my ($status, $flows) = SWAMP::ToolLicense::fetch_flows($floodlight_url);
	print "Flows:\n";
	while (my ($key, $value) = each(%$flows)) {
		print "  dpid: $key\n";
		foreach my $item (@$value) {
			my $name =(keys %$item)[0];
			if ($name =~ m/^$floodlight_flowprefix/) {
				my $match = $item->{$name}->{'match'};
				my $src = $match->{'ipv4_src'} || 'N/A';
				my $dst = $match->{'ipv4_dst'} || 'N/A';
				my $port = $match->{'outPort'} || 'N/A';
				my $action = $match->{'actions'}->{'actions'} || 'N/A';
				print "    $name $src -> $dst port: $port\n";
			}
		}
	}
}

sub ps_flow_on { my ($vmname, $params) = @_ ;
	my $floodlight_params = [$params->{'floodlight_url'}, $params->{'floodlight_flowprefix'}, $params->{'floodlight_port'}];
	my $parasoft_params = [$params->{'parasoft_server_mac'}, $params->{'parasoft_server_ip'}];
	my $vm_params = [$vmname, $params->{'nameserver'}, $params->{'vmdomain'}];
	my $rulenames = SWAMP::ToolLicense::floodlight_flows_on($floodlight_params, $parasoft_params, $vm_params);
	return $rulenames;
}

sub ps_flow_off { my ($floodlight_url, $rulenames) = @_ ;
	foreach my $rulename (@$rulenames) {
    	SWAMP::ToolLicense::flow_off_by_rulename($floodlight_url, $rulename);
	}
}

Log::Log4perl::easy_init($TRACE);
show_params();
my $rulenames;
my $floodlight_url = $env_params->{$environment}->{'floodlight_url'};
my $floodlight_flowprefix = $env_params->{$environment}->{'floodlight_flowprefix'};
while (1) {
	show_switches($floodlight_url);
	show_flows($floodlight_url, $floodlight_flowprefix);
	$floodlight_flowprefix = $env_params->{$environment}->{'floodlight_flowprefix'};
	print "Command: ";
	my $answer = <STDIN>;
	chomp $answer;
	last if (! $answer);
	if ($answer eq 'on') {
		$rulenames = ps_flow_on($vmname, $env_params->{$environment}) if ($vmname);
	}
	elsif ($answer eq 'off') {
		ps_flow_off($floodlight_url, $rulenames) if ($rulenames);
	}
	elsif ($answer eq 'all') {
		$floodlight_flowprefix = '';
	}
	elsif ($answer eq 'dt' || $answer eq 'it' || $answer eq 'pd') {
		$environment = $answer;
		$floodlight_url = $env_params->{$environment}->{'floodlight_url'};
		$floodlight_flowprefix = $env_params->{$environment}->{'floodlight_flowprefix'};
		show_params();
	}
	else {
		$floodlight_flowprefix = $answer;
	}
}
print "Hello World!\n";
