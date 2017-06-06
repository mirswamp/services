# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2017 Software Assurance Marketplace

package SWAMP::ToolLicense;

use 5.014;
use utf8;
use strict;
use warnings;
use JSON qw(to_json from_json);
use Log::Log4perl;
use POSIX qw(strftime);
use SWAMP::vmu_Support qw(
	systemcall
	getSwampConfig
);
use SWAMP::vmu_AssessmentSupport qw(
	isSwampInABox
	isLicensedTool
	isParasoftTool
	isGrammaTechTool
	isRedLizardTool
);
use SWAMP::Libvirt qw(getVMIPAddress);

use parent qw(Exporter);
our (@EXPORT_OK);
BEGIN {
    require Exporter;
    @EXPORT_OK = qw(
		openLicense
		closeLicense
    );
}

my $log = Log::Log4perl->get_logger(q{});

sub fetch_switches { my ($floodlight_url) = @_ ;
	# Fetch the switch information
	my $address = "$floodlight_url/wm/core/controller/switches/json";
	my ($output, $status) = systemcall(qq{curl -q -s -X GET $address});
	if ($status) {
    	$log->error("Unable to acquire list of floodlight switches from $address: $status [$output]");
		return $status;
	}
	my $switches = from_json($output);
	return ($status, $switches);
}

sub fetch_flows { my ($floodlight_url) = @_ ;
    # Fetch all of the flows
    my $address = "$floodlight_url/wm/staticflowpusher/list/all/json";
    my ($output, $status) = systemcall(qq{curl -q -s -X GET $address});
	if ($status) {
    	$log->error("Unable to acquire list of floodlight flows from $address: $status [$output]");
		return $status;
	}
    my $flows = from_json($output);
	return ($status, $flows);
}

sub flow_off_by_rulename { my ($floodlight_url, $rulename) = @_ ;
	my $address = "$floodlight_url/wm/staticflowpusher/json";
	my ($output, $status) = systemcall(qq{curl -q -s -X DELETE -d '{"name":"$rulename"}' $address});
	if ($status) {
		$log->error("Unable to remove rule: $rulename from $address: $status [$output]");
		return $status;
	}
	return ($status, $output);
}

sub all_off { my ($floodlight_url, $floodlight_flowprefix) = @_ ;
	my ($status, $ref) = fetch_flows($floodlight_url);
	return 0 if ($status);
    my $nRemoved = 0;
    foreach my $key ( keys $ref ) {
        foreach my $rulename ( keys $ref->{$key} ) {
            if ($rulename =~ /^$floodlight_flowprefix/sxm) {
				($status, my $output) = flow_off_by_rulename($floodlight_url, $rulename);
                if (! $status) {
                	$nRemoved += 1;
				}
            }
        }
    }
    return $nRemoved;
}

sub getvmmacaddr { my ($vmdomainname) = @_ ;
	my ($vmmac, $status) = systemcall(qq{virsh dumpxml $vmdomainname | grep 'mac address'});
	if ($status) {
		$log->error("Unable to get MAC address of $vmdomainname $status [$vmmac]");
		return q{};
	}
	if ($vmmac =~ m/((?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2})/isxm) {
		$vmmac = $1;
	}
	$log->info("MAC address of $vmdomainname [$vmmac]");
	return $vmmac;
}

sub build_rulename { my ($floodlight_flowprefix, $time, $vmhostname, $idx) = @_ ;
	my $date = sprintf(strftime('%Y%m%d%H%M%S', localtime($time)));
	my $rulename;
	if ($vmhostname =~ m/(\d+)/sxm) {
		$vmhostname = $1;
	}
	$rulename = "$floodlight_flowprefix-$vmhostname-$date-$idx";
	return $rulename;
}

sub floodlight_flows_on { my ($floodlight_url, $floodlight_params) = @_ ;
	my $time = time();
    my ($floodlight_flowprefix, $src_ip, $dst_ip, $port, $vmhostname) = @{$floodlight_params};
	my ($fstatus, $switches) = fetch_switches($floodlight_url);
	return [] if ($fstatus);
	my $idx = 1;    # Flows must have unique names, use a simple counter
	my $address = "$floodlight_url/wm/staticflowpusher/json";
	my @rulenames;
	# Need a flow for each switch
	foreach my $switch (@{$switches}) {
		# Update flow rule for forward direction
		my $rulename = build_rulename($floodlight_flowprefix, $time, $vmhostname, $idx);
    	my %flow = (
        	"switch"     => $switch->{'switchDPID'},
        	"name"       => $rulename,
        	"priority"   => 65,
        	'tcp_dst'   => $port,
        	'ip_proto'   => '6',    # TCP protocol. If no protocol is specified,
                                	# Any proto is allowed
        	'eth_type' => '2048',
        	'active'     => 'true',
        	'actions'    => 'output=normal'
    	);
    	$flow{'ipv4_src'} = $src_ip;
        $flow{'ipv4_dst'} = $dst_ip . '/32';

    	my $flow_data = to_json( \%flow );
		my ($output, $status) = systemcall(qq{curl -q -s -X POST -d '$flow_data' $address});
		$log->trace("curl forward to: $address $status [$output] $flow_data");
		if ($status) {
			$log->error("Unable to add rule: $rulename to $address: $status [$output]");
		}
		else {
			push @rulenames, $rulename;
		}
    	$idx += 1;

    	# Update the flow rule for the reverse direction, allowing any port back
    	delete $flow{'tcp_dst'};
		$flow{'tcp_src'} = $port;
		$rulename = build_rulename($floodlight_flowprefix, $time, $vmhostname, $idx);
    	$flow{'name'} = $rulename;
        $flow{'ipv4_src'} = $dst_ip . '/32';
    	$flow{'ipv4_dst'} = $src_ip;
      	$flow_data = to_json( \%flow );
		($output, $status) = systemcall(qq{curl -q -s -X POST -d '$flow_data' $address});
		$log->trace("curl back to: $address $status [$output] $flow_data");
		if ($status) {
			$log->error("Unable to add rule: $rulename to $address: $status [$output]");
		}
		else {
			push @rulenames, $rulename;
		}

    	$idx++;
	}
	return \@rulenames;
}

sub openLicense { my ($config, $bogref, $vmhostname, $vmip) = @_ ;
    if (!isSwampInABox($config) && isLicensedTool($bogref)) {

        my $floodlight_url = $config->get('floodlight');

        my ($license_flowprefix, $license_port, $license_serverip);
        if (isParasoftTool($bogref)) {
            $license_flowprefix = $config->get('parasoft_flowprefix');
            $license_port = int( $config->get('parasoft_port') );
            $license_serverip = $config->get('parasoft_server_ip');
            $log->info("open floodlight rule for Parasoft $license_serverip $license_port");
        }
        elsif (isGrammaTechTool($bogref)) {
            $license_flowprefix = $config->get('grammatech_flowprefix');
            $license_port = int( $config->get('grammatech_port') );
            $license_serverip = $config->get('grammatech_server_ip');
            $log->info("open floodlight rule for GrammaTech $license_serverip $license_port");
        }
        elsif (isRedLizardTool($bogref)) {
            $license_flowprefix = $config->get('redlizard_flowprefix');
            $license_port = int( $config->get('redlizard_port') );
            $license_serverip = $config->get('redlizard_server_ip');
            $log->info("open floodlight rule for RedLizard $license_serverip $license_port");
        }

        $log->trace("Floodlight: $floodlight_url $license_flowprefix $license_port");
        $log->trace("License Server IP: " . ($license_serverip || 'N/A'));

        my $nameserver = $config->get('nameserver');
        my $vmnetdomain = $config->get('vmnetdomain');
        $log->trace("VM: $nameserver $vmnetdomain ");

        if (! $vmip || $vmip =~ m/corrupt|timeout/sxm) {
            # second chance to get vmip on previous error
            $vmip = getVMIPAddress($config, $vmhostname);
            if (! $vmip || $vmip =~ m/corrupt|timeout/sxm) {
                $log->error("Unable to obtain vmip for $vmhostname - error: $vmip");
                return (undef, $vmip);
            }
            $log->info("VMIP for $vmhostname: $vmip");
        }

        my $floodlight_params = [$license_flowprefix, $vmip, $license_serverip, $license_port, $vmhostname];

        my $rulenames = floodlight_flows_on($floodlight_url, $floodlight_params);
        $log->info("added rule count: ", scalar(@{$rulenames}));
        foreach my $rulename (@{$rulenames}) {
            $log->trace("added rule: $rulename");
        }
        return ($rulenames, $vmip);
    }
    # second chance to get vmip on previous error - or pass through previous success
    if (! $vmip || $vmip =~ m/corrupt|timeout/sxm) {
        my $nameserver = $config->get('nameserver');
        my $vmnetdomain = $config->get('vmnetdomain');
        $log->trace("VM: $nameserver $vmnetdomain ");

        $vmip = getVMIPAddress($config, $vmhostname);
        if (! $vmip || $vmip =~ m/corrupt|timeout/sxm) {
            $log->error("Unable to obtain vmip for $vmhostname - error: $vmip");
            return (undef, $vmip);
        }
        $log->info("VMIP for $vmhostname: $vmip");
    }
    return (undef, $vmip);
}

sub closeLicense { my ($config, $bogref, $license_result) = @_ ;
    if (!isSwampInABox($config) && isLicensedTool($bogref)) {
        my $floodlight_url = $config->get('floodlight');
        foreach my $rulename (@{$license_result}) {
            flow_off_by_rulename($floodlight_url, $rulename);
            $log->trace("removed rule: $rulename");
        }
        $log->info("removed rule count: ", scalar(@{$license_result}));
    }
    return ;
}

1;
