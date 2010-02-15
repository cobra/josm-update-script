#!/bin/bash
#
# Copyright (C) 2009 "Cobra" from <http://www.openstreetmap.org>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#
# homepage and wiki for this script: http://github.com/cobra/josm-update-script http://wiki.github.com/cobra/josm-update-script
#
# Startup-script for josm:
#   - gets always the newest version of josm-latest.jar or josm-tested.jar (configurable)
#   - backs up old versions (useful when the new one doesn't work properly)
#   - is able to launch an old version of josm (via josm -r [revision])
#   - passes all arguments to josm - you can pass files to open with josm, e.g. 'josm trace0*.gpx trace10.gpx'
#   - sets environment variables, passes correct parameters to java and use alsa instead of oss
#   - writes a log to ~/.josm/josm.log
#
# configuration (in file josm.conf):
#   - change archive-directory if desired
#   - select josm variant(latest/tested)
#   - adjust number of desired backups
#   - do you use compiz? Then uncomment that line.
#   - adjust amount of RAM available to josm
#   - if you want to change or add some parameters for java look at the last line
#
# usage:
#   josm.sh [-hloqu] [-r revision] [-v version] [FILE(S)]
#
#   Options:
#   -h  displays a help text
#   -l	lists all saved versions of josm and exits
#   -o  work offline, doesn't try to update
#   -q  suppresses the output of josm's stdout and stderr but still writes the log
#   -r	starts this revision of josm, revision is either an absolute number or "last" for next to last saved version
#   -u  update without starting josm
#   -v  overrides the configured version of josm (can be either "latest" or "tested")
#

# include configuration file
. josm.conf
usage="Usage: `basename $0` [-h] [-l] [-o] [-q] [-r revision] [-u] [-v version] [files]"
# global variables
rev_tested=0
rev_tested=0
rev_nightly=0
rev_local=0
# flags
override_rev=0
update=0
bequiet=0
offline=0


# if $dir doesn't exist, create it (initial setup):
if [ -d $dir ]; then :
  else mkdir -p $dir; echo "directory $dir does not exist; creating it..."
fi

cd $dir

checkrev() {
	# parameter: revision to check
	# returns: 0 if revision is present
	if ls josm*.jar | grep $1 >/dev/null; then
		return 0
	else return 1
	fi
}

getbuildrev() {
	# reads revisions of josm
	# parameter: version to check, either "latest" or "tested"
	# returns: revision of given version, 0 when connection timed out
	if [ $offline -eq 0 ]; then
		wget -qO /tmp/josm-version --tries=$retries --timeout=$timeout http://josm.openstreetmap.de/version
		if [ $? -ne 0 ]; then
			offline=1
			echo "could not get version from server, working in offline mode" >&2
			return 1
		fi
		rev_latest=`grep latest /tmp/josm-version | awk '{print $2}'`
		rev_tested=`grep tested /tmp/josm-version | awk '{print $2}'`
		rev_nightly=`grep $1 /tmp/josm-version | awk '{print $2}'`
		return 0
	else return 1
	fi
}

getlocalrev() {
	# parameter: none
	# returns: the newest local revision
	if ls josm-*.jar > /dev/null; then
		rev_local=`ls josm*.jar | cut -d '-' -f 2 | cut -d '.' -f 1 | tail -n 1`
		return 0
	else return 1
	fi
}

update() {
	# parameter: $1: version to update, either "latest" or "tested"; $2: revision
	# returns: 0 for successful update, 1 for failed update
	if [ $offline -eq 0 ]; then
		echo "downloading josm-$version, revision $2..."
		wget -O josm-$2.jar -N http://josm.openstreetmap.de/download/josm-$1.jar
		return $?
	else return 1
	fi
}

# parse arguments
set -- `getopt "hloqr:uv:" "$@"` || {
	echo $usage 1>&2
	exit 1
}

while :
	do
		case "$1" in
			-h) echo $usage; exit 0 ;;
			-l) echo "available revisions of josm: "; ls josm*.jar | cut -d '-' -f 2 | cut -d '.' -f 1 ; exit 0 ;;
			-o) offline=1 ;;
			-q) bequiet=1 ;;
			-r) shift; override_rev=1; rev="$1" ;;
			-u) update=1 ;;
			-v) shift; version="$1" ;;
			--) break ;;
		esac
		shift
	done
shift

### -u: update
if [ $update -eq 1 ]; then
	if [ $offline -eq 0 ]; then
		getbuildrev $version
		if checkrev $rev_nightly; then
			echo "josm-$version revision $rev_nightly is uptodate"
			exit 0
		else
			echo "josm-$version revision $rev_nightly is available, updating..."
			update $version $rev_nightly
			exit 0
		fi
	else
		echo "offline - no update possible. exiting"
		exit 1
	fi


### -r: start specified revision
elif [ $override_rev -eq 1 ]; then
	if [ $rev = last ]; then
		rev=`ls josm*.jar | cut -d '-' -f 2 | cut -d '.' -f 1 | tail -n 2 | head -n 1`
	fi
	if checkrev $rev; then
		echo "forcing use of local revision $rev"
	else
		echo "revision $rev not found! Use `basename $0` -l to display a list of available revisions. exiting."
		exit 1
	fi

### normal start and update - tested
elif [ $version = tested ]; then
	getbuildrev $version
	if checkrev $rev_nightly; then
		echo "local revision $rev_nightly is uptodate"
		rev=$rev_nightly
	else
		echo "local revision is $rev_local, latest available revision is $rev_nightly - starting download of josm-$version..."
		update $version $rev_nightly
		rev=$rev_nightly
	fi

### normal start and update - latest
else
	getlocalrev
	getbuildrev $version
	if [ $rev_local -ge $rev_nightly ]; then
		echo "local revision is $rev_local, latest available revision is $rev_nightly - using local revision $rev_local"
		rev=$rev_local
	else
		echo "local revision is $rev_local, latest available revision is $rev_nightly - starting download of josm-$version..."
		update $version $rev_nightly
		rev=$rev_local
	fi
fi

### cleanup
if [ $offline -eq 0 ]; then
	i=1
	while [ `ls josm*.jar | grep -c ''` -gt $numbackup ]; do
		oldestrev=`ls josm*.jar | cut -d '-' -f 2 | cut -d '.' -f 1 | head -n $i | tail -n 1`
		# don't delete current tested
		if [ $oldestrev -ne $rev_tested ]; then
			echo "deleting josm revision $oldestrev"
			rm josm-$oldestrev.jar
		else i=`expr $i + 1`
		fi
		if [ `expr $i + 1` -eq  $numbackup ]; then
			echo "error while cleaning up - \$numbackup set too low."
			break;
		fi
	done
fi

# start josm: use alsa instead of oss, enable 2D-acceleration, set maximum memory for josm, pass all arguments to josm and write a log:
	cd $OLDPWD
	echo "starting josm..."
	if [ $bequiet -eq 0 ]
		then aoss java -jar -Xmx$mem -Dsun.java2d.opengl=true $dir/josm-$rev.jar $@ 2>&1 | tee ~/.josm/josm.log &
		else aoss java -jar -Xmx$mem -Dsun.java2d.opengl=true $dir/josm-$rev.jar $@ >~/.josm/josm.log 2>&1 &
	fi
	echo "josm started with PID $!"

