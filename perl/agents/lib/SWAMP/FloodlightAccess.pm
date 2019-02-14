# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2019 Software Assurance Marketplace

package SWAMP::FloodlightAccess;

use 5.014;
use utf8;
use strict;
use warnings;
use JSON qw(to_json);
use Log::Log4perl;
use POSIX qw(strftime);
use SWAMP::vmu_Support qw(
	from_json_wrapper
	systemcall
	isSwampInABox
	getVMIPAddress
);
use SWAMP::vmu_AssessmentSupport qw(
	needsFloodlightAccessTool
	isParasoft9Tool
	isParasoft10Tool
	isGrammaTechTool
	isRedLizardTool
	isSynopsysTool
	isOWASPDCTool
);

use parent qw(Exporter);
our (@EXPORT_OK);
BEGIN {
    require Exporter;
    @EXPORT_OK = qw(
		openFloodlightAccess
		closeFloodlightAccess
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
	my $switches = from_json_wrapper($output);
	$status = 1 if (! defined($switches));
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
    my $flows = from_json_wrapper($output);
	$status = 1 if (! defined($flows));
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
    foreach my $key ( keys %{$ref} ) {
        foreach my $rulename ( keys %{$ref->{$key}} ) {
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

sub build_rulename { my ($floodlight_flowprefix, $time, $vmhostname, $idx, $port) = @_ ;
	my $date = sprintf(strftime('%Y%m%d%H%M%S', localtime($time)));
	my $rulename;
	if ($vmhostname =~ m/(\d+)/sxm) {
		$vmhostname = $1;
	}
	$rulename = "$floodlight_flowprefix-$vmhostname-$date-$idx-$port";
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
		my $rulename = build_rulename($floodlight_flowprefix, $time, $vmhostname, $idx, $port);
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
		$rulename = build_rulename($floodlight_flowprefix, $time, $vmhostname, $idx, $port);
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

sub openFloodlightAccess { my ($config, $bogref, $vmhostname, $vmip) = @_ ;
    if (!isSwampInABox($config) && needsFloodlightAccessTool($bogref)) {

        my $floodlight_url = $config->get('floodlight');

        my ($floodlight_flowprefix, $server_port, $server_aux_port, $serverip);
        if (isParasoft10Tool($bogref)) {
            $floodlight_flowprefix = $config->get('parasoft_flowprefix');
            $server_port = int( $config->get('parasoft_dtp_port') );
            $serverip = $config->get('parasoft_dtp_server_ip');
            $log->info("open floodlight rule for Parasoft DTP $serverip $server_port");
        }
        elsif (isParasoft9Tool($bogref)) {
            $floodlight_flowprefix = $config->get('parasoft_flowprefix');
            $server_port = int( $config->get('parasoft_port') );
            $serverip = $config->get('parasoft_server_ip');
            $log->info("open floodlight rule for Parasoft $serverip $server_port");
        }
        elsif (isGrammaTechTool($bogref)) {
            $floodlight_flowprefix = $config->get('grammatech_flowprefix');
            $server_port = int( $config->get('grammatech_port') );
            $serverip = $config->get('grammatech_server_ip');
            $log->info("open floodlight rule for GrammaTech $serverip $server_port");
        }
        elsif (isRedLizardTool($bogref)) {
            $floodlight_flowprefix = $config->get('redlizard_flowprefix');
            $server_port = int( $config->get('redlizard_port') );
            $serverip = $config->get('redlizard_server_ip');
            $log->info("open floodlight rule for RedLizard $serverip $server_port");
        }
        elsif (isSynopsysTool($bogref)) {
            $floodlight_flowprefix = $config->get('synopsys_flowprefix');
            $server_port = int( $config->get('synopsys_port') );
            $server_aux_port = int( $config->get('synopsys_aux_port') );
            $serverip = $config->get('synopsys_server_ip');
            $log->info("open floodlight rule for Synopsys $serverip $server_port and $server_aux_port");
        }
		elsif (isOWASPDCTool($bogref)) {
            $floodlight_flowprefix = $config->get('owaspdc_flowprefix');
            $server_port = int( $config->get('owaspdc_port') );
            $serverip = $config->get('owaspdc_server_ip');
            $log->info("open floodlight rule for OWASP $serverip $server_port");
		}

        $log->trace("Floodlight: $floodlight_url $floodlight_flowprefix $server_port");
        $log->trace("License Server IP: " . ($serverip || 'N/A'));

        my $nameserver = $config->get('nameserver');
        my $vmnetdomain = $config->get('vmnetdomain');
        $log->trace("VM nameserver: $nameserver VM domain: $vmnetdomain");

        if (! $vmip || $vmip =~ m/corrupt|timeout/sxm) {
            # second chance to get vmip on previous error
            $vmip = getVMIPAddress($vmhostname);
            if (! $vmip || $vmip =~ m/corrupt|timeout/sxm) {
                $log->error("Unable to obtain vmip for $vmhostname - error: $vmip");
                return (undef, $vmip);
            }
            $log->info("VMIP for $vmhostname: $vmip");
        }

        my $floodlight_params = [$floodlight_flowprefix, $vmip, $serverip, $server_port, $vmhostname];

        my $rulenames = floodlight_flows_on($floodlight_url, $floodlight_params);
        $log->info("added rule count: ", scalar(@{$rulenames}));
        foreach my $rulename (@{$rulenames}) {
            $log->trace("added rule: $rulename");
        }
		if ($server_aux_port) {
			my $floodlight_params = [$floodlight_flowprefix, $vmip, $serverip, $server_aux_port, $vmhostname];

			my $aux_rulenames = floodlight_flows_on($floodlight_url, $floodlight_params);
			$log->info("added rule count: ", scalar(@{$rulenames}));
			foreach my $rulename (@{$aux_rulenames}) {
				$log->trace("added rule: $rulename");
				push @$rulenames, $rulename;
			}
		}
        return ($rulenames, $vmip);
    }
    # second chance to get vmip on previous error - or pass through previous success
    if (! $vmip || $vmip =~ m/corrupt|timeout/sxm) {
        my $nameserver = $config->get('nameserver');
        my $vmnetdomain = $config->get('vmnetdomain');
        $log->trace("VM: $nameserver $vmnetdomain ");

        $vmip = getVMIPAddress($vmhostname);
        if (! $vmip || $vmip =~ m/corrupt|timeout/sxm) {
            $log->error("Unable to obtain vmip for $vmhostname - error: $vmip");
            return (undef, $vmip);
        }
        $log->info("VMIP for $vmhostname: $vmip");
    }
    return (undef, $vmip);
}

sub closeFloodlightAccess { my ($config, $bogref, $license_result) = @_ ;
    if (!isSwampInABox($config) && needsFloodlightAccessTool($bogref)) {
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
