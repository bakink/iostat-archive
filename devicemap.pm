#!/usr/bin/perl -w


package devicemap;

use strict;
use Data::Dumper;
use File::Basename;
use Cwd;
use Carp;

sub new {

	my $pkg = shift;
	my $class = ref($pkg) || $pkg;

	my $deviceMap;
	my $devices;

	return bless my $self = { 
		deviceMap => $deviceMap, 
		devices => $devices 
	} => ( ref $class || $class );

}

sub processMap {

	my $self = shift;

=head1 Device Hash - map raw devices to a hashed map and list of devices

 Key will be the raw device - this is what is seenin v$asm_disk

    1  select path from v$asm_disk
    2* order by 1
  SQL> /

  PATH
  --------------------------------------------------------------------------------
  /dev/raw/raw3
  /dev/raw/raw4
  /dev/raw/raw5
  /dev/raw/raw6
  /dev/raw/raw7
  /dev/raw/raw8
  /dev/raw/raw9

  %devices = (
    '/dev/raw/raw3' => {
      scsi_link => '/dev/iscsi/0/part1',
      scsi_dev => '/dev/sdj1',
      description => 'Catalog Table'
    },
  ...
  )


 example usage:

  use lib '.';
  use devicemap;

  my $deviceParser = new devicemap();

  $deviceParser->processMap;

  my @devices = @{$deviceParser->{devices}};
  my %deviceMap = %{$deviceParser->{deviceMap}};

  print Dumper(\@devices);
  print Dumper(\%deviceMap);

  # how to walk the hash
  foreach my $rawDev ( sort keys %deviceMap ) {
    printf "%-15s ->   %-15s  %-30s\n",
    $rawDev,
    $deviceMap{$rawDev}->{scsi_dev},
    $deviceMap{$rawDev}->{description};
  }

=cut

	my %deviceMap=();

	open RC, '</etc/rc.d/rc.local' or die "cannot open rc.local - $!\n";

	while (<RC>){
		next unless /^raw/;
		#print;
		chomp;
		my ($dummy1, $rawDevice, $linkName, $dummy2, @description) = split(/\s+/);
		my $description=join(' ',@description);
	
		# the $linkName should be a symlink
		my $relScsiDev = readlink($linkName);
		die "$linkName is not a symlink\n" unless $relScsiDev;
	
		# get absolute path of scsi device
		my $linkDir = dirname($linkName);
		#print "DIR: $linkDir\n";

		my $symPath="${linkDir}/$relScsiDev";
		#print "SYMPATH: $symPath\n";

		my $scsiDev = Cwd::abs_path($symPath);

		#print "SCSI DEV: $scsiDev\n";

		$deviceMap{$rawDevice} = {
			scsi_link => $linkName,
			scsi_dev => $scsiDev,
			description => $description,
		};	

	}

	close RC;

	#print Dumper(\%deviceMap);

	my @scsiDevs = map ($deviceMap{$_}->{scsi_dev} , keys %deviceMap);
	#print Dumper(\@scsiDevs);


	$self->{deviceMap} = \%deviceMap;
	$self->{devices} = \@scsiDevs;
}

1;


