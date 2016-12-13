# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#** @file SWAMP::AssessmentTools.pm
#
# @brief Methods for use by the assessmentTask
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 08/09/13 10:29:54
#*
#
package SWAMP::AssessmentTools;

use 5.014;
use utf8;
use strict;
use warnings;
use parent qw(Exporter);

BEGIN {
    our $VERSION = '1.00';
}
our (@EXPORT_OK);

BEGIN {
    require Exporter;
    @EXPORT_OK = qw(
    addUserDepends
      builderUser
      builderPassword
      copyInputs
      createAssessConfigs
      createMIRAssess
      debugMessage
      deployTarball
      errorMessage
      extractDepends
      getBOGValue
      infoMessage
      invokeResultCollector
	  isRubyTool
	  isFlake8Tool
	  isBanditTool
	  isAndroidTool
	  isHRLTool
	  isParasoftC
	  isParasoftJava
	  isParasoftTool
	  isGrammaTechCS
	  isGrammaTechTool
	  isRedLizardG
	  isRedLizardTool
      isJavaTool
      isJavaBytecodePackage
      mergeDependencies
      packageType
      parseStatusOut
      saveRunresults
      warnMessage
    );
}

use Archive::Tar;
use Carp qw(croak carp);
use Cwd qw(abs_path);
use English '-no_match_vars';
use File::Basename qw(dirname basename);
use File::Copy qw(move cp);
use File::Path qw(make_path);
use File::Spec qw(catfile);
use Log::Log4perl;
use Log::Log4perl::Level;

use SWAMP::Client::ResultCollectorClient qw(saveResult);
use SWAMP::SWAMPUtils qw(checksumFile systemcall getSWAMPDir trim saveProperties makezip getSwampConfig);
use SWAMP::PackageTypes qw(
  $C_CPP_PKG_STRING 
  $JAVA7SRC_PKG_STRING 
  $JAVA7BYTECODE_PKG_STRING 
  $JAVA8SRC_PKG_STRING 
  $JAVA8BYTECODE_PKG_STRING 
  $PYTHON2_PKG_STRING 
  $PYTHON3_PKG_STRING 
  $ANDROID_JAVASRC_PKG_STRING 
  $RUBY_PKG_STRING 
  $RUBY_SINATRA_PKG_STRING
  $RUBY_ON_RAILS_PKG_STRING
  $RUBY_PADRINO_PKG_STRING
  $ANDROID_APK_PKG_STRING 

  $CPP_TYPE 
  $PYTHON_TYPE 
  $JAVA_TYPE 
  $RUBY_TYPE
);

use constant 'PARSERID' => q{parse};
use constant 'FRAMEWORKID' => q{framework};

# first check for files with platform in the path
# if none found
# then check for files with noarch in the path 
# if symbolic links are found, pass back to caller
# and call again recursively - nested links are not handled
sub copy_tool_files { my ($tar, $files, $platform, $dest) = @_ ;
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
     	# print 'Extracting: ', $file->name, " to: $dest/$filename\n";
     	$tar->extract_file($file->name, "$dest/$filename");
		$found = 1;
	}
	if (! $found) {
		foreach my $file (@{$files}) {
			next if ($file->name =~ m/\/$/sxm);
			next if ($file->name !~ m/noarch/sxm);
			my $filename = basename($file->name);
			# print 'Extracting: ', $file->name, " to: $dest/$filename\n";
			$tar->extract_file($file->name, "$dest/$filename");
		}
	}
    return $retval;
}

sub copyInputsTools {
    my $bogref  = shift;
    my $dest    = shift;
	infoMessage($bogref->{'execrunid'}, qq{copyInputs copy tool files with platform: $bogref->{'platform'}});
	my $tar = Archive::Tar->new($bogref->{'toolpath'}, 1);
	my @files = $tar->get_files();
	# if tool bundle uses symbolic link for this platform handle that here
	my $links = copy_tool_files($tar, \@files, $bogref->{'platform'}, $dest);
	foreach my $link (@{$links}) {
		copy_tool_files($tar, \@files, $link->linkname, $dest);
	}
	if (-r "$dest/os-dependencies-tool.conf") {
		system("cat $dest/os-dependencies-tool.conf >> $dest/os-dependencies.conf");
	}
	# merge tool-os-dependencies.conf into os-dependencies.conf if extant
	if (-r "$dest/tool-os-dependencies.conf") {
		system("cat $dest/tool-os-dependencies.conf >> $dest/os-dependencies.conf");
	}
	return 1;
}

#** @function copyInputs( \%bogref )
# @brief Copy files from the shared filesystem into our input folder.
#
# @param bogref reference to a BOG containing at least toolpath and packagepath keys
# @return
# @see
#*
sub copyInputs {
    my $bogref  = shift;
    my $dest    = shift;
    my $testing = shift;
    make_path( $dest, { 'error' => \my $err } );
    if ( @{$err} ) {
        for my $diag ( @{$err} ) {
            my ( $file, $message ) = %{$diag};
            if ( $file eq q{} ) {
                errorMessage( $bogref->{'execrunid'}, "Cannot make input folder: $message" );
            }
            else {
                errorMessage( $bogref->{'execrunid'}, "Cannot make input folder: $file $message" );
            }
        }
        return 0;
    }
    if ( !defined( $bogref->{'packagepath'} ) ) {
        errorMessage( $bogref->{'execrunid'}, "BOG is missing packagepath specification." );
        return 0;
    }
    if ( !defined( $bogref->{'toolpath'} ) ) {
        errorMessage( $bogref->{'execrunid'}, "BOG is missing toolpath specification." );
        return 0;
    }
	if (! copyInputsTools($bogref, $dest)) {
		return 0;
	}
	# create services.conf in the input destination directory
	if (isParasoftTool($bogref)) {
    	my $config = getSwampConfig();
        my $value = $config->get('tool.ps-ctest.license.host');
		system("echo tool-ps-ctest-license-host = $value >> $dest/services.conf");
        $value = $config->get('tool.ps-ctest.license.port');
		system("echo tool-ps-ctest-license-port = $value >> $dest/services.conf");
        $value = $config->get('tool.ps-jtest.license.host');
		system("echo tool-ps-jtest-license-host = $value >> $dest/services.conf");
        $value = $config->get('tool.ps-jtest.license.port');
		system("echo tool-ps-jtest-license-port = $value >> $dest/services.conf");
	}
	elsif (isGrammaTechTool($bogref)) {
    	my $config = getSwampConfig();
        my $value = $config->get('tool.gt-csonar.license.host');
		system("echo tool-gt-csonar-license-host = $value >> $dest/services.conf");
        $value = $config->get('tool.gt-csonar.license.port');
		system("echo tool-gt-csonar-license-port = $value >> $dest/services.conf");
	}
	elsif (isRedLizardTool($bogref)) {
    	my $config = getSwampConfig();
        my $value = $config->get('tool.rl-goanna.license.host');
		system("echo tool-rl-goanna-license-host = $value >> $dest/services.conf");
        $value = $config->get('tool.rl-goanna.license.port');
		system("echo tool-rl-goanna-license-port = $value >> $dest/services.conf");
	}

    # Copy the package tarball into VM input folder from the SAN.
    if ( !cp( $bogref->{'packagepath'}, $dest ) ) {
        errorMessage( $bogref->{'execrunid'},
            "Cannot read packagepath $bogref->{'packagepath'} $OS_ERROR" );
        return 0;
    }
    
    # Here we extract the optional pkg-os-dependencies.conf files from the package tarball.
    # pkg-os-dependencies.conf => pkg-dependencies.conf
    #
    #
    addUserDepends($bogref, "$dest/os-dependencies.conf" );
    # per CSA-2001, we no longer need to use the hardcoded dependencies.
    #    extractDepends( $bogref, "$dest/os-dependencies.conf" );
    my $basedir = getSWAMPDir();
    my $file = abs_path("$basedir/thirdparty/resultparser.tar");
    if (!defined($testing)) {
        # Add result parser to the $dest (input) folder
        deployTarball(PARSERID, $file, $dest);
        # Add result parser's *-os-dependencies.conf to the mix, and merge for uniqueness
        if (-r "$dest/os-dependencies-parser.conf") {
            system("cat $dest/os-dependencies-parser.conf >> $dest/os-dependencies.conf");
        }
    }

    # Copy UW assessment tool(s)
    # This bit of code understands the file layout within the UW assessment tools and usually 
    # needs to be updated whenever they change formats.
    if ( !defined($testing) ) {
        if (!copyFramework($bogref, $basedir, $dest)) {
            return 0;
        }
    }

    # Copy watchdog script into input disk
    if ( !defined($testing) && !cp( "$basedir/etc/swamp_watchdog", $dest ) ) {
        errorMessage( $bogref->{'execrunid'}, "Cannot copy watchdog script $OS_ERROR" );
        return 0;
    }
    # Copy LOC tool
    if ( !defined($testing) && !cp( "$basedir/bin/cloc-1.60.pl", $dest ) ) {
        errorMessage( $bogref->{'execrunid'}, "Cannot copy LOC tool $OS_ERROR" );
        return 0;
    }
    return 1;
}

sub deployTarByPlatform { my ($tarfile, $compressed, $dest, $platform) = @_ ;
    my $iter = Archive::Tar->iter($tarfile, $compressed, {'filter' => qr/$platform/sxm});
	my $member = $iter->();
	if (! $member) {
    	$iter = Archive::Tar->iter($tarfile, $compressed, {'filter' => qr/noarch/sxm});
		$member = $iter->();
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
                    $linkmember->extract($destname);
                }
            }
            else {
                my $basename = basename($link->name);
                my $destname = $dest . qq{/}. $basename;
                if ($link->name =~ m/swamp-conf\/sys-os-dependencies.conf/sxm) {
                    $destname = $dest . qq{/os-dependencies-framework.conf};
                }
                $link->extract($destname);
            }
        }
        else {
            my $basename = basename($member->name);
            my $destname = $dest . qq{/}. $basename;
            if ($member->name =~ m/swamp-conf\/sys-os-dependencies.conf/sxm) {
                $destname = $dest . qq{/os-dependencies-framework.conf};
            }
            $member->extract($destname);
        }
		$member = $iter->();
    }
	return;
}

sub copyFramework {
    my $bogref  = shift;
    my $basedir = shift;
    my $dest = shift;
    my $file;
	if (isJavaPackage($bogref)) {
		$file = abs_path("$basedir/thirdparty/java-assess.tar.gz");
	}
	elsif (isRubyPackage($bogref)) {
		$file = abs_path("$basedir/thirdparty/ruby-assess.tar.gz");
	}
	elsif (isPythonPackage($bogref)) {
		$file = abs_path("$basedir/thirdparty/python-assess.tar.gz");
	}
	elsif (isCPackage($bogref)) {
		$file = abs_path("$basedir/thirdparty/c-assess.tar.gz");
	}
    if (! -r $file) {
        errorMessage($bogref->{'execrunid'}, "Cannot see assessment toolchain $file");
        return 1;
    }
	my $platform = $bogref->{'platform'} . qq{/};
	deployTarByPlatform($file, 1, $dest, $platform);
	if (-r "$dest/os-dependencies-framework.conf") {
		system("cat $dest/os-dependencies-framework.conf >> $dest/os-dependencies.conf");
	}

    # remove empty os-dependencies file
    if (-z "$dest/os-dependencies.conf") {
        unlink("$dest/os-dependencies.conf");
    }
    else {
        mergeDependencies("$dest/os-dependencies.conf");
    }
    return 1;
}

sub isRubyTool {
	my $bogref = shift;
	return (
		$bogref->{'toolname'} eq 'RuboCop' || 
		$bogref->{'toolname'} eq 'ruby-lint' ||
		$bogref->{'toolname'} eq 'Reek' ||
		$bogref->{'toolname'} eq 'Brakeman' ||
		$bogref->{'toolname'} eq 'Dawn'
	);
}
sub isRubyPackage {
    my $bogref = shift;
    return ( 
		$bogref->{'packagetype'} eq $RUBY_PKG_STRING ||
		$bogref->{'packagetype'} eq $RUBY_SINATRA_PKG_STRING ||
		$bogref->{'packagetype'} eq $RUBY_ON_RAILS_PKG_STRING ||
		$bogref->{'packagetype'} eq $RUBY_PADRINO_PKG_STRING
	);
}
sub isFlake8Tool {
	my $bogref = shift;
	return ($bogref->{'toolname'} eq 'Flake8');
}
sub isBanditTool {
	my $bogref = shift;
	return ($bogref->{'toolname'} eq 'Bandit');
}
sub isAndroidTool {
	my $bogref = shift;
	return ($bogref->{'toolname'} eq 'Android lint');
}
sub isHRLTool {
	my $bogref = shift;
	return ($bogref->{'toolname'} eq 'HRL');
}
sub isParasoftC {
    my $bogref = shift;
    return ($bogref->{'toolname'} eq 'Parasoft C/C++test');
}
sub isParasoftJava {
    my $bogref = shift;
    return ($bogref->{'toolname'} eq 'Parasoft Jtest');
}
sub isParasoftTool {
    my $bogref = shift;
    return (isParasoftC($bogref) || isParasoftJava($bogref));
}
sub isGrammaTechCS {
    my $bogref = shift;
    return ($bogref->{'toolname'} eq 'Grammatech CodeSonar');
}
sub isGrammaTechTool {
    my $bogref = shift;
    return (isGrammaTechCS($bogref));
}
sub isRedLizardG {
    my $bogref = shift;
    return ($bogref->{'toolname'} eq 'Red Lizard Goanna');
}
sub isRedLizardTool {
    my $bogref = shift;
    return (isRedLizardG($bogref));
}

#** @function isJavaTool ( \%bogref )
# @brief Return true if the tool is a java based tool, false otherwise. False 
# implies C/C++ or Python tool.
# @return true if the tool specified in \%bogref is for Java.
#*
sub isJavaTool {
    my $bogref = shift;
    return ( $bogref->{'toolname'} =~ /(Findbugs|PMD|Archie|Checkstyle|error-prone|Parasoft\ Jtest)/isxm);
}
sub isJavaPackage {
    my $bogref = shift;
    return (
		$bogref->{'packagetype'} eq $ANDROID_JAVASRC_PKG_STRING || 
		$bogref->{'packagetype'} eq $ANDROID_APK_PKG_STRING || 
		$bogref->{'packagetype'} eq $JAVA7SRC_PKG_STRING || 
		$bogref->{'packagetype'} eq $JAVA7BYTECODE_PKG_STRING ||
		$bogref->{'packagetype'} eq $JAVA8SRC_PKG_STRING || 
		$bogref->{'packagetype'} eq $JAVA8BYTECODE_PKG_STRING
	);
}
sub isJavaBytecodePackage {
    my $bogref = shift;
    return ( 
		$bogref->{'packagetype'} eq $JAVA7BYTECODE_PKG_STRING ||
		$bogref->{'packagetype'} eq $JAVA8BYTECODE_PKG_STRING
	);
}
sub isCTool {
    my $bogref = shift;
    return ( $bogref->{'toolname'} =~ /(GCC|Clang Static Analyzer|cppcheck)/isxm);
}
sub isCPackage {
    my $bogref = shift;
    return ( $bogref->{'packagetype'} eq $C_CPP_PKG_STRING);
}
sub isPythonTool {
    my $bogref = shift;
    return ( $bogref->{'toolname'} =~ /Pylint/isxm);
}
sub isPythonPackage {
    my $bogref = shift;
    return ( $bogref->{'packagetype'} eq $PYTHON2_PKG_STRING || $bogref->{'packagetype'} eq $PYTHON3_PKG_STRING);
}

sub packageType {
    my $bogref = shift;
    if (isJavaPackage($bogref)) {
        return $JAVA_TYPE;
    }
    elsif (isPythonPackage($bogref)) {
        return $PYTHON_TYPE;
    }
    elsif (isCPackage($bogref)) {
        return $CPP_TYPE;
    }
    elsif (isRubyPackage($bogref)) {
        return $RUBY_TYPE;
    }
    return;
}


#** @function idPackage( $archive )
# @brief Open a package file and detect the build a histogram of the languages.
#
# @param archive The name of file to assess. Assumed to be either tar or zip format.
# @return reference to a hash containing 2 keys 'c' and 'java' and the total number of files
# of each type found in the file as the key values.
#*
sub idPackage {
    my $archive = shift;
    my @filenames;
    my $extract;
    if ( $archive =~ /\.zip$/sxmi ) {
        $extract = 'unzip -l -qq';
    }
    else {
        $extract = 'tar tvf';
    }
    $archive = abs_path($archive);
    if ( open( my $fh, q{-|}, "$extract $archive" ) ) {
        while (<$fh>) {
            chomp;
            my @fields = split( /\ /sxm, $_ );
            push @filenames, pop @fields;
        }
        if ( !close $fh ) {

        }
    }

    # More languages could be added here.
    my %lang = ( 'c' => 0, 'java' => 0 );
    my %extensions = (
        'cpp'   => 'c',
        'cc'    => 'c',
        'cxx'   => 'c',
        'h'     => 'c',
        'hpp'   => 'c',
        'hxx'   => 'c',
        'java'  => 'java',
        'jar'   => 'java',
        'class' => 'java',
    );
    foreach my $file (@filenames) {
        my $filename = basename($file);
        my $id       = 'unk';
        foreach my $ext ( keys %extensions ) {
            if ( $filename =~ /\.$ext$/sxmi ) {
                $id = $extensions{$ext};
                last;
            }
        }
        $lang{$id}++;
    }
    return \%lang;
}

#** @function createMIRAssess( \%bogref, $dest)
# @brief Based on informaiton in the bogref, create the
# assess.sh script that will be called by run.sh. This is
# only done for the MIR toolchain.
#
# @param bogref reference to a hash that is the BOG (Bill of Goods).
# @param dest folder in which to create run.sh and assess.sh
# @return  1 on success, 0 on failure.
#*
sub createMIRAssess {
    my $bogref = shift;
    my $dest   = shift;    # 'input'
    my $ret    = 0;

    # Create the assess.sh script, which does the actual assessment
    if ( open( my $fd, '>', abs_path("${dest}/assess.sh") ) ) {

        my $toolpath  = basename( $bogref->{'toolpath'} );
        my $deploycmd = $bogref->{'tooldeploy'};
        $deploycmd =~ s/toolpath/$toolpath/sxmg;
        my $deploypkgcmd = $bogref->{'packagedeploy'};
        my $package      = basename( $bogref->{'packagepath'} );
        my $invoke       = $bogref->{'toolinvoke'};
        $invoke =~ s/%/,/sxmg;
        my $xsltcmd;

        if ( $bogref->{'toolname'} =~ /Findbugs/sxm ) {
            $invoke =~ s/-low/-low -xml:withMessages -projectName $bogref->{'packagename'}/sxm;
            my $path = $bogref->{'toolinvoke'};
            $path =~ s/\/.*$//sxm;
            $xsltcmd =
qq{<xslt in="Findbugs.xml" out="Findbugs.html" style="$path/src/xsl/fancy-hist.xsl"/>};
        }
        elsif ( $bogref->{'toolname'} =~ /PMD/sxm ) {
            my $path = $bogref->{'toolinvoke'};
            $path =~ s/\/.*$//sxm;
            $xsltcmd =
qq{<xslt in="PMD.xml" style="$path/etc/xslt/pmd-report-per-class.xslt" out="PMD.html"/>};
        }

        # Subsitute actual the packageinvoke value for instance of 'packageinvoke'
        # 10.4.2013 Here we have a fork in the data model
        # Going forward BOGs will not have a packageinvoke field, but rather will have
        # a source and binary invoke section.
        #        $invoke =~ s/packageinvoke/$bogref->{'packageinvoke'}/gsxm;
        if ( $bogref->{'toolname'} =~ /Findbugs/sxm ) {
            $invoke =~ s/packageinvoke/$bogref->{'packagebuildoutputpath'}/gsxm;
        }
        elsif ( $bogref->{'toolname'} =~ /PMD/sxm ) {
            $invoke =~ s/packageinvoke/$bogref->{'packagesourcepath'}/gsxm;
        }
        else {
            # ???
        }
        my $buildcmd = $bogref->{'packagebuild'};
        if ( $buildcmd =~ /null/sxm ) {
            $buildcmd = 'echo';
        }

        print $fd "#!/bin/bash\n";
        print $fd "set -x\n";
        print $fd "echo ::Copying files,`date +%s`\n";
        print $fd "/bin/cp -f \$VMINPUTDIR/$toolpath .\n";
        print $fd "/bin/cp -f \$VMINPUTDIR/$package .\n";

        # We will probably need the package for Normal runs as well, but
        # we will want the built package so that it contains all sources
        if ( !defined( $bogref->{'gav'} ) ) {
            print $fd "/bin/cp -f \$VMINPUTDIR/$package \$VMOUTPUTDIR\n";
        }
        print $fd "echo ::done Copying,\$?,`date +%s`\n";

        # Deploy the tool
        print $fd "echo ::Deploying_tool,`date +%s`\n";
        print $fd "$deploycmd\n";
        print $fd "echo ::done deploying_tool ,\$?,`date +%s`\n";

        # Touch a timestamp file so that we can simply
        # check which files have been placed since NOW.
        my $timestampfile = '_timestampfile';
        print $fd "touch $timestampfile\n";

        # Deploy the package
        print $fd "echo ::Deploying_package,`date +%s`\n";
        print $fd "$deploypkgcmd $package\n";
        print $fd "echo ::done deploying_ package ,\$?,`date +%s`\n";

        # Build the package
        if ( $buildcmd ne 'echo' ) {
            print $fd "echo ::Building_package,`date +%s`\n";
            print $fd "$buildcmd\n";
            print $fd "echo ::done Building package,\$?, `date +%s`\n";
        }

        if ( defined($xsltcmd) ) {
            $xsltcmd =
                q{<?xml version="1.0" encoding="UTF-8"?><project name="swamp">}
              . $xsltcmd
              . q{</project>};
            print $fd "echo '$xsltcmd' > swampxslt.xml\n";
        }

        # Create a output zip file containing the package and build results.
        # TODO this needs to change for UW toolchain. Currently not used, but was
        # planned for CodeDX
        print $fd "find . -cnewer $timestampfile | zip \$VMOUTPUTDIR/srcArchive.zip -\@\n";

        # Compute LOC on the package
        print $fd "echo ::LOC_package,`date +%s`\n";
        print $fd "perl \$VMINPUTDIR/cloc-1.60.pl --csv --quiet $package\n";
        print $fd "echo ::done LOC_package,\$?,`date +%s`\n";

        # Run the tool on the package
        print $fd "echo ::Assessing_package,`date +%s`\n";
        print $fd "$invoke > results.log 2>&1\n"; # results.log is STDERR/STDOUT from the assessment
        if ( defined($xsltcmd) ) {
            print $fd "ant -f swampxslt.xml >> results.log 2>&1\n";
        }
        print $fd "echo ::done Assessing_package ,\$?, `date +%s`\n";
        print $fd "echo ::Archiving_results,`date +%s`\n";
        print $fd "tar czvf \$VMOUTPUTDIR/results.tar.gz *.xml *.html *.log\n";
        print $fd "echo ::done Archiving_results ,\$?,`date +%s`\n";
        if ( !close($fd) ) {
            warnMessage( $bogref->{'execrunid'}, "Cannot close assess.sh $OS_ERROR" );
        }
        $ret = 1;
    }
    else {
        errorMessage( $bogref->{'execrunid'}, "Cannot create assess.sh $OS_ERROR" );
    }
    return $ret;
}

#** @function createAssessConfigs( \%bogref, $dest)
# @brief Based on informaiton in the bogref, create the
# package.conf, tool.conf and build.conf
# only done for the UW toolchain.
#
# @param bogref reference to a hash that is the BOG (Bill of Goods).
# @param dest folder in which to save config files.
# @return  1 on success, 0 on failure.
#*
sub createAssessConfigs {
    my $bogref = shift;
    my $dest   = shift;    # 'input'
    my $user     = shift;
    my $password = shift;
    my $ret      = 0;

    if (!saveProperties( "$dest/run-params.conf", {
        'SWAMP_USERNAME' => $user,
        'SWAMP_USERID' => '9999',
        'SWAMP_PASSWORD'=> $password })) {
        warnMessage( $bogref->{'execrunid'}, 'Cannot save run-params.conf' );
    }
    my $goal = q{build+assess+parse};
	my $runprops = {'goal' => $goal};
    my $config = getSwampConfig();
    my $internet_inaccessible = $config->get('SWAMP-in-a-Box.internet-inaccessible') || 'false';
	$runprops->{'internet-inaccessible'} = $internet_inaccessible;
    if (! saveProperties( "$dest/run.conf", $runprops)) {
        warnMessage( $bogref->{'execrunid'}, 'Cannot save run.conf' );
        return $ret;
    }

	if (! createToolConf($bogref, $dest)) {
		warnMessage($bogref->{'execrunid'}, 'Cannot create tool.conf');
		return $ret;
	}
    if ( !createPackageConf( $bogref, $dest ) ) {
        warnMessage( $bogref->{'execrunid'}, 'Cannot create package.conf' );
        return $ret;
    }
    $ret = 1;

    return $ret;
}
## no critic (ProhibitHashBarewords)
sub randoString {
    return join q{}, @_ [ map { rand @_ } 1 .. shift ] ;
}
## use critic

sub builderUser {
    return 'builder';
}
sub builderPassword {
    return randoString(8, q{a}..q{z},q{0}..q{9},q{A}..q{Z},q{!},q{_});
}

sub getBOGValue {
    my $bogref = shift;
    my $key    = shift;
    my $ret;
    if ( defined( $bogref->{$key} ) ) {
        $ret = trim( $bogref->{$key} );
        $ret =~ s/null//sxm;
        if ( !length($ret) ) {
            $ret = undef;
        }
    }
    return $ret;
}

#** @function createPackageConfigs( \%bogref, $dest)
# @brief Based on informaiton in the bogref, create the
# package.conf
# only done for the UW toolchain.
#
# @param bogref reference to a hash that is the BOG (Bill of Goods).
# @param dest folder in which to save config files.
# @return  1 on success, 0 on failure.
#*
sub createPackageConf {
    my $bogref = shift;
    my $dest   = shift;
    my %packageConfig;
    $packageConfig{'build-sys'}    = getBOGValue( $bogref, 'packagebuild_system' );
	if (isJavaBytecodePackage($bogref) && ! $packageConfig{'build-sys'}) {
		$packageConfig{'build-sys'} = 'java-bytecode';
	}
    $packageConfig{'build-file'}   = getBOGValue( $bogref, 'packagebuild_file' );
    $packageConfig{'build-target'} = getBOGValue( $bogref, 'packagebuild_target' );
    $packageConfig{'build-opt'}    = getBOGValue( $bogref, 'packagebuild_opt' );
    $packageConfig{'build-dir'}    = getBOGValue( $bogref, 'packagebuild_dir' );
    $packageConfig{'build-cmd'}    = getBOGValue( $bogref, 'packagebuild_cmd' );
    $packageConfig{'config-opt'}   = getBOGValue( $bogref, 'packageconfig_opt' );
    $packageConfig{'config-dir'}   = getBOGValue( $bogref, 'packageconfig_dir' );
    $packageConfig{'config-cmd'}   = getBOGValue( $bogref, 'packageconfig_cmd' );
    $packageConfig{'classpath'}    = getBOGValue( $bogref, 'package_classpath' );

	# 2 new fields for android assess 1.08.2015
    $packageConfig{'android-sdk-target'}    = getBOGValue( $bogref, 'android_sdk_target' );
    $packageConfig{'android-redo-build'}    = getBOGValue( $bogref, 'android_redo_build' );

	# 2 new fields for android assess 8.18.2015
    $packageConfig{'android-lint-target'} = getBOGValue( $bogref, 'android_lint_target' );
    $packageConfig{'gradle-wrapper'} = getBOGValue( $bogref, 'use_gradle_wrapper' );

	# 2 new fields for android+maven assess 8.31.2015
    $packageConfig{'android-maven-plugin'} = getBOGValue( $bogref, 'android_maven_plugin' );
    $packageConfig{'maven-version'} = getBOGValue( $bogref, 'maven_version' );

	# 3 new fields for ruby assess 8.18.2015
	if (isRubyPackage($bogref)) {
		my $bog_package_type = getBOGValue( $bogref, 'packagetype' );
		my $ruby_language_type = (split q{ }, $bog_package_type)[0];
		my $ruby_package_type = lc((split q{ }, $bog_package_type)[-1]);
		my $bog_language_version = getBOGValue( $bogref, 'language_version' );
    	$packageConfig{'package-language'} = $ruby_language_type;
    	$packageConfig{'package-type'} = $ruby_package_type;
		if ($bog_language_version) {
    		$packageConfig{'package-language-version'} = lc($ruby_language_type) . q{-} . $bog_language_version;
		}
	}

	# new field for java 8 support
	if (isJavaPackage($bogref)) {
		my $bog_package_type = getBOGValue($bogref, 'packagetype');
		if ($bog_package_type =~ m/Java\s7/sxm) {
    		$packageConfig{'package-language-version'} = 'java-7';
		}
		elsif ($bog_package_type =~ m/Java\s8/sxm) {
    		$packageConfig{'package-language-version'} = 'java-8';
		}
	}
	
    # 3 new fields for bytecode assess 2.10.2014
    $packageConfig{'package-classpath'} = getBOGValue($bogref, 'packageclasspath');
    $packageConfig{'package-srcdir'} = getBOGValue($bogref, 'packagebytecodesourcepath');
    $packageConfig{'package-auxclasspath'} = getBOGValue($bogref, 'packageauxclasspath');

    foreach my $key ( keys %packageConfig ) {
        if ( !defined( $packageConfig{$key} ) ) {
            delete $packageConfig{$key};
        }
    }

    $packageConfig{'package-archive'} = basename( $bogref->{'packagepath'} );
    $packageConfig{'package-dir'}     = trim( $bogref->{'packagesourcepath'} );
    my $packagename = $packageConfig{'package-archive'};

    # Remove well known extensions
    $packagename =~ s/.tar.gz$//sxm;
    $packagename =~ s/.tgz$//sxm;
    $packagename =~ s/.tar.bz2$//sxm;
    $packagename =~ s/.zip$//sxm;
    my @packageStuff = split( /-/sxm, $packagename );
	if (scalar(@packageStuff) <= 1) {
    	$packageConfig{'package-version'} = 'unknown';
	}
	else {
    	$packageConfig{'package-version'} = pop @packageStuff;
	}
    $packageConfig{'package-short-name'} = join( q{-}, @packageStuff );
    return saveProperties( "$dest/package.conf", \%packageConfig );
}

#** @function createToolConf( \%bogref, $dest)
# @brief Create the tool.conf file for this assessment run. This config file
# contains input needed by the UW team's assessment tools.
#
# @param bogref Reference to our Bill Of Goods file describing the arun
# @param dest Location to create the tool.conf file.
# @return 0 on failure, 1 on success.
#*
sub createToolConf {
    my $bogref = shift;
    my $dest   = shift;

    if ( -r "$dest/tool.conf" ) {
        infoMessage($bogref->{'execrunid'}, q{tool.conf already exists, skipping.});
        return 1;
    }

    my %toolConfig;
    # GCC is special in that it only needs one item in tool.conf: tool-type
    if ( $bogref->{'toolname'} =~ /gcc/isxm ) {
        $toolConfig{'tool-type'} = 'gcc-warn';
    }
    return saveProperties( "$dest/tool.conf", \%toolConfig );
}

#** @function saveRunresults( $out, \%bogref)
# @brief copy the entire output folder to the results folder.
# This is intended as a debugging measure in the event a run fails.
#
# @param out Folder which contains all results from the run.
# @param bogref Reference to the BOG under assessment
# @return undef
#*
sub saveRunresults {
    my $out       = shift;
    my $bogref    = shift;
    my $tarball   = shift;
    my $execrunid = $bogref->{'execrunid'};

    # Gluster/tar sometimes report incorrect file sizes
    my ( $output, $status ) = systemcall("tar --exclude=lost+found -czf $tarball $out");
    if ($status) {
        warnMessage( $bogref->{'execrunid'}, "Creating run $tarball said: [$output]" );
    }
    ( $output, $status ) = systemcall("mv -f $tarball $out");
    if ($status) {
        warnMessage( $bogref->{'execrunid'}, "Unable to mv ($tarball) to $out [$output, $status]" );
    }
    my $sharedfolder = File::Spec->catfile( $bogref->{'resultsfolder'}, $execrunid );
    make_path($sharedfolder);
    infoMessage( $execrunid, "Saving run results [$out] to $sharedfolder" );
    ( $output, $status ) =
      systemcall("/bin/cp -r $out $sharedfolder && /bin/chown -R mysql:mysql $sharedfolder");
    if ($status) {
        errorMessage( $bogref->{'execrunid'},
            "Unable to save run results [$output] $status" );
    }
    return;
}

#** @function invokeResultCollector( { 'bogref' => \%bogref, 'tarball' => $tarball, 'soughtfile' => $soughtfile, 'logfile' => $logfile })
# @brief Call saveResult method on the ResultCollector interface
#
# @param {} hashmap with the following keys:<ul>
# <li>'bogref' reference to BOG (Bill Of Goods) hash.</li>
# <li>'tarball' The name of the tarball containing the results to pass to saveResult.</li>
# <li>'soughtfile' The name of the file within tarball to send to saveResult</li>
# <li>'logfile' The name of the logfile to send to saveResult</li>
# <li>'extractFile' If true then soughtFile needs to be extracted from the tarball.
# </ul>
# @return
# @see
#*
sub invokeResultCollector {
    my %options = (
        'extractFile' => 1,
        @_
    );
    my $bogref     = $options{'bogref'};
    my $tarball    = $options{'tarball'};
    my $soughtFile = $options{'soughtfile'};
    my $logfile    = $options{'logfile'};
	my $weaknesses = $options{'weaknesses'};

    if ( !-r $tarball ) {
        errorMessage( $bogref->{'execrunid'},
            "there is no $tarball from which to extract results" );
        return;
    }
    my $execrunid = $bogref->{'execrunid'};

    #    my $sharedfolder = File::Spec->catfile( dirname( $bogref->{'packagepath'} ),
    #        q{..}, 'results', $execrunid );
    my $sharedfolder = File::Spec->catfile( $bogref->{'resultsfolder'}, $execrunid );

    #my $sharedfolder = abs_path($bogref->{'resultsfolder'});
    debugMessage( $bogref->{'execrunid'},
        "sharedfolder is $sharedfolder (packagepath=[" . $bogref->{'packagepath'} . "]" );

    # MYSQL needs to own our result files so they can be cleaned up.
    my ( $uid, $gid ) = ( getpwnam('mysql') )[ 2, 3 ];
    my $chownFiles = 1;
    my @filesToChown;

    if ( !defined($uid) || !defined($gid) ) {
        warnMessage( $bogref->{'execrunid'}, "Cannot determine UID or GID of mysql" );
        $chownFiles = 0;
    }

    # 1) Create results folder in shared area
    make_path($sharedfolder);
    push @filesToChown, $sharedfolder;

    if ( !cp( $logfile, $sharedfolder ) ) {
        errorMessage( $bogref->{'execrunid'},
            "Cannot copy log file $logfile to $sharedfolder: $OS_ERROR" );
    }
    my $sourceArchive = $bogref->{'packagepath'};
    # CodeDX can only understand zip files.
    if ($sourceArchive !~ /\.zip$/sxm)  {
        $sourceArchive = makezip ($sourceArchive);
    }
    push @filesToChown, $sharedfolder;
    if ( !cp( $sourceArchive, $sharedfolder ) ) {
        warnMessage( $bogref->{'execrunid'},
            "Cannot copy source archive file $sourceArchive to $sharedfolder: $OS_ERROR" );
    }
    my $resultsfile = File::Spec->catfile( $sharedfolder, $soughtFile );
    $logfile       = File::Spec->catfile( $sharedfolder, basename($logfile) );
    $sourceArchive = File::Spec->catfile( $sharedfolder, basename($sourceArchive) );

    debugMessage( $bogref->{'execrunid'},
        "resultsfile is now a filename $resultsfile. logfile is [$logfile]" );

    if ( $options{'extractFile'} ) {

        # new uses eval to detect tar ball type, which is very chatty
        # temporarily turn off die handler.
        my $handler = $SIG{'__DIE__'};
        local $SIG{'__DIE__'} = 'DEFAULT';
        my $tar = Archive::Tar->new( $tarball, 1 );
        local $SIG{'__DIE__'} = $handler;

        debugMessage( $bogref->{'execrunid'}, "trying to extract $tarball" );

        # 2) Find soughtFile in $tarball
        $tar->extract_file( $soughtFile, $resultsfile );
        $soughtFile =~ s/\.xml$/.html/sxm;
    }
    else {
        cp( File::Spec->catfile( dirname($tarball), $soughtFile ), $resultsfile );
    }

    #    $resultsfile =~s/\.xml$/.html/sxm;
    #    $tar->extract_file( $soughtFile, $resultsfile );

    # 3) call saveResult with it.
    my %results;
    $results{'execrunid'}      = $execrunid;
    $results{'weaknesses'}     = $weaknesses;
    $results{'pathname'}       = abs_path($resultsfile);
    $results{'sha512sum'}      = checksumFile( abs_path($resultsfile) );
    $results{'logpathname'}    = abs_path($logfile);
    $results{'log512sum'}      = checksumFile( abs_path($logfile) );
    $results{'sourcepathname'} = abs_path($sourceArchive);
    $results{'source512sum'}   = checksumFile( abs_path($sourceArchive) );
    push @filesToChown, $results{'pathname'};
    push @filesToChown, $results{'logpathname'};
    push @filesToChown, $results{'sourcepathname'};

    # Sonatype jobs have 'gav' keys
    if ( defined( $bogref->{'gav'} ) ) {
        $results{'gav'}          = $bogref->{'gav'};
        $results{'toolname'}     = $bogref->{'toolname'};
        $results{'platform'}     = $bogref->{'platform'};
        $results{'packagename'}  = $bogref->{'packagename'};
        $results{'senttoazolla'} = 'false';
        my $propfile = File::Spec->catfile( $sharedfolder, 'results.properties' );
        saveProperties( $propfile, \%results );
        $results{'results.properties'} = abs_path($propfile);
        push @filesToChown, $results{'results.properties'};
    }
    if ($chownFiles) {
        if ( chown( $uid, $gid, @filesToChown ) != @filesToChown ) {
            warnMessage( $bogref->{'execrunid'},
                "Cannot chown files [@filesToChown] to mysql user. $OS_ERROR" );
        }
    }

    if ( !defined( $bogref->{'testmode'} ) ) {
        Log::Log4perl->get_logger(q{})->info($bogref->{'execrunid'}, 'calling saveResult with: ', sub { use Data::Dumper; Dumper(\%results); });
        my $res = saveResult( \%results );

        if ( defined( $res->{'error'} ) ) {
            errorMessage( $bogref->{'execrunid'}, "saveResult : $res->{'error'}" );
        }
    }

    return;

}

#** @function parseStatusOut( $output, \$retryref )
# @brief Given the dashboard from c-assess or java-assess, parse the output to see if
# the assessement run failed. The definition of the output is:
#-------------------------------------
#- status.out
#-------------------------------------
#  file updated in the output directory with a dashboard of the progress.
#  lines are added as tasks are completed, and are formatted as follows:
#
#  <status>: <task> <extra-msg> <duration>
#    ----------
#    multiline-msg
#    ----------
#
#  <status>    alphanumeric value that start in column 1 and followed by a ':'
#              current values are PASS, FAIL, NOTE, SKIP
#  <task>      alphanumberic plus '-' and '_'
#  <extra-msg> optional parenthesis surrounded characters without control
#              character
#  <duration>  optional decimal number of seconds followed by 's'
#
#  multiline-msg's are deliminited by a line of 10 '-' characters, each line and
#                  the delimiter are preceded by two space characters.
#          the message is associated with the preceeding task
#
#  If any of the status's are FAIL, the whole run should be considered failed.
#
# @param  output the content of status.out as a single string
# @param  retryref a reference to a scalar indicating the assessment should be retried
# @return 1 if the assessment run is current OK, 0 otherwise. if 0 and retry is 1, retry the assessment
# @see
#*
sub parseStatusOut {
    my $status_out = shift;
    my $retryref   = shift;
    my @lines      = split( /\n/sxm, $status_out );
    my $ret        = 1;                               # Assume all is well.
    my @fails;
    my $why;
    my $sawAll = 0;
    setRef( $retryref, 0 );

	my $weaknesses;
    foreach (@lines) {
        Log::Log4perl->get_logger(q{})->info("status.out: $_");
        if (/^FAIL:/sxm) {
            $ret = 0;
            push @fails, $_;
        }
        if ( /^PASS:\s*all/sxm || /^FAIL:\s*all/sxm ) {
            $sawAll = 1;
        }
        if (/^NOTE:\s*retry/sxm) {
            $ret = 0;
            Log::Log4perl->get_logger(q{})
              ->info(qq{status.out indicates assessment should be retried. $_});
            setRef( $retryref, 1 );
        }
		if (/parse-results\s*\(weaknesses\s*:\s*(\d+)\)/sxm) {
			$weaknesses = $1;
		}
    }
    if ( !$sawAll ) {
        Log::Log4perl->get_logger(q{})->warn(q{Did not detect 'all' token in status.out});
    }
    if ( !$ret ) {
        $why = join( "\n", @fails );
    }
    return ($ret, $why, $weaknesses);
}

sub setRef {
    my $ref = shift;
    my $val = shift;
    if ( ref($ref) eq "SCALAR" ) {
        ${$ref} = $val;
    }
    else {
        Log::Log4perl->get_logger(q{})->warn( 'setRef called with a non-scalar ref: ' . ref($ref) );
    }
    return;
}

# Perform in place merge or property file. All properties are preserved, but only 1 key=value pair allowed. All values concatenated.
sub mergeDependencies {
    my $file = shift;
    if (open (my $fd, '<', abs_path($file))) {
        my %map;
        while (<$fd>) {
            next if (!/=/sxm); # Skip non-property looking lines
            chomp;
            my ($key, $value)=split(/=/sxm,$_);
            $map{$key} .= "$value ";
        }
        if (!close ($fd)) {
            
        }
        if (open(my $fd, '>', abs_path($file))) {
            foreach my $key (keys %map) {
                print $fd "$key=$map{$key}\n";
            }
            if (!close($fd)) {
                
            }
        }
    }
    return;
}
sub addUserDepends {
    my $bogref   = shift;
    my $destfile = shift;
    my $logger   = Log::Log4perl->get_logger(q{});
    if ( !defined( $bogref->{'packagedependencylist'} )
        || $bogref->{'packagedependencylist'} eq q{null} )
    {
            $logger->warn("Nothing to do");
        return;
    }
    if ( open( my $fh, '>>', $destfile ) ) {
        $logger->info("opened $destfile ");
        print $fh "dependencies-$bogref->{'platform'}=$bogref->{'packagedependencylist'}\n";
        if ( !close $fh ) {
            $logger->warn("Error closing $destfile: $OS_ERROR");
        }
    }
    else {
        $logger->error("Cannot append to $destfile :$OS_ERROR");
    }

    return;
}

#** @function extractDepends( $bogref, $destfile)
# @brief Given a bill of good (BOG) extract the package dependency information from the SWAMP provided
# dependencies.tar file.
#
# @param bogref Reference to the current Bill Of Goods structure being used
# @param destfile Name of the destination file to APPEND dependencies
# @return
#*
sub extractDepends {
    my $bogref   = shift;
    my $destfile = shift;
    my $basedir  = getSWAMPDir();
    my $keyfile  = abs_path("$basedir/thirdparty/dependencykeys.txt");
    my $tarfile  = abs_path("$basedir/thirdparty/dependencies.tar");
    my $logger   = Log::Log4perl->get_logger(q{});
    if ( open( my $fh, '<', $keyfile ) ) {

        # Find basename($bogref->{'packagepath'}) in keyfile
        my $key = q{package.} . basename( $bogref->{'packagepath'} );
#        $key =~ s/\+/\\\+/sxm;
        my $value;
        while (<$fh>) {
            chomp;
            my ($pkey, $pvalue)=split(/=/sxm, $_);
            if ($pkey eq $key) {
                $value = $pvalue;
            }
        }
        if ( !close($fh) ) {
            $logger->warn("Cannot open $keyfile: $OS_ERROR");
        }
        if ($value) {
            # Not checking return by design, these files are optional and if the tar fails, so be it.
            # In this case we want to append to the os-dependencies.conf file.
            # NB this is system call and not systemcall intentionally, we don't want STDERR added to the mix.
            system("/bin/tar -xf $tarfile -O $value >> $destfile");
        }
    }
    else {
        $logger->warn("Cannot open $keyfile: $OS_ERROR");
    }
    return;
}

sub frameworkDeploy {
    my ($opts)     = @_;
    my $member = $opts->{'member'};
    my $tar = $opts->{'archive'};
    my $dest = $opts->{'dest'};
    if ( $member =~ /swamp-conf\/sys-os-dependencies.conf/sxm ) {
        $tar->extract_file( $member, "$dest/os-dependencies-framework.conf" );
    }
    if ( $member =~ /in-files/sxm ) {
        my $filename = basename($member);
        $tar->extract_file( $member, "$dest/$filename" );
    }
    return;
}
sub parserDeploy {
    my ($opts)     = @_;
    my $member = $opts->{'member'};
    my $tar = $opts->{'archive'};
    my $dest = $opts->{'dest'};
    if ( $member =~ /parser-os-dependencies.conf/sxm ) {
        $tar->extract_file( $member, "$dest/os-dependencies-parser.conf" );
    }
    if ( $member =~ /in-files/sxm ) {
        my $filename = basename($member);
        $tar->extract_file( $member, "$dest/$filename" );
    }
    return;
}
sub deployTarball {
    my $callbackid  = shift;
    my $tarfile = shift;
    my $dest    = shift;
    my $platform = shift;
    my $callback;
    if ($callbackid eq PARSERID) {
        $callback = \&parserDeploy;
    }
    elsif ($callbackid eq FRAMEWORKID) {
        $callback = \&frameworkDeploy;
    }
    else {
        return 0;
    }

    my $tar = Archive::Tar->new( $tarfile, 1 );
    my @list = $tar->list_files();
    my %options = ( 'archive' => $tar, 'dest' => $dest );
    if (defined($platform)) {
        $options{'platform'} = $platform;
    }

    foreach my $member (@list) {
        # Skip directory
        next if ( $member =~ /\/$/sxm );
        $options{'member'} = $member;
        $callback->(\%options);
    }
    return 1;
}
sub warnMessage {
    my $who = shift;
    my $msg = shift;
    return logMessage( $WARN, $who, $msg );
}

sub errorMessage {
    my $who = shift;
    my $msg = shift;
    return logMessage( $ERROR, $who, $msg );
}

sub debugMessage {
    my $who = shift;
    my $msg = shift;
    return logMessage( $DEBUG, $who, $msg );
}

sub infoMessage {
    my $who = shift;
    my $msg = shift;
    return logMessage( $INFO, $who, $msg );
}

sub logMessage {
    my $level     = shift;
    my $execrunid = shift;
    my $msg       = shift;
    Log::Log4perl->get_logger(q{})->log( $level, $execrunid . q{:} . $msg );
    return;
}
1;

__END__
=pod

=encoding utf8

=head1 NAME

=head1 SYNOPSIS

Write the Manual page for this package

=head1 DESCRIPTION

=head1 OPTIONS

=over 8

=item 


=back

=head1 EXAMPLES

=head1 SEE ALSO

=cut
 

