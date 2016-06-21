#!/bin/sh


# start the iostat archiver if it is not running

LOCKFILE=/tmp/iostat_running_${HOSTNAME}.lock

# -s	means files exists and non-zero length
if [ -s "$LOCKFILE" ]; then
# the "-0" does not kill the process but return "0" if the process is running,
# or returns a not 0 if the process is not running
	if ! kill -0 $(cat $LOCKFILE) 2> /dev/null; then
		echo "[WARNING]\n\tRemoving stale lockfile $LOCKFILE"
	else
		echo "[ERROR]\n\tPID $(cat $LOCKFILE) already running $LOCKFILE"
		exit 2
	fi
else
	echo "[OK]"
fi

# $$	is the pid of the shell
echo $$ > $LOCKFILE

~/bin/iostat_archive.pl -iostat_home $HOME/iostat -iostat_frequency 60
