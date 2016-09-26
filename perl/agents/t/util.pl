# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2016 Software Assurance Marketplace

# Handy test support functions
use Log::Log4perl;
sub start_server {
    my $server=shift;
    my $pid;
    logDebug("start_server: ($server)");
    if ( !defined( $pid = fork() ) ) {
        die "fork() error: $!, stopped";
    }
    elsif ($pid) {
        sleep 1;
        return $pid;
    }
    else {
        # Must exec here so we can be killed by parent.
        exec($server);
    }

}

sub stop_server {
    my $pid = shift;

    # Per RT 27778, use 'KILL' instead of 'INT' as the stop-server signal for
    # MSWin platforms:
    my $SIGNAL = ( $^O eq "MSWin32" ) ? 'KILL' : 'INT';
    kill $SIGNAL, $pid;
    sleep 2;    # give the old sockets time to go away
}

# Expects a hash ref from rpc call
sub callOK {
    my $ref = shift;
    if (ref($ref)  ne "HASH") {
        logDebug("ERROR: result not a hash ref $ref");
        return 0;
    }
    if (exists($ref->{'error'})) {
        if (ref($ref->{'error'})) {
            logDebug("ERROR hash:");
            foreach my $kk (keys %{$ref->{'error'}}) {
                logDebug("ERROR: $kk : ".${$ref->{'error'}}{$kk});
            }
        }
        else {
            logDebug("ERROR : ".$ref->{'error'});
        }
        return 0;
    }
    return 1;
}
sub callFAIL {
    return !callOK(shift);
}
sub logDebug {
    my	( $msg )	= @_;
    if (Log::Log4perl->initialized()) {
        Log::Log4perl->get_logger(q{})->debug($msg);
    }
    else {
        print {*STDERR} "Logging off: $msg\n";
    }
    return ;
} 

1;
