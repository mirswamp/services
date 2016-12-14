# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

package SWAMP::ToolLicense;

use 5.014;
use utf8;
use strict;
use warnings;
use parent qw(Exporter);
use JSON qw(to_json from_json);
use Log::Log4perl;
use POSIX qw(strftime);

use SWAMP::SWAMPUtils qw(systemcall getSwampConfig);
use SWAMP::AssessmentTools qw(isParasoftTool isGrammaTechTool isRedLizardTool);

BEGIN {
    our $VERSION = '0.01';
}
our (@EXPORT_OK);

BEGIN {
    require Exporter;
    @EXPORT_OK = qw(
		getVMIPAddr
		openLicense
		closeLicense
    );
}

sub fetch_switches { my ($floodlight_url) = @_ ;
	# Fetch the switch information
	my $address = "$floodlight_url/wm/core/controller/switches/json";
	my ($output, $status) = systemcall(qq{curl -q -s -X GET $address});
	if ($status) {
    	my $log = Log::Log4perl->get_logger(q{});
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
    	my $log = Log::Log4perl->get_logger(q{});
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
		my $log = Log::Log4perl->get_logger(q{});
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

sub getvmmacaddr { my ($vmname) = @_ ;
	my ($vmmac, $status) = systemcall(qq{virsh dumpxml $vmname | grep 'mac address'});
	if ($status) {
		my $log = Log::Log4perl->get_logger(q{});
		$log->error("Unable to get MAC address of $vmname: $status [$vmmac]");
		return q{};
	}
	if ($vmmac =~ m/((?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2})/isxm) {
		$vmmac = $1;
	}
	my $log = Log::Log4perl->get_logger(q{});
	$log->info("MAC address of $vmname [$vmmac]");
	return $vmmac;
}

# returns 1 for success
# returns 0 for not yet
# returns -1 for error
sub parsevmipaddr { my ($where, $vmname, $vmdomain, $nameserver) = @_ ;
	my $vmip;
	if ($where ne 'nslookup') {
		my @lines = `cat $where`;
		chomp @lines;
		@lines = grep {/$vmname/sxm} @lines;
		$vmip = $lines[0];
		if ($vmip) {
			$vmip = (split q{ }, $vmip)[2];
		}
		if ($vmip) {
			return (1, $vmip);
		}
		return (0, q{});
	}
	else {
		my $host = $vmname . q{.} . $vmdomain;
		my ($output, $status) = systemcall(qq{nslookup -nosearch $host $nameserver});
		if (! $status) {
			if ($output =~ m/Address:\ ((?:\d{1,3}\.){3}\d{1,3})/sxm) {
				$vmip = $1;
				return (1, $vmip);
			}
			return (-1, $output);
		}
		else {
			return (0, $output);
		}
	}
}

sub getvmipaddr { my ($vmname, $vmdomain, $nameserver, $vmleases) = @_ ;
	my $log = Log::Log4perl->get_logger(q{});
	my $vmip;
	my $where = $vmleases;
	if (! $where || ! -r $where) {
		$where = 'nslookup';
	}

	# nslookup will never succeed on a SWAMP-on-a-Box
	# act as if it timed out, which matches the behavior of previous releases
	if ($where eq 'nslookup') {
		my $config = getSwampConfig();
		if ($config->get('SWAMP-in-a-Box') eq 'yes') {
			$vmip = 'vm ip timeout';
			return $vmip;
		}
	}

	my $max_attempts = 15;
	my $sleep_time = 7;
	# sleep for at most sleep_time * (max_attempts - 1) on failure
	my $start_time = time();
	for my $attempt (1 .. $max_attempts) {
		my ($status, $output) = parsevmipaddr($where, $vmname, $vmdomain, $nameserver);
		my $end_time = time();
		if (1 == $status) {
			$log->info("IP address of $vmname [$output] derived from: $where after $attempt attempts - time: ", $end_time - $start_time);
			$vmip = $output;
			last;
		}
		elsif (-1 == $status) {
			$log->info("IP address of $vmname [$output] not derived from: $where after $attempt attempts - time: ", $end_time - $start_time);
			$vmip = 'vm ip corrupt';
			last;
		}
		elsif ($attempt >= $max_attempts) {
			$log->error("Unable to derive IP address of $vmname [$output] from: $where after $attempt attempts - time: ", $end_time - $start_time);
			$vmip = 'vm ip timeout';
			last;
		}
		sleep($sleep_time);
	}
	return $vmip;
}

sub trimaddr { my ($addr) = @_ ;
	my $retval = $addr;
	$addr =~ s/\://gsxm;
	$addr =~ s/\.//gsxm;
	$addr =~ s/\///gsxm;
	return $addr;
}

sub build_rulename { my ($floodlight_flowprefix, $time, $vmname, $idx) = @_ ;
	my $date = sprintf(strftime('%Y%m%d%H%M%S', localtime($time)));
	my $rulename;
	if ($vmname =~ m/(\d+)/sxm) {
		$vmname = $1;
	}
	$rulename = "$floodlight_flowprefix-$vmname-$date-$idx";
	return $rulename;
}

sub floodlight_flows_on { my ($floodlight_url, $floodlight_params) = @_ ;
	my $time = time();
	my $log = Log::Log4perl->get_logger(q{});
    my ($floodlight_flowprefix, $src_ip, $dst_ip, $port, $vmname) = @{$floodlight_params};
	my ($fstatus, $switches) = fetch_switches($floodlight_url);
	return [] if ($fstatus);
	my $idx = 1;    # Flows must have unique names, use a simple counter
	my $address = "$floodlight_url/wm/staticflowpusher/json";
	my @rulenames;
	# Need a flow for each switch
	foreach my $switch (@{$switches}) {
		# Update flow rule for forward direction
		my $rulename = build_rulename($floodlight_flowprefix, $time, $vmname, $idx);
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
		$rulename = build_rulename($floodlight_flowprefix, $time, $vmname, $idx);
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

sub getVMIPAddr { my ($config, $vmname) = @_ ;
	my $vmdomain = $config->get('vmdomain');
	my $nameserver = $config->get('nameserver');
	my $vmleases = $config->get('vmleases');
	my $vmip = getvmipaddr($vmname, $vmdomain, $nameserver, $vmleases);
	return $vmip;
}

sub openLicense { my ($config, $bogref, $vmname, $vmip) = @_ ;
	if (SWAMP::AssessmentTools::isParasoftTool($bogref) ||
		SWAMP::AssessmentTools::isGrammaTechTool($bogref) ||
		SWAMP::AssessmentTools::isRedLizardTool($bogref)) {
		my $log = Log::Log4perl->get_logger(q{});

        my $floodlight_url = $config->get('floodlight');

		my ($license_flowprefix, $license_port, $license_serverip);
		if (SWAMP::AssessmentTools::isParasoftTool($bogref)) {
        	$license_flowprefix = $config->get('parasoft_flowprefix');
        	$license_port = int( $config->get('parasoft_port') );
        	$license_serverip = $config->get('parasoft_server_ip');
		}
		elsif (SWAMP::AssessmentTools::isGrammaTechTool($bogref)) {
        	$license_flowprefix = $config->get('grammatech_flowprefix');
        	$license_port = int( $config->get('grammatech_port') );
        	$license_serverip = $config->get('grammatech_server_ip');
		}
		elsif (SWAMP::AssessmentTools::isRedLizardTool($bogref)) {
        	$license_flowprefix = $config->get('redlizard_flowprefix');
        	$license_port = int( $config->get('redlizard_port') );
        	$license_serverip = $config->get('redlizard_server_ip');
		}

		$log->trace("Floodlight: $floodlight_url $license_flowprefix $license_port");
		$log->trace("Parasoft Server IP: " . ($license_serverip || 'N/A'));

		my $nameserver = $config->get('nameserver');
		my $vmdomain = $config->get('vmdomain');
		$log->trace("VM: $nameserver $vmdomain ");

		if (! $vmip || $vmip =~ m/corrupt|timeout/sxm) {
			# second chance to get vmip on previous error
			my $vmleases = $config->get('vmleases');
			$log->trace("VM leases: $vmleases ");
			$vmip = getvmipaddr($vmname, $vmdomain, $nameserver, $vmleases);
			if (! $vmip || $vmip =~ m/corrupt|timeout/sxm) {
				$log->error("Unable to obtain vmip for $vmname using $nameserver $vmdomain - error: $vmip");
				return (undef, $vmip);
			}
			$log->info("VMIP for $vmname: $vmip using $nameserver $vmdomain");
		}

		my $floodlight_params = [$license_flowprefix, $vmip, $license_serverip, $license_port, $vmname];

		my $rulenames = floodlight_flows_on($floodlight_url, $floodlight_params);
		foreach my $rulename (@{$rulenames}) {
			$log->trace("added rule: $rulename");
		}
		return ($rulenames, $vmip);
	}
	# second chance to get vmip on previous error - or pass through previous success
	if (! $vmip || $vmip =~ m/corrupt|timeout/sxm) {
		my $log = Log::Log4perl->get_logger(q{});
		my $nameserver = $config->get('nameserver');
		my $vmdomain = $config->get('vmdomain');
		$log->trace("VM: $nameserver $vmdomain ");

		my $vmleases = $config->get('vmleases');
		$log->trace("VM leases: $vmleases ");
		$vmip = getvmipaddr($vmname, $vmdomain, $nameserver, $vmleases);
		if (! $vmip || $vmip =~ m/corrupt|timeout/sxm) {
			$log->error("Unable to obtain vmip for $vmname using $nameserver $vmdomain - error: $vmip");
			return (undef, $vmip);
		}
		$log->info("VMIP for $vmname: $vmip using $nameserver $vmdomain");
	}
	return (undef, $vmip);
}

sub closeLicense { my ($config, $bogref, $license_result) = @_ ;
	if (SWAMP::AssessmentTools::isParasoftTool($bogref) ||
		SWAMP::AssessmentTools::isGrammaTechTool($bogref) ||
		SWAMP::AssessmentTools::isRedLizardTool($bogref)) {
        my $floodlight_url = $config->get('floodlight');
		my $log = Log::Log4perl->get_logger(q{});
		foreach my $rulename (@{$license_result}) {
			flow_off_by_rulename($floodlight_url, $rulename);
			$log->trace("removed rule: $rulename");
		}
	}
	return ;
}

1;
