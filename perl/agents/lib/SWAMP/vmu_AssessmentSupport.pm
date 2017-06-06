# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2017 Software Assurance Marketplace

package SWAMP::vmu_AssessmentSupport;
use strict;
use warnings;
use English '-no_match_vars';
use RPC::XML;
use RPC::XML::Client;
use Date::Parse qw(str2time);
use Log::Log4perl;
use Archive::Tar;
use File::Basename qw(basename);
use File::Copy qw(move cp);

use SWAMP::vmu_Support qw(
    trim
    systemcall
    getSwampDir
    getSwampConfig
    getLoggingConfigString
    loadProperties
    saveProperties
    rpccall
);
use SWAMP::vmu_PackageTypes qw(
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
    $WEB_SCRIPTING_PKG_STRING

    $CPP_TYPE
    $PYTHON_TYPE
    $JAVA_TYPE
    $RUBY_TYPE
    $SCRIPT_TYPE
);

use parent qw(Exporter);
our (@EXPORT_OK);
BEGIN {
    require Exporter;
    @EXPORT_OK = qw(
      identifyAssessment
      builderUser
      builderPassword
      updateRunStatus
      updateAssessmentStatus
      updateClassAdAssessmentStatus
      saveResult
      doRun
      updateExecutionResults
      copyAssessmentInputs
      createAssessmentConfigs
      isSwampInABox
      isLicensedTool
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
      isJavaPackage
      isCPackage
      isPythonPackage
      isRubyPackage
      isScriptPackage
      packageType
    );
}

my $global_swamp_config;
my $log = Log::Log4perl->get_logger(q{});

sub _randoString {
    return join q{}, @_ [ map { rand @_ } 1 .. shift ] ;
}

sub builderUser {
    my $result = 'builder';
    return $result;
}
sub builderPassword {
    my $result = _randoString(8, q{a}..q{z},q{0}..q{9},q{A}..q{Z},q{!},q{_});
    return $result;
}

sub identifyAssessment { my ($bogref) = @_ ;
    $log->info("Execrunuid: $bogref->{'execrunid'}");
    $log->info("Package: $bogref->{'packagename'} $bogref->{'packagepath'}");
    $log->info("Tool: $bogref->{'toolname'} $bogref->{'toolpath'}");
    $log->info("Platform: $bogref->{'platform'}");
}

#####################
#   AgentClient     #
#####################

my $agentUri;
my $agentClient;

sub _configureAgentClient {
    $global_swamp_config ||= getSwampConfig();
    my $host = $global_swamp_config->get('agentMonitorHost');
    my $port = $global_swamp_config->get('agentMonitorJobPort');
    my $uri = "http://$host:$port";
    undef $agentClient;
    return $uri;
}

# UNUSED
sub updateAssessmentStatus { my ($execrunid, $status) = @_ ;
    $agentUri ||= _configureAgentClient();
    $agentClient ||= RPC::XML::Client->new($agentUri);
    my $req = RPC::XML::request->new('agentMonitor.updateAssessmentStatus',
        RPC::XML::string->new($execrunid),
        RPC::XML::string->new($status)
    );
    my $result = rpccall($agentClient, $req);
    if ($result->{'error'}) {
        $log->error("updateAssessmentStatus - error: $result->{'error'}");
        return 0;
    }
    return 1;
}

#########################
#   DispatcherClient    #
#########################

my $dispatcherUri;
my $dispatcherClient;

sub _configureDispatcherClient {
    $global_swamp_config ||= getSwampConfig();
    my $host = $global_swamp_config->get('dispatcherHost');
    my $port = $global_swamp_config->get('dispatcherPort');
    my $uri = "http://$host:$port";
    undef $dispatcherClient;
    return $uri;
}

#####################
#   RunController   #
#####################

sub doRun { my ($execrunuid) = @_ ;
    $log->debug("doRun called with execrunuid: $execrunuid");
    my $options = {'execrunid' => $execrunuid};
    my $req = RPC::XML::request->new('swamp.runController.doRun', RPC::XML::struct->new($options));
    $dispatcherUri ||= _configureDispatcherClient();
    $dispatcherClient ||= RPC::XML::Client->new($dispatcherUri);
    my $result = rpccall($dispatcherClient, $req);
    if ($result->{'error'}) {
        $log->error("doRun with $execrunuid error: $result->{'error'}");
        return 0;
    }
    return 1;
}

#############################
#   ExecuteRecordCollector  #
#############################

sub _getSingleExecutionRecord { my ($execrunid) = @_ ;
    my %map;
    $map{'execrunid'} = $execrunid;
    my $req = RPC::XML::request->new('swamp.execCollector.getSingleExecutionRecord', RPC::XML::struct->new(\%map));
    $dispatcherUri ||= _configureDispatcherClient();
    $dispatcherClient ||= RPC::XML::Client->new($dispatcherUri);
    my $result = rpccall($dispatcherClient, $req);
    # Convert date strings back to epoch times
    if (! $result->{'error'}) {
        $result = $result->{'value'};
        # Patch up the record if necessary so that it can be sent back thru updateExecutionResults.
        if (defined($result->{'run_date'})) {
            if ($result->{'run_date'} ne 'null') {
                $result->{'run_date'} = scalar localtime str2time($result->{'run_date'});
            }
            else {
                delete $result->{'run_date'};
            }
        }
        if (defined($result->{'lines_of_code'})) {
            if ($result->{'lines_of_code'} eq 'null') {
                $result->{'lines_of_code'} = 'i__0';
            }
            else {
                $result->{'lines_of_code'} = "i__$result->{'lines_of_code'}";
            }
        }
        if (defined($result->{'execute_node_architecture_id'})) {
            if ($result->{'execute_node_architecture_id'} eq 'null') {
                $result->{'execute_node_architecture_id'} = 'unknown';
            }
        }
        if (defined($result->{'cpu_utilization'})) {
            if ($result->{'cpu_utilization'} eq 'null') {
                $result->{'cpu_utilization'} = 'd__0';
            }
            else {
                $result->{'cpu_utilization'} = "d__$result->{'cpu_utilization'}";
            }
        }
        if (defined($result->{'completion_date'})) {
            if ($result->{'completion_date'} ne 'null') {
                # Ignore 0 and negative numbers
                my $timeVal = str2time($result->{'completion_date'});
                if ($timeVal > 1) {
                    $result->{'completion_date'} = scalar localtime $timeVal;
                }
                else {
                    delete $result->{'completion_date'};
                }
            }
            else {
                delete $result->{'completion_date'};
            }
        }
    }
    return $result;
}

sub updateExecutionResults { my ($execrunid, $newrecord, $finalStatus) = @_ ;
    my $oldrecord   = _getSingleExecutionRecord($execrunid);
    $log->debug('updateExecutionResults oldrecord: ', sub {use Data::Dumper; Dumper($oldrecord);});
    if ($oldrecord->{'error'}) {
        $log->error("updateExecutionResults - error: $oldrecord->{'error'}");
        return;
    }
    if (! defined($oldrecord)) {
        $oldrecord = {
            'run_date'                     => scalar localtime,
            'cpu_utilization'              => 'd__0',
            'lines_of_code'                => 'i__0',
            'execute_node_architecture_id' => 'unknown'
        };
    }
    else {
        # If the run_date has never been set, set it
        if (! defined($oldrecord->{'run_date'})) {
            $oldrecord->{'run_date'} = scalar localtime;
        }
    }
    if ($finalStatus) {
        $oldrecord->{'completion_date'} = scalar localtime;
    }
    else {
        delete $oldrecord->{'completion_date'} ;
    }
    # merge oldrecord into newrecord
    if (! $oldrecord->{'error'}) {
        $newrecord = { %$oldrecord, %$newrecord };
    }
    # Add other parameters to newrecord
    $newrecord->{'execrunid'} = $execrunid;
    $newrecord->{'timestamp'} = "i__" . time();
    $log->debug('updateExecutionResults newrecord: ', sub {use Data::Dumper; Dumper($newrecord);});
    my $req = RPC::XML::request->new('swamp.execCollector.updateExecutionResults', RPC::XML::struct->new($newrecord));
    $dispatcherUri ||= _configureDispatcherClient();
    $dispatcherClient ||= RPC::XML::Client->new($dispatcherUri);
    my $result = rpccall($dispatcherClient, $req);
    if ($result->{'error'}) {
        $log->error("updateExecutionResults - error: $result->{'error'}");
    }
}

sub updateRunStatus { my ($execrunid, $status, $finalStatus) = @_ ;
    $finalStatus ||= 0;
    updateExecutionResults($execrunid, {'status' => $status}, $finalStatus);
}

#####################
#   ResultCollector #
#####################

sub saveResult { my ($mapref) = @_ ;
    if (!defined($mapref->{'pathname'})) {
        $log->error('saveResult - error: hash is missing pathname');
        return {'error', 'hash is missing pathname'};
    }
    if (!defined($mapref->{'execrunid'})) {
        $log->error('saveResult - error: hash is missing execrunid');
        return {'error', 'hash is missing execrunid'};
    }
    if ($mapref->{'pathname'} ne $mapref->{'pathname'}) {
        $log->error("saveResult - pathname is not canonical $mapref->{'pathname'} vs " . $mapref->{'pathname'});
        return {'error', "pathname is not canonical $mapref->{'pathname'} vs " . $mapref->{'pathname'}};
    }
    my $req = RPC::XML::request->new('swamp.resultCollector.saveResult', RPC::XML::struct->new($mapref));
    $dispatcherUri ||= _configureDispatcherClient();
    $dispatcherClient ||= RPC::XML::Client->new($dispatcherUri);
    my $result = rpccall($dispatcherClient, $req);
    if ($result->{'error'}) {
        $log->error("saveResult - error: $result->{'error'}");
        return 0;
    }
    return 1;
}

#############################
#   CopyAssessmentInputs    #
#############################

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
        $log->debug("_copy_tool_files - extract: $file->name to $dest/$filename");
         $tar->extract_file($file->name, "$dest/$filename");
        $found = 1;
    }
    if (! $found) {
        foreach my $file (@{$files}) {
            next if ($file->name =~ m/\/$/sxm);
            next if ($file->name !~ m/noarch/sxm);
            my $filename = basename($file->name);
            $log->debug("_copy_tool_files - extract: $file->name to $dest/$filename");
            $tar->extract_file($file->name, "$dest/$filename");
        }
    }
    return $retval;
}

sub _copyInputsTools { my ($bogref, $dest) = @_ ;
    my $tar = Archive::Tar->new($bogref->{'toolpath'}, 1);
    my @files = $tar->get_files();
    # if tool bundle uses symbolic link for this platform handle that here
    my $links = _copy_tool_files($tar, \@files, $bogref->{'platform'}, $dest);
    foreach my $link (@{$links}) {
        _copy_tool_files($tar, \@files, $link->linkname, $dest);
    }
    if (-r "$dest/os-dependencies-tool.conf") {
        $log->debug("Adding $dest/os-dependencies-tool.conf");
        system("cat $dest/os-dependencies-tool.conf >> $dest/os-dependencies.conf");
    }
    # merge tool-os-dependencies.conf into os-dependencies.conf if extant
    if (-r "$dest/tool-os-dependencies.conf") {
        $log->debug("Adding $dest/tool-os-dependencies.conf");
        system("cat $dest/tool-os-dependencies.conf >> $dest/os-dependencies.conf");
    }
    return 1;
}

sub copyAssessmentInputs { my ($bogref, $dest) = @_ ;
    if (!defined($bogref->{'packagepath'})) {
        $log->error($bogref->{'execrunid'}, "BOG is missing packagepath specification.");
        return 0;
    }
    if (!defined( $bogref->{'toolpath'})) {
        $log->error($bogref->{'execrunid'}, "BOG is missing toolpath specification.");
        return 0;
    }
    if (! _copyInputsTools($bogref, $dest)) {
        return 0;
    }
    # create services.conf in the input destination directory
    if (isParasoftTool($bogref)) {
        $global_swamp_config ||= getSwampConfig();
        my $value = $global_swamp_config->get('tool.ps-ctest.license.host');
        system("echo tool-ps-ctest-license-host = $value >> $dest/services.conf");
        $value = $global_swamp_config->get('tool.ps-ctest.license.port');
        system("echo tool-ps-ctest-license-port = $value >> $dest/services.conf");
        $value = $global_swamp_config->get('tool.ps-jtest.license.host');
        system("echo tool-ps-jtest-license-host = $value >> $dest/services.conf");
        $value = $global_swamp_config->get('tool.ps-jtest.license.port');
        system("echo tool-ps-jtest-license-port = $value >> $dest/services.conf");
    }
    elsif (isGrammaTechTool($bogref)) {
        $global_swamp_config ||= getSwampConfig();
        my $value = $global_swamp_config->get('tool.gt-csonar.license.host');
        system("echo tool-gt-csonar-license-host = $value >> $dest/services.conf");
        $value = $global_swamp_config->get('tool.gt-csonar.license.port');
        system("echo tool-gt-csonar-license-port = $value >> $dest/services.conf");
    }
    elsif (isRedLizardTool($bogref)) {
        $global_swamp_config = getSwampConfig();
        my $value = $global_swamp_config->get('tool.rl-goanna.license.host');
        system("echo tool-rl-goanna-license-host = $value >> $dest/services.conf");
        $value = $global_swamp_config->get('tool.rl-goanna.license.port');
        system("echo tool-rl-goanna-license-port = $value >> $dest/services.conf");
    }

    # Copy the package tarball into VM input folder from the SAN.
    if (! cp($bogref->{'packagepath'}, $dest)) {
        $log->error($bogref->{'execrunid'}, "Cannot read packagepath $bogref->{'packagepath'} $OS_ERROR");
        return 0;
    }

    _addUserDepends($bogref, "$dest/os-dependencies.conf");
    my $basedir = getSwampDir();
    my $file = "$basedir/thirdparty/resultparser.tar";
    _deployTarball($file, $dest);
    # Add result parser's *-os-dependencies.conf to the mix, and merge for uniqueness
    if (-r "$dest/os-dependencies-parser.conf") {
        $log->debug("Adding $dest/os-dependencies-parser.conf");
        system("cat $dest/os-dependencies-parser.conf >> $dest/os-dependencies.conf");
    }

    if (! _copyFramework($bogref, $basedir, $dest)) {
        return 0;
    }

    # Copy LOC tool
    if (! cp("$basedir/bin/cloc-1.68.pl", $dest)) {
        $log->error($bogref->{'execrunid'}, "Cannot copy LOC tool $OS_ERROR");
        return 0;
    }
    return 1;
}

sub _deployTarByPlatform { my ($tarfile, $compressed, $dest, $platform) = @_ ;
    $log->debug("_deployTarByPlatform - tarfile: $tarfile platform: $platform dest: $dest");
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
                    $log->debug("_deployTarByPlatform - extract symlink dir: $destname to $dest");
                    $linkmember->extract($destname);
                }
            }
            else {
                my $basename = basename($link->name);
                my $destname = $dest . qq{/}. $basename;
                if ($link->name =~ m/swamp-conf\/sys-os-dependencies.conf/sxm) {
                    $destname = $dest . qq{/os-dependencies-framework.conf};
                }
                $log->debug("_deployTarByPlatform - extract symlink file: $destname to $dest");
                $link->extract($destname);
            }
        }
        else {
            my $basename = basename($member->name);
            my $destname = $dest . qq{/}. $basename;
            if ($member->name =~ m/swamp-conf\/sys-os-dependencies.conf/sxm) {
                $destname = $dest . qq{/os-dependencies-framework.conf};
            }
            $log->debug("_deployTarByPlatform - extract file: $destname to $dest");
            $member->extract($destname);
        }
        $member = $iter->();
    }
    return;
}

sub _copyFramework { my ($bogref, $basedir, $dest) = @_ ;
    my $file;
    my $compressed = 0;
    if (isJavaPackage($bogref)) {
        $file = "$basedir/thirdparty/java-assess.tar";
    }
    elsif (isRubyPackage($bogref)) {
        $file = "$basedir/thirdparty/ruby-assess.tar";
    }
    elsif (isCPackage($bogref)) {
        $file = "$basedir/thirdparty/c-assess.tar.gz";
        $compressed = 1;
    }
    elsif (isScriptPackage($bogref) || isPythonPackage($bogref)) {
        $file = "$basedir/thirdparty/script-assess.tar";
    }
    if (! -r $file) {
        $log->error($bogref->{'execrunid'}, "Cannot see assessment toolchain $file");
        return 1;
    }
    my $platform = $bogref->{'platform'} . qq{/};
    _deployTarByPlatform($file, $compressed, $dest, $platform);
    if (-r "$dest/os-dependencies-framework.conf") {
        $log->debug("Adding $dest/os-dependencies-framework.conf");
        system("cat $dest/os-dependencies-framework.conf >> $dest/os-dependencies.conf");
    }

    # remove empty os-dependencies file
    if (-z "$dest/os-dependencies.conf") {
        unlink("$dest/os-dependencies.conf");
    }
    else {
        _mergeDependencies("$dest/os-dependencies.conf");
    }

    # Preserve the provided run.sh, we'll invoke it from our run.sh
    if (-r "$dest/run.sh") {
        $log->debug("renaming $dest/run.sh");
        if (! move( "$dest/run.sh", "$dest/_run.sh")) {
            $log->error($bogref->{'execrunid'}, "Cannot move run.sh to _run.sh in $dest");
        }
    }
    return 1;
}

sub isSwampInABox { my ($config) = @_ ;
    if ($config->exists('SWAMP-in-a-Box')) {
        if ($config->get('SWAMP-in-a-Box') =~ /yes/sxmi) {
            return 1;
        }
    }
    return 0;
}

sub isLicensedTool { my ($bogref) = @_ ;
    return (isParasoftTool($bogref) ||
            isGrammaTechTool($bogref) ||
            isRedLizardTool($bogref));
}

sub isRubyTool { my ($bogref) = @_ ;
    return (
        $bogref->{'toolname'} eq 'RuboCop' ||
        $bogref->{'toolname'} eq 'ruby-lint' ||
        $bogref->{'toolname'} eq 'Reek' ||
        $bogref->{'toolname'} eq 'Brakeman' ||
        $bogref->{'toolname'} eq 'Dawn'
    );
}
sub isRubyPackage { my ($bogref) = @_ ;
    return (
        $bogref->{'packagetype'} eq $RUBY_PKG_STRING ||
        $bogref->{'packagetype'} eq $RUBY_SINATRA_PKG_STRING ||
        $bogref->{'packagetype'} eq $RUBY_ON_RAILS_PKG_STRING ||
        $bogref->{'packagetype'} eq $RUBY_PADRINO_PKG_STRING
    );
}
sub isFlake8Tool { my ($bogref) = @_ ;
    return ($bogref->{'toolname'} eq 'Flake8');
}
sub isBanditTool { my ($bogref) = @_ ;
    return ($bogref->{'toolname'} eq 'Bandit');
}
sub isAndroidTool { my ($bogref) = @_ ;
    return ($bogref->{'toolname'} eq 'Android lint');
}
sub isHRLTool { my ($bogref) = @_ ;
    return ($bogref->{'toolname'} eq 'HRL');
}
sub isParasoftC { my ($bogref) = @_ ;
    return ($bogref->{'toolname'} eq 'Parasoft C/C++test');
}
sub isParasoftJava { my ($bogref) = @_ ;
    return ($bogref->{'toolname'} eq 'Parasoft Jtest');
}
sub isParasoftTool { my ($bogref) = @_ ;
    return (isParasoftC($bogref) || isParasoftJava($bogref));
}
sub isGrammaTechCS { my ($bogref) = @_ ;
    return ($bogref->{'toolname'} eq 'GrammaTech CodeSonar');
}
sub isGrammaTechTool { my ($bogref) = @_ ;
    return (isGrammaTechCS($bogref));
}
sub isRedLizardG { my ($bogref) = @_ ;
    return ($bogref->{'toolname'} eq 'Red Lizard Goanna');
}
sub isRedLizardTool { my ($bogref) = @_ ;
    return (isRedLizardG($bogref));
}
sub isJavaTool { my ($bogref) = @_ ;
    return ($bogref->{'toolname'} =~ /(Findbugs|PMD|Archie|Checkstyle|error-prone|Parasoft\ Jtest)/isxm);
}
sub isJavaPackage { my ($bogref) = @_ ;
    return (
        $bogref->{'packagetype'} eq $ANDROID_JAVASRC_PKG_STRING ||
        $bogref->{'packagetype'} eq $ANDROID_APK_PKG_STRING ||
        $bogref->{'packagetype'} eq $JAVA7SRC_PKG_STRING ||
        $bogref->{'packagetype'} eq $JAVA7BYTECODE_PKG_STRING ||
        $bogref->{'packagetype'} eq $JAVA8SRC_PKG_STRING ||
        $bogref->{'packagetype'} eq $JAVA8BYTECODE_PKG_STRING
    );
}
sub isJavaBytecodePackage { my ($bogref) = @_ ;
    return (
        $bogref->{'packagetype'} eq $JAVA7BYTECODE_PKG_STRING ||
        $bogref->{'packagetype'} eq $JAVA8BYTECODE_PKG_STRING
    );
}
sub isCTool { my ($bogref) = @_ ;
    return ($bogref->{'toolname'} =~ /(GCC|Clang Static Analyzer|cppcheck)/isxm);
}
sub isCPackage { my ($bogref) = @_ ;
    return ($bogref->{'packagetype'} eq $C_CPP_PKG_STRING);
}
sub isPythonTool { my ($bogref) = @_ ;
    return ($bogref->{'toolname'} =~ /Pylint/isxm);
}
sub isPythonPackage { my ($bogref) = @_ ;
    return ($bogref->{'packagetype'} eq $PYTHON2_PKG_STRING || $bogref->{'packagetype'} eq $PYTHON3_PKG_STRING);
}
sub isScriptPackage { my ($bogref) = @_ ;
    return ($bogref->{'packagetype'} eq $WEB_SCRIPTING_PKG_STRING);
}

sub packageType { my ($bogref) = @_ ;
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
    elsif (isScriptPackage($bogref)) {
        return $SCRIPT_TYPE;
    }
    return;
}

sub createAssessmentConfigs { my ($bogref, $dest, $user, $password) = @_ ;
    my $goal = q{build+assess+parse};
    if (! saveProperties("$dest/run-params.conf", {
        'SWAMP_USERNAME' => $user,
        'SWAMP_USERID' => '9999',
        'SWAMP_PASSWORD'=> $password}
    )) {
        $log->warn($bogref->{'execrunid'}, 'Cannot save run-params.conf');
    }
    my $runprops = {'goal' => $goal};
    $global_swamp_config ||= getSwampConfig();
    my $internet_inaccessible = $global_swamp_config->get('SWAMP-in-a-Box.internet-inaccessible') || 'false';
    $runprops->{'internet-inaccessible'} = $internet_inaccessible;
    if (! saveProperties( "$dest/run.conf", $runprops)) {
        $log->warn($bogref->{'execrunid'}, 'Cannot save run.conf');
        return 0;
    }
    if (! _createPackageConf($bogref, $dest)) {
        $log->warn($bogref->{'execrunid'}, 'Cannot create package.conf');
        return 0;
    }
    return 1;
}

sub _getBOGValue { my ($bogref, $key) = @_ ;
    my $ret;
    if (defined($bogref->{$key})) {
        $ret = trim($bogref->{$key});
        $ret =~ s/null//sxm;
        if (! length($ret)) {
            $ret = undef;
        }
    }
    return $ret;
}

sub _createPackageConf { my ($bogref, $dest) = @_ ;
    my %packageConfig;
    $packageConfig{'build-sys'}    = _getBOGValue( $bogref, 'packagebuild_system' );
    if (isJavaBytecodePackage($bogref) && ! $packageConfig{'build-sys'}) {
        $packageConfig{'build-sys'} = 'java-bytecode';
    }
    $packageConfig{'build-file'}   = _getBOGValue( $bogref, 'packagebuild_file' );
    $packageConfig{'build-target'} = _getBOGValue( $bogref, 'packagebuild_target' );
    $packageConfig{'build-opt'}    = _getBOGValue( $bogref, 'packagebuild_opt' );
    $packageConfig{'build-dir'}    = _getBOGValue( $bogref, 'packagebuild_dir' );
    $packageConfig{'build-cmd'}    = _getBOGValue( $bogref, 'packagebuild_cmd' );
    $packageConfig{'config-opt'}   = _getBOGValue( $bogref, 'packageconfig_opt' );
    $packageConfig{'config-dir'}   = _getBOGValue( $bogref, 'packageconfig_dir' );
    $packageConfig{'config-cmd'}   = _getBOGValue( $bogref, 'packageconfig_cmd' );
    $packageConfig{'classpath'}    = _getBOGValue( $bogref, 'package_classpath' );

    # 2 new fields for android assess 1.08.2015
    $packageConfig{'android-sdk-target'}    = _getBOGValue( $bogref, 'android_sdk_target' );
    $packageConfig{'android-redo-build'}    = _getBOGValue( $bogref, 'android_redo_build' );

    # 2 new fields for android assess 8.18.2015
    $packageConfig{'android-lint-target'} = _getBOGValue( $bogref, 'android_lint_target' );
    $packageConfig{'gradle-wrapper'} = _getBOGValue( $bogref, 'use_gradle_wrapper' );

    # 2 new fields for android+maven assess 8.31.2015
    $packageConfig{'android-maven-plugin'} = _getBOGValue( $bogref, 'android_maven_plugin' );
    $packageConfig{'maven-version'} = _getBOGValue( $bogref, 'maven_version' );

    # 3 new fields for ruby assess 8.18.2015
    if (isRubyPackage($bogref)) {
        my $bog_package_type = _getBOGValue( $bogref, 'packagetype' );
        my $ruby_language_type = (split q{ }, $bog_package_type)[0];
        my $ruby_package_type = lc((split q{ }, $bog_package_type)[-1]);
        my $bog_language_version = _getBOGValue( $bogref, 'language_version' );
        $packageConfig{'package-language'} = $ruby_language_type;
        $packageConfig{'package-type'} = $ruby_package_type;
        if ($bog_language_version) {
            $packageConfig{'package-language-version'} = lc($ruby_language_type) . q{-} . $bog_language_version;
        }
    }

    # new field for java 8 support
    if (isJavaPackage($bogref)) {
        my $bog_package_type = _getBOGValue($bogref, 'packagetype');
        if ($bog_package_type =~ m/Java\s7/sxm) {
            $packageConfig{'package-language-version'} = 'java-7';
        }
        elsif ($bog_package_type =~ m/Java\s8/sxm) {
            $packageConfig{'package-language-version'} = 'java-8';
        }
    }

    # 3 new fields for bytecode assess 2.10.2014
    $packageConfig{'package-classpath'} = _getBOGValue($bogref, 'packageclasspath');
    $packageConfig{'package-srcdir'} = _getBOGValue($bogref, 'packagebytecodesourcepath');
    $packageConfig{'package-auxclasspath'} = _getBOGValue($bogref, 'packageauxclasspath');

    # 1 new field for script assess 12.15.2016
    if (isScriptPackage($bogref)) {
        $packageConfig{'package-language'} = _getBOGValue($bogref, 'package_language');
    }

    # 1 new field for script assess python assessments 01.20.2017
    if (isPythonPackage($bogref)) {
		my $packagetype = _getBOGValue($bogref, 'packagetype');
		my $packagelanguage = '';
		if ($packagetype eq 'Python2') {
			$packagelanguage = 'Python-2';
		}
		elsif ($packagetype eq 'Python3') {
			$packagelanguage = 'Python-3';
		}
        $packageConfig{'package-language'} = $packagelanguage;
    }

    foreach my $key ( keys %packageConfig ) {
        if ( !defined( $packageConfig{$key} ) ) {
            delete $packageConfig{$key};
        }
    }

    $packageConfig{'package-archive'} = basename($bogref->{'packagepath'});
    $packageConfig{'package-dir'}     = trim($bogref->{'packagesourcepath'});
    my $packagename = $packageConfig{'package-archive'};

    # Remove well known extensions
    $packagename =~ s/.tar.gz$//sxm;
    $packagename =~ s/.tgz$//sxm;
    $packagename =~ s/.tar.bz2$//sxm;
    $packagename =~ s/.zip$//sxm;
    my @packageStuff = split /-/sxm, $packagename;
    if (scalar(@packageStuff) <= 1) {
        $packageConfig{'package-version'} = 'unknown';
    }
    else {
        $packageConfig{'package-version'} = pop @packageStuff;
    }
    $packageConfig{'package-short-name'} = join( q{-}, @packageStuff );
    return saveProperties("$dest/package.conf", \%packageConfig);
}

sub _mergeDependencies { my ($file) = @_ ;
    $log->debug("_mergeDependencies - file: $file");
    if (open (my $fd, '<', $file)) {
        my %map;
        while (<$fd>) {
            next if (!/=/sxm); # Skip non-property looking lines
            chomp;
            my ($key, $value)=split(/=/sxm,$_);
            $map{$key} .= "$value ";
        }
        close($fd);
        if (open(my $fd, '>', $file)) {
            foreach my $key (keys %map) {
                print $fd "$key=$map{$key}\n";
            }
            close($fd);
        }
    }
    return;
}

sub _addUserDepends { my ($bogref, $destfile) = @_ ;
    if (!defined($bogref->{'packagedependencylist'}) || $bogref->{'packagedependencylist'} eq q{null}) {
        $log->info("addUserDepends - No packagedependencylist in BOG");
        return;
    }
    if (open(my $fh, '>>', $destfile)) {
        $log->info("addUserDepends - opened $destfile");
        print $fh "dependencies-$bogref->{'platform'}=$bogref->{'packagedependencylist'}\n";
        if (! close($fh)) {
            $log->warn("adduserDepends - Error closing $destfile: $OS_ERROR");
        }
    }
    else {
        $log->error("addUserDepends - Cannot append to $destfile :$OS_ERROR");
    }
    return;
}

sub _parserDeploy { my ($opts) = @_;
    my $member = $opts->{'member'};
    my $tar = $opts->{'archive'};
    my $dest = $opts->{'dest'};
    if ($member =~ /parser-os-dependencies.conf/sxm) {
        $log->debug("_parserDeploy - extract: $member to $dest/os-dependencies-parser.conf");
        $tar->extract_file($member, "$dest/os-dependencies-parser.conf");
    }
    if ($member =~ /in-files/sxm) {
        my $filename = basename($member);
        $log->debug("_parserDeploy - extract: $member to $dest/$filename");
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

#########################
#   HTCondor ClassAd    #
#########################

sub updateClassAdAssessmentStatus { my ($execrunuid, $vmhostname, $status) = @_ ;
    $global_swamp_config ||= getSwampConfig();
    my $HTCONDOR_COLLECTOR_HOST = $global_swamp_config->get('htcondor_collector_host');
    $log->info("Status: $status");
    my ($output, $stat) = systemcall("condor_advertise -pool $HTCONDOR_COLLECTOR_HOST UPDATE_AD_GENERIC - <<'EOF'
MyType=\"Generic\"
Name=\"$execrunuid\"
SWAMP_vmu_assessment_vmhostname=\"$vmhostname\"
SWAMP_vmu_assessment_status=\"$status\"
EOF
");
    if ($stat) {
        $log->error("Error - condor_advertise returns: $output $stat");
    }
}

1;
