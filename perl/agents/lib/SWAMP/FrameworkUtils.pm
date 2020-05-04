# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2020 Software Assurance Marketplace

package SWAMP::FrameworkUtils;
use 5.014;
use utf8;
use strict;
use warnings;
use English '-no_match_vars';
use File::Basename qw(basename dirname);
use File::Spec qw(catfile);
use XML::LibXML;
use XML::LibXSLT;
use SWAMP::vmu_Support qw(getSwampDir);
use JSON;
# required for MongoDB
use MongoDB;
use parent qw(Exporter);

our (@EXPORT_OK);
BEGIN {
    require Exporter;
    @EXPORT_OK = qw(generateErrorJson saveErrorJson generateMongoJson);
}

my $stdDivPrefix = q{ } x 2;
my $stdDivChars  = q{-} x 10;
my $stdDiv       = "$stdDivPrefix$stdDivChars";

# statusOutObj = ReadStatusOut(filename)
#
# ReadStatusOut returns a hash containing the parsed status.out file.
#
# A status.out file consists of task lines in the following format with the
# names of these elements labeled
#
#     PASS: the-task-name (the-short-message)           40.186911s
#
#     |     |              |                            |        |
#     |     task           shortMsg                     dur      |
#     status                                               durUnit
#
# Each task may also optional have a multi-line message (the msg element).
# The number of spaces before the divider are removed from each line and the
# line-feed is removed from the last line of the message
#
#     PASS: the-task-name (the-short-message)           40.186911s
#       ----------
#       line A
#       line A+1
#       ----------
# The returned hash contains a hash for each task.  The key is the name of the
# task.  If there are duplicate task names, duplicate keys are named using the
# scheme <task-name>#<unique-number>.
#
# The hash for each task contains the following keys
#
#   status    - one of PASS, FAIL, SKIP, or NOTE
#   task      - name of the task
#   shortMsg  - shortMsg or undef if not present
#   msg       - msg or undef if not present
#   dur       - duration is durUnits or undef if not present
#   durUnit   - durUnits: 's' is for seconds
#   linenum   - line number where task started in file
#   name      - key used in hash (usually the same as task)
#   text      - unparsed text
#
# Besides a hash for each task, the hash function returned from ReadStatusOut
# also contains the following additional hash elements:
#
#   #order     - reference to an array containing references to the task hashes
#                in the order they appeared in the status.out file
#   #errors    - reference to an array of errors in the status.out file
#   #warnings  - reference to an array of warnings in the status.out file
#   #filename  - filename read
#
# If there are no errors or warnings (the arrays are 0 length), then exists can
# be used to check for the existence of a task.  The following would correctly
# check if that run succeeded:
#
# my $s = ReadStatusOut($filename)
# if (!@{$s->{'#errors'}} && !@{$s->{'#warnings'}})  {
#     if (exists $s->{all} && $s->{all}{status} eq 'PASS')  {
#         print "success\n";
#     }  else  {
#         print "no success\n";
#     }
# }  else  {
#     print "bad status.out file\n";
# }
#
#
sub ReadStatusOut { my ($lines) = @_ ;
	my %status = (
		'#order'	=> [],
		'#errors'	=> [],
		'#warnings'	=> [],
	);
	my $lineNum = 0;
	my $msgLineNum;
	# required fields
	my ($name, $status);
	while ($lineNum < scalar(@$lines)) {
		my $line = $lines->[$lineNum];
		# optional fields
		
        my ($shortMsg, $msg, $dur, $durUnit);
		if ($line =~ m/^[A-Z]+\:/) {
			($status, my $rest) = split '\:', $line, 2;
			($name, $rest) = split ' ', $rest, 2;
            if ($rest && ($rest =~ m/^\(.*\)/)) {
				($shortMsg, $rest) = split '\)', $rest, 2;
				$shortMsg =~ s/^\(//;
			}
			if ($rest && ($rest =~ m/^(\d+(?:\.\d+)?)([a-zA-Z]*)\s*.*$/)) {
				($dur, $durUnit) = ($1, $2);
			}
			# look ahead for msg
			$msgLineNum = $lineNum + 1;
			my $inMsgLine = 0;
			while ($msgLineNum < scalar(@$lines)) {
				my $nextLine = $lines->[$msgLineNum];
				last if ($nextLine =~ m/^[A-Z]+\:/);
				if ($nextLine !~ m/^\s*$/) {
					# msg start marker
					if ($nextLine eq $stdDiv) {
						$inMsgLine = ! $inMsgLine;
						if (! $inMsgLine) {
							$msgLineNum += 1;
							last;
						}
					}
					# add line to msg
					elsif ($inMsgLine) {
						$msg .= $nextLine;
					}
				}
				$msgLineNum += 1;
			}
			$status{$name} = {
				'status'   => $status,
				'name'     => $name,
				'task'     => $name,
				'shortMsg' => $shortMsg,
				'msg'      => $msg,
				'dur'      => $dur,
				'durUnit'  => $durUnit,
				'linenum'  => $lineNum,
				'text'     => $line,
			};
			push @{ $status{'#order'} }, $status{$name};
		}
		$lineNum = $msgLineNum;
	}
	return \%status;
}

sub generateMongoJson { my ($tarball, $topdir) = @_;
    my %report; 
    my $skip = 1;
	if ($skip) {	
	#load and save the status out
	my ($statusOut, $status) = loadStatusOut($tarball, $topdir);
	$report{'status_out'} = $statusOut;

	if ($status) {
		#include specific error
		$report{'error_message'} = addErrorNote($status);
		my $string;
        my $nOut;
        my $nErr;
        #$report{'no-build'} = addBuildfailures($status, $tarball, $topdir);
        ($nOut, $string) = addStdout($status, $tarball);

		#load and save the stdout
		if ($nOut > 0) {
            $report{'stdout'} = $string;
        }
		#load and save the stderr
		($nErr, $string) = addStderror($status, $tarball);
        if ($nErr > 0) {
            $report{'stderr'} = $string;
        }
		#load and save the versions
		 $string = rawTar($tarball, qq{$topdir/versions.txt});
        if ($string) {
        	$report{'version_information'} = $string
		}
	}
    }
	return \%report
    
}

# Read all the accessment error report from outputdisk.tar.gz,
# and store all of them into a perl dictionary.
sub generateErrorJson {
	my ($tarball, $topdir, @metadata) = @_;

	my %report;
	#save all the metadata
	$report{'package_name'} = $metadata[0];
	$report{'package_version'} = $metadata[4];
	$report{'platform_name'} = $metadata[2];
	$report{'platform_version'} = $metadata[6]; 
	$report{'tool_name'} = $metadata[1];
	$report{'tool_version'} = $metadata[5];
	$report{'assessment_start_ts'} = $metadata[3];
	$report{'assessment_end_ts'} = $metadata[7];
	$report{'report_generation_ts'} = $metadata[8]; 
	my $skip = 1;
	if ($skip) {	
	#load and save the status out
	my ($statusOut, $status) = loadStatusOut($tarball, $topdir);
	$report{'status_out'} = $statusOut;

	if ($status) {
		#include specific error
		$report{'error_message'} = addErrorNote($status);
		my $string;
        my $nOut;
        my $nErr;
        #$report{'no-build'} = addBuildfailures($status, $tarball, $topdir);
        ($nOut, $string) = addStdout($status, $tarball);

		#load and save the stdout
		if ($nOut > 0) {
            $report{'stdout'} = $string;
        }
		#load and save the stderr
		($nErr, $string) = addStderror($status, $tarball);
        if ($nErr > 0) {
            $report{'stderr'} = $string;
        }
		#load and save the versions
		 $string = rawTar($tarball, qq{$topdir/versions.txt});
        if ($string) {
        	$report{'version_information'} = $string
		}
	}
    }
	return \%report
}

# Convert a perl dictionary representing the accessment error report infomation into a string, 
# and then save it on the disk.
sub saveErrorJson {
	my ( $report, $filename) = @_;
	my $json_text = encode_json ($report);
	my $fh;
	if ( !open $fh, '>', $filename ) {
		return 0;
	}
	# prints the converted json text into the Json file
	print $fh $json_text;
	close $fh;
	return 1;
}

sub loadStatusOut { my ($tarball, $topdir) = @_ ;
    my $statusOut = rawTar($tarball, qq{$topdir/status.out});
    if ($statusOut) {
		my $lines = [split "\n", $statusOut];
		my $status = ReadStatusOut($lines);
		return ($statusOut, $status);
    }
    return;
}

#load the accessment time from the swamp_run.out file in the outputdisk.tar.gz
sub loadTimeOut{my ($tarball, $topdir) = @_ ;
    my $swampOut = rawTar($tarball, qq{$topdir/swamp_run.out});
    my $lines = [split "\n", $swampOut];
    my $lineNum = 0;
    while ($lineNum < scalar(@$lines)) {
        my $currline = $lines->[$lineNum];
        if($currline eq "========================== date"){
            return $lines->[$lineNum + 1];
        }
        $lineNum = $lineNum + 1;
    }
    return;
}

# addErrorNote will return an array of array with format [[task1, msg1],[task2, msg2]],
# or a string if no error detected or unable to parse status.out.
sub addErrorNote { my ($s) = @_;
    my $note;
    my @notelist;
    if ( !@{ $s->{'#errors'} } && !@{ $s->{'#warnings'} } ) {
        if ( exists $s->{'all'} && $s->{'all'}{'status'} eq 'PASS' ) {
            $note  = "No errors detected";
        }
        else {
            my $errCnt   = scalar @{ $s->{'#errors'} };
            my $warnCnt  = scalar @{ $s->{'#warnings'} };
            $note = "(errors: $errCnt, warnings: $warnCnt)\n";
            foreach my $t ( @{ $s->{'#order'} } ) {
                my $status   = $t->{'status'};
                my $taskName = $t->{'task'};

                if ( $taskName ne q{all} && $status eq q{FAIL} ) {
                    my @currErrorString;
                    push @currErrorString, $taskName;
                    if (defined($t->{'msg'})) {
                        push @currErrorString, $t->{msg};
                    }
                    else {
                        push @currErrorString, "No error message found";
                    }
                    push @notelist, \@currErrorString;
                }
            }
        }
        return \@notelist;
    }
    else {
        $note = q{Unable to parse status.out};
    }
    return $note;
}

sub tarTarTOC {
    my $tarball = shift;
    my $subfile = shift;
    my ( $output, $status ) =
      ( $_ = qx {tar -O -xzf $tarball $subfile | tar tzvf - 2>/dev/null}, $CHILD_ERROR >> 8 );
    if ($status) {
        return;
    }
    else {
        return split( /\n/sxm, $output );
    }
}

sub tarCat{
    my $tarball = shift;
    my $subfile = shift;
    my $file = shift;
    my ( $output, $status ) =
      ( $_ = qx {tar -O -xzf $tarball $subfile | tar -O -xzf - $file 2>/dev/null}, $CHILD_ERROR >> 8 );
    if ($status) {
        return;
    }
    else {
        return $output;
    }
}
sub tarTOC {
    my $tarball = shift;
    my ( $output, $status ) = ( $_ = qx {tar -tzvf $tarball 2>/dev/null}, $CHILD_ERROR >> 8 );
    if ($status) {
        return;
    }
    else {
        return split( /\n/sxm, $output );
    }
}
sub addBuildfailures { my ($status_out, $tarball, $topdir) = @_;
    my @files = tarTOC($tarball);
    foreach (@files) {
        if (/source-compiles.xml/xsm) {
            my $rawxml = rawTar($tarball, qq{$topdir/source-compiles.xml});
            my $xslt = XML::LibXSLT->new();
            my $source;
            my $success = eval { $source = XML::LibXML->load_xml( 'string' => $rawxml ); };
            my $xsltfile =  File::Spec->catfile( getSwampDir(), 'etc', 'no-build.xslt' );
            if ( defined($success) ) {
                my $style_doc  = XML::LibXML->load_xml( 'location' => "$xsltfile", 'no_cdata' => 1 );
                my $stylesheet = $xslt->parse_stylesheet($style_doc);
                my $result = $stylesheet->transform($source);
                return $result->toString();
            }
        }
    }
    return;
}

sub addStdout { my ($status_out, $tarball) = @_;
    return findFiles($tarball, q{(build_stdout|configure_stdout|resultparser.log)});

}

sub addStderror { my ($status, $tarball) = @_;
    return findFiles($tarball, q{(build_stderr|configure_stderr)});
}

sub findFiles { my ($tarball, $pattern) = @_;
    my $string;
    my @files=tarTOC($tarball);
    my $nFound = 0;
    foreach (@files) {
        if (/.tar.gz$/sxm) {
            chomp;
            my @line=split(q{ }, $_);
            my $files = getFiles($tarball, $pattern, $line[-1]);
            if ($files) {
                $string .= $files;
                $nFound++;
            }
        }
    }
    return ($nFound, $string);
}

sub getFiles { my ($tarball, $pattern, $subfile) = @_;
    my @files = tarTarTOC( $tarball, $subfile );
    my $str;
    foreach (@files) {
        if (/$pattern/sxm) {
            if (/swa_tool/sxm) {
                next;
            }
            chomp;
            my @line = split( q{ }, $_ );
            $str .= "FILE: $line[-1] from $subfile\n";
            $str .= tarCat( $tarball, $subfile, $line[-1] );
        }
    }
    return $str;
}

sub addGenericError { my ($tarball) = @_;
    return q{Unable to determine the final status of the assessment.};
}

sub rawTar { my ($tarball, $file) = @_ ;
    my ( $output, $status ) = ( $_ = qx {tar -O -xzf $tarball $file 2>/dev/null}, $CHILD_ERROR >> 8 );
    if ($status) {
		return;
    }
    else {
		return $output;
    }
}

1;
