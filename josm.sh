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
#   josm.sh [-hlqru] [revision] [FILE(S)]
#
#   Options:
#   -h  displays a help text
#   -l	lists all saved versions of josm and exits
#   -q  suppresses the output of josm's stdout and stderr but still writes the log
#   -r	starts this revision of josm, revision is either an absolute number or "last" for next to last saved version
#   -u  update without starting josm
#

# include configuration file
. josm.conf
usage="Usage: `basename $0` [-h] [-l] [-q] [-r revision] [-u] [files]"

cd $dir

# parse arguments
set -- `getopt "hlqr:u" "$@"` || {
      echo $usage 1>&2
      exit 1
}
override_rev=0
latestrev=-1
update=0
bequiet=0
while :
do
      case "$1" in
           -h) echo $usage; exit 0 ;;
           -l) echo "available revisions of josm: "; ls josm*.jar | cut -d '-' -f 2 | cut -d '.' -f 1 ; exit 0 ;;
           -q) bequiet=1 ;;
           -r) shift; override_rev=1; latestrev="$1" ;;
           -u) update=1 ;;
           --) break ;;
      esac
      shift
done
shift

# parse special revision argument "last" for using next to last revision
if [ $override_rev -eq 1 -a $latestrev = last ]
  then
    latestrev=`ls josm*.jar | cut -d '-' -f 2 | cut -d '.' -f 1 | tail -n 2 | head -n 1`
fi

# if $dir doesn't exist, create it (initial setup):
if [ -d $dir ]; then :
  else mkdir -p $dir; echo "directory $dir does not exist; creating it..."
fi

# get revision number of newest local version:
if ls josm-*.jar > /dev/null;
  then latestlocalrev=`ls josm*.jar | cut -d '-' -f 2 | cut -d '.' -f 1 | tail -n 1`
  else latestlocalrev=0
fi

# get revision number of backed up versions
oldestrev=`ls josm*.jar | cut -d '-' -f 2 | cut -d '.' -f 1 | head -n 1`

# count backed up versions
numsaved=`ls josm*.jar | grep -c ''`

if [ $override_rev -eq 1 ]
  # check if desired revision is available:
  then
    if ls josm*.jar | cut -d '-' -f 2 | cut -d '.' -f 1 | grep $latestrev
      then
        echo "forcing use of revision $latestrev"
      else
        echo "revision $latestrev not found! Use `basename $0` -l to display a list of available revisions. exiting."
        exit 1
    fi
  else
    # get revision number of desired version
    latestrev=`wget -qO - --tries=$retries --timeout=$timeout http://josm.openstreetmap.de/version | grep $version | cut -d ' ' -f 2`
    if [ ${latestrev:=0} -eq 0 ]
      then echo "could not get version from server, working in offline mode"
    fi

    # download current revision of josm if newest local revision is older than the current revision of josm on the server
    if [ $latestrev -eq 0 ]
      then
        echo "working offline, using latest local version $latestlocalrev..."
        latestrev=$latestlocalrev
      else
      if [ $latestlocalrev -lt $latestrev ]
        then
          echo "latest local version is $latestlocalrev, latest available version is $latestrev - starting download..."
          wget -O $dir/josm-$latestrev.jar -N http://josm.openstreetmap.de/download/josm-$version.jar
          # delete oldest file if enough newer ones are present
          if [ $numsaved -gt $numbackup ]
            then rm $dir/josm-$oldestrev.jar
          fi
        else
        if [ $latestlocalrev -gt $latestrev ]
          then
            echo "latest local version is newer than version on the server ($latestrev) - using local version $latestlocalrev"
            latestrev=$latestlocalrev
          else
            echo "local version $latestlocalrev is already uptodate"
        fi
      fi
    fi
fi

# start josm: use alsa instead of oss, enable 2D-acceleration, set maximum memory for josm, pass all arguments to josm and write a log:
if [ $update -eq 0 ]
  then
    cd $OLDPWD
    echo "starting josm..."
    if [ $bequiet -eq 0 ]
      then
        aoss java -jar -Xmx$mem -Dsun.java2d.opengl=true $dir/josm-$latestrev.jar $@ 2>&1 | tee ~/.josm/josm.log &
      else
        aoss java -jar -Xmx$mem -Dsun.java2d.opengl=true $dir/josm-$latestrev.jar $@ >~/.josm/josm.log 2>&1 &
    fi
    echo "josm started with PID $!"
fi
