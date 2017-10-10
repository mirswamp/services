# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2017 Software Assurance Marketplace

package SWAMP::Libvirt;
use utf8;
use strict;
use warnings;
use 5.010;
use English '-no_match_vars';
use Log::Log4perl;
use Log::Log4perl::Level;
use JSON qw(from_json);
use SWAMP::vmu_Support qw(systemcall);
use XML::Parser;

use parent qw(Exporter);
our (@EXPORT_OK);

BEGIN {
    require Exporter;
    @EXPORT_OK = qw(
      getVMIPAddress
    );
}

my $log = Log::Log4perl->get_logger(q{});

my $IP_FROM_NSLOOKUP               = 0;
my $IP_FROM_LIBVIRT_DNSMASQ_STATUS = 1;
my $IP_FROM_LIBVIRT_DNSMASQ_LEASES = 2;
my $IP_FROM_NOWHERE                = 99;

my $network_bridge_name = q{};

sub _xml_bridge_node {
    my $expat_ref       = shift @_;
    my $element_name    = shift @_;
    my $attribute_name  = shift @_;
    my $attribute_value = shift @_;

    while ($attribute_name) {
        if ($attribute_name eq 'name') {
            $network_bridge_name = $attribute_value;
            last;
        }
        $attribute_name  = shift @_;
        $attribute_value = shift @_;
    }

    return;
}

my ($IP_SOURCE_TYPE, $IP_SOURCE);
sub _findVMIPSource {
	if ($IP_SOURCE_TYPE && $IP_SOURCE) {
		return($IP_SOURCE_TYPE, $IP_SOURCE);
	}
    my ($config) = @_;
    #
    # If no SWAMP-in-a-Box network is defined, use `nslookup`.
    #
    my $network_name = $config->get('SWAMP-in-a-Box.libvirt.network') || q{};

    if ($network_name eq q{}) {
		if (! $IP_SOURCE_TYPE || ($IP_SOURCE_TYPE != $IP_FROM_NSLOOKUP)) {
        	$log->info('Using nslookup');
		}
		$IP_SOURCE_TYPE = $IP_FROM_NSLOOKUP;
		$IP_SOURCE = 'nslookup';
		return($IP_SOURCE_TYPE, $IP_SOURCE);
    }
    else {
        $log->debug("Found SWAMP-in-a-Box.libvirt.network: $network_name");
    }

    #
    # Otherwise, lookup the bridge's name and locate the "leases" file.
    #
    $network_bridge_name = q{};

    my ($network_xml, $status) = systemcall(qq{virsh net-dumpxml $network_name});
    my $xml_parser = XML::Parser->new(Handlers => { Start => \&_xml_bridge_node });
    $xml_parser->parse($network_xml);

    if ($network_bridge_name eq q{}) {
        $log->error('Failed to determine network bridge name');
    }

    my $status_file = "/var/lib/libvirt/dnsmasq/${network_bridge_name}.status";
    my $leases_file = "/var/lib/libvirt/dnsmasq/${network_name}.leases";

    if (-r $status_file) {
		if (! $IP_SOURCE_TYPE || ($IP_SOURCE_TYPE != $IP_FROM_LIBVIRT_DNSMASQ_STATUS)) {
        	$log->info("Found $status_file");
		}
        $IP_SOURCE_TYPE = $IP_FROM_LIBVIRT_DNSMASQ_STATUS; 
		$IP_SOURCE = $status_file;
		return($IP_SOURCE_TYPE, $IP_SOURCE);
    }

    if (-r $leases_file) {
		if (! $IP_SOURCE_TYPE || ($IP_SOURCE_TYPE != $IP_FROM_LIBVIRT_DNSMASQ_LEASES)) {
        	$log->info("Found $leases_file");
		}
        $IP_SOURCE_TYPE = $IP_FROM_LIBVIRT_DNSMASQ_LEASES; 
		$IP_SOURCE = $leases_file;
		return($IP_SOURCE_TYPE, $IP_SOURCE);
    }

    $log->error("Couldn't read $status_file");
    $log->error("Couldn't read $leases_file");
    $log->error('Failed to determine where to find VM IP addresses');
    $IP_SOURCE_TYPE = $IP_FROM_NOWHERE; 
	$IP_SOURCE = q{};
	return($IP_SOURCE_TYPE, $IP_SOURCE);
}

sub _queryNslookup {
    my ($vmhostname, $vmnetdomain, $name_server) = @_;
    my $host_name = "${vmhostname}.${vmnetdomain}";
	# systemcall with silent
    my ($output, $status) = systemcall(qq{nslookup -nosearch $host_name $name_server}, 1);

    if (!$status) {
        if ($output =~ m/Address:\ ((?:\d{1,3}\.){3}\d{1,3})/sxm) {
            my $vm_ip = $1;
            return ($vm_ip, 1);
        }
        return ($output, -1);
    }
    else {
        return ($output, 0);
    }
}

sub _queryLibvirtStatusFile {
    my ($vmhostname, $status_file_name) = @_;
    my ($status_file_contents, $exit_code) = systemcall(qq{cat $status_file_name});
    my $data_ref = from_json($status_file_contents);

    for my $vm (@{$data_ref}) {
        if ($vm->{'hostname'} eq $vmhostname) {
            return ($vm->{'ip-address'}, 1);
        }
    }

    return (q{}, 0);
}

sub _queryLibvirtLeasesFile {
    my ($vmhostname, $leases_file_name) = @_;
    my ($leases_file_contents, $exit_code) = systemcall(qq{cat $leases_file_name});
	my @leases_file_contents = split "\n", $leases_file_contents;

    my @lines = grep { /$vmhostname/sxm } @leases_file_contents;
	if (! scalar(@lines)) {
		return (q{}, 0);
	}
    my $vm_ip = $lines[0];
    chomp $vm_ip;

    if ($vm_ip) {
        $vm_ip = (split q{ }, $vm_ip)[2];
    }
    if ($vm_ip) {
        return ($vm_ip, 1);
    }
    return (q{}, 0);
}

#
# Returns: 1 for success, 0 for "no info yet", -1 for error
#
sub _queryVMIPSource {
    my ($config, $vmhostname) = @_;
    my ($ip_source_type, $ip_source) = _findVMIPSource($config);

    if ($ip_source_type == $IP_FROM_NSLOOKUP) {
        my $vmnetdomain   = $config->get('vmnetdomain') || q{};
        my $name_server = $config->get('nameserver') || q{};
        return _queryNslookup($vmhostname, $vmnetdomain, $name_server);
    }

    if ($ip_source_type == $IP_FROM_LIBVIRT_DNSMASQ_LEASES) {
        return _queryLibvirtLeasesFile($vmhostname, $ip_source);
    }

    if ($ip_source_type == $IP_FROM_LIBVIRT_DNSMASQ_STATUS) {
        return _queryLibvirtStatusFile($vmhostname, $ip_source);
    }

    return (q{}, -1);
}

sub getVMIPAddress {
    my ($config, $vmhostname) = @_;
    my $vm_ip        = q{};
    my $vmip_lookup_attempts = $config->get('vmip_lookup_attempts') || 50;
    my $vmip_lookup_sleep   = $config->get('vmip_lookup_sleep') || 3;

    my $start_time = time;

    for my $attempt (1 .. $vmip_lookup_attempts) {
        my ($output, $status) = _queryVMIPSource($config, $vmhostname);

        my $end_time = time;

        if ($status == 1) {
            $vm_ip = $output;
            $log->info("Obtained IP address of $vmhostname $vm_ip after: $attempt attempts time: ", $end_time - $start_time);
            last;
        }
        elsif ($status == -1) {
            $vm_ip = 'vm ip corrupt';
            $log->error("Error encountered while determining IP address of $vmhostname after: $attempt attempts");
            $log->error("Output from last query: $output");
            $log->error('Time taken: ', $end_time - $start_time, ' seconds');
            last;
        }
        elsif ($attempt >= $vmip_lookup_attempts) {
            $vm_ip = 'vm ip timeout';
            $log->error("Unable to determine IP address of $vmhostname after $attempt attempts");
            $log->error("Output from last query: $output");
            $log->error('Time taken: ', $end_time - $start_time, ' seconds');
            last;
        }

        sleep $vmip_lookup_sleep;
    }

    return $vm_ip;
}

1;
