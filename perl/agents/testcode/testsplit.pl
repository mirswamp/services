#!/usr/bin/env perl
use strict;
use warnings;

my $returned_execrunuid = 'vrun_a2cbee23-c32c-11e8-932e-0025b51000fd_CodeDX';
my $viewer_name = '';
$viewer_name = (split '_', $returned_execrunuid)[2] if ($returned_execrunuid);
print "returned_execrunuid: $returned_execrunuid viewer_name: $viewer_name\n";
print "Hello World!\n";
