#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

use strict;
use warnings;
use English '-no_match_vars';
use File::Basename qw(basename);
use File::Copy qw(copy);
use File::Spec::Functions;
use Log::Log4perl qw(:easy);
use FindBin;
use Archive::Tar;
use lib "../lib";
use SWAMP::vmu_Support qw{
	getSwampDir
	systemcall
	job_database_connect
	job_database_disconnect
};
use SWAMP::vmu_AssessmentSupport qw(
	copyAssessmentInputs
	isJavaPackage
	isRubyPackage
	isCPackage
    isScriptPackage
	isPythonPackage
	isDotNetPackage
);

my $dbuser = 'web';
my $dbpassword = 'swampinabox';
my $toolbase = '/swamp/store/SCATools';
my $log = Log::Log4perl->get_logger(q{});

sub _getPlatformIdentifiers {
    my $dbh = job_database_connect($dbuser, $dbpassword);
    if ($dbh) {
        my $query = q{SELECT platform_identifier FROM platform_store.platform_version};
        my $names = $dbh->selectcol_arrayref($query);
        job_database_disconnect($dbh);
        return $names if ($names && scalar(@$names));
    }   
    return;
}

sub _getToolPaths {
    my $dbh = job_database_connect($dbuser, $dbpassword);
    if ($dbh) {
        my $query = q{SELECT tool_path FROM tool_shed.tool_version};
        my $names = $dbh->selectcol_arrayref($query);
        job_database_disconnect($dbh);
        return $names if ($names && scalar(@$names));
	}
    return;
}

############################
# OLD copyAssessmentInputs #
############################

sub _parserDeploy { my ($opts) = @_;
    my $member = $opts->{'member'};
    my $tar = $opts->{'archive'};
    my $dest = $opts->{'dest'};
    if ($member =~ /parser-os-dependencies.conf/sxm) {
        $log->info("_parserDeploy - extract: $member to $dest/os-dependencies-parser.conf");
        $tar->extract_file($member, "$dest/os-dependencies-parser.conf");
    }
    if ($member =~ /in-files/sxm) {
        my $filename = basename($member);
        $log->info("_parserDeploy - extract: $member to $dest/$filename");
        $tar->extract_file($member, "$dest/$filename");
    }
    return;
}

sub _deployTarball { my ($tarfile, $dest) = @_ ;
    my $tar = Archive::Tar->new($tarfile, 1);
    my @list = $tar->list_files();
    my %options = ('archive' => $tar, 'dest' => $dest);
    foreach my $member (@list) {
        # Skip directory
        next if ($member =~ /\/$/sxm);
        $options{'member'} = $member;
        _parserDeploy(\%options);
    }
    return 1;
}

sub _deployTarByPlatform { my ($tarfile, $compressed, $dest, $platform) = @_ ;
    $log->info("_deployTarByPlatform - tarfile: $tarfile platform: $platform dest: $dest");
    my $iter = Archive::Tar->iter($tarfile, $compressed, {'filter' => qr/$platform/sxm});
    my $member = $iter->();
    if (! $member) {
        $iter = Archive::Tar->iter($tarfile, $compressed, {'filter' => qr/noarch/sxm});
        $member = $iter->();
    }
    if (! $member) {
        $log->error("_deployTarByPlatform - $platform and noarch not found in $tarfile");
    }
    while ($member) {
        if ($member->is_dir) {
            $member = $iter->();
            next;
        }
        if ($member->is_symlink) {
            my $linkname = $member->linkname;
            $linkname =~ s/^(?:\.\.\/)*//sxm;
            my $link = Archive::Tar->iter($tarfile, $compressed, {'filter' => qr/$linkname/sxm})->();
            if ($link->is_dir) {
                $linkname = $link->name;
                my $linkiter = Archive::Tar->iter($tarfile, $compressed, {'filter' => qr/$linkname/sxm});
                while (my $linkmember = $linkiter->()) {
                    if ($linkmember->is_dir) {
                        $member = $iter;
                        next;
                    }
                    my $basename = basename($linkmember->name);
                    my $destname = $dest . qq{/}. $basename;
                    if ($linkmember->name =~ m/swamp-conf\/sys-os-dependencies.conf/sxm) {
                        $destname = $dest . qq{/os-dependencies-framework.conf};
                    }
                    $log->info("_deployTarByPlatform - extract symlink dir: $destname to $dest");
                    $linkmember->extract($destname);
                }
            }
            else {
                my $basename = basename($link->name);
                my $destname = $dest . qq{/}. $basename;
                if ($link->name =~ m/swamp-conf\/sys-os-dependencies.conf/sxm) {
                    $destname = $dest . qq{/os-dependencies-framework.conf};
                }
                $log->info("_deployTarByPlatform - extract symlink file: $destname to $dest");
                $link->extract($destname);
            }
        }
        else {
            my $basename = basename($member->name);
            my $destname = $dest . qq{/}. $basename;
            if ($member->name =~ m/swamp-conf\/sys-os-dependencies.conf/sxm) {
                $destname = $dest . qq{/os-dependencies-framework.conf};
            }
            $log->info("_deployTarByPlatform - extract file: $destname to $dest");
            $member->extract($destname);
        }
        $member = $iter->();
    }
    return;
}

sub _copyFramework { my ($bogref, $basedir, $dest) = @_ ;
    my $file;
    if (isJavaPackage($bogref)) {
        $file = "$basedir/thirdparty/java-assess.tar";
    }
    elsif (isRubyPackage($bogref)) {
        $file = "$basedir/thirdparty/ruby-assess.tar";
    }
    elsif (isCPackage($bogref)) {
        $file = "$basedir/thirdparty/c-assess.tar";
    }
    elsif (isScriptPackage($bogref) || isPythonPackage($bogref) || isDotNetPackage($bogref)) {
        $file = "$basedir/thirdparty/script-assess.tar";
    }
    my $compressed = 0;
    if (! -r $file) {
		$file .= '.gz';
		$compressed = 1;
    	if (! -r $file) {
        	$log->error($bogref->{'execrunid'}, "Cannot see assessment toolchain $file");
        	return 0;
		}
    }
    my $platform_identifier = $bogref->{'platform_identifier'} . qq{/};
	$log->info("using framework: $file $compressed on platform: $platform_identifier");
    _deployTarByPlatform($file, $compressed, $dest, $platform_identifier);
    if (-r "$dest/os-dependencies-framework.conf") {
        $log->info("Adding $dest/os-dependencies-framework.conf");
        system("cat $dest/os-dependencies-framework.conf >> $dest/os-dependencies.conf");
    }

    # remove empty os-dependencies file
    if (-z "$dest/os-dependencies.conf") {
        unlink("$dest/os-dependencies.conf");
    }
    else {
        SWAMP::vmu_AssessmentSupport::_mergeDependencies("$dest/os-dependencies.conf");
    }

    return 1;
}

# first check for files with platform in the path
# if none found
# then check for files with noarch in the path
# if symbolic links are found, pass back to caller
# and call again recursively - nested links are not handled
sub _copy_tool_files { my ($tar, $files, $platform, $dest) = @_ ;
	my $retval = [];
    my $found = 0;
    foreach my $file (@{$files}) {
    	next if ($file->name =~ m/\/$/sxm);
    	next if ($file->name !~ m/$platform/sxm);
    	if ($file->is_symlink) {
        	push @{$retval}, $file;
            next;
        }
        my $filename = basename($file->name);
        $log->debug('_copy_tool_files - extract: ', $file->name, " to $dest/$filename");
        if (! $tar->extract_file($file->name, "$dest/$filename")) {
			$log->error();
			return ($retval, 0);
		}
        $found = 1;
    }
    if (! $found) {
        foreach my $file (@{$files}) {
            next if ($file->name =~ m/\/$/sxm);
            next if ($file->name !~ m/noarch/sxm);
            my $filename = basename($file->name);
            $log->debug('_copy_tool_files - extract: ', $file->name, " to $dest/$filename");
            if (! $tar->extract_file($file->name, "$dest/$filename")) {
				$log->error();
				return ($retval, 0);
			}
        }
    }
    return ($retval, 1);
}

sub _copyInputsTools { my ($bogref, $dest) = @_ ;
    my $tar = Archive::Tar->new($bogref->{'toolpath'}, 1);
	if (! $tar) {
		$log->error();
		return 0;
	}
    my @files = $tar->get_files();
	if (! @files || ! scalar(@files)) {
		$log->error();
		return 0;
	}
    # if tool bundle uses symbolic link for this platform handle that here
    my ($links, $status) = _copy_tool_files($tar, \@files, $bogref->{'platform_identifier'}, $dest);
	if (! $status) {
		$log->error();
		return 0;
	}
    foreach my $link (@{$links}) {
        (undef, $status) = _copy_tool_files($tar, \@files, $link->linkname, $dest);
		if (! $status) {
			$log->error();
			return 0;
		}
    }
    if (-r "$dest/os-dependencies-tool.conf") {
        $log->info("Adding $dest/os-dependencies-tool.conf");
        system("cat $dest/os-dependencies-tool.conf >> $dest/os-dependencies.conf");
    }
    # merge tool-os-dependencies.conf into os-dependencies.conf if extant
    if (-r "$dest/tool-os-dependencies.conf") {
        $log->info("Adding $dest/tool-os-dependencies.conf");
        system("cat $dest/tool-os-dependencies.conf >> $dest/os-dependencies.conf");
    }
    return 1;
}

sub old_copyAssessmentInputs { my ($bogref, $dest) = @_ ;
    if (! defined($bogref->{'packagepath'})) {
        $log->error($bogref->{'execrunid'}, "BOG is missing packagepath specification.");
        return 0;
    }
	if (! -r $bogref->{'packagepath'}) {
        $log->error($bogref->{'execrunid'}, ' package: ', $bogref->{'packagepath'}, ' not readable.');
		return 0;
	}
    if (!defined( $bogref->{'toolpath'})) {
        $log->error($bogref->{'execrunid'}, "BOG is missing toolpath specification.");
        return 0;
    }
	if (! -r $bogref->{'toolpath'}) {
        $log->error($bogref->{'execrunid'}, ' tool: ', $bogref->{'toolpath'}, ' not readable.');
		return 0;
	}
	my $status;
	eval {
		$status = _copyInputsTools($bogref, $dest);
	};
	if ($@ || ! $status) {
		$log->error("_copyInputsTools failed for: ", $bogref->{'toolpath'}, ' status: ', defined($status) ? $status : 'no status',  " eval result: $@");
		return 0;
	}
	
    my $basedir = getSwampDir();
    # copy services.conf to the input destination directory
	my $servicesconf = catfile($basedir, 'etc', 'services.conf');
    if (! copy($servicesconf, $dest)) {
        $log->error($bogref->{'execrunid'}, "Cannot copy $servicesconf to $dest $OS_ERROR");
        return 0;
    }
	
    # Copy the package tarball into VM input folder from the SAN.
    if (! copy($bogref->{'packagepath'}, $dest)) {
        $log->error($bogref->{'execrunid'}, "Cannot read packagepath $bogref->{'packagepath'} $OS_ERROR");
        return 0;
    }

    SWAMP::vmu_AssessmentSupport::_addUserDepends($bogref, "$dest/os-dependencies.conf");
    my $file = "$basedir/thirdparty/resultparser.tar";
    _deployTarball($file, $dest);
    # Add result parser's *-os-dependencies.conf to the mix, and merge for uniqueness
    if (-r "$dest/os-dependencies-parser.conf") {
        $log->info("Adding $dest/os-dependencies-parser.conf");
        system("cat $dest/os-dependencies-parser.conf >> $dest/os-dependencies.conf");
    }

    if (! _copyFramework($bogref, $basedir, $dest)) {
        return 0;
    }

    return 1;
}

my $oldinputfolder = q{oldin};
my $newinputfolder = q{newin};
sub create_folders {
	if (-d $newinputfolder) {
		system("rm -rf $newinputfolder");
	}
	mkdir $newinputfolder;
	if (! -d $newinputfolder) {
		print "Error - $newinputfolder not found\n";
		exit(0);
	}
	if (-d $oldinputfolder) {
		system("rm -rf $oldinputfolder");
	}
	mkdir $oldinputfolder;
	if (! -d $oldinputfolder) {
		print "Error - $oldinputfolder not found\n";
		exit(0);
	}
}

Log::Log4perl->easy_init($ERROR);

my $toolpaths = [];
my $platform_identifiers = [];
if (defined($ARGV[0])) {
	my $toolfile = $ARGV[0];
	my $platform_identifier = $ARGV[1];
	if (! $platform_identifier) {
		$platform_identifier = 'ubuntu-16.04-64';
	}
	if ($platform_identifier =~ m/^all$/i) {
		$platform_identifiers = _getPlatformIdentifiers();
	}
	else {
		push @$platform_identifiers, $platform_identifier;
	}
	my $toolpath;
	if (-r $toolfile) {
		$toolpath = $toolfile;
	}
	else {
		my $tooldir = 'bundled';
		$toolpath = catfile($toolbase, $tooldir, $toolfile);
		if (! -r $toolpath) {
			$tooldir = 'MIR';
			$toolpath = catfile($toolbase, $tooldir, $toolfile);
		}
	}
	push @$toolpaths, $toolpath;
}
else {
	$toolpaths = _getToolPaths();
	$platform_identifiers = _getPlatformIdentifiers();
}

my $execrunuid = 0;
my $packagepath = '/swamp/store/SCAPackages/e1031386-a303-4fa8-96d5-41d7969bf820/snappy-c-master.zip';
foreach my $toolpath (@$toolpaths) {
	next if (! -r $toolpath);
	foreach my $platform_identifier (@$platform_identifiers) {
		create_folders();
		my $bogref = {
			'execrunid'				=> $execrunuid++,
			'packagepath'			=> $packagepath,
			'packagetype'			=> 'C/C++',
			'toolpath'				=> $toolpath,
			'platform_identifier'	=> $platform_identifier,
		};
		my $old_result = old_copyAssessmentInputs($bogref, $oldinputfolder);
		my ($new_result, $error_output) = copyAssessmentInputs($bogref, $newinputfolder);
		if ($old_result && $new_result) {
			my $cmd = qq{diff -r $oldinputfolder $newinputfolder};
			my ($output, $status, $error_output) = systemcall($cmd, 1);
			print "$toolpath $platform_identifier\n";
			if ($status) {
				chomp $output;
				chomp $error_output;
				print "$cmd $status - output:\n$output\nerror: $error_output\n" if ($status);
			}
		}
		else {
			print "$toolpath $platform_identifier\n";
			print "\t$error_output\n" if ($error_output);
			print "\n";
		}
	}
}
