#!/bin/sh

errfile=iostat_sum.err

# any errors will likely be due to trying to combine
# partial files.
# files that do not have the same timestamps down to the
# minute will cause errors - this may be because the iostat
# collector was not running all day for some reason

> $errfile

for timestamp in $(ls  mapped_files/fling8/*| cut -d_ -f 4|cut -f1 -d\.)
do
	echo $timestamp
	glint8_file=mapped_files/glint8/iostat_mapped_${timestamp}.csv
	fling8_file=mapped_files/fling8/iostat_mapped_${timestamp}.csv
	combined_file=combined/iostat_combined_${timestamp}.csv

	[ -r "$glint8_file" ] || {
		echo cannot open $glint8_file
		exit 1
	}

	[ -r "$fling8_file" ] || {
		echo cannot open $fling8_file
		exit 2
	}


	echo "#############################################" >> $errfile
	echo "# file: $fling8_file" >> $errfile
	echo "# file: $glint8_file">> $errfile
	echo "#############################################" >> $errfile

	./iostat_sum.pl -file $fling8_file -file $glint8_file > $combined_file 2>>$errfile


done

