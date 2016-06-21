#!/usr/bin/perl -w

use strict;

use File::stat;
use Data::Dumper;
use verbose;
use Getopt::Long;

use constant IOSTAT_CMD => '/usr/bin/iostat';

-x IOSTAT_CMD || die "Cannot execute " . IOSTAT_CMD . "\n";

my %optctl = ();

my $optResults = GetOptions(\%optctl,
	"iostat_home=s",
	"iostat_frequency=i",
	"iostat_count=i",
	"help",
	"debug!",
	"verbosity=i",
	"verbosity_dest=s",
);

unless($optResults) {
	warn "invalid options specified\n";
	usage(1);
};

my ($iostatHome, $iostatFrequency, $iostatCount, $verbosity, $verbosityDest, $help);

# help?
usage(0) if $optctl{help};

# get and verify iostat home 
$iostatHome = defined($optctl{iostat_home}) ? $optctl{iostat_home} : '';
unless ($iostatHome) {
	warn "please use -iostat_home parameter\n";
	usage(2) ;
}

-d $iostatHome || die "$iostatHome directory does not exist\n";
-r $iostatHome || die "$iostatHome is not readable\n";
-w $iostatHome || die "$iostatHome is not writable\n";
-x $iostatHome || die "$iostatHome - cannot cd\n";

# get iostat frequency
$iostatFrequency = defined($optctl{iostat_frequency}) ? $optctl{iostat_frequency} : '';
unless ($iostatFrequency) {
	warn "please use -iostat_frequency to define report frequency\n";
	usage(3);
}

# get iostat report count - this is optional
# run forever if not defined - do this my just setting $iostatCount=''
$iostatCount = defined($optctl{iostat_count}) ? $optctl{iostat_count} : '';

# get verbosity level - 0 by default
$verbosity = defined($optctl{verbosity}) ? $optctl{verbosity} : 0;
$verbosity = 3 if $optctl{debug};

# get verbosity dest - this is optional - ignore if verbosity is 0
$verbosityDest = defined($optctl{verbosity_dest}) ? $optctl{verbosity_dest} : '';
my $VBH = *STDERR;  # verbosity file handle
if ( $verbosityDest ) {
	if ( 0 == $verbosity ) {
		warn "verbosity is set to 0 - ignoring -verbosity_dest $verbosityDest\n";
	} else {
		open VBH,">$verbosityDest" || die "cannot create $verbosityDest - $!\n";
		$VBH = *VBH;
	}
}

my $v = new verbose(
	{
		VERBOSITY=>$verbosity,
		LABELS=>1,
		TIMESTAMP=>1,
		HANDLE=>$VBH,
	}
);

# example verbosity print
# my %h=(a=>1, b=>2, c=>3);
# print $VBH "doing some work with \%h\n"; $v->print(2,'reference to %h', \%h);

=head1 iostat output files

 create two types of output files
 1) straight iostat output to IOSTAT_HOME/iostat_DATE
 2) CSV output to IOSTAT_HOME/iostat_DATE.csv

 Note:  NFS stats (-n) are not being collected, as they two most important
        metrics, service time and utilization, are not available

 collect the following fot the CSV file from iostat -x
 CPU
    %user   - Show the percentage of CPU utilization that occurred while executing at the user level (application).
    %system - Show the percentage of CPU utilization that occurred while executing at the system level (kernel).
    %iowait - Show the percentage of time that the CPU or CPUs were idle during which the system had an outstanding disk I/O request.
    %steal  - Show the percentage of time spent in involuntary wait by the virtual CPU or CPUs while the hypervisor was servicing another virtual processor.  
    %idle   - Show the percentage of time that the CPU or CPUs were idle and the system did not have an outstanding disk I/O request.

 DEVICE

    rrqm/s   - The number of read requests merged per second that were queued to the device.
    wrqm/s   - The number of write requests merged per second that were queued to the device.
    r/s      - The number of read requests that were issued to the device per second.
    w/s      - The number of write requests that were issued to the device per second.
    rsec/s   - The number of sectors read from the device per second.
    wsec/s   - The number of sectors written to the device per second.
    avgrq-sz - The average size (in sectors) of the requests that were issued to the device.
    avgqu-sz - The average queue length of the requests that were issued to the device.
    await    - The average time (in milliseconds) for I/O requests issued to the device to be served. 
               This includes the time spent by the requests in queue and the time spent servicing them.
    svctm    - The average service time (in milliseconds) for I/O requests that were issued to the device. 
               Warning! Do not trust this field any more. This field will be removed in a future sysstat version.
               Note: svctim is all we have to work with in iostat as install in RedHat 5.x
    %util    - Percentage of CPU time during which I/O requests were issued to the device (bandwidth utilization for the device). 
               Device saturation occurs when this value is close to 100%.

=cut

open IOSTAT,IOSTAT_CMD . " -x $iostatFrequency $iostatCount |" || die "cannot open pipe from " . IOSTAT_CMD . " - $!\n";

my %cpuStats=();
my %deviceStats=();

# -x output
#avg-cpu:  %user   %nice %system %iowait  %steal   %idle
           #2.04    0.00    2.35    0.62    0.00   94.99

=head1 CSV line format

 device,timestamp,cpu_user,cpu_system,cpu_iowait,cpu_steal,cpu_idle,rrqm_s,wrqm_s,r_s,w_s,rsec_s,wsec_s,avgrq-sz,avgqu-sz,await,svctm,util

=cut

my %cpuHdrs = (
	user		=> 0,
	system	=> 2,
	iowait	=> 3,
	steal		=> 4,
	idle		=> 5,
);

my @cpuHdrsOrdered =  sort { $cpuHdrs{$a} <=> $cpuHdrs{$b} } keys %cpuHdrs;
#print Dumper(\@cpuHdrsOrdered);

# -x output
#Device:         rrqm/s   wrqm/s   r/s   w/s   rsec/s   wsec/s avgrq-sz avgqu-sz   await  svctm  %util
#sda               1.40     8.42  1.47  2.71    45.79    89.08    32.24     0.01    3.30   1.07   0.45

my %deviceHdrs = (
	device	=> 0,
	rrqm_s	=> 1,
	wrqm_s	=> 2,
	r_s		=> 3,
	w_s		=> 4,
	rsec_s	=> 5,
	wsec_s	=> 6,
	'avgrq-sz'	=> 7,
	'avgqu-sz'	=> 8,
	await		=> 9,
	svctm		=> 10,
	util		=> 11,
);

my @deviceHdrsOrdered =  sort { $deviceHdrs{$a} <=> $deviceHdrs{$b} } keys %deviceHdrs;

#print Dumper(\@deviceHdrsOrdered);
#exit;


my ($cpuHdrReached,$deviceHdrReached,$pastInitHdr)=(0,0,0);
my $reportCounter=0;
my %dateHash = getTimestamps();
my $prevDateStamp=$dateHash{DATESTAMP};
my $csvHdr = "device,timestamp,cpu_user,cpu_system,cpu_iowait,cpu_steal,cpu_idle,rrqm_s,wrqm_s,r_s,w_s,rsec_s,wsec_s,avgrq-sz,avgqu-sz,await,svctm,util\n";

my $iostatOutFile=qq(${iostatHome}/iostat_${dateHash{DATESTAMP}});
my $iostatCSVFile=qq(${iostatHome}/iostat_${dateHash{DATESTAMP}}.csv);

my $printCSVHdr = -w $iostatCSVFile ? 0 : 1;

open IOSTAT_OUT, ">>$iostatOutFile" || die "cannot append $iostatOutFile - $!\n";
open IOSTAT_CSV, ">>$iostatCSVFile" || die "cannot append $iostatCSVFile - $!\n";

while (<IOSTAT>) {

	chomp;
	next if /^$/;
	my $line = $_;
	$line =~ s/^\s+//;
	my $printLine = $_;

	# the first report from 'iostat  -x 1' is always cumulative
	# we do not want that report in CSV
	# take all output following the 2nd 'avg-cpu'
	# when $reportConter++ >= 1

	if ( ! $pastInitHdr ) {
		$line =~ /avg-cpu/ || next;
		next unless $reportCounter++ >= 1;
		$cpuHdrReached = $pastInitHdr = 1;

		print IOSTAT_OUT "Date: $dateHash{TIMESTAMP}\n" if $printLine =~ /avg-cpu/;
		print IOSTAT_OUT "$printLine\n";
		# do not print the CSV hdr if the file already exists
		# this can occur at intial startup when appending to current file
		print IOSTAT_CSV $csvHdr if $printCSVHdr;
		$printCSVHdr=0;

		$v->print(2,'$cpuHdrReached - pastInit:', [$cpuHdrReached]);
		$v->print(2,'$$pastInitHdr - pastInit:', [$pastInitHdr]);
		next;
	}

	$v->print(1,"chkhdr line", [$line]);


	# always print stdout
	if ($printLine =~ /avg-cpu/) {
		%dateHash = getTimestamps();

		# determine the files to write to
		# only need to check this when the day changes
		# assign only 1 time at the top of first loop through
		# further assignments occur when the new CPU header is
		# detected - otherwise the date could change in the middle
		# of the report and split the report

		if ( $prevDateStamp ne $dateHash{DATESTAMP} ) {
			$prevDateStamp = $dateHash{DATESTAMP};
			$iostatOutFile=qq(${iostatHome}/iostat_${dateHash{DATESTAMP}});
			$iostatCSVFile=qq(${iostatHome}/iostat_${dateHash{DATESTAMP}}.csv);
			open IOSTAT_OUT, ">>$iostatOutFile" || die "cannot append $iostatOutFile - $!\n";
			open IOSTAT_CSV, ">>$iostatCSVFile" || die "cannot append $iostatCSVFile - $!\n";

			# this CSV header prints on subsequent opens
			print IOSTAT_CSV $csvHdr;
		}
	}

	print IOSTAT_OUT "Date: $dateHash{TIMESTAMP}\n" if $printLine =~ /avg-cpu/;
	print IOSTAT_OUT "$printLine\n";

	if ($line =~ /^avg-cpu/) {
		$v->print(1,"sethdr - CPU", []);
		$cpuHdrReached=1;
		$deviceHdrReached=0;
		next;
	}

	if ($line =~ /^Device:/) {
		$v->print(1,"sethdr - DEVICE", []);
		$deviceHdrReached=1;
		$cpuHdrReached=0;
		next;
	}


	$v->print(3,'$cpuHdrReached:', [$cpuHdrReached]);
	$v->print(3,'$deviceHdrReached:', [$deviceHdrReached]);

	if ($cpuHdrReached) {
		$v->print(1,'cpuHdrReached - $line',[$line]);
		$v->print(1,'cpuHdrReached - %cpuHdrs',\%cpuHdrs);

		my @cpuStats=split(/\s+/,$line);
		foreach my $cpuHdr ( keys %cpuHdrs ) {
			$cpuStats{$cpuHdr} = $cpuStats[$cpuHdrs{$cpuHdr}];
			$cpuStats{$cpuHdr} = 0 unless $cpuStats{$cpuHdr};
		}

		$v->print(1,'cpuHdrReached - @cpuStats',\@cpuStats);
		$v->print(1,'cpuHdrReached - %cpuStats',\%cpuStats);

		$cpuHdrReached=0;
		$deviceHdrReached=0;

		# get timestamps at the top of CPU header to avoid
		# possibly splitting report in the middle when the
		# date changes
		#%dateHash = getTimestamps();

		next;
	}

	if ($deviceHdrReached) {
		$v->print(3,"deviceHdrReached - line", [$line]);
		$v->print(1,"devhdr line:", [$line]);
		my @deviceStats=split(/\s+/,$line);
		foreach my $deviceHdr ( keys %deviceHdrs ) {
			$deviceStats{$deviceHdr} = $deviceStats[$deviceHdrs{$deviceHdr}];
			$deviceStats{$deviceHdr} = 0 unless $deviceStats{$deviceHdr};
		}

		# output here
		#device,timestamp,cpu_user,cpu_system,cpu_iowait,cpu_steal,cpu_idle,rrqm_s,wrqm_s,r_s,w_s,rsec_s,wsec_s,avgrq-sz,avgqu-sz,await,svctm,util
		print IOSTAT_CSV join(',',
			(
				$deviceStats{device},
				$dateHash{TIMESTAMP_CSV},
				$cpuStats{user},
				$cpuStats{system},
				$cpuStats{iowait},
				$cpuStats{steal},
				$cpuStats{idle},
				$deviceStats{rrqm_s},
				$deviceStats{wrqm_s},
				$deviceStats{r_s},
				$deviceStats{w_s},
				$deviceStats{rsec_s},
				$deviceStats{wsec_s},
				$deviceStats{'avgrq-sz'},
				$deviceStats{'avgqu-sz'},
				$deviceStats{await},
				$deviceStats{svctm},
				$deviceStats{util},
			)
		), "\n";

		$v->print(2,'%deviceStats',\%deviceStats);
	}

}

sub usage {

	my $exitVal = shift;
	use File::Basename;
	my $basename = basename($0);
	print qq{
$basename

usage: $basename - gather and save iostats 

  $basename -iostat_home \$HOME/iostat -iostat_frequency 5


-iostat_home        directory where iostat files are saved
-iostat_frequency   iostat interval in seconds
-iostat_count       integer for number of iostat reports - omit to run indefinitely
-verbosity          level of verbosity 0-3
-verbosity_dest     verbose goes to STDERR by default
                    provide a file name to redirect
-help               show usage

examples here:

  $basename -iostat_home \$HOME/iostat -iostat_frequency 5 -verbosity 2 -verbosity_dest iostat_verbose.txt

};

	exit eval { defined($exitVal) ? $exitVal : 0 };
}

{

my $setTimestamp;

sub getTimestamps {

	# comment out Test::MockTime when not testing
	# as it will not be available on production systems
	#use Test::MockTime qw(:all);

=head1 getTimestamps

 my %dateHash= getTimestamps();

 print qq{
    timestamp: $dateHash{TIMESTAMP}
    timestamp: $dateHash{TIMESTAMP_CSV}
    datestamp: $dateHash{DATESTAMP}
	 monthday : $dateHash{MONTHDAY}
 };

 TIMESTAMP_CSV is formatted "yyyy-mm-dd hh24:mi:ss" for MS Excel

=cut

	my $dateHash={};

	# use Test::MockTime to set the date for testing
	#set_absolute_time('2012-01-01 07:59:46 GMT','%Y-%m-%d% %H:%M:%S %Z') unless $setTimestamp++;

	my ($sec,$min,$hour,$mday,$mon,$year) = (localtime(time))[0..5];

	$year += 1900;
	$mon += 1;

	$mday=substr('0'.$mday,-2,2);
	$mon=substr('0'.$mon,-2,2);
	$sec=substr('0'.$sec,-2,2);
	$min=substr('0'.$min,-2,2);
	$hour=substr('0'.$hour,-2,2);

	my ($datestamp, $timestamp, $timestampCSV);

	$datestamp=qq(${year}-${mon}-${mday});
	$timestamp=qq(${datestamp}_${hour}-${min}-${sec});
	$timestampCSV=qq(${datestamp} ${hour}:${min}:${sec});

	#print "sub datastamp: $datestamp\n";
	#print "sub timestamp: $timestamp\n";

	$dateHash->{DATESTAMP} = $datestamp;
	$dateHash->{TIMESTAMP} = $timestamp;
	$dateHash->{TIMESTAMP_CSV} = $timestampCSV;
	$dateHash->{MONTHDAY}  = $mday;

	%{$dateHash};

}

}
