#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

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
my $amport = $config->get('agentMonitorPort');
my $lpport = $config->get('launchPadPort');

my $lclient = RPC::XML::Client->new("http://$host:$lpport");
my $amclient = RPC::XML::Client->new("http://$host:$amport");
listMethods($lclient);
listMethods($amclient);

print "Hello World!\n";
