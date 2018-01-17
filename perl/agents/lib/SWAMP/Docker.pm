# This file is subject to the terms and conditions defined in
# 'LICENSE.txt', which is part of this source code distribution.
#
# Copyright 2012-2018 Software Assurance Marketplace

package SWAMP::Docker;
use 5.014;
use utf8;
use strict;
use warnings;
use File::Basename;
use File::Path qw(make_path remove_tree);
use File::Copy qw(copy);

use parent qw(Exporter);
our (@EXPORT_OK);
BEGIN {
    require Exporter;
    @EXPORT_OK = qw(
		DockerSetupInput
		DockerWatch
		DockerGetIP
		DockerGetState
		DockerStop
		DockerStart
    );
}

sub DockerSetupInput { my ($vendor, $input, $project, $apikey, $threadfix_version, $checktimeout_frequency, $checktimeout_duration, $verbose) = @_ ;
	if (-d $input) {
		print "Deleting input directory\n" if ($verbose);
		remove_tree($input)
	}
	my @files = `find -L . -maxdepth 1 -type f`;
	chomp @files;
	print "Creating input directory\n" if ($verbose);
	make_path($input);

	# threadfix.war
	my $warfile = File::Spec->catfile($vendor, '..', 'war', "threadfix.${threadfix_version}.war");
	print "Copying $warfile to input as threadfix.war\n" if ($verbose);
	copy($warfile, File::Spec->catfile($input, 'threadfix.war'));

	# mysql database with users table
	my $dbfile = File::Spec->catfile($vendor, '..', 'databases', "emptydb-mysql-threadfix.sql");
	my $inputfile = File::Spec->catfile($input, 'emptydb-mysql-threadfix.sql');
	print "Copying $dbfile to input as emptydb-mysql-threadfix.sql\n" if ($verbose);
	copy($dbfile, $inputfile);

	# flushprivileges
	$dbfile = File::Spec->catfile($vendor, '..', 'databases', "flushprivs.sql");
	$inputfile = File::Spec->catfile($input, 'flushprivs.sql');
	print "Copying $dbfile to input as flushprivs.sql\n" if ($verbose);
	copy($dbfile, $inputfile);
	
	# resetdb drops and creates threadfix database
	$dbfile = File::Spec->catfile($vendor, '..', 'databases', "resetdb-threadfix.sql");
	$inputfile = File::Spec->catfile($input, 'resetdb-threadfix.sql');
	print "Copying $dbfile to input as resetdb-threadfix.sql\n" if ($verbose);
	copy($dbfile, $inputfile);
	
	# emptydb* install empty threadfix database
	$dbfile = File::Spec->catfile($vendor, '..', 'databases', "emptydb-threadfix-${threadfix_version}.sql");
	$inputfile = File::Spec->catfile($input, 'emptydb-threadfix.sql');
	print "Copying $dbfile to input as emptydb-threadfix.sql\n" if ($verbose);
	copy($dbfile, $inputfile);

	# checktimeout
	my $checktimeout = File::Spec->catfile($vendor, '..', 'swamp', 'vrunchecktimeout');
	print "Copying $checktimeout to input with CHECKTIMEOUT_DURATION=$checktimeout_duration\n" if ($verbose);
	$inputfile = File::Spec->catfile($input, 'checktimeout');
	system("echo CHECKTIMEOUT_DURATION=$checktimeout_duration >> $inputfile");
	system("cat $checktimeout >> $inputfile");
	$checktimeout = File::Spec->catfile($vendor, '..', 'swamp', "checktimeout.pl");
	$inputfile = File::Spec->catfile($input, 'checktimeout.pl');
	print "Copying $checktimeout to input as checktimeout.pl\n" if ($verbose);
	copy($checktimeout, $inputfile);

	# run.sh
	my $runsh = File::Spec->catfile($vendor, '..', 'swamp', 'vrun.sh');
	print "Copying $runsh to input with CHECKTIMEOUT_FREQUENCY=$checktimeout_frequency, PROJECT=$project and APIKEY=$apikey\n" if ($verbose);
	$inputfile = File::Spec->catfile($input, 'run.sh');
	system("echo '#!/usr/bin/env bash' >> $inputfile");
	system("echo CHECKTIMEOUT_FREQUENCY=$checktimeout_frequency >> $inputfile");
	system("echo PROJECT=$project >> $inputfile");
	system("echo APIKEY=$apikey >> $inputfile");
	system("cat $runsh >> $inputfile");
	system("echo 'while true; do sleep 30; done' >> $inputfile");
	system("chmod +x $inputfile");

	# jdbc.properties
	$dbfile = File::Spec->catfile($vendor, '..', 'config', "threadfix.jdbc.properties");
	$inputfile = File::Spec->catfile($input, 'threadfix.jdbc.properties');
	print "Copying $dbfile to input as threadfix.jdbc.properties\n" if ($verbose);
	copy($dbfile, $inputfile);
	
	
	foreach my $file (@files) {
		print "Copying $file to input\n" if ($verbose);
		copy($file, File::Spec->catfile($input, $file));
	}
	return 1;
}

sub DockerWatch { my ($showcontents, $eventsdir, $verbose) = @_ ;
	my @event_files = `find $eventsdir -maxdepth 1 -type f 2>&1`;
	chomp @event_files;
	my $retval = 0;
	foreach my $file (sort @event_files) {
		if ($verbose) {
			print basename($file);
			if ($showcontents && (-r $file)) {
				my $filesize = (stat $file)[7] || 0;
				if ($filesize > 120) {
					print "($filesize): Error - file size > 120 bytes"
				}
				else {
					my $result = `cat $file`;
					chomp $result;
					print "($filesize): ", $result;
				}
			}
			print "\n";
		}
		$retval = 1 if ($file =~ m/UP/);
		if ($file =~ m/shutdown/) {
			$retval = -1;
			last;
		}
	}
	print "\n" if ($verbose);
	return $retval;
}

sub DockerGetIP { my ($dockername, $verbose) = @_ ;
	print "Obtaining ip for $dockername\n" if ($verbose);
	my $result = `docker inspect --format '{{.NetworkSettings.IPAddress}}' $dockername`;
	chomp $result;
	return $result;
}

sub DockerGetState { my ($dockername, $verbose) = @_ ;
	my $result = `docker inspect --format '{{.State.Running}}' $dockername`;
	chomp $result;
	print "Docker: $dockername state: $result\n" if ($verbose);
	return 1 if ($result eq 'true');
	return 0 if ($result eq 'false');
	return $result;
}

sub DockerStop { my ($dockername, $verbose) = @_ ;
	my $state = DockerGetState($dockername, $verbose);
	if ($state) {
		my $result = `docker stop -t 10 $dockername 2>&1`;
	}
	my $result = `docker rm $dockername 2>&1`;
}

sub DockerStart { my ($dockername, $input, $output, $events, $verbose) = @_ ;
	print "Starting: $dockername\n" if ($verbose);
	my $command = "docker run --interactive=false --tty=false -d -v $input:/mnt/in -v $output:/mnt/out -v $events:/mnt/events --name $dockername universal-viewer /mnt/in/run.sh";
	my $result = `$command 2>&1`;
	my $status = $?;
	chomp $result;
	print "docker run result: <$result> exit status: <$status>\n" if ($verbose);
	$status = $status >> 8;
	return 1 if (! $status);
	return 0;
}

1;
