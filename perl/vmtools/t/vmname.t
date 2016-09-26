#/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

# Test the assessmentTools package methods

use 5.014;
use strict;
use warnings;

use Cwd qw(abs_path getcwd);
use Carp qw(croak);
use Archive::Tar;
use English '-no_match_vars';
use File::Spec;
use File::Basename qw(basename);
use File::Path qw(rmtree);
use Getopt::Long;
use Log::Log4perl::Level;
use Log::Log4perl;
use Test::More;

BEGIN {
    use_ok('VMTools', qw(isMasterImage masternameToDisplayname masterizeName displaynameToMastername));
}

#use VMTools qw(isMasterImage masternameToDisplayname);

# Version 1 master name is /^condor.*-master-\d+.qcow2/
# Version 2 master name is /^condor.*
# VMPLATNAME - SWAMP name for the platform used to start the VM. 
# These are of the format VMOSDISTRO-VMOSVERSION-ARCH-SN, where ARCH is 32 or 64, and SN has an 
# initial value of ‘01’ and is incremented by 1 when any change is made to a publicly available 
# image, and the vendor, version and arch are unchanged.  If the vendor, version or arch change 
# the SN should be reset to ‘01’. Add digits if necessary to represent the SN, but always include 
# a minimum of 2 digits. After the initial change to the SN the SN should not change until the VM 
# has been made public, so testing has a stable name. The VMPLATUUID and VMPLATUPDATE should be 
# updated on all changes. [added in version 2.0]

my @outcomes=('not a', 'a V1', 'a V2');
my %masterNames= (
q{helloworld} => 0,  
q{condor-codedx1.0.5-rhel-6.5-64-viewer-master-2014031301.qcow2} => 1,
q{condor-debian-7.0-64-master-2013082601.qcow2} => 1,
q{condor-debian-7.0-64-master-2013083001.qcow2} => 1,
q{condor-debian-7.0-64-master-2013092501.qcow2} => 1,
q{condor-debian-7.0-64-master-2013121201.qcow2} => 1,
q{condor-windows-7.SP1-64-master-2013061801.qcow2} => 1,
q{condor-codedx1.0.4-rhel-6.5-64-viewer-master-2014012801.qcow2} => 1,
q{condor-codedx1.0.4-rhel-6.5-64-viewer-master-2014020301.qcow2} => 1,
q{condor-codedx1.0.4-rhel-6.5-64-viewer-master-2014020601.qcow2} => 1,
q{condor-codedx1.0.4-rhel-6.5-64-viewer-master-2014032001.qcow2} => 1,
q{condor-codedx1.0.5-rhel-6.5-64-viewer-master-2014031301.qcow2} => 1,
q{condor-codedx-rhel-6.5-64-viewer-master-2013010601.qcow2} => 1,
q{condor-debian-7.0-64-master-2013092501.qcow2} => 1,
q{condor-debian-7.0-64-master-2013121201.qcow2} => 1,
q{condor-debian-7.0-64-master-2013122601.qcow2} => 1,
q{condor-debian-7.0-64-master-2014013001.qcow2} => 1,
q{condor-fedora-18.0-64-master-2013081401.qcow2} => 1,
q{condor-fedora-18.0-64-master-2013083001.qcow2} => 1,
q{condor-fedora-19.0-64-master-2013081401.qcow2} => 1,
q{condor-fedora-19.0-64-master-2013083001.qcow2} => 1,
q{condor-rhel-6.4-32-master-2013083001.qcow2} => 1,
q{condor-rhel-6.4-32-master-2014021001.qcow2} => 1,
q{condor-rhel-6.4-64-codedxmaster-2013100301.qcow2} => 0,
q{condor-rhel-6.4-64-master-2013083001.qcow2} => 1,
q{condor-rhel-6.4-64-master-2014021001.qcow2} => 1,
q{condor-scientific-5.9-32-master-2013092701.qcow2} => 1,
q{condor-scientific-5.9-32-master-2013101401.qcow2} => 1,
q{condor-scientific-5.9-64-master-2013083001.qcow2} => 1,
q{condor-scientific-5.9-64-master-2013101401.qcow2} => 1,
q{condor-scientific-6.4-64-master-2013082601.qcow2} => 1,
q{condor-scientific-6.4-64-master-2013083001.qcow2} => 1,
q{condor-ubuntu-12.04-64-master-2013083001.qcow2} => 1,
q{condor-ubuntu-12.04-64-master-2013122601.qcow2} => 1,
q{condor-ubuntu-12.04-64-batlab-master-2014060601.qcow2} => 1,
q{condor-windows-7.SP1-64-master-2013101801.qcow2} => 1,
q{condor-windows-7.SP1-64-master-2013101802.qcow2} => 1,
q{condor-debian-7.4-64-01-master-2014030601.qcow2} => 2,
q{condor-rhel-6.5-32-01-master-2014030701.qcow2} => 2,
# 99 is not a recognized architecture
q{condor-rhel-6.5-99-01-master-2014030701.qcow2} => 0,
q{condor-debian-7.4-64-01-master-2014030601.qcow2} => 2,
q{condor-fedora-18-64-01-master-2014030601.qcow2} => 2,
q{condor-fedora-19-64-01-master-2014030601.qcow2} => 2,
q{condor-rhel-6.5-32-01-master-2014030701.qcow2} => 2,
q{condor-rhel-6.5-64-01-master-2014030701.qcow2} => 2,
q{condor-scientific-5.10-32-01-master-2014030701.qcow2} => 2,
q{condor-scientific-5.10-64-01-master-2014030701.qcow2} => 2,
q{condor-scientific-6.5-64-01-master-2014030601.qcow2} => 2,
q{condor-ubuntu-12.04-64-01-master-2014030701.qcow2} => 2,
q{condor-ubuntu-12.04-64-02-master-2014030701.qcow2} => 2,
q{condor-ubuntu-12.04-64-94-master-2014030701.qcow2} => 2,
q{condor-ubuntu-12.04-99-94-master-2014030701.qcow2} => 0,
q{condor-debian-6.0.9-32-01-batlab-master-2014060401.qcow2} => 1,
q{condor-debian-6.0.9-64-01-batlab-master-2014060401.qcow2} => 1,
q{condor-debian-7.5-64-01-batlab-master-2014060501.qcow2} => 1,
q{condor-fedora-19-64-01-batlab-master-2014060901.qcow2} => 1,
q{condor-fedora-20-64-01-batlab-master-2014060901.qcow2} => 1,
q{condor-rhel-6.5-64-01-batlab-master-2014061301.qcow2} => 1,
q{condor-rhel-7.0-64-00-batlab-2014062300.qcow2} => 0,
q{condor-scientific-5.10-32-01-batlab-master-2014061101.qcow2} => 1,
q{condor-scientific-5.10-64-01-batlab-master-2014061101.qcow2} => 1,
q{condor-scientific-6.5-32-01-batlab-master-2014061101.qcow2} => 1,
q{condor-scientific-6.5-64-01-batlab-master-2014061101.qcow2} => 1,
q{condor-ubuntu-12.04-64-01-batlab-master-2014060601.qcow2} => 1,
q{condor-ubuntu-14.04-64-01-batlab-master-2014060601.qcow2} => 1,
q{condor-android-ubuntu-12.04-64-master-2014101701.qcow2} => 1,
);

my %displayNames = (
 q{condor-codedx-rhel-6.5-64-viewer-master-2013010601.qcow2}  => q{codedx-rhel-6.5-64-viewer}  ,
 q{condor-codedx1.0.5-rhel-6.5-64-viewer-master-2014031301.qcow2}  => q{codedx1.0.5-rhel-6.5-64-viewer}  ,
 q{condor-codedx1.0.5-rhel-6.5-64-viewer-master-2014031301.qcow2}  => q{codedx1.0.5-rhel-6.5-64-viewer}  ,
 q{condor-debian-7.0-64-master-2013121201.qcow2}  => q{debian-7.0-64}  ,
 q{condor-debian-7.0-64-master-2014013001.qcow2}  => q{debian-7.0-64}  ,
 q{condor-debian-7.4-64-01-master-2014030601.qcow2}  => q{debian-7.4-64-01}  ,
 q{condor-debian-7.4-64-01-master-2014030601.qcow2}  => q{debian-7.4-64-01}  ,
 q{condor-fedora-18-64-01-master-2014030601.qcow2}  => q{fedora-18-64-01}  ,
 q{condor-fedora-18.0-64-master-2013083001.qcow2}  => q{fedora-18.0-64}  ,
 q{condor-fedora-19-64-01-master-2014030601.qcow2}  => q{fedora-19-64-01}  ,
 q{condor-fedora-19.0-64-master-2013083001.qcow2}  => q{fedora-19.0-64}  ,
 q{condor-rhel-6.4-32-master-2014021001.qcow2}  => q{rhel-6.4-32}  ,
 q{condor-rhel-6.4-64-master-2014021001.qcow2}  => q{rhel-6.4-64}  ,
 q{condor-rhel-6.5-32-01-master-2014030701.qcow2}  => q{rhel-6.5-32-01}  ,
 q{condor-rhel-6.5-32-01-master-2014030701.qcow2}  => q{rhel-6.5-32-01}  ,
 q{condor-rhel-6.5-64-01-master-2014030701.qcow2}  => q{rhel-6.5-64-01}  ,
 q{condor-scientific-5.10-32-01-master-2014030701.qcow2}  => q{scientific-5.10-32-01}  ,
 q{condor-scientific-5.10-64-01-master-2014030701.qcow2}  => q{scientific-5.10-64-01}  ,
 q{condor-scientific-5.9-32-master-2013101401.qcow2}  => q{scientific-5.9-32}  ,
 q{condor-scientific-5.9-64-master-2013101401.qcow2}  => q{scientific-5.9-64}  ,
 q{condor-scientific-6.4-64-master-2013083001.qcow2}  => q{scientific-6.4-64}  ,
 q{condor-scientific-6.5-64-01-master-2014030601.qcow2}  => q{scientific-6.5-64-01}  ,
 q{condor-ubuntu-12.04-64-02-master-2014030701.qcow2}  => q{ubuntu-12.04-64-02}  ,
 q{condor-ubuntu-12.04-64-master-2013122601.qcow2}  => q{ubuntu-12.04-64}  ,
q{condor-ubuntu-12.04-64-batlab-master-2014060601.qcow2} => q{ubuntu-12.04-64-batlab},
 q{condor-windows-7.SP1-64-master-2013061801.qcow2}  => q{windows-7.SP1-64}  ,
 q{condor-windows-7.SP1-64-master-2013101802.qcow2}  => q{windows-7.SP1-64}  ,
q{condor-debian-6.0.9-32-01-batlab-master-2014060401.qcow2} => q{debian-6.0.9-32-01-batlab},
q{condor-debian-6.0.9-64-01-batlab-master-2014060401.qcow2} => q{debian-6.0.9-64-01-batlab},
q{condor-debian-7.5-64-01-batlab-master-2014060501.qcow2} => q{debian-7.5-64-01-batlab},
q{condor-fedora-19-64-01-batlab-master-2014060901.qcow2} => q{fedora-19-64-01-batlab},
q{condor-fedora-20-64-01-batlab-master-2014060901.qcow2} => q{fedora-20-64-01-batlab},
q{condor-rhel-6.5-64-01-batlab-master-2014061301.qcow2} => q{rhel-6.5-64-01-batlab},
q{condor-scientific-5.10-32-01-batlab-master-2014061101.qcow2} => q{scientific-5.10-32-01-batlab},
q{condor-scientific-5.10-64-01-batlab-master-2014061101.qcow2} => q{scientific-5.10-64-01-batlab},
q{condor-scientific-6.5-32-01-batlab-master-2014061101.qcow2} => q{scientific-6.5-32-01-batlab},
q{condor-scientific-6.5-64-01-batlab-master-2014061101.qcow2} => q{scientific-6.5-64-01-batlab},
q{condor-ubuntu-12.04-64-01-batlab-master-2014060601.qcow2} => q{ubuntu-12.04-64-01-batlab},
q{condor-ubuntu-14.04-64-01-batlab-master-2014060601.qcow2} => q{ubuntu-14.04-64-01-batlab},
q{condor-android-ubuntu-12.04-64-master-2014101701.qcow2} => q{android-ubuntu-12.04-64},
);
# Hashmaps to check for name collisions between v1 and v2 images.
my %v1names;
my %v2names;
foreach my $file (sort keys %masterNames) {
    # v1 names  ( $name =~ /^condor.*-master-\d+.qcow2/mxs ) {
    my $result = isMasterImage($file);
    my $expected = $masterNames{$file};
    my $wid = 60 - length($file);
    my $testname = "$file ". " " x$wid . " is $outcomes[$expected] master";
        
    is($result, $masterNames{$file}, $testname);
    if ($result != 0 && defined($displayNames{$file})) {
        my $display = masternameToDisplayname($file);
        $testname = "$file displays as $display";
        is($display, $displayNames{$file}, $testname);
        my $version = $file;
        $version =~s/^.*master-//;
        $version =~s/.qcow2//;
        $testname = "$displayNames{$file} + $version masterizes as $file";
        is (masterizeName($displayNames{$file}, $version), $file, $testname);
        if ($result == 1) {
            $v1names{$display} = 1;
        }
        elsif ($result == 2) {
            $v2names{$display} = 1;
        }
    }
}
# check to see that there are no collisions between v1 names and v2 names.
foreach my $name (keys %v1names) {
    my $testname = "v1 $name does not collide with v2";
    is (defined($v2names{$name}), q{}, $testname);
    if(defined($v2names{$name})) {
        warn "$name exists in v2";
    }
}
foreach my $name (keys %v2names) {
    my $testname = "v2 $name does not collide with v1";
    is (defined($v1names{$name}), q{}, $testname);
    if(defined($v1names{$name})) {
        warn "$name exists in v1";
    }
}

my @filenames = keys(%masterNames) ;
is (displaynameToMastername(q{debian-7.0-64}, \@filenames),q{condor-debian-7.0-64-master-2014013001.qcow2}, 'Find master debian -7.0-64');
is (displaynameToMastername(q{ubuntu-12.04-64}, \@filenames), q{condor-ubuntu-12.04-64-master-2013122601.qcow2}, 'Find master ubuntu-12.04-64');
is (displaynameToMastername(q{android-ubuntu-12.04-64}, \@filenames), q{condor-android-ubuntu-12.04-64-master-2014101701.qcow2}, 'Find master android-ubuntu-12.04-64');
is (displaynameToMastername(q{scientific-6.5-32-01-batlab}, \@filenames), q{condor-scientific-6.5-32-01-batlab-master-2014061101.qcow2},'Find master scientific-6.5-32-01-batlab');

is (displaynameToMastername(q{rhel-6.4-64}, \@filenames), q{condor-rhel-6.4-64-master-2014021001.qcow2} , 'Find master rhel-6.4-64');

is (displaynameToMastername('fedora-18-64-01', \@filenames), q{condor-fedora-18-64-01-master-2014030601.qcow2}, 'Find master fedora 18-64 V2');
is (displaynameToMastername('fedora-18-64-01', \@filenames), q{condor-fedora-18-64-01-master-2014030601.qcow2}, 'Find master fedora 18-64 V2');
isnt (displaynameToMastername('fedora-18.0-64', \@filenames), q{condor-fedora-18.0-64-master-2013080001.qcow2}, 'skip old fedora 18-64 V1');
is (displaynameToMastername('fedora-18.0-64', \@filenames), q{condor-fedora-18.0-64-master-2013083001.qcow2}, 'Find master fedora 18-64 V1');
is (displaynameToMastername('codedx1.0.4-rhel-6.5-64-viewer', \@filenames), q{condor-codedx1.0.4-rhel-6.5-64-viewer-master-2014032001.qcow2},'Find master Code Dx 1.04');
isnt (displaynameToMastername('codedx1.0.4-rhel-6.5-64-viewer', \@filenames), q{condor-codedx1.0.4-rhel-6.5-64-viewer-master-2013032001.qcow2},'skip old Code Dx 1.04');
done_testing();
