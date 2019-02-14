#!/usr/bin/env perl
use strict;
use warnings;
use Log::Log4perl qw(:easy);
use lib '../lib';
use SWAMP::vmu_Support qw(
	createQcow2Disks
	patchDeltaQcow2ForInit
);

Log::Log4perl->easy_init($ALL);
my $log = Log::Log4perl->get_logger(q{});
my $bogref = {
	'platform'	=> 'ubuntu-16.04-64',
};
my $vmhostname = 'tjabhostname';
my $execrunuid = 'tjabexecrunuid';
my $inputfolder = 'qcow_input';
my $outputfolder = 'qcow_output';
mkdir $inputfolder if (! -d $inputfolder);
mkdir $outputfolder if (! -d $outputfolder);
my $imagename = createQcow2Disks($bogref, $inputfolder, $outputfolder);
$imagename = 'condor-ubuntu-16.04-64-master-2018110101.qcow2';
my $yearstamp = ($imagename =~ m/\-(\d{4})\d{6}\.qcow2$/) ? $1 : 0;
if (! $imagename) {
    $log->error("createQcow2Disks failed for: $execrunuid");
    exit;
}
if (! patchDeltaQcow2ForInit($imagename, $vmhostname)) {
    $log->error("patchDeltaQcow2ForInit failed for: $execrunuid $imagename $vmhostname");
	exit;
}
print "Hello World!\n";
