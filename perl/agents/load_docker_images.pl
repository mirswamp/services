#!/usr/bin/env perl
use strict;
use warnings;

my $force = 1;

my $base_docker_images = [
	'condor-centos-6.10-64-master-2019090501_docker.tar.xz',
	'condor-centos-7.7-64-master-2020040602_docker.tar.xz',
	'condor-debian-7.11-64-master-2019040200_docker.tar.xz',
	'condor-debian-8.11-64-master-2019040200_docker.tar.xz',
	'condor-fedora-21-64-master-2019010100_docker.tar.xz',
	'condor-fedora-22-64-master-2019010100_docker.tar.xz',
	'condor-fedora-23-64-master-2019010100_docker.tar.xz',
	'condor-fedora-24-64-master-2019010100_docker.tar.xz',
	'condor-scientific-6.10-64-master-2019090501_docker.tar.xz',
	'condor-scientific-7.7-64-master-2020040602_docker.tar.xz',
	'condor-ubuntu-12.04-64-master-2019040200_docker.tar.xz',
	'condor-ubuntu-14.04-64-master-2019010100_docker.tar.xz',
	'condor-ubuntu-16.04-64-master-2020031801_docker.tar.xz',
];

my $load_docker_images = [
	'condor-centos-6.10-64-master-2019090501_docker.tar.xz',
	'condor-centos-7.7-64-master-2020040602_docker.tar.xz',
	'condor-debian-7.11-64-master-2019040200_docker.tar.xz',
	'condor-debian-8.11-64-master-2019040200_docker.tar.xz',
	'condor-scientific-6.10-64-master-2019090501_docker.tar.xz',
	'condor-scientific-7.7-64-master-2020040602_docker.tar.xz',
];

my $loaded_images = {};
my @loaded_images = `docker images | grep condor-`;
foreach my $image (@loaded_images) {
	chomp $image;
	$image =~ s/^swamp\///;
	$image = (split ' ', $image)[0];
	$loaded_images->{$image} = 1;
}

foreach my $image_file (@$load_docker_images) {
	chomp $image_file;
	my $test_image = $image_file;
	$test_image =~ s/_docker.tar.xz$//;
	if ($force || ! exists($loaded_images->{$test_image})) {
		print "Loading: $image_file\n";
		system("docker load -i $image_file");
	}
}
print "Hello World!\n";
