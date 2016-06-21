#!/usr/bin/perl -w

use strict;
use Data::Dumper;
use verbose;
use Getopt::Long;

my %optctl = ();
my @iostatFiles=();

my $optReturn = GetOptions(\%optctl,
	"file=s" => \@iostatFiles,
	"verbose=i",
	"help",
	"debug!"
);

usage(2) unless $optReturn;

my $numFiles=0;
foreach my $file (@iostatFiles) {
	if ( -f $file ) {$numFiles++}
	else {die "cannot read file $file - $!\n"}
}

usage(1) if $numFiles < 2;

my $verbosity = defined($optctl{verbose}) ? $optctl{verbose} : 0;

my $v = verbose->new(
{
	VERBOSITY=>$verbosity,
	LABELS=>1,
	TIMESTAMP=>1,
	HANDLE=>*STDOUT
}
																								          );

=head1 %devices()

 this is a hash of devices to accumulate data for
 these devices have been mapped to usage name - eg sda1 = 'Cluster Data'

=cut

my %devices = (
	'Archive Logs'		=> 1,
	'Catalog Index'	=> 1,
	'Catalog Table'	=> 1,
	'Cluster Registry'=> 1,
	'Log Exports'		=> 1,
	'Report Index'		=> 1,
	'Report Table'		=> 1,
	'Temp Table'		=> 1,
	'Voting Disk'		=> 1,
);


=head1 %iostatActions()

 setup a hash to determine if a value should be averaged, added, or nothing

 possible values

 add: add the values
 avg: avg the values
 lbl: this is a lable - use as is

 the keys to this hash are found in the header line of the iostat file

 my %iostatActions = (
	 device     => 'lbl',
	 timestamp  => 'lbl',
	 cpu_use    => 'avg',
    ...

=cut

my %iostatActions = (
	device			=> 'lbl',
	timestamp		=> 'lbl',
	cpu_user			=> 'avg',
	cpu_system		=> 'avg',
	cpu_iowait		=> 'avg',
	cpu_steal		=> 'avg',
	cpu_idle			=> 'avg',
	rrqm_s			=> 'add',
	wrqm_s			=> 'add',
	r_s				=> 'add',
	w_s				=> 'add',
	rsec_s			=> 'add',
	wsec_s			=> 'add',
	'avgrq-sz'		=> 'avg',
	'avgqu-sz'		=> 'avg',
	await				=> 'avg',
	svctm				=> 'avg',
	util				=> 'avg',
);


=head1 %deviceStats()

 this hash will accumulate stats per device

 %deviceStats = (
   device1 => {
	  timestamp => {
        stat1 => value,
        stat2 => value,
        ...
     }
	},
   device2 => {
	  timestamp => {
        stat1 => value,
        stat2 => value,
        ...
     }
	},
 )

=cut

my %deviceStats=();
# %divisors is used when averages are calculated
my %divisors=();

my @iostatValMap = qw(cpu_user cpu_system cpu_iowait cpu_steal cpu_idle rrqm_s wrqm_s r_s w_s rsec_s wsec_s avgrq-sz avgqu-sz await svctm util);

# operate on the first file, then get the others in a loop
# as the first file will not require calculating values
my $file = shift @iostatFiles;

# track the timestamps in the initial file load
# this is use later to output in order
my @timestamps=();
my %timestamps=();

$v->print (1,"iostat file:", [$file]);
open IOSTAT, "$file" || die "cannot open $file - $!\n";
while (<IOSTAT>) {
	# skip header line
	next if $. == 1;
	chomp;

	# get device, timestamp and values
	# skip if device is not one we are looking for
	my ($device,$timestamp,@ioValues) = split(/,/);
	next unless exists $devices{$device};

	#print Dumper(\@ioValues);

	# ignore the seconds portion of timestamp
	# iostat is being taken once per minute, so to combine
	# them we need only minute granularity
	$timestamp =~ s/^(.+)(:[\d]{2})$/$1/;

	# only push once
	push @timestamps,$timestamp if $timestamps{$timestamp}++ < 1;
	$v->print(2,"Timestamp:", [$timestamp]);
	
	# map the values to headers 
	my $i=0;
	$deviceStats{$device}->{$timestamp} = { map { $iostatValMap[$i++] => $_ } @ioValues };
	$i=0;
	$divisors{$device}->{$timestamp} = { map { $iostatValMap[$i++] => 1 } @ioValues };

}

#print Dumper(\@timestamps);
#print Dumper(\%divisors);
#print Dumper(\%deviceStats);

# now process the remaining files

#print Dumper(\@iostatFiles);
#exit;

foreach my $file ( @iostatFiles ) {
	$v->print (1,"iostat file:", [$file]);
	open IOSTAT, "$file" || die "cannot open $file - $!\n";
	while (<IOSTAT>) {
		# skip header line
		next if $. == 1;
		chomp;

		# get device, timestamp and values
		# skip if device is not one we are looking for
		my ($device,$timestamp,@ioValues) = split(/,/);
		next unless exists $devices{$device};

		#print Dumper(\@ioValues);

		# ignore the seconds portion of timestamp
		# iostat is being taken once per minute, so to combine
		# them we need only minute granularity
		$timestamp =~ s/^(.+)(:[\d]{2})$/$1/;
		$v->print(2,"Timestamp:", [$timestamp]);
	
		my ($i,$i2)=(0,0);
		#$deviceStats{$device}->{$timestamp} = { map { $iostatValMap[$i++] => $_ } @ioValues };
		$deviceStats{$device}->{$timestamp} = { 
			map { 
				$iostatValMap[$i++] => 
				$_ + $deviceStats{$device}->{$timestamp}{$iostatValMap[$i2++]} 
			} @ioValues 
		};

		($i,$i2)=(0,0);
		$divisors{$device}->{$timestamp} = { 
			map { 
				$iostatValMap[$i++] => 
				$divisors{$device}->{$timestamp}{$iostatValMap[$i2++]} + 1 
			} @ioValues 
		};
	}
}

#print Dumper(\%deviceStats);

# now make adjustments to values that should be averages

foreach my $device ( keys %devices ) {
	#print "Device: $device\n";
	foreach my $timestamp ( keys %{$deviceStats{$device}} ) {
		#print "\tTimestamp: $timestamp\n";
		my $stats = $deviceStats{$device}->{$timestamp};
		foreach my $stat ( keys %{$stats} ) {
			#print "stat: $stat\n";
			next unless $iostatActions{$stat} eq 'avg';
			#print "Calculating avg for $stat\n";
			$stats->{$stat} /= $divisors{$device}->{$timestamp}{$stat};
		}
	}
}

#print Dumper(\%divisors);
#print Dumper(\%deviceStats);


# now write the output
# output will be in device, timestamp order
# values will be ordered the same as in the original report
# use order of values in @iostatValMap 

#print the header
print "device,timestamp,cpu_user,cpu_system,cpu_iowait,cpu_steal,cpu_idle,rrqm_s,wrqm_s,r_s,w_s,rsec_s,wsec_s,avgrq-sz,avgqu-sz,await,svctm,util\n";

# there will be errors if @timestamps does not have the
# same timestamps as found in the files, though that should
# not happen

foreach my $device ( keys %devices ) {
	foreach my $timestamp ( @timestamps ) {
		print "$device,$timestamp";
		my $stats = $deviceStats{$device}->{$timestamp};
		foreach my $stat ( @iostatValMap ) {
			printf ",%-6.3f",$stats->{$stat};
		}
		print "\n";
	}
}

sub usage {

	my $exitVal = shift;
	use File::Basename;
	my $basename = basename($0);
	print qq{
$basename

usage: $basename - combine iostat archives 

this will only work for iostat archive files with matching device names
at least two files must be specified or the script will exit with error

	$basename -file file1 -file file2 -file file3 ...

..

examples here:

	$basename -file server1/iostat_2012-01-12.csv -file server2/iostat_2012-01-12.csv
};

	exit eval { defined($exitVal) ? $exitVal : 0 };
}


