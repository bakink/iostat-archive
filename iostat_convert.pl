#!/usr/bin/perl

# Jared Still
# still@pythian.com

=head1 iostat_convert.pl

Convert iostat files to XLS, adding charts for util, r/sec and w/sec


=cut


use warnings;
use strict;
use Getopt::Long;
use Data::Dumper;
use Excel::Writer::XLSX;

my $debug = 0;

my %optctl = ();
my @columnsToChart=();

my $optResult = Getopt::Long::GetOptions(
	\%optctl, 
	"csv_file=s",
	"spreadsheet_file=s",
	"col=s" => \@columnsToChart, 
	"sysdba!",
	"sysoper!",
	"z","h","help");

unless ($optResult) {
	warn "please provide options\n";
	Usage(3);
}



if (
	$optctl{h} 
	|| $optctl{z}
	|| $optctl{help}
) {
	Usage(0);
}

my $i=0;
my %chartableColumns = map { $_ => $i++ } qw(cpu_user cpu_system cpu_iowait cpu_steal cpu_idle rrqm_s wrqm_s r_s w_s rsec_s wsec_s avgrq-sz avgqu-sz await svctm util);

# the default iostat numbers of interest:
# r_s + w_s = IOPS
# util = how many resources going to IO

my @chartCols;
# headings expected in first line of file
my @hdrs = qw(device timestamp cpu_user cpu_system cpu_iowait cpu_steal cpu_idle rrqm_s wrqm_s r_s w_s rsec_s wsec_s avgrq-sz avgqu-sz await svctm util);

if (@columnsToChart){

	foreach my $colname (@columnsToChart) {
		unless (exists $chartableColumns{$colname}) {
			warn "invalid column $colname specified\n";
			Usage(4);
		}
		push @chartCols, indexArray($colname,@hdrs);
	}	

} else { # defaults

	foreach my $col ( qw{util await r_s w_s} ) {
		push @chartCols, indexArray($col,@hdrs);
	}

}

#print '@chartCols - ', Dumper(\@chartCols);
#print '@columnsToChart - ', Dumper(\@columnsToChart);
#exit;


my $xlFile = defined($optctl{spreadsheet_file}) ? $optctl{spreadsheet_file} : 'exceltest.xls';

my $csvFile;
if ( defined($optctl{csv_file}) ) {
	$csvFile = $optctl{csv_file};
	unless (-r $csvFile) {
		warn "cannot open $csvFile = $!\n";
		Usage(2);
	}
} else {
	warn "must include -csv_file on command line\n";
	Usage(1);
}

my $currentDate = localtime;

my $workbook;
my %worksheets = ();

my %fonts = (
	fixed			=> 'Courier New',
	fixed_bold	=> 'Courier New',
	text			=> 'Arial',
	text_bold	=> 'Arial',
);

my %fontSizes = (
	fixed			=> 10,
	fixed_bold	=> 10,
	text			=> 10,
	text_bold	=> 10,
);

my $maxColWidth = 50;
my $counter = 0;
my $interval = 100;

# create workbook
#$workbook = Spreadsheet::WriteExcel->new(${xlFile});
$workbook = Excel::Writer::XLSX->new(${xlFile});

die "Problems creating new Excel file ${xlFile}: $!\n" unless defined $workbook;

# create formats
# create the page


my $textFormat = $workbook->add_format();
my $numberFormat = $workbook->add_format();
$numberFormat->set_num_format('0.000');


open IOSTAT, "<$csvFile" || die "cannot open $csvFile - $!\n";

my %dataLineCount = ();
my %data=();

# assuming that this csv file has devices that
# have been mapped to names - 'Catalog Table','Archive Logs'...
my %devicesToChart = (
	'Archive Logs' => 1,
	'Catalog Index' => 1,
	'Catalog Table' => 1,
	'Cluster Registry' => 1,
	'Temp Table' => 1,
	'Voting Disk' => 1,
	'Log Exports' => 1,
	'Report Index' => 1,
	'Report Table' => 1,
);


while (<IOSTAT>){

	chomp;
	my $line=$_;

	my @ioData=();
	my ($device) = split(/,/,$line);

	next unless exists $devicesToChart{$device};

	#print "line: $. - $line\n";
	if ( $. > 1 ) {
		my @ioText = (split(/,/),$line)[0,1];
		my @ioNumbers = (split(/,/,$line))[2..17];
		s{^\s+|\s+$}{}g foreach @ioNumbers;

		@ioData = @ioText;
		push @ioData,@ioNumbers;
	} #else {
		#@ioData = split(/,/,$line);
		#@hdrs = @ioData;
		#next;
	#}

	$data{$device}{$dataLineCount{$device}++} = \@ioData;

}

# create worksheets

foreach my $device ( sort keys %dataLineCount ) {
	$worksheets{$device} = $workbook->add_worksheet($device);
	$worksheets{$device}->set_column(2,20,undef,$numberFormat);
}

foreach my $device ( sort keys %dataLineCount ) {
	my $deviceData = $data{$device};
	$worksheets{$device}->write_row(0,0,\@hdrs);
	my $linecount=1;
	foreach my $timestamp ( sort {$a<=>$b} keys %{$deviceData} ) {
		$worksheets{$device}->write_row($linecount++,0,\@{$deviceData->{$timestamp}});
	}
}


my @alpha = map (chr(),(65..90)); # A-Z

foreach my $device ( sort keys %dataLineCount ) {

	# freeze pane at header
	$worksheets{$device}->freeze_panes(1,1);

	my $chartNum = 0;
	foreach my $hdrElement (@chartCols) {
		my $chart = $workbook->add_chart( type => 'line', name => "$device" . '-' . $hdrs[$hdrElement], embedded => 1 );
		# each chart consumes about 16 rows
		$worksheets{$device}->insert_chart('A' . (($chartNum * 16) + 1), $chart);

		# add data to the chart
		my $categories = "='$device'" . '!$B$2:$B$' . $dataLineCount{$device};
		my $values = "='$device'" . '!$' . $alpha[$hdrElement] . '$2:$' . $alpha[$hdrElement] . '$' . $dataLineCount{$device};

		$chart->add_series(
			name => $hdrs[$hdrElement],
			categories => $categories,
			values => $values
		);

		$chartNum++;
	}
}



sub Usage {
	my $exitval = shift;
	use File::Basename;
	my $basename = basename($0);

	print qq{

usage: $basename  convert iostat CSV to XLS with charts

-csvfile            Name of CSV file containing iostat data
-spreadsheet_file   Name of spreadsheet file to create. Defaults to roles.xls
-col                Name of column to chart
                    Multiple columns may be charted:
                    -col col1 -col col2 ...

                    Possible chart columns:
                    cpu_user cpu_system cpu_iowait cpu_steal cpu_idle rrqm_s 
                    wrqm_s r_s w_s rsec_s wsec_s avgrq-sz avgqu-sz await svctm util

                    Default chart columns:
                    util await r_s w_s

};

	exit $exitval;

}

# find the element # of a text value
# call with indexArray('text',@array);

sub indexArray {
	1 while $_[0] ne pop;
	$#_;
}


