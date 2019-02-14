#!/usr/bin/env perl
use strict;
use warnings;

sub get_final_viewer_status { my ($file) = @_ ;
    my $fh;
    if (! open($fh, '<', $file)) {
        return ''; 
    }   
    my @lines = <$fh>;
    close($fh);
    chomp @lines;                                                                                        
    return $lines[-1];
}

my $viewer_status = get_final_viewer_status('JobVMEvents.log');
print "viewer_status: $viewer_status\n";
print "Hello World!\n";
