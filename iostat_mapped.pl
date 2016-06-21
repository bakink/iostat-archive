#!/usr/bin/perl -w


=head1 iostat_mapped.pl

 use with iostat when raw is used for disks
 such as with oracle and ASM

 drive names are replaced with what they are used for in oracle

 this works only because the SysAdmins thoughtfully commented 
 the /etc/rc.d/rc.local file

 otherwise we would just show the raw name, which would still be
 better than the std device name, as the raw name is what appears
 in v$asm_disk

 see drivemap.pm for more details

 example:

 iostat 1 2 | ./iostat_mapped.pl

  oracle@rabble8.arc> iostat 1 2 | ./iostat_mapped.pl
  Linux 2.6.18-194.3.1.el5 (rabble8.arc)  12/22/11

  avg-cpu:  %user   %nice %system %iowait  %steal   %idle
             2.10    0.00    0.44    1.35    0.00   96.10

  Device:            tps   Blk_read/s   Blk_wrtn/s   Blk_read   Blk_wrtn
  sda               8.45         0.97       202.36    3719636  772995646
  sda1              0.00         0.00         0.00       6427         22
  sda2              8.45         0.97       202.36    3712904  772995624
  dm-0             25.36         0.97       202.36    3711722  772994928
  dm-1              0.00         0.00         0.00        896        696
  sdb               1.60        50.17        45.25  191644252  172841144
  Temp Table        1.60        50.17        45.25  191643838  172841144
  sdc               4.85      1359.76        38.64 5194194476  147585432
  Report Index      4.85      1359.75        38.64 5194194062  147585432
  sdd               2.93         2.08         0.96    7944584    3685394
  Voting Disk       2.93         2.08         0.96    7944169    3685394
  sde              14.63      1978.33       176.56 7557111852  674464312
  Report Table     14.63      1978.33       176.56 7557111442  674464312
  sdf               0.58         1.48         3.81    5671034   14566720
  Cluster Registry  0.58         1.48         3.81    5670621   14566720
  sdg               4.51      1575.51        14.22 6018369988   54317072
  Catalog Index     4.51      1575.51        14.22 6018369574   54317072
  sdh              17.12      1493.01      1268.00 5703238446 4843698006
  Archive Logs     17.12      1493.01      1268.00 5703238036 4843698006
  sdi               2.63       224.63       264.77  858070836 1011421672
  Log Exports       2.63       224.63       264.77  858070426 1011421672
  sdj              28.17      3324.48       301.48 12699327868 1151654792
  Catalog Table    28.17      3324.48       301.48 12699327458 1151654792




=cut

use strict;
use Data::Dumper;
use File::Basename;

use lib '/home/oracle/local/lib';

use devicemap;

my $debug=0;

my $deviceParser = new devicemap();

$deviceParser->processMap;

my @devices = @{$deviceParser->{devices}};
my %deviceMap = %{$deviceParser->{deviceMap}};

print "\@devices:\n", Dumper(\@devices) if $debug;
print "\%deviceMap:\n", Dumper(\%deviceMap) if $debug;

# walk the hash
#foreach my $rawDev ( sort keys %deviceMap ) {
	#printf "%-15s ->   %-15s  %-30s\n",
		#$rawDev,
		#$deviceMap{$rawDev}->{scsi_dev},
		#$deviceMap{$rawDev}->{description};
#}

# get basename for device - use to with iostat
my %deviceBase = map { basename($_) => $_} @devices;

# reverse map scsi dev to raw for lookup later
my %rawMap = map { basename($deviceMap{$_}->{scsi_dev}) => $_ } keys %deviceMap;
print "\%rawMap:\n", Dumper(\%rawMap) if $debug;
my $deviceGrepStr = join('|',keys %deviceBase);

print "\%deviceBase:\n", Dumper(\%deviceBase) if $debug;

my $firstLine=1;
my $splitStr='\s+';
my $fileType='iostat';

# get the iostat pipeline
while(<>) {
	chomp;
	my $line=$_;

	# look for comma in output to determine how to split line
	# commas do not appear in iostat output
	# commas do appear in CSV files
	if ($firstLine) {
		$firstLine = 0;
		if ($line =~ /,/) {
			$splitStr = ',' if $line =~ /,/;
			$fileType='CSV';
		}
	}
	
	my $matched = grep(/^$deviceGrepStr/,$line);
	#print "GETDEV: $getDev\n" if $getDev;
	if ($matched) {
		my ($baseDevice) = split(/$splitStr/,$line);
		#print "GETDEV: $baseDevice\n";
		#print "RAW MAP:  $rawMap{$baseDevice}\n";
		my $description = $deviceMap{$rawMap{$baseDevice}}->{description};
		if ( $fileType eq 'iostat' ) {
			#print "DESC:  $description\n";
			my ($descLen, $baseDeviceNameLen, $pad);
			$descLen = length($description);
			$baseDeviceNameLen = length($baseDevice);
			$pad = '';
			$pad = substr(' ' x 20,0,$descLen - $baseDeviceNameLen) if $descLen > $baseDeviceNameLen;
			$line =~ s/^$baseDevice$pad/$description/;
		} else { # CSV
			my @ary=split(/$splitStr/,$line);
			$ary[0] = $description;
			$line = join(',',@ary);
		}		
	}
	print "$line\n";
}


