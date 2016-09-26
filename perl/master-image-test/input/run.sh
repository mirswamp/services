#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

use 5.008;
use utf8;
use strict;
use warnings;
use English '-no_match_vars';
use Getopt::Long;
use Carp qw(croak);
our $VERSION = '1.00';

# VMINPUTDIR - full path to the input directory (suggested value /mnt/in).
#
# VMOUTPUTDIR - full path to the output directory (suggested value /mnt/out).
#
# VMUID - uid for owner of files and directories within the input directory, and the user ID for the VM username. If a username is created with this uid, the primary gid should be the value defined in VMGID.
#
# VMUSERNAME - suggested username to use for the VM username for the uid defined in VMUID (suggested value vmrun).
#
# VMGID - gid for owner of files and directories within the input directory, and the group ID for the VM username.
#
# VMGROUPNAME - suggested groupname to use for the VM username for the gid defined in VMGID (suggested value vmrun).
#
# VMUSERADD - full path to command that creates a user on the host. This command should use the system’s command to create an account (useradd or adduser), including registering the user’s account and group, and creating the user’s home directory. It should minimally support the Linux options -u, -U, and -g.
#
# VMGROUPADD - full path to command that creates a group on the host. This command should use the system’s command to create an account (groupadd or addgroup). It should minimally support the Linux option -g.
#
# VMCREATEVMUSER - full path to command that creates a user and group using the current values of the environment variables VMUID, VMUSERNAME, VMGID, and VMGROUPNAME.
#
# VMSHUTDOWN - full path to command that shuts down and powers off the VM. This command should be executable by any user on the VM.
my @vars =
  qw/VMINPUTDIR VMOUTPUTDIR VMUID VMUSERNAME VMGID VMGROUPNAME VMGROUPADD VMCREATEVMUSER VMSHUTDOWN/;
my %toolversions = (
    'autoconf' => '-V',
    'bison'    => '-V',
    'byacc'    => '-V',
    'cmake'    => '--version',
    'flex'     => '-V',
    'gcc'      => '--version',
    'g++'      => '--version',
    'gdb'      => '-version',
    'gzip'     => '-V',
    'java'     => '-version',
    'libtool'  => '--version',
    'm4'       => '--version',
    'make'     => '--version',
    'patch'    => '--version',
    'perl'     => '--version',
    'strace'   => '-V',
    'tar'      => '--version',
    'valgrind' => '--version',
    'wget'     => '--version'
);
my @errors;
my $nErrors = 0;

sub systemCmd {
    my $cmd = shift;
    my ( $output, $status ) = ( $_ = qx{$cmd 2>&1}, $CHILD_ERROR >> 8 );
    return ( $output, $status );
}

sub addError {
    my $msg = shift;
    push @errors, $msg;
    return ++$nErrors;
}
my ( $output, $status ) =
  systemCmd("sudo hostname -f");    # Running as root, this should work
if ( $status != 0 ) {
    addError("Sudo failed: $output");
}
foreach my $tool ( keys %toolversions ) {
    my $cmd = "$tool $toolversions{$tool}";
    ( $output, $status ) = systemCmd($cmd);
    # sci5.9 byacc is ancient and doesn't grok version
    # requests.
    if ( $status == 0 || ($tool eq 'byacc' && $status == 1) ) {
        #        chomp $output;
        #        print "$tool: yes$output\n";
    }
    else {
        addError("Missing package: $tool");
    }
}
foreach my $varName (@vars) {
    if ( !defined( $ENV{$varName} ) ) {
        addError("Missing environment variable: $varName");
    }
}
if ( defined( $ENV{'VMINPUTDIR'} ) ) {
    if ( !-r $ENV{'VMINPUTDIR'} ) {
        addError("Missing VMINPUTDIR directory $ENV{'VMINPUTDIR'}");
    }
}
my $log = "/tmp/out.txt";
if ( defined( $ENV{'VMOUTPUTDIR'} ) ) {
    if ( !-r $ENV{'VMOUTPUTDIR'} ) {
        addError("Missing VMOUTPUTDIR directory $ENV{'VMOUTPUTDIR'}");
    }
    else {
        $log = "$ENV{'VMOUTPUTDIR'}/out.txt";
    }
}
if ( open( my $logfh, ">", $log ) ) {
    print $logfh "Log started ", scalar localtime, "\n";
    print $logfh "Hostname: ", `hostname -f`, "\n";
    if ( $nErrors > 0 ) {
        foreach (@errors) {
            print $logfh "$_\n";
        }
        print $logfh "Total Errors: $nErrors\n";
    }
    else {
        print $logfh "OK!\n";
    }
    print $logfh "Log ended ", scalar localtime, "\n";
    close $logfh or croak "Cannot close log file $OS_ERROR";
}
else {
    systemCmd('logger "Cannot create log"');
}
if (defined($ENV{'VMSHUTDOWN'})) {
    systemCmd($ENV{'VMSHUTDOWN'});
}
exit $nErrors;
