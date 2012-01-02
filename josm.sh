#!/bin/bash
#
# Copyright (C) 2011 "Cobra" from <http://www.openstreetmap.org>
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
#   -s  get and build latest revision from SVN. Can be combined with -u and -r. Requires svn and ant to be installed.
#   -u  update without starting josm
#   -v  overrides the configured version of josm (can be either "latest" or "tested")
#

# include configuration file
. `dirname $0`/josm.conf
usage="Usage: `basename $0` [-h] [-l] [-o] [-q] [-r revision] [-s] [-u] [-v version] [files]"
# global variables
rev_tested=0
rev_tested=0
rev_nightly=0
rev_local=0
rev_svn=0
# flags
override_rev=0
update=0
bequiet=0
offline=0
svn=0

# if $dir doesn't exist, create it (initial setup):
if [ -d $dir ]; then :
  else mkdir -p $dir; echo "directory $dir does not exist; creating it..."
fi
if [ -d ~/.josm ]; then :
	else mkdir ~/.josm; echo "directory ~/.josm does not exist; creating it..."
fi

cd $dir

checkrev() {
	# checks archive for certain revision
	# parameter: revision to check
	# returns: 0 if revision is present
	if ls $dir/josm*.jar | grep $1 >/dev/null; then
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

terminate() {
	# terminates this script, tail and josm
	echo "terminating... please wait"
	kill -TERM $josmpid
	if [ $bequiet -eq 0 ]
		then kill $tailpid
	fi
}

trap terminate SIGINT SIGTERM

# parse arguments
set -- `getopt "hj:loqr:suv:" "$@"` || {
	echo $usage 1>&2
	exit 1
}

while :
	do
		case "$1" in
			-h) echo $usage; exit 0 ;;
			-j) shift; override_jar=1; jarfile="$1" ;;
			-l) echo "available revisions of josm: "; ls josm*.jar | cut -d '-' -f 2 | cut -d '.' -f 1 ; exit 0 ;;
			-o) offline=1 ;;
			-q) bequiet=1 ;;
			-r) shift; override_rev=1; rev="$1" ;;
			-s) svn=1 ;;
			-u) update=1 ;;
			-v) shift; version="$1" ;;
			--) break ;;
		esac
		shift
	done
shift

### -s: use svn
if [ $svn -eq 1 ]; then
	if [ $offline -eq 1 ]; then
		echo "can't access svn in offline mode. exiting."
		exit 1
	fi
	if ! svn --version > /dev/null ; then
		echo "can't find svn binary. please install svn first."
		exit 1
	fi
	if ! ant -version > /dev/null ; then
		echo "can't find ant binary. please install ant first."
		exit 1
	fi

	if [ $override_rev -eq 1 ]; then
		#checkout specific revision
		echo "checking out revision $rev..."
		svn co -r $rev http://josm.openstreetmap.de/svn/trunk $svndir
		if [ $? -eq 1 ]; then
			echo "svn checkout failed. exiting."
			exit 1
		fi
		cd $svndir
	else
		# checkout latest svn revision
		if [ -d $svndir ]; then
			cd $svndir
			echo "checking svn repository for updates..."
			svn up
			if [ $? -eq 1 ]; then
				echo "svn update failed. exiting."
				exit 1
			fi
		else
			echo "local working copy does not exist, checking out..."
			svn co http://josm.openstreetmap.de/svn/trunk $svndir
			if [ $? -eq 1 ]; then
				echo "svn checkout failed. exiting."
				exit 1
			fi
			cd $svndir
		fi
	fi

	# get revision, check against existing binaries
	rev_svn=`svn info | grep Revision | cut -d ' ' -f 2`

	if checkrev $rev_svn; then
		# no changes, use existing binary
		echo "revision $rev_svn is already existing, skipping build."
		rev=$rev_svn	
	else
		# build josm, move to archive; you can add any options fo ant here if you need them
		echo "attempting to build revision $rev_svn..."
		ant
		if [ $? -eq 0 ]; then
			echo "build of revision $rev_svn from svn successful"
			cp $svndir/dist/josm-custom.jar $dir/josm-$rev_svn.jar
			rev=$rev_svn
		else
			echo "build failed, exiting."
			exit 1
		fi
	fi

	# terminate if -u is set as well
	if [ $update -eq 1 ]; then
		echo "update from svn finished, exiting."
		exit 0;
	else
		cd $dir
	fi

### -u: update
elif [ $update -eq 1 ]; then
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

### override jar file
elif [ $override_jar -eq 1 ]; then
	echo "using manually set jar file $jarfile"

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
		rev=$rev_nightly
	fi
fi

### cleanup
if [ ${offline:-0} -eq 0 -a ${override_jar:-0} -eq 0 ]; then
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

	if [ $override_jar -ne 1 ]; then
		jarfile="$dir/josm-$rev.jar"
	fi

	# use aoss only if it's installed
	aoss > /dev/null 2>&1
	if [ $? -eq 1 ]; then
		aoss java -jar -Xmx$mem -Dsun.java2d.opengl=$useopengl $jarfile $@ >~/.josm/josm.log 2>&1 &
	else
		java -jar -Xmx$mem -Dsun.java2d.opengl=$useopengl $jarfile $@ >~/.josm/josm.log 2>&1 &
	fi
	
	josmpid=$!

	echo "josm started with PID $josmpid"

	if [ $bequiet -eq 0 ]
		then tail -f ~/.josm/josm.log &
		tailpid=$!
	fi

	wait $josmpid
	if [ $bequiet -eq 0 ]
		then kill $tailpid
	fi
	echo "josm terminated"
