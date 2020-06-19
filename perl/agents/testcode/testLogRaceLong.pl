#!/usr/bin/env perl
use strict;
use warnings;
use English '-no_match_vars';
use Log::Log4perl;

my $log;
sub logfilename {
	my $name = 'testLogRace.log';
	return $name;
}

my $conf = q(
log4perl.logger	= ALL, Logfile
# general messages appender and layout
log4perl.appender.Logfile          = Log::Log4perl::Appender::File
log4perl.appender.Logfile.umask    = sub { 0000 };
# general log file
log4perl.appender.Logfile.filename = sub { logfilename(); };
log4perl.appender.Logfile.syswrite = 1 
log4perl.appender.Logfile.mode     = append
log4perl.appender.Logfile.layout   = Log::Log4perl::Layout::PatternLayout
# generic - date, pid, file, line, chomp nl nl
# log4perl.appender.Logfile.layout.ConversionPattern = %d [%P]: %F{1}-%L %m%n%n
# add %p - event priority
# log4perl.appender.Logfile.layout.ConversionPattern = %d [%p %P]: %F{1}-%L %m%n%n
# add %T - stack trace
# log4perl.appender.Logfile.layout.ConversionPattern = %d [%P]: %F{1}-%L %m%n[%T]%n%n
# add %p %T
log4perl.appender.Logfile.layout.ConversionPattern = %d [%p %P]: %F{1}-%L %m%n[%T]%n%n
);

my $loopmax = 5000000;
my $dumpvar = 0;
Log::Log4perl->init(\$conf);
$log = Log::Log4perl->get_logger(q{});
$log->info("$PROGRAM_NAME ($PID) Begin");
$log->info("$PROGRAM_NAME ($PID) Loop: ", 
	sub { 
		use Data::Dumper; 
		for (my $i = 0; $i < $loopmax; $i++) { 
			$dumpvar += 1; 
			print "$dumpvar/$loopmax\r";
		} 
		print "\n";
		Dumper($dumpvar); }
);
$log->info("$PROGRAM_NAME ($PID) Exit");
exit(0);
