# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#** @file VRun.pm
#
# @brief This package contains the testable methods used by vrunTask.pl
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 12/23/2013 14:27:58
#*
#
package SWAMP::VRunTools;

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
        createrunscript 
        copyvruninputs
        parseRunOut
    );
}

use Cwd qw(abs_path);
use English '-no_match_vars';
use File::Copy qw(move cp);
use File::Path qw(make_path);
use File::Basename qw(basename);
use Carp qw(croak carp);
use Log::Log4perl;
use Log::Log4perl::Level;
use SWAMP::SWAMPUtils qw(trim systemcall getSWAMPDir getSwampConfig);

#** @function createrunscript( \%bogref, $dest, $timeout )
# @brief Create the run.sh script and ancillary scripts for this viewer VM
#
# @param bogref Reference to the Bill Of Goods hash 
# @param dest Name of the folder in which to create run.sh
# @param timeout Number of seconds of idle time before this VM shuts itself down
# @return 1 on success, 0 on failure
#*
#	CodeDX files
#	vrun.sh
#	vrunchecktimeout
#	codedx_viewerdb.sh
#
#	codedx.war
#	emptydb-codedx.sql
#	emptydb-mysql.sql
#	swamp-codedx-service
#	checktimeout.pl
#	logback.xml
#	codedx.props
#	codedx_viewerdb.tar.gz
#

# This handles vrun.sh, vrunchecktimeout, and codedx_viewerdb.sh 
sub createrunscript_codedx { my ($bogref, $dest) = @_ ;
    my $ret    = 1;

    my $basedir = getSWAMPDir();

	# set CHECKTIMEOUT_FREQUENCY in run.sh in vm input directory
	# set PROJECT in run.sh in vm input directory
	# cat vrun.sh into run.sh in vm input directory
	my $vrunsh = abs_path("$basedir/thirdparty/codedx/swamp/vrun.sh");
	my $inputvrunsh = abs_path("${dest}/run.sh");
	my $checktimeout_frequency = getSwampConfig()->get('vruntimeout_frequency') // '10';
    my ($output, $status) = systemcall("echo CHECKTIMEOUT_FREQUENCY=$checktimeout_frequency > $inputvrunsh");
	if ($status) {
        Log::Log4perl->get_logger(q{})->error("Cannot set CHECKTIMEOUT_FREQUENCY=$checktimeout_frequency in: $inputvrunsh $OS_ERROR");
		$ret = 0;
	}
    ($output, $status) = systemcall("echo PROJECT=$bogref->{'urluuid'} >> $inputvrunsh");
	if ($status) {
        Log::Log4perl->get_logger(q{})->error("Cannot set PROJECT=$bogref->{'urluuid'} in: $inputvrunsh $OS_ERROR");
		$ret = 0;
	}
    ($output, $status) = systemcall("cat $vrunsh >> $inputvrunsh");
	if ($status) {
        Log::Log4perl->get_logger(q{})->error("Cannot add: $vrunsh to: $inputvrunsh $OS_ERROR");
		$ret = 0;
	}

	# set PROJECT in codedx_viewerdb.sh in vm input directory
	# cat codedx_viewerdb.sh into codedx_viewerdb.sh in vm input directory
	my $codedx_viewerdbsh = abs_path("$basedir/thirdparty/codedx/swamp/codedx_viewerdb.sh");
	my $inputcodedx_viewerdbsh = abs_path("${dest}/codedx_viewerdb.sh");
    ($output, $status) = systemcall("echo PROJECT=$bogref->{'urluuid'} >> $inputcodedx_viewerdbsh");
	if ($status) {
        Log::Log4perl->get_logger(q{})->error("Cannot set PROJECT=$bogref->{'urluuid'} in: $inputcodedx_viewerdbsh $OS_ERROR");
		$ret = 0;
	}
    ($output, $status) = systemcall("cat $codedx_viewerdbsh >> $inputcodedx_viewerdbsh");
	if ($status) {
        Log::Log4perl->get_logger(q{})->error("Cannot add: $codedx_viewerdbsh to: $inputcodedx_viewerdbsh $OS_ERROR");
		$ret = 0;
	}
	
	# set CHECKTIMEOUT_DURATION in checktimeout
	# set CHECKTIMEOUT_LASTLOG in checktimeout
	# copy checktimeout to vm input directory
	my $checktimeout = abs_path("$basedir/thirdparty/codedx/swamp/vrunchecktimeout");
	my $inputchecktimeout = abs_path("${dest}/checktimeout");
	my $checktimeout_duration = getSwampConfig()->get('vruntimeout_duration') // '28800';
    ($output, $status) = systemcall("echo CHECKTIMEOUT_DURATION=$checktimeout_duration > $inputchecktimeout");
	if ($status) {
        Log::Log4perl->get_logger(q{})->error("Cannot set CHECKTIMEOUT_DURATION=$checktimeout_duration in: $inputchecktimeout $OS_ERROR");
		$ret = 0;
	}
	my $checktimeout_lastlog = getSwampConfig()->get('vruntimeout_lastlog') // '3600';
    ($output, $status) = systemcall("echo CHECKTIMEOUT_LASTLOG=$checktimeout_lastlog >> $inputchecktimeout");
	if ($status) {
        Log::Log4perl->get_logger(q{})->error("Cannot set CHECKTIMEOUT_LASTLOG=$checktimeout_lastlog in: $inputchecktimeout $OS_ERROR");
		$ret = 0;
	}
    ($output, $status) = systemcall("cat $checktimeout >> $inputchecktimeout");
	if ($status) {
        Log::Log4perl->get_logger(q{})->error("Cannot add: $checktimeout to: $inputchecktimeout $OS_ERROR");
		$ret = 0;
	}
    return $ret;
}

# This handles codedx.war, emptydb-codedx.sql, emptydb-mysql.sql, swamp-codedx-service, checktimeout.pl, logback.xml, codedx.props, codedx_viewerdb.tar.gz
sub copyvruninputs_codedx { my ($bogref, $dest) = @_ ;
	my $ret = 1;
    make_path( $dest, { 'error' => \my $err } );
    if ( @{$err} ) {
        for my $diag ( @{$err} ) {
            my ( $file, $message ) = %{$diag};
            if ( $file eq q{} ) {
                Log::Log4perl->get_logger(q{})->error("Cannot make input folder: $message" );
            }
            else {
                Log::Log4perl->get_logger(q{})->error("Cannot make input folder: $file $message" );
            }
        }
        return 0;
    }
	my $basedir = getSWAMPDir();
	# copy codedx.war to vm input directory
	my $file = abs_path("$basedir/thirdparty/codedx/vendor/codedx.war");
	if (! cp($file, $dest)) {
		Log::Log4perl->get_logger(q{})->error("Cannot copy $file to $dest $OS_ERROR" );
		$ret = 0;
	}
	# copy empty codedx database sql script to vm input directory
	$file = abs_path("$basedir/thirdparty/codedx/swamp/emptydb-codedx.sql");
	if (! cp($file, $dest)) {
		Log::Log4perl->get_logger(q{})->error("Cannot copy $file to $dest $OS_ERROR" );
		$ret = 0;
	}
	# copy empty mysql database sql script to vm input directory
	$file = abs_path("$basedir/thirdparty/codedx/swamp/emptydb-mysql.sql");
	if (! cp($file, $dest)) {
		Log::Log4perl->get_logger(q{})->error("Cannot copy $file to $dest $OS_ERROR" );
		$ret = 0;
	}
	# copy swamp-codedx shutdown service to vm input directory
	$file = abs_path("$basedir/thirdparty/codedx/swamp/swamp-codedx-service");
	if (! cp($file, $dest)) {
		Log::Log4perl->get_logger(q{})->error("Cannot copy $file to $dest $OS_ERROR" );
		$ret = 0;
	}
	# copy checktimeout.pl to vm input directory
	$file = abs_path("$basedir/thirdparty/codedx/swamp/checktimeout.pl");
	if (! cp($file, $dest)) {
		Log::Log4perl->get_logger(q{})->error("Cannot copy $file to $dest $OS_ERROR" );
		$ret = 0;
	}
	# copy logback.xml to vm input directory
	$file = abs_path("$basedir/thirdparty/codedx/swamp/logback.xml");
	if (! cp($file, $dest)) {
		Log::Log4perl->get_logger(q{})->error("Cannot copy $file to $dest $OS_ERROR" );
		$ret = 0;
	}
	# copy codedx.props to vm input directory
	# set swa.admin.system-key in codedx.props
	my $codedxprops = abs_path("$basedir/thirdparty/codedx/swamp/codedx.props");
	my $inputcodedxprops = abs_path("${dest}/codedx.props");
	if (! cp($codedxprops, $inputcodedxprops)) {
		Log::Log4perl->get_logger(q{})->error("Cannot copy $codedxprops to $inputcodedxprops $OS_ERROR" );
		$ret = 0;
	}
    my ($output, $status) = systemcall("echo swa.admin.system-key=$bogref->{'apikey'} >> $inputcodedxprops");
	if ($status) {
        Log::Log4perl->get_logger(q{})->error("Cannot set swa.admin.system-key=$bogref->{'apikey'} in: $inputcodedxprops $OS_ERROR");
		$ret = 0;
	}
	
    # It is OK to not specify a db_path, this just means it has never been persisted
    if (defined($bogref->{'db_path'}) && length($bogref->{'db_path'}) > 2) {
		my $basename = basename($PROGRAM_NAME);
		if (! -r $bogref->{'db_path'}) {
			Log::Log4perl->get_logger('viewer')->trace("$basename file: $bogref->{'db_path'} not found");
		}
		else {
        	if (cp($bogref->{'db_path'}, $dest)) {
				Log::Log4perl->get_logger('viewer')->trace("$basename copy: $bogref->{'db_path'} to $dest");
        	}
			else {
            	# Error, but non-fatal.
				Log::Log4perl->get_logger('viewer')->trace("$basename copy failed: $bogref->{'db_path'} to $dest $OS_ERROR");
            	Log::Log4perl->get_logger(q{})->error("Cannot copy $bogref->{'db_path'} to $dest $OS_ERROR");
			}
		}
    }
    return $ret;
}

#	ThreadFix files
#	vrun.sh
#	vrunchecktimeout
#	threadfix_viewerdb.sh
#
#	threadfix.war
#	emptydb-threadfix.sql
#	emptydb-mysql-threadfix.sql
#	flushprivs.sql
#	resetdb-threadfix.sql
#	swamp-threadfix-service
#	checktimeout.pl
#	threadfix.jdbc.properties
#	threadfix_viewerdb.tar.gz

# This handles vrun.sh and vrunchecktimeout
sub createrunscript_threadfix { my ($bogref, $dest) = @_ ;
    my $ret    = 1;

    my $basedir = getSWAMPDir();

	# set CHECKTIMEOUT_FREQUENCY in run.sh in vm input directory
	# set PROJECT in run.sh in vm input directory
	# set APIKEY in run.sh in vm input directory
	# cat vrun.sh into run.sh in vm input directory
	my $vrunsh = abs_path("$basedir/thirdparty/threadfix/swamp/vrun.sh");
	my $inputvrunsh = abs_path("${dest}/run.sh");
	my $checktimeout_frequency = getSwampConfig()->get('vruntimeout_frequency') // '10';
    my ($output, $status) = systemcall("echo CHECKTIMEOUT_FREQUENCY=$checktimeout_frequency > $inputvrunsh");
	if ($status) {
        Log::Log4perl->get_logger(q{})->error("Cannot set CHECKTIMEOUT_FREQUENCY=$checktimeout_frequency in: $inputvrunsh $OS_ERROR");
		$ret = 0;
	}
    ($output, $status) = systemcall("echo PROJECT=$bogref->{'urluuid'} >> $inputvrunsh");
	if ($status) {
        Log::Log4perl->get_logger(q{})->error("Cannot set PROJECT=$bogref->{'urluuid'} in: $inputvrunsh $OS_ERROR");
		$ret = 0;
	}
    ($output, $status) = systemcall("echo APIKEY=$bogref->{'apikey'} >> $inputvrunsh");
	if ($status) {
        Log::Log4perl->get_logger(q{})->error("Cannot set APIKEY=$bogref->{'apikey'} in: $inputvrunsh $OS_ERROR");
		$ret = 0;
	}
    ($output, $status) = systemcall("cat $vrunsh >> $inputvrunsh");
	if ($status) {
        Log::Log4perl->get_logger(q{})->error("Cannot add: $vrunsh to: $inputvrunsh $OS_ERROR");
		$ret = 0;
	}

	# set PROJECT in threadfix_viewerdb.sh in vm input directory
	# cat threadfix_viewerdb.sh into threadfix_viewerdb.sh in vm input directory
	my $threadfix_viewerdbsh = abs_path("$basedir/thirdparty/threadfix/swamp/threadfix_viewerdb.sh");
	my $inputthreadfix_viewerdbsh = abs_path("${dest}/threadfix_viewerdb.sh");
    ($output, $status) = systemcall("echo PROJECT=$bogref->{'urluuid'} >> $inputthreadfix_viewerdbsh");
	if ($status) {
        Log::Log4perl->get_logger(q{})->error("Cannot set PROJECT=$bogref->{'urluuid'} in: $inputthreadfix_viewerdbsh $OS_ERROR");
		$ret = 0;
	}
    ($output, $status) = systemcall("cat $threadfix_viewerdbsh >> $inputthreadfix_viewerdbsh");
	if ($status) {
        Log::Log4perl->get_logger(q{})->error("Cannot add: $threadfix_viewerdbsh to: $inputthreadfix_viewerdbsh $OS_ERROR");
		$ret = 0;
	}
	
	# set CHECKTIMEOUT_DURATION in checktimeout
	# set CHECKTIMEOUT_LASTLOG in checktimeout
	# copy checktimeout to vm input directory
	my $checktimeout = abs_path("$basedir/thirdparty/threadfix/swamp/vrunchecktimeout");
	my $inputchecktimeout = abs_path("${dest}/checktimeout");
	my $checktimeout_duration = getSwampConfig()->get('vruntimeout_duration') // '28800';
    ($output, $status) = systemcall("echo CHECKTIMEOUT_DURATION=$checktimeout_duration > $inputchecktimeout");
	if ($status) {
        Log::Log4perl->get_logger(q{})->error("Cannot set CHECKTIMEOUT_DURATION=$checktimeout_duration in: $inputchecktimeout $OS_ERROR");
		$ret = 0;
	}
	my $checktimeout_lastlog = getSwampConfig()->get('vruntimeout_lastlog') // '3600';
    ($output, $status) = systemcall("echo CHECKTIMEOUT_LASTLOG=$checktimeout_lastlog >> $inputchecktimeout");
	if ($status) {
        Log::Log4perl->get_logger(q{})->error("Cannot set CHECKTIMEOUT_LASTLOG=$checktimeout_lastlog in: $inputchecktimeout $OS_ERROR");
		$ret = 0;
	}
    ($output, $status) = systemcall("cat $checktimeout >> $inputchecktimeout");
	if ($status) {
        Log::Log4perl->get_logger(q{})->error("Cannot add: $checktimeout to: $inputchecktimeout $OS_ERROR");
		$ret = 0;
	}
    return $ret;
}

# This handles threadfix.war, emptydb-threadfix.sql, emptydb-mysql-threadfix.sql, flushprivs.sql, resetdb-threadfix.sql, swamp-threadfix-service, checktimeout.pl, threadfix.jdbc.properties
sub copyvruninputs_threadfix { my ($bogref, $dest) = @_ ;
	my $ret = 1;
    make_path( $dest, { 'error' => \my $err } );
    if ( @{$err} ) {
        for my $diag ( @{$err} ) {
            my ( $file, $message ) = %{$diag};
            if ( $file eq q{} ) {
                Log::Log4perl->get_logger(q{})->error("Cannot make input folder: $message" );
            }
            else {
                Log::Log4perl->get_logger(q{})->error("Cannot make input folder: $file $message" );
            }
        }
        return 0;
    }
	my $basedir = getSWAMPDir();
	# copy threadfix.war to vm input directory
	my $file = abs_path("$basedir/thirdparty/threadfix/vendor/threadfix.war");
	if (! cp($file, $dest)) {
		Log::Log4perl->get_logger(q{})->error("Cannot copy $file to $dest $OS_ERROR" );
		$ret = 0;
	}
	# copy empty threadfix database sql script to vm input directory
	$file = abs_path("$basedir/thirdparty/threadfix/swamp/emptydb-threadfix.sql");
	if (! cp($file, $dest)) {
		Log::Log4perl->get_logger(q{})->error("Cannot copy $file to $dest $OS_ERROR" );
		$ret = 0;
	}
	# copy empty mysql database sql script to vm input directory
	$file = abs_path("$basedir/thirdparty/threadfix/swamp/emptydb-mysql-threadfix.sql");
	if (! cp($file, $dest)) {
		Log::Log4perl->get_logger(q{})->error("Cannot copy $file to $dest $OS_ERROR" );
		$ret = 0;
	}
	# copy flushprivs.sql to vm input directory
	$file = abs_path("$basedir/thirdparty/threadfix/swamp/flushprivs.sql");
	if (! cp($file, $dest)) {
		Log::Log4perl->get_logger(q{})->error("Cannot copy $file to $dest $OS_ERROR" );
		$ret = 0;
	}
	# copy resetdb-threadfix.sql to vm input directory
	$file = abs_path("$basedir/thirdparty/threadfix/swamp/resetdb-threadfix.sql");
	if (! cp($file, $dest)) {
		Log::Log4perl->get_logger(q{})->error("Cannot copy $file to $dest $OS_ERROR" );
		$ret = 0;
	}
	# copy swamp-threadfix down service to vm input directory
	$file = abs_path("$basedir/thirdparty/threadfix/swamp/swamp-threadfix-service");
	if (! cp($file, $dest)) {
		Log::Log4perl->get_logger(q{})->error("Cannot copy $file to $dest $OS_ERROR" );
		$ret = 0;
	}
	# copy checktimeout.pl to vm input directory
	$file = abs_path("$basedir/thirdparty/threadfix/swamp/checktimeout.pl");
	if (! cp($file, $dest)) {
		Log::Log4perl->get_logger(q{})->error("Cannot copy $file to $dest $OS_ERROR" );
		$ret = 0;
	}
	# copy threadfix.jdbc.properties to vm input directory
	$file = abs_path("$basedir/thirdparty/threadfix/swamp/threadfix.jdbc.properties");
	if (! cp($file, $dest)) {
		Log::Log4perl->get_logger(q{})->error("Cannot copy $file to $dest $OS_ERROR" );
		$ret = 0;
	}
    # It is OK to not specify a db_path, this just means it has never been persisted
    if (defined($bogref->{'db_path'}) && length($bogref->{'db_path'}) > 2) {
		my $basename = basename($PROGRAM_NAME);
		if (! -r $bogref->{'db_path'}) {
			Log::Log4perl->get_logger('viewer')->trace("$basename file: $bogref->{'db_path'} not found");
		}
		else {
			my ($output, $status) = systemcall("tar -C $dest -xzf $bogref->{'db_path'}");
			if ($status) {
            	# Error, but non-fatal.
				Log::Log4perl->get_logger('viewer')->trace("$basename untar failed: $bogref->{'db_path'} to $dest error: <$output>");
            	Log::Log4perl->get_logger(q{})->error("Cannot untar: $bogref->{'db_path'} to $dest error: <$output>");
			}
			else {
				Log::Log4perl->get_logger('viewer')->trace("$basename untar: $bogref->{'db_path'} to $dest");
        	}
		}
    }
    return $ret;
}

sub createrunscript { my ($bogref, $dest) = @_ ;
	my $retval = 0;
	if ($bogref->{'viewer'} eq 'CodeDX') {
		$retval = createrunscript_codedx($bogref, $dest);
	}
	elsif ($bogref->{'viewer'} eq 'ThreadFix') {
		$retval = createrunscript_threadfix($bogref, $dest);
	}
	return $retval;
}

sub copyvruninputs { my ($bogref, $dest) = @_ ;
	my $retval = 0;
	if ($bogref->{'viewer'} eq 'CodeDX') {
		$retval = copyvruninputs_codedx($bogref, $dest);
	}
	elsif ($bogref->{'viewer'} eq 'ThreadFix') {
		$retval = copyvruninputs_threadfix($bogref, $dest);
	}
	return $retval;
}

sub parseRunOut {
    my $bogref = shift;
    my $output = shift;
    my @lines    = split( /\n/sxm, $output );
    my %values;
    $values{'apikey'} = $bogref->{'apikey'};
    $values{'project'} = $bogref->{'project'};
    $values{'state'} = 'starting';
    my $inIF = 0;
    my $lastLine=q{};
    foreach (@lines) {
        if (/^BEGIN\sifconfig /sxm) {
            $inIF = 1;
            next;
        }
        if ($inIF) {
            if (/^END\sifconfig/sxm) {
                $inIF = 0;
                next;
            }
            else {
               $_=~s/^.*inet//xms;
               $_=~s/\/.*$//xms;
               $values{'ipaddr'} = trim($_);
               $values{'state'} = 'ready';
            }
        }
        $lastLine = $_;
    }
    return %values;
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
 

