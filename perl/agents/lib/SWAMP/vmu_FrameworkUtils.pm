# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2018 Software Assurance Marketplace

package SWAMP::vmu_FrameworkUtils;
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

use parent qw(Exporter);
our (@EXPORT_OK);
BEGIN {
    require Exporter;
    @EXPORT_OK = qw(savereport generatereport);
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

sub generatereport { my ($tarball, $topdir) = @_ ;
    my ($statusOut, $status) = loadStatusOut($tarball, $topdir);
    
    my %report;
	$report{'statusOut'} = $statusOut;
    $report{'tarball'} = basename $tarball;
    $report{'accessmentTime'} = loadTimeOut($tarball, $topdir);
    if ($status) {
		# Add case statement here to include other report files based on specific error conditions
		#
        $report{'error'} = addErrorNote($status);
        my $string;
        my $nOut;
        my $nErr;
        $report{'no-build'} = addBuildfailures($status, $tarball, $topdir);
        ($nOut, $string) = addStdout($status, $tarball);
        if ($nOut > 0) {
            $report{'stdout'} = $string;
        }
        ($nErr, $string) = addStderror($status, $tarball);
        if ($nErr > 0) {
            $report{'stderr'} = $string;
        }
        # if (($nOut + $nErr) == 0) {
            # $report{'error'} .= q{<p><b>Unable to find specific stdout/stderr, showing output from entire assessment:</b><p>};
            # $report{'error'} .= rawTar($tarball, qq{$topdir/run.out});
        # }
        $string = rawTar($tarball, qq{$topdir/versions.txt});
        if ($string) {
            $report{'versions'} = $string;
        }
    }
    else {
        $report{'error'} = addGenericError($tarball);
    }
    return \%report;
}

sub savereport {
    my ( $report, $filename, $url, $header) = @_;
    my @headerlist = @{$header};
	my $fh;
    my $uuid = dirname ($filename);
    $uuid =~ s/^.*\///sxm;
    if ( !open $fh, '>', $filename ) {
        return 0;
    }
	
    print $fh qq{<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">\n};

    print $fh "<HTML><HEAD><TITLE>Failed Assessment Report</TITLE></HEAD>\n";
    print $fh "<BODY>\n";
    print $fh '<H1><div class="icon"><i class="fa fa-bug"></i></div>Failed Assessment Report</H1>';
	print $fh '<ol class="breadcrumb"><li><a href="#home"><i class="fa fa-home"></i>Home</a></li><li><i class="fa fa-info"></i>About</li></ol>';

	print $fh '<div class="row"><div class="col-sm-3"><h2>Package Name</h2><span>'. ($headerlist[0]).'</span></div><div class="col-sm-3"><h2>Tool Name</h2><span>'.($headerlist[1]).'</span></div> <div class="col-sm-3"><h2>Platform Name</h2><span>'.($headerlist[2]).'</span></div><div class="col-sm-3"><h2>Assessment Start Time</h2><span>'.($headerlist[3]).'</span></div></div>';

	print $fh '<div class="row"><div class="col-sm-3"><h2>Package Version</h2><span>'. ($headerlist[4]).'</span></div><div class="col-sm-3"><h2>Tool Version</h2><span>'.($headerlist[5]).'</span></div> <div class="col-sm-3"><h2>Platform Version</h2><span>'.($headerlist[6]).'</span></div><div class="col-sm-3"><h2>Assessment Complete Time</h2><span>'.($headerlist[7]).'</span></div></div>';
	
	print $fh "<hr>";	

    if ( $report->{'no-build'} ) {
        print $fh "<li><a href=\"#nobuild\">Error messages from no-build step</a></li>\n";
    }
    if ( $report->{'error'} ) {
        print $fh "<li><a href=\"#error\">Error messages from assessment</a></li>\n";
    }
    if ( $report->{'stdout'} ) {
        print $fh "<li><a href=\"#stdout\">Standard out</a></li>\n";
    }
    if ( $report->{'stderr'} ) {
        print $fh "<li><a href=\"#stderr\">Standard error</a></li>\n";
    }
    if ( $report->{'versions'} ) {
        print $fh "<li><a href=\"#versions\">Version information</a></li>\n";
    }
    print $fh qq{<li><a href=\"${url}$uuid/$report->{'tarball'}\">Download all failed results as a single file</a></li>};
    print $fh qq{<li><a href=\"https://www.swampinabox.org/doc/statusout.pdf\" target=\"_blank\">Status.out and Debugging SWAMP Failures</a></li>};
    print $fh "<p>";

	if ($report->{'statusOut'}) {
        print $fh "<hr><H2><a id=\"statusOut\">Contents of assessment status.out</a></H2>\n";
        print $fh "<pre>$report->{'statusOut'}</pre>\n";
	}
    if ($report->{'no-build'}) {
        print $fh "$report->{'no-build'}\n";
    }
    if ( $report->{'error'} ) {
        print $fh "<hr><H2><a id=\"error\">Error messages from assessment</a></H2>\n";
        print $fh "<pre>$report->{'error'}</pre>\n";
    }
    if ( $report->{'stdout'} ) {
        print $fh "<hr><H2><a id=\"stdout\">Standard out</a></H2>\n";
        print $fh "<pre>$report->{'stdout'}</pre>\n";
    }
    if ( $report->{'stderr'} ) {
        print $fh "<hr><H2><a id=\"stderr\">Standard error</a></H2>\n";
        print $fh "<pre>$report->{'stderr'}</pre>\n";
    }
    if ($report->{'versions'}) {
        print $fh "<hr><H2><a id=\"versions\">Version information</a></H2>\n";
        my @versions =split(/\n/sxm, $report->{'versions'});
        #print $fh "<pre><TABLE><TR><TH align=left>Component</TH><TH align=left>Version</TH>\n";
    	    
        print $fh '<table><thead><tr><th><i class="fa fa-cog"></i><span> Component</span></th><th><i class="fa fa-code-fork"></i><span> Version</span></th></tr></thead><tbody>';
		foreach (@versions) {
            my ($component,$version)=split(/:/sxm);
            print $fh "<tr><td>$component</td><td>$version</td></tr>\n";
        }
        print $fh "</tbody></TABLE>\n";
    }
    print $fh "<hr><pre>Report generated: ",scalar localtime,"</pre>\n";
    print $fh "</BODY>\n";
    print $fh "</HTML>\n";
    if (!close $fh) {
        
    }
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

sub addErrorNote { my ($s) = @_;
    my $note;
    if ( !@{ $s->{'#errors'} } && !@{ $s->{'#warnings'} } ) {
        if ( exists $s->{'all'} && $s->{'all'}{'status'} eq 'PASS' ) {
            $note  = "No errors detected";
        }
        else {
            my $errCnt   = scalar @{ $s->{'#errors'} };
            my $warnCnt  = scalar @{ $s->{'#warnings'} };
            my $errorString;
            $note = "(errors: $errCnt, warnings: $warnCnt)\n";
            $errorString .=
              '<TABLE><thead><TR><TH><i class="fa fa-exclamation-triangle"></i><span> Failing Step</span></TH><TH><i class="fa fa-commenting-o"></i><span> Error Message</span></TH></TR></thead><tbody>';
            foreach my $t ( @{ $s->{'#order'} } ) {
                my $status   = $t->{'status'};
                my $taskName = $t->{'task'};
                if ( $taskName ne q{all} && $status eq q{FAIL} ) {
                    $errorString .= "<TR><TD>$taskName</TD>";
                    if (defined($t->{'msg'})) {
                        $errorString .= "<TD>$t->{msg}</TD></TR>";
                    }
                    else {
                        $errorString .= "<TD>No error message found</TD>";
                    }
                }
            }
            $errorString .= '</tbody></TABLE>';
            $note = $errorString;
        }
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
            #say "file $_";
            my @line = split( q{ }, $_ );
            $str .= "<b>FILE: $line[-1] from $subfile</b>\n";
            $str .= tarCat( $tarball, $subfile, $line[-1] );
            $str .= q{<p>};
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
