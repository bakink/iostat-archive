#!/bin/sh

export PATH=~/local/bin:$PATH

cd ~/iostat

for f in iostat_201*.csv
do
	mappedfile=$(echo $f | sed -e s/iostat/iostat_mapped/ )
	[ -f "$mappedfile" ] || {
		echo  "working: iostat_mapped.pl $f > $mappedfile"
		iostat_mapped.pl $f > $mappedfile
	}
done

