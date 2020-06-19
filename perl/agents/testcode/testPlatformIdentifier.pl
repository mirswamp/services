#!/usr/bin/env perl
use strict;
use warnings;
use Log::Log4perl qw(:easy);
use lib '../lib';
use SWAMP::vmu_Support qw(
	platformIdentifierToImage
	imageToPlatformIdentifier
);

my $verbose = 0;

sub show_bog { my ($title, $bogref) = @_ ;
	print "$title\n" if ($title);
	print '  platform_identifier: ', $bogref->{'platform_identifier'}, "\n";
	print '  platform_type: ', $bogref->{'platform_type'}, "\n";
	print '  platform_image: ', $bogref->{'platform_image'}, "\n";
}

Log::Log4perl->easy_init($INFO);
my $bogref = {};

my $lines = [];
if (! -t) {
	$lines = [(<STDIN>)];
}
elsif ($ARGV[0]) {
	if ($ARGV[1]) {
		$lines = [$ARGV[0] . ',' . $ARGV[1]];
	}
	else {
		$lines = [$ARGV[0]];
	}
}
foreach my $line (@$lines) {
	print $line;
	chomp $line;
	my ($platform_identifier, $platform_type) = split ',', $line;
	$bogref->{'platform_identifier'} = $platform_identifier;
	$bogref->{'platform_type'} = $platform_type;
	$bogref->{'platform_image'} = '';
	show_bog('Before:', $bogref) if ($verbose);
	my $platform_image = platformIdentifierToImage($bogref);
	$bogref->{'platform_image'} = $platform_image;
	$bogref->{'platform_identifier'} = imageToPlatformIdentifier($platform_image);
	my $title = 'After:' if ($verbose);
	show_bog($title, $bogref);
}
