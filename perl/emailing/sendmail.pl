#!/usr/bin/env perl 

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

#** @file sendmail.pl
#
# @brief
# @author Dave Boulineau (db), dboulineau@continuousassurance.org
# @date 02/27/2014 12:40:53
#*

use 5.014;
use utf8;
use warnings;
use strict;
use FindBin qw($Bin);
use lib ( "$FindBin::Bin/../perl5", "$FindBin::Bin/lib" );

use Getopt::Long qw/GetOptions/;
use Pod::Usage qw/pod2usage/;
use Email::MIME;

use English '-no_match_vars';
use Carp qw(carp croak);
use Email::Sender::Simple qw(sendmail);
use Email::Sender::Transport::SMTP;

my $help = 0;
my $man  = 0;
our $VERSION = '1.00';
my $dryrun = 0;
my $templatefile;
my $list;

GetOptions(
    'dryrun'     => \$dryrun,
    'list=s'     => \$list,
    'template=s' => \$templatefile,
    'help|?'     => \$help,
    'man'        => \$man,
) or pod2usage(2);

if ($help) { pod2usage(1); }
if ($man) { pod2usage( '-verbose' => 2 ); }
my ($subject, $template)= readtemplate($templatefile);
# first, create your message
my $transport = Email::Sender::Transport::SMTP->new( { host => 'swa-service-1.mirsam.org' } );
if ( open( my $fh, '<', $list ) ) {
    while (<$fh>) {
        next if (/^#/);
        next if ($. eq 1);
        chomp;

        #student_email,student_name,prof_name,url
        my ( $email, $student, $prof, $url ) = split( /,/sxm, $_ );

        my $body = $template;
        # Populate the template with actual values.
        $body =~ s/<student_name>/$student/g;
        $body =~ s/<prof_name>/$prof/g;
        $body =~ s/<student_email>/$email/g;
        $body =~ s/<url>/$url/g;
        if ( !$dryrun ) {
            my $message = Email::MIME->create(
                header_str => [
                    From =>
                      '"Software Assurance Marketplace: Do Not Reply"<do-not-reply@mir-swamp.org>',
                    To      => $email,
                    Subject => $subject,
                ],
                attributes => {
                    encoding => 'quoted-printable',
                    charset  => 'utf-8',
                },
                body_str => $body,
            );
            sendmail( $message, { transport => $transport } );
            sleep 1;
        }
        else {
            print "=" x 80, "\n";
            print "Subject: [$subject]\n";
            print "$body\n";
        }
    }
    close ($fh);
}
else {
    croak "Cannot open $list $OS_ERROR";
}
sub readtemplate {
    my $filename = shift;
    my $subject;
    my $body;
    my $inBody = 0;
    if (open(my $fh, '<', $filename)) {
        while (<$fh>) {
            if (!$inBody && /^Subject:/) {
            chomp;
                $_ =~ s/^Subject:\s+//;
                $subject = $_;
                next;
            }
            if (!$inBody && /^Msg Body:/) {
                $inBody = 1;
                $_ =~ s/^Msg Body://;
                $body .= $_;
                next;
            }
            if ($inBody) {
                $body .= $_;
            }
        }
        close ($fh);
    }
    else {
        carp "Cannot open $filename $OS_ERROR";
    }
    return ($subject, $body);;
}

__END__ =pod

=encoding utf8

=head1 NAME

sendmail.pl 

=head1 SYNOPSIS

sendmail.pl  --template templatefile.txt --list emaillist.csv --help

=head1 DESCRIPTION

sendmail.pl Will send emails to users listed in B<emaillist.csv> 

=head1 OPTIONS

=over 8

=item --man

Show manual page

=back

=over 8

=item --help

Show this help message

=back

=over 8

=item B<--list I<emaillist.csv>>

A comma separated list of the form student_email,student_name,prof_name,url.
The first line of this file is assumed to be a header and is disregarded.

=back

=over 8

=item B<--template I<template file>>

Specify the name of the template file to use. Template is expected to contain a
subject specification line, beginning with 'Subject:' followed by the single
subject line and the message body. The message body is assumed to be all text
after the line beginning with 'Msg Body:'. Within the message body, any text of
the form <student_email> will be replaced with the email of the student email
column from I<emaillist.csv>. Text of the form <url> will be replaced with the
URL column of I<emaillist.csv>. Text of the form <student_name> will be
replaced with the student name column from I<emaillist.csv> and text of the
form <prof_name> will be replaced with the professor column of
I<emaillist.csv>.

=back

=cut
