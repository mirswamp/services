# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

package VMTools;

use 5.010;
use utf8;
use strict;
use warnings;
use FindBin qw($Bin);
use parent qw(Exporter);
use English '-no_match_vars';
use File::Spec qw(catfile);
use XML::Simple;
use File::Basename qw(basename);
use lib ("$FindBin::Bin/lib", "$FindBin::Bin/../perl5", "/opt/swamp/perl5");

# TODO: currently relies upon module existing in /opt/swamp/perl5, consider
# packaging VMTools such that you don't have to rely on an absolute path
use SWAMP::vmu_Support qw(
    getLoggingConfigString
    systemcall
);

use constant 'ONEK' => 1024;
use Log::Log4perl;

BEGIN {
    $VMTools::VERSION = '1.04';
}
our (@EXPORT_OK);

BEGIN {
    require Exporter;
    @EXPORT_OK = qw(checkEffectiveUser displaynameToMastername extractOutput 
      startVM
      defineVM
      destroyVM
      inspectmaster
      getvmdeltafilename 
      getvmbackingfilename
      rebasevm
      removeVM
      isMasterImage
      masterizeName
      listMasters
      listVMs
      createImages
      createXML
      _getLoggingConfigString
      masternameToDisplayname
      masterimagefolder
      vmconvert
      setvmprojectdir
      setvmimagedir
      vmVNCDisplay
      vmExists
      vmState);
}

my $VIRSH        = '/usr/bin/virsh';
my $QEMUIMG      = '/usr/bin/qemu-img';
my $MAKEFS       = '/usr/bin/virt-make-fs';
my $GUESTFISH    = '/usr/bin/guestfish';
my $SHRED        = '/usr/bin/shred';
# my $TEMPLATE_VM  = '/usr/local/etc/swamp/templ.xml';
my $TEMPLATE_VM  = "$Bin/templ.xml";
my $SYSTEMPREFIX = q{};

# my $MASTER_IMAGE_FOLDER = '/var/lib/libvirt/images';
my $MASTER_IMAGE_FOLDER = '/swamp/platforms/images';
my $PROJECT_FOLDER      = '/swamp/working/project';
my $EMPTY               = '/usr/local/empty';
my $origusername  = 'unknown';
my $log = Log::Log4perl->get_logger(q{});

sub isMasterImage {
    my ($name) = @_;
    my $ret = 0;
    if ( $name =~ /^condor-(\w+-[\d.]+-\d\d)-(\d\d)-master-(\d+).qcow2$/mxs) {
        #say "<$1><$2><$3>";
        if ($1 =~ /32$/sxm || $1 =~ /64$/sxm) {
            $ret = 2;
        }
    }
    elsif ( $name =~ /^condor.*-master-\d+.qcow2$/mxs ) {
        $ret = 1;
    }
    return $ret;
}

sub displaynameToMastername {
    my $name = shift;
    my $fileref = shift; # optional
    my @files;
    if (!defined($fileref)) {
        opendir( my $dir, $MASTER_IMAGE_FOLDER )
          or $log->error("Cannot opendir $MASTER_IMAGE_FOLDER $ERRNO");
        @files = readdir($dir);
        closedir($dir);
    }
    else {
        foreach (@{$fileref}) {
            push @files, $_;
        }
    }
    my $maxImage = 0;
    foreach (@files) {
        next if ( $_ eq qq{.} || $_ eq qq{..} );
        if ( isMasterImage($_) && $_ =~ /condor-${name}-master/mxs ) {
            $_ =~ s/^.*master-//mxs;
            $_ =~ s/.qcow2$//mxs;
            if ( $_ > $maxImage ) {
                $maxImage = $_;
            }
        }
    }
    if ( $maxImage > 0 ) {
        #return "condor-${name}-master-${maxImage}.qcow2";
        return masterizeName ($name, $maxImage);
    }
    return;
}
sub masterizeName {
    my $relname = shift;
    my $internalVersion = shift;
    return "condor-${relname}-master-${internalVersion}.qcow2";
}

sub masternameToDisplayname {
    my ($name) = @_;
    $name =~ s/^condor-(.*)-master-\d+.qcow2/$1/mxs;
    return $name;
}

sub masterimagefolder {
    return $MASTER_IMAGE_FOLDER;
}

#** @function inspectmaster( $mastername )
# @brief Run virt-inspect2 on a master image (.qcow2)
#
# @param mastername The name of the masterfile (file only, no folder). This can be
# either shorten output from --list option or full from --list --full option.
# @return XML output listing inspection results -or- An error string.
#*
sub inspectmaster {
    my $mastername = shift;
    my $file;
    if (isMasterImage($mastername)) { 
        $file = File::Spec->catfile($MASTER_IMAGE_FOLDER, $mastername);
    }
    else {
        $file = File::Spec->catfile($MASTER_IMAGE_FOLDER, displaynameToMastername($mastername));
    }
    my ( $output, $status ) = ( $_ = qx{virt-inspector2 $file 2>/dev/null}, $CHILD_ERROR >> 8 );
    if (!$status) {
        return $output;
    }
    else {
        $log->error("Unable to run inspection of master on $file from system $status");
        return "ERROR: Unable to run virt-inspect on $file:\nerror from system $status";
    }
}

# Full master names are of the form 'condor-distro-master-YYYYMMDD.qcow2
# condor-fedora-18.0-64-master-2013060301.qcow2
sub listMasters {
    my $fullnames = shift // 0;
    my @list;
    if ( -d $MASTER_IMAGE_FOLDER ) {
        opendir( my $dir, $MASTER_IMAGE_FOLDER );
        my @files = readdir $dir;
        closedir $dir;
        my %masters;
        foreach (@files) {
            if ( isMasterImage($_) ) {
                if ($fullnames) {
                    push @list, $_;
                }
                else {
                    $masters{masternameToDisplayname($_)} = 1;
                }
            }
        }
        if (!$fullnames) {
            foreach ( keys %masters ) {
                push @list, $_;
            }
        }
    }
    return @list;
}

sub vmVNCDisplay {
    my ($vmname) = @_;
    my ( $output, $status ) = systemcall("$VIRSH vncdisplay $vmname");
    if ($status) {
        $log->error("Unable to get vncdisplay: reported error is $output");
        return 1;
    }
    else {
        # print "$output";
        $log->error("$output");
    }
    return 0;
}

# Return 1 if VM exists, 0 otherwise
sub vmExists {
    my ($vmname) = @_;
    my ( $output, $status ) = systemcall("$VIRSH list --all --name");
    if ($status) {
        $log->error("Unable to obtain list of VMs: error reported is $output");
        return 0;
    }
    my @vms = split( /\n/mxs, $output );
    foreach (@vms) {
        chomp;
        if ( $_ eq $vmname ) {
            return 1;
        }
    }
    return 0;
}

sub vmState {
    my ($vmname) = @_;
    my ( $output, $status ) = systemcall("$VIRSH domstate $vmname");
    if ( !$status ) {
        chomp $output;
        chomp $output;
        return $output;
    }
    else {
        $log->error("Unable to obtain VM state: error reported is $output");
        return "undefined";
    }
}

# Start a VM
sub startVM {
    my ($vmname) = @_;
    my $ret = 1;
    if ( vmExists($vmname) ) {
        my $state = vmState($vmname);

        # NB: A state table could simplify this code
        if ( $state eq "shut off" ) {
            my ( $output, $status ) = systemcall("$VIRSH start $vmname");
            if ($status) {
                $log->error("VM $vmname cannot be started: error reported is $output");
            }
            else {
                # Make a symlink to the vm log
                my $dir = getVMDir($vmname);
                if ( !-r "$dir/${vmname}.log" ) {
                    systemcall("/bin/ln -s /var/log/libvirt/qemu/${vmname}.log $dir/${vmname}.log");
                }
                $ret = 0;
            }
        }    
        # VM states that are not shut off
        elsif ( $state eq "paused" ) {
            $log->error("VM '$vmname' is currently running but suspended.");
        }
        elsif ( $state eq "in shutdown" ) {
            $log->erorr("VM '$vmname' is currently shutting down.");
        }
        elsif ( $state eq "running" ) {
            $log->error("VM '$vmname' is already started.");
        }
        else {
            $log->error("VM '$vmname' unknown state [$state]");
        } 
    }
    else {
        $log->error("Cannot find a VM named $vmname");
    }
    return $ret;
}

sub vmconvert {
    my $masterfile = shift;
    my $vmwarefile = shift;
    my ($output, $status) = systemcall(qq{$QEMUIMG convert $masterfile -O vmdk $vmwarefile});
    if ($status) {
        $log->error("Error converting $masterfile to $vmwarefile: $output");
        return 0;
    }
    return 1;
}
sub getvmbackingfilename {
    my $vmname = shift;
    my $delta = getvmdeltafilename($vmname);
    my ($output, $status) = systemcall(qq{$QEMUIMG info $delta  | /bin/sed -e' /backing/!d' -e 's/^backing file: //'});
    if ($status) {
        return;
    }
    else {
        chomp $output;
        return $output;
    }
}
sub rebasevm {
    my $vmdeltafile = shift;
    my $masterfile  = shift;
    my ( $output, $status ) = systemcall(qq{$QEMUIMG rebase -u -b $masterfile $vmdeltafile});
    if ($status) {
        $log->error("Error rebasing $vmdeltafile onto $masterfile $OS_ERROR ($output)");
        return 0;
    }
    else {
        # This writes the deltas in the VM file to the new master image (which
        # is now the VM's backing file)
        ( $output, $status ) = systemcall(qq{$QEMUIMG commit $vmdeltafile});
        if ($status) {
            $log->error("Error committing $vmdeltafile: $OS_ERROR ($output)");
            return 0;
        }
        return 1;
    }

}
sub getvmdeltafilename {
    my $vmname = shift;
    return getVMDir($vmname)."/${vmname}.qcow2";
}
sub getVMDir {
    my ($vmname) = @_;
    if ( defined $vmname ) {
        return "${PROJECT_FOLDER}/${vmname}";
    }
    else {
        return "${PROJECT_FOLDER}";
    }
}

#** @function setvmimagedir( $dir )
# @brief Override location of master image folder. BatLab will most likely be the only client of this behavior.
#
# @param dir the new directory that to be searched for master images. 
# N.B. this should be called BEFORE anything else uses accessing master images.
# @return 1 if the provided path is a directory at the time of the call, 0 otherwise.
#*
sub setvmimagedir {
    my $dir = shift // q{};
    if ( -d $dir ) {
        $MASTER_IMAGE_FOLDER = $dir;
        return 1;
    }
    return 0;
}
#** @function setvmprojectdir( $dir )
# @brief Override location of vm project folder. BatLab will most likely be the only client of this behavior.
#
# @param dir the new directory that to be used for input/output/delta qcow images
# N.B. this should be called BEFORE anything else begins VM creation.
# @return 1 if the provided path is a directory at the time of the call, 0 otherwise.
#*
sub setvmprojectdir {
    my $dir = shift // q{};
    if ( -d $dir ) {
        $PROJECT_FOLDER = $dir;
        return 1;
    }
    return 0;
}

sub extractOutput {
    my ( $dirpath, $vmname ) = @_;
    if ( !-d $dirpath ) {
        $log->error("$dirpath does not exist");
        return 1;
    }
    my $vmdir = getVMDir($vmname);
    open( my $script, '>', "$vmdir/gfout.sh" )
      or $log->error("Cannot create guestfish script $ERRNO");
    print $script "add $vmdir/outputdisk.qcow2\n";
    print $script "run\n";
    print $script "mount /dev/sda /\n";
    print $script "glob copy-out /* $dirpath\n";
    close $script or $log->erorr("Cannot close guestfish script $OS_ERROR");
    my ( $output, $status ) = systemcall("${GUESTFISH} -f $vmdir/gfout.sh");

    if ($status) {
        $log->error("Output extraction failed: $output $status");
        return 1;
    }
    return 0;
}

sub createImages {
    my ( $dirpath, $vmname, $imagename, $outsize, $makeMaster ) = @_;

    my $output = q{};
    my $status = 0;
    my $vmdir  = getVMDir($vmname);
    my $ostype = 'unknown';
    my $fstype = 'ext3';                          # default file system type
    mkdir("$vmdir");

    # If not a master image, use master as a backing file.
    if ( $makeMaster == 0 ) {
        $imagename = displaynameToMastername($imagename);
        $log->info("Creating base image for VM \"$vmname\"");
        ( $output, $status ) = systemcall(
"$QEMUIMG create -b ${MASTER_IMAGE_FOLDER}/${imagename} -f qcow2 ${vmdir}/${vmname}.qcow2"
        );
        if ($status) {
            $log->error("Image creation failed: $output $status");
            return 1;
        }
        open( my $script, '>', "$vmdir/gf.sh" )
          or $log->error("Cannot create guestfish script $ERRNO");
        print $script "#!${GUESTFISH} -f\n";

        # Command to run run.sh from init scripts
        my $runshcmd =
"\"#!/bin/bash\\n/bin/chmod 01777 /mnt/out;[ -r /etc/profile.d/vmrun.sh ] && . /etc/profile.d/vmrun.sh;[ -r /opt/swamp/etc/profile.d/vmrun.sh ] && . /opt/swamp/etc/profile.d/vmrun.sh;/bin/chown 0:0 /mnt/out;/bin/chmod +x /mnt/in/run.sh && cd /mnt/in && nohup /mnt/in/run.sh > /mnt/out/nohup.out 2>&1 &\\n\"";

        # NB: This logic should be table driven and from a config file, not
        # hardcoded.
        # Based on the OS, need to modify various files
        my $osimage = $imagename;
        $osimage =~ s/sysprep//msg;
        $osimage =~ s/wkstn//msg;
        ( $ostype, $status ) = SWAMP::vmu_Support::_insertIntoInit( $osimage, $script, $runshcmd, $vmname, $imagename );
        if ( $status == 1 ) {    # error already emitted
            return $status;
        }

        $log->info("Modifying base image: type detected $ostype");

        # 8/19/2013 Adding files for Jeff G's manifest scripts to parse
        $imagename = basename($imagename);
        $imagename =~ s/\.qcow2$//sxm;
        print $script "write /etc/vm-master-name \"$imagename\\n\"\n";
        print $script "write /etc/vm-master-mode \"interactive\\n\"\n";

        print $script "\n";
        close $script or $log->error("Cannot close guestfish script $OS_ERROR");

        # if we are a Windows OS, don't run the guest fish script
        if ( $ostype !~ /Windows/mxs ) {
            ( $output, $status ) =
              systemcall("${GUESTFISH} -f $vmdir/gf.sh -a ${vmdir}/${vmname}.qcow2 -i </dev/null");
            if ($status) {
                $log->error("Image modification failed: $output $status");
                return 1;
            }
        }
    }
    else {
        # Handle the master image case.
        if ( $makeMaster == 1 ) {

            open( my $script, '>', "$vmdir/gf.sh" )
              or $log->error("Cannot create guestfish script $ERRNO");
            print $script "#!${GUESTFISH} -f\n";

            # 8/19/2013 Adding files for Jeff G's manifest scripts to parse
            my $name = basename($imagename);
            $name =~ s/\.qcow2$//sxm;
            print $script "write /etc/vm-master-name \"$name\\n\"\n";
            print $script "write /etc/vm-master-mode \"master\\n\"\n";
            print $script "\n";
            close $script or $log->error("Cannot close guestfish script $OS_ERROR");
            ( $output, $status ) = systemcall("${GUESTFISH} -f $vmdir/gf.sh -a $imagename -i </dev/null");

            if ($status) {
                $log->error("Image modification failed: $output $status");
                return 1;
            }
        }

    }

    if ( $ostype =~ /Windows/mxs ) {
        $fstype = 'vfat --partition=mbr';
    }

    if ( $makeMaster != 0 ) {
        $log->info("Creating input disk image");
        ( $output, $status ) = systemcall(

         #"$MAKEFS --type=ext3 --size=+${outsize}M --format=qcow2 ${EMPTY} ${vmdir}/inputdisk.qcow2"
"$MAKEFS --type=${fstype} --size=+${outsize}M --format=qcow2 ${EMPTY} ${vmdir}/inputdisk.qcow2"
        );
    }
    else {
        if ( -d $dirpath ) {
            $log->info("Creating input disk image");

            # It has been seen that virt-make-fs incorrectly estimates the size
            # of filesystems with .zip files in them. Pad by +10M.
            ( $output, $status ) = systemcall(

 #                "$MAKEFS --type=ext3 --size=+1G --format=qcow2 $dirpath ${vmdir}/inputdisk.qcow2"
				"$MAKEFS --type=${fstype} --size=+1G --format=qcow2 $dirpath ${vmdir}/inputdisk.qcow2"
            );
            if ($status) {
                $log->info("Input disk creation failed: $output");
                return 1;
            }
        }
        else {
            $log->info("Input disk folder $dirpath does not exist.");
            return 1;
        }
    }

    $log->info("Creating output disk image");
    ( $output, $status ) = systemcall(

#        "$MAKEFS --type=ext3 --size=+${outsize}M --format=qcow2 ${EMPTY} ${vmdir}/outputdisk.qcow2"
"$MAKEFS --type=${fstype} --size=+${outsize}M --format=qcow2 ${EMPTY} ${vmdir}/outputdisk.qcow2"
    );
    if ($status) {
        $log->error("output disk creation failed: $output");
        return 1;
    }
    
    $log->info("Creating export disk image");
	($output, $status) = systemcall("qemu-img create -f raw ${vmdir}/${vmname}-events.raw 2M");
	if ($status) {
        $log->error("qemu-img create export disk creation failed: $output");
		return 1;
	}
	($output, $status) = systemcall("mkfs.ext2 -F ${vmdir}/${vmname}-events.raw");
	if ($status) {
        $log->error("mkfs.ext2 export disk creation failed: $output");
		return 1;
	}
    return 0;
}

sub createXML {
    my %options=(@_);
    my $vmname = $options{'vmname'};
    my $nCPU = $options{'nCPU'};
    my $memMB = $options{'memMB'};
    my $imagename = $options{'imagename'};
    my $macaddr = $options{'macaddr'};
    my $makeMaster = $options{'isMaster'};
#    my ( $vmname, $nCPU, $memMB, $imagename, $macaddr, $makeMaster ) = @_;
    my $xs = XML::Simple->new( 'KeepRoot' => 1, 'ForceArray' => 1, 'NoSort' => 1 );
    if ( !-r $TEMPLATE_VM ) {
        $log->error("Cannot read xml template $TEMPLATE_VM");
        return 1;
    }

    # Slurp in the XML template
    my $xmlref = $xs->XMLin($TEMPLATE_VM);
    $memMB *= ONEK;    # needs to be represented as KB
    $xmlref->{'domain'}[0]->{'name'}[0]                       = "$vmname";
    $xmlref->{'domain'}[0]->{'vcpu'}[0]->{'content'}          = "$nCPU";
    $xmlref->{'domain'}[0]->{'memory'}[0]->{'content'}        = "$memMB";
    $xmlref->{'domain'}[0]->{'currentMemory'}[0]->{'content'} = "$memMB";
    if ( defined( $xmlref->{'domain'}[0]->{'uuid'}[0] ) ) {
        undef $xmlref->{'domain'}[0]->{'uuid'}[0];
    }
    if (defined($macaddr)) {
        $xmlref->{'domain'}[0]->{'devices'}[0]->{'interface'}[0]->{'mac'}[0]->{'address'}= "$macaddr";

    }
    my $disks = $xmlref->{'domain'}[0]->{'devices'}[0]->{'disk'};
    my $vmdir = getVMDir($vmname);
    mkdir("$vmdir");
    my $baseimage;

    if ($makeMaster) {
        $baseimage = $imagename;
    }
    else {
        $baseimage = "${vmdir}/${vmname}.qcow2";
    }
    foreach my $disk ( @{$disks} ) {
        if ( $disk->{'target'}[0]->{'dev'} eq "sda" ) {
            $disk->{'source'}[0]->{'file'} = $baseimage;
        }
        elsif ( $disk->{'target'}[0]->{'dev'} eq "sdb" ) {
            $disk->{'source'}[0]->{'file'} = "${vmdir}/inputdisk.qcow2";
        }
        elsif ( $disk->{'target'}[0]->{'dev'} eq "sdc" ) {
            $disk->{'source'}[0]->{'file'} = "${vmdir}/outputdisk.qcow2";
        }
        elsif ( $disk->{'target'}[0]->{'dev'} eq "sdd" ) {
            $disk->{'source'}[0]->{'file'} = "${vmdir}/${vmname}-events.raw";
        }
    }
    my $xmlout = $xs->XMLout($xmlref);
    if ( open( my $out, '>', "$vmdir/${vmname}.xml" ) ) {
        print $out $xmlout;
        close $out or $log->error("Cannot write to VM XML file $OS_ERROR");
        return 0;
    }
    else {
        $log->error("Cannot create XML $ERRNO");
        return 1;
    }
}

sub destroyVM {
    my ($vmname) = @_;
    my ( $output, $status ) = systemcall("$VIRSH destroy $vmname");
    if ($status) {
        $log->error("Unable to undefine $vmname: $output");
        return 1;
    }
    return 0;
}

sub removeVM {
    my ($vmname) = @_;
    my ( $output, $status ) = systemcall("$VIRSH undefine $vmname");
    if ($status) {
        $log->error("Unable to undefine $vmname: $output");
        return 1;
    }

    # Got here, ok to shred files and folder.
    my $folder = getVMDir($vmname);
    opendir( my $dir, $folder )
      or $log->info("Cannot find vm folder $folder $ERRNO\n");
    my @files = readdir($dir);
    closedir($dir);
    foreach (@files) {
        my $name = "$folder/$_";
        if ( -f $name ) {
            if ( -l $name ) {    # Do not shred symlinks, just remove.
                unlink($name);
            }
            else {
                #                ( $output, $status ) = systemcall("$SHRED -u $name");
                ( $output, $status ) = systemcall("/bin/rm -f $name");
            }
            if ($status) {
                $log->info("Unable to remove $name: $output");
                return 1;
            }
        }
    }
    rmdir $folder;
    return 0;
}

sub defineVM {
    my ($vmname) = @_;
    my $dir = getVMDir($vmname);
    my ( $output, $status ) = systemcall("$VIRSH define ${dir}/${vmname}.xml");
    my $ret = 0;
    if ( !$status ) {
        if ( open( my $id, '>', "${dir}/.creator" ) ) {
            print $id "$origusername\n";
            close $id or $log->info("Cannot close .creator file $OS_ERROR");
        }
    }
    else {
        $log->info("Unable to define VM: $output");
        $ret = 1;
    }
    return $ret;
}

sub listVMs {
    my $id = "unknown";
    if ( defined( $ENV{'SUDO_USER'} ) ) {
        $id = $ENV{'SUDO_USER'};
    }
    my @vms;
    if ( opendir( my $dir, $PROJECT_FOLDER ) ) {
        my @dirs = readdir $dir;
        closedir $dir;
        foreach (@dirs) {
            my $file = "$PROJECT_FOLDER/$_/.creator";
            if ( -r "$file" ) {
                if ( open( my $fh, '<', "$file" ) ) {
                    my $creatorID = <$fh>;
                    close $fh
                      or $log->error("Cannot close .creator file $OS_ERROR");
                    chomp $creatorID;
                    if ( $creatorID eq $id ) {
                        push @vms, $_;
                    }
                }
            }
        }
    }
    else {
        $log->info("Cannot read project folder.");
        return ();
    }
    return @vms;
}

# return 1 if OK to proceed, 0 otherwise
sub checkEffectiveUser {
    if ( defined( $ENV{'SUDO_USER'} ) ) {
        $origusername = $ENV{'SUDO_USER'};
    }
    my $username = getpwuid($EUID);
    if ( $username ne "root" ) {
        return 0;
    }
    return 1;
}

sub enableTestMode {
    $SYSTEMPREFIX = 'echo';

    mkdir $PROJECT_FOLDER;
    return;
}

sub _getLoggingConfigString {
        return getLoggingConfigString();
}
1;
__END__

=pod

=encoding utf8

=head1 NAME

VMTools - methods for creation and manipulating VMs 

=head1 SYNOPSIS

  use VMTools qw(init vmExists startVM pkgshutdown);

  my $vmname="rhel6VM1";
  init($vmname, "logging identity");

  if (vmExists($vmname)) {
    startVM($vmname);
  }

  pkgshutdown();

=head1 VERSION

version 0.900

=head1 DESCRIPTION

This package implements methods for creation and manipulation of VM images.

=over 4

=item logMsg

Write message to logs

@param message textual message to log

=item errorMsg

Write message to logs and standard error

@param message textual message to log

=back

=over 4

=item systemcall

  ($output, $status) = VMTools::systemcall("command");

Executes a command via Perl's L<system|system> function and returns STDOUT
and STDERR as output and the command's exit code as status.

@param command - the command to execute

@return output - the STDOUT of the execution

@return status - the return status code

=back

=cut
