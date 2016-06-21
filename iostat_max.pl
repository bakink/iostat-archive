#!/usr/bin/perl -w

# iostat_max.pl
# find the max values for stats from iostat archives
# reads STDIN

use strict;
use Data::Dumper;

use constant MAXLINES => 100;  # for testing
use constant DEBUG => 0; 

my (@hdrsList,%hdrsNameMap,%hdrsValMap,%maxVals);
my ($recsep) = (',');

while(<>) {

	chomp;

	# hdr on the first line
	if ($. == 1) {
		@hdrsList = split(/$recsep/);

		my $i=0;
		%hdrsNameMap = map { $_ => $i++ } @hdrsList;
		$i=0;
		%hdrsValMap = map { $i++ => $_ } @hdrsList;
		print join(' - ',@hdrsList),"\n" if DEBUG;
		print Dumper(\%hdrsNameMap) if DEBUG;
		print Dumper(\%hdrsValMap) if DEBUG;
		next;
	}

	last if $. > MAXLINES && DEBUG;

	if (DEBUG){print;print"\n"}

	my @metrics = split(/$recsep/);
	my $device=$metrics[0];

	# maxVals is a hash of device=>{metric1 => val, metric2 => val,...}
	#$maxVals{
		#$hdrsList[$hdrsMap{device}] => {
		#}
	#}

	my %metrics=();
	# start with 1 as 0 is device
	foreach my $i ( 1..$#hdrsList ) {
		$metrics{$hdrsValMap{$i}} = $metrics[$i];
	}
	print Dumper(\%metrics) if DEBUG;

	# skip timestamp 
	foreach my $key ( keys %metrics ) {
		next if $key eq 'timestamp';
		if ( defined($maxVals{$device}->{$key} )) {
			$maxVals{$device}->{$key} = 
				$metrics{$key} > $maxVals{$device}->{$key} 
				? $metrics{$key}
				: $maxVals{$device}->{$key};
		} else {
			$maxVals{$device}->{$key} = $metrics{$key};
		}
	}

}


print Dumper(\%maxVals) if DEBUG;

# output max values

foreach my $device ( sort keys %maxVals ) {
	print "DEVICE: $device\n";
	my %metrics = %{$maxVals{$device}};
	print Dumper(\%metrics) if DEBUG;
	foreach my $idx ( 1..$#hdrsList) {
		next if $hdrsList[$idx] eq 'timestamp';
		printf "\t%-13s %10.2f\n", $hdrsList[$idx].':',$metrics{$hdrsList[$idx]};
	}
}


