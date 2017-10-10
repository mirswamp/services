#!/usr/bin/env perl
use strict;
use warnings;
use lib '/opt/swamp/perl5';
use SWAMP::vmu_Support qw(getSwampConfig);
use RPC::XML::Client;

sub listMethods { my ($client) = @_ ;
	my $res = $client->send_request('system.listMethods');
	print "res: ", join(', ', @{$res->value}), "\n";
	my $methods = $res->value();
	foreach my $method (@$methods) {
		if ($method =~ m/^launchPad./ || $method =~ m/^agentMonitor./) {
			print "method: $method\n";
			my $res = $client->send_request('system.methodSignature', $method);
			foreach my $sig (@{$res->value()}) {
				print '  ', join(', ', @{$sig}), "\n";
			}
		}
	}
}

my $config = getSwampConfig();
my $host = $config->get('agentMonitorHost');
my $lport = $config->get('agentMonitorPort');
my $amport = $config->get('agentMonitorJobPort');

my $lclient = RPC::XML::Client->new("http://$host:$lport");
my $amclient = RPC::XML::Client->new("http://$host:$amport");
listMethods($lclient);
listMethods($amclient);

print "Hello World!\n";
