#!/usr/bin/env perl

# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2019 Software Assurance Marketplace

use strict;
use warnings;
use Data::UUID;

# maximum number of execution records
my $MAX_EXECUTION_RECORDS = 1000;

# launch_counter threshold
my $launch_counter_threshold = 15;

# hash of execution records indexed by execrunuid
my $execution_records = [];

sub show_execution_records {
	if (scalar(@$execution_records) > 0) {
		print scalar(@$execution_records), "\texecrunuid\t\t\t\tlf\tlc\tld\n";
		my $ecount = 0; my $lcount = 0; my $qcount = 0; my $dcount = 0;
		for (my $index = 0; $index < scalar(@$execution_records); $index++) {
			my $execution_record = $execution_records->[$index];
			print $index, ")\t",
			$execution_record->{'execrunuid'}, "\t", 
			$execution_record->{'launch_flag'}, "\t",
			$execution_record->{'launch_counter'}, "\t",
			$execution_record->{'launch_decrement'}, "\t";
			if ($execution_record->{'launch_flag'}) {
				if ($execution_record->{'launch_counter'} >= $launch_counter_threshold) {
					print 'Expired';
					$ecount += 1;
				}
				elsif ($execution_record->{'launch_decrement'} == 1) {
					print 'Launch';
					$lcount += 1;
				}
				else {
					print 'Query';
					$qcount += 1;
				}
			}
			else {
				print 'Done';
				$dcount += 1;
			}
			print "\n";
		}
		print "expired: $ecount launch: $lcount query: $qcount done: $dcount total: (", $ecount + $lcount + $qcount + $dcount, ")\n";
	}
	else {
		print "no records\n";
	}
}

sub add_execution_record {
	my $execrunuid = Data::UUID->new()->create_str();
	my $execution_record = {
		'execrunuid'		=> $execrunuid,
		'launch_flag'		=> 1,
		'launch_counter'	=> 0,
		'launch_decrement'	=> 1,
	};
	push @$execution_records, $execution_record;
}

# add a random number of execution records
sub add_execution_records { my ($count) = @_ ;
	# add 0 to 2 or count records
	$count = int(rand(3)) if (! defined($count));
	for (my $i = 1; $i <= $count; $i++) {
		add_execution_record();
	}
	print "Added: $count new records\n";
}

# "query" execution_records "database table" for launchable records
# launchable means launch_flag is 1 and launch_counter < launch_counter_threshold
sub get_launchable_execution_record_indexes {
	my $retval = [];
	my $count = 0;
	for (my $index = 0; $index < scalar(@$execution_records); $index++) {
		my $execution_record = $execution_records->[$index];
		if ($execution_record->{'launch_flag'} && 
		   ($execution_record->{'launch_counter'} < $launch_counter_threshold)) {
		   $count += 1;
		   push @$retval, $index;
		}
	}
	print "Found: $count launch candidate records\n";
	return $retval;
}

# simulate successful launch 
# randomly determine whether record is launched
sub launch_execution_record { my ($index) = @_ ;
	my $execution_record = $execution_records->[$index];
	my $roll_dice = int(rand(6)) + 1;
	if ($roll_dice == 5) {
		$execution_record->{'launch_flag'} = 0;
		return 1;
	}
	return 0;
}

my $interactive = 0;
foreach my $arg (@ARGV) {
	$interactive = 1 if ($arg eq '-i');
	$MAX_EXECUTION_RECORDS = $arg if ($arg =~ m/^\d+$/);
}
if (! $interactive) {
	add_execution_records(3);
}
while (1) {
	show_execution_records();
	print "\n";
	if ($interactive) {
		print 'Continue: ';
		my $answer = <STDIN>;
		last if (($answer =~ m/q/i) || ($answer =~ m/n/i));
	}
	last if (scalar(@$execution_records) >= $MAX_EXECUTION_RECORDS);
	my $launch_indexes = get_launchable_execution_record_indexes();
	if (! $interactive) {
		last if (scalar(@$launch_indexes) == 0);
	}
	my $attempt_count = 0;
	my $success_count = 0;
	foreach my $index (@$launch_indexes) {
		my $execution_record = $execution_records->[$index];
		$execution_record->{'launch_decrement'} -= 1;
		if ($execution_record->{'launch_decrement'} == 0) {
			$execution_record->{'launch_counter'} += 1;
			$execution_record->{'launch_decrement'} = $execution_record->{'launch_counter'} + 1;
			$success_count += launch_execution_record($index);
			$attempt_count += 1;
		}
	}
	print "Successfully launched: $success_count out of: $attempt_count launchable records\n";
	add_execution_records();
}
print "Hello World!\n";
