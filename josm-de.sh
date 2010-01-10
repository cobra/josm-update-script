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
# homepage und wiki für dieses script: http://github.com/cobra/josm-update-script http://wiki.github.com/cobra/josm-update-script
#
# Startup-script für josm:
#   - aktualisiert josm falls nötig auf die aktuelle Version von latest oder tested (einstellbar)
#   - sichert alte Versionen (sehr hilfreich, wenn die neue Version nicht funktioniert wie gewünscht)
#   - erlaubt es, eine alte Version zu starten (per josm -r [revision])
#   - übergibt alle Argumente an JOSM, nützlich um einen oder mehrere Dateien direkt in JOSM zu öffnen
#   - setzt Umgebungsvariablen, übergibt die passenden Parameter an Java und sorgt dafür, dass alsa benutzt wird
#   - schreibt eine Logdatei nach ~/.josm/josm.log
#
# Konfiguration (in der Datei josm-de.conf):
#   - Verzeichnis für die gespeicherten josm-Versionen anpassen, falls gewünscht
#   - josm-Variante wählen (latest/tested)
#   - Anzahl der gesicherten Versionen anpassen, falls gewünscht
#   - Wird compiz (3D-Desktop) benutzt? Dann bitte die entsprechende Zeile auskommentieren
#   - Menge des für josm verfügbaren Speichers anpassen
#   - Wer andere Parameter für java oder josm ändern möchte, kann das in der letzten Zeile tun
#
# Benutzung:
#   josm-de.sh [-lr] [revision] [DATEI(EN)]
#
#   Optionem:
#   -l	alle gespeicherten josm-Versionen ausgeben und beenden
#   -r	die angegebene Version von josm starten, als Argument entweder eine (lokal vorhandene) Revisionsnummer angeben oder "last" für die vorletzte gespeicherte
#
 
# Konfigurationsdatei einbinden
. josm-de.conf
 
cd $dir
 
# parse arguments
set -- `getopt "hlr:" "$@"` || {
      echo "Benutzung: `basename $0` [-h] [-l] [-r revision] [Dateien]" 1>&2
      exit 1
}
override_rev=0
latestrev=-1
while :
do
      case "$1" in
           -h) echo "Benutzung: `basename $0` [-h] [-l] [-r revision] [Dateien]"; exit 0 ;;
           -l) echo "Verfügbare josm-Versionen: "; ls josm*.jar | cut -d '-' -f 2 | cut -d '.' -f 1 ; exit 0 ;;
           -r) shift; override_rev=1; latestrev="$1" ;;
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
  else mkdir -p $dir; echo "Verzeichnis $dir existiert nicht; wird angelegt..."
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
        echo "Erzwinge Benutzung von Version $latestrev"
      else
        echo "Revision $latestrev konnte nicht gefunden werden! `basename $0` -l zeigt eine Liste der verfügbaren Versionen. Ende."
        exit 1
    fi
  else
    # get revision number of desired version
    latestrev=`wget -qO - --tries=$retries --timeout=$timeout http://josm.openstreetmap.de/version | grep $version | cut -d ' ' -f 2`
    if [ ${latestrev:=0} -eq 0 ]
      then echo "Konnte aktuelle Version nicht vom Server lesen, wechsle in Offline-Modus"
    fi
 
    # download current revision of josm if newest local revision is older than the current revision of josm on the server
    if [ $latestrev -eq 0 ]
      then
        echo "Offline-Modus, benutze letzte aktuelle Version $latestlocalrev"
        latestrev=$latestlocalrev
      else
      if [ $latestlocalrev -lt $latestrev ]
        then
          echo "aktuelle lokale Version ist $latestlocalrev, neueste verfügbare Version ist $latestrev - starte download..."
          wget -O $dir/josm-$latestrev.jar -N http://josm.openstreetmap.de/download/josm-$version.jar
          # delete oldest file if enough newer ones are present
          if [ $numsaved -gt $numbackup ]
            then rm $dir/josm-$oldestrev.jar
          fi
        else
        if [ $latestlocalrev -gt $latestrev ]
          then
            echo "aktuelle lokale Version ist neuer als die Version auf dem Server ($latestrev) - benutze lokale Version $latestlocalrev"
            latestrev=$latestlocalrev
          else
            echo "lokale Version $latestlocalrev ist bereits aktuell"
        fi
      fi
    fi
fi
 
# start josm: use alsa instead of oss, enable 2D-acceleration, set maximum memory for josm, pass all arguments to josm and write a log:
cd $OLDPWD
echo "starte josm..."
aoss java -jar -Xmx$mem -Dsun.java2d.opengl=true $dir/josm-$latestrev.jar $@ >~/.josm/josm.log 2>&1 &
echo "josm wurde mit mit PID $! gestartet"

