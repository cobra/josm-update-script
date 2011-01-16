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
#   josm.sh [-hloqu] [-r revision] [-v version] [DATEI(EN)]
#
#   Optionen:
#   -h  gibt einen Hilfetext aus
#   -l	zeigt alle verfügbaren Revisionen von josm an, josm wird nicht gestartet
#   -o  arbeitet offline ohne update-Versuch
#   -q  unterdrückt josms Ausgabe auf das Terminal, schreibt nur die Logdatei
#   -r	startet die angegebene Version von josm, als Argument entweder eine (lokal vorhandene) Revisionsnummer angeben oder "last" für die vorletzte gespeicherte
#   -s  aktuelle Revision aus dem SVN laden und kompilieren. Kann mit -u und -r kombiniert werden. svn und ant müssen dafür installiert sein.
#   -u  aktualisiert josm ohne es zu starten
#   -v  startet statt der konfigurierten Version von josm die hier angegebene (kann "latest" oder "tested" sein)
#

# include configuration file
. ./josm.conf
usage="Benutzung: `basename $0` [-h] [-l] [-o] [-q] [-r Revision] [-u] [-v Version] [Dateien]"
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
  else mkdir -p $dir; echo "Verzeichnis $dir existiert nicht; wird angelegt..."
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
			echo "Konnte aktuelle Version nicht vom Server lesen, wechsle in Offline-Modus" >&2
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
		echo "lade josm-$version, revision $2 herunter..."
		wget -O josm-$2.jar -N http://josm.openstreetmap.de/download/josm-$1.jar
		return $?
	else return 1
	fi
}

# parse arguments
set -- `getopt "hloqr:suv:" "$@"` || {
	echo $usage 1>&2
	exit 1
}

while :
	do
		case "$1" in
			-h) echo $usage; exit 0 ;;
			-l) echo "Verfügbare josm-Versionen: "; ls josm*.jar | cut -d '-' -f 2 | cut -d '.' -f 1 ; exit 0 ;;
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
		echo "Kein Zugriff auf das svn im offline-Modus. Ende."
		exit 1
	fi
	if ! svn --version > /dev/null ; then
		echo "svn konnte nicht gefunden werden. Bitte zuerst svn installieren."
		exit 1
	fi
	if ! ant -version > /dev/null ; then
		echo "ant konnte nicht gefunden weredn. Bitte zuerst ant installieren."
		exit 1
	fi

	if [ $override_rev -eq 1 ]; then
		#checkout specific revision
		echo "Revision $rev wird ausgecheckt..."
		svn co -r $rev http://josm.openstreetmap.de/svn/trunk $svndir
		if [ $? -eq 1 ]; then
			echo "Auschecken fehlgeschlagen. Ende."
			exit 1
		fi
		cd $svndir
	else
		# checkout latest svn revision
		if [ -d $svndir ]; then
			cd $svndir
			echo "svn-Repository auf Updates prüfen..."
			svn up
			if [ $? -eq 1 ]; then
				echo "svn-Update fehlgeschlagen. Ende."
				exit 1
			fi
		else
			echo "Lokale Arbeitskopie existiert nicht, auschecken..."
			svn co http://josm.openstreetmap.de/svn/trunk $svndir
			if [ $? -eq 1 ]; then
				echo "Auschecken fehlgeschlagen. Ende."
				exit 1
			fi
			cd $svndir
		fi
	fi

	# get revision, check against existing binaries
	rev_svn=`svn info | grep Revision | cut -d ' ' -f 2`

	if checkrev $rev_svn; then
		# no changes, use existing binary
		echo "Revision $rev_svn ist bereits vorhanden, Kompilieren wird übersprungen."
		rev=$rev_svn	
	else
		# build josm, move to archive; you can add any options fo ant here if you need them
		echo "Versuche, Revision $rev_svn zu kompilieren..."
		ant
		if [ $? -eq 0 ]; then
			echo "Kompilieren von Revision $rev_svn aus dem SVN erfolgreich"
			cp $svndir/dist/josm-custom.jar $dir/josm-$rev_svn.jar
			rev=$rev_svn
		else
			echo "Kompilieren fehlgeschlagen, Ende."
			exit 1
		fi
	fi

	# terminate if -u is set as well
	if [ $update -eq 1 ]; then
		echo "Update aus svn ist vollständig, Ende."
		exit 0;
	else
		cd $dir
	fi

### -u: update
elif [ $update -eq 1 ]; then
	if [ $offline -eq 0 ]; then
		getbuildrev $version
		if checkrev $rev_nightly; then
			echo "josm-$version revision $rev_nightly ist aktuell"
			exit 0
		else
			echo "josm-$version revision $rev_nightly ist verfügbar, aktualisieren..."
			update $version $rev_nightly
			exit 0
		fi
	else
		echo "offline - keine Aktualisierung möglich. Ende"
		exit 1
	fi


### -r: start specified revision
elif [ $override_rev -eq 1 ]; then
	if [ $rev = last ]; then
		rev=`ls josm*.jar | cut -d '-' -f 2 | cut -d '.' -f 1 | tail -n 2 | head -n 1`
	fi
	if checkrev $rev; then
		echo "Erzwinge Benutzung von Version $rev"
	else
		echo "Revision $rev konnte nicht gefunden werden! `basename $0` -l zeigt eine Liste der verfügbaren Versionen. Ende."
		exit 1
	fi

### normal start and update - tested
elif [ $version = tested ]; then
	getbuildrev $version
	if checkrev $rev_nightly; then
		echo "Lokale Revision $rev_nightly ist aktuell"
		rev=$rev_nightly
	else
		echo "Lokale Revision ist $rev_local, neueste verfügbare Revision ist $rev_nightly - starte Download von josm-$version..."
		update $version $rev_nightly
		rev=$rev_nightly
	fi

### normal start and update - latest
else
	getlocalrev
	getbuildrev $version
	if [ $rev_local -ge $rev_nightly ]; then
		echo "Lokale Revision ist $rev_local, neueste verfügbare Revision ist $rev_nightly - benutze lokale Revision $rev_local"
		rev=$rev_local
	else
		echo "Lokale Revision ist $rev_local, neueste verfügbare Revision ist $rev_nightly - starte Download von josm-$version..."
		update $version $rev_nightly
		rev=$rev_nightly
	fi
fi

### cleanup
if [ $offline -eq 0 ]; then
	i=1
	while [ `ls josm*.jar | grep -c ''` -gt $numbackup ]; do
		oldestrev=`ls josm*.jar | cut -d '-' -f 2 | cut -d '.' -f 1 | head -n $i | tail -n 1`
		# don't delete current tested
		if [ $oldestrev -ne $rev_tested ]; then
			echo "Lösche josm Revision $oldestrev"
			rm josm-$oldestrev.jar
		else i=`expr $i + 1`
		fi
		if [ `expr $i + 1` -eq  $numbackup ]; then
			echo "Fehler beim Aufräumen - \$numbackup ist zu niedrig."
			break;
		fi
	done
fi

# start josm: use alsa instead of oss, enable 2D-acceleration, set maximum memory for josm, pass all arguments to josm and write a log:
	cd $OLDPWD
	echo "starte josm..."
	# use aoss only if it's installed
	aoss > /dev/null 2>&1
	if [ $? -eq 1 ]; then
		aoss java -jar -Xmx$mem -Dsun.java2d.opengl=$useopengl $dir/josm-$rev.jar $@ >~/.josm/josm.log 2>&1 &
	else
		java -jar -Xmx$mem -Dsun.java2d.opengl=$useopengl $dir/josm-$rev.jar $@ >~/.josm/josm.log 2>&1 &
	fi

	echo "josm wurde mit mit Prozess-ID $! gestartet"

	if [ $bequiet -eq 0 ]
		then tail -f ~/.josm/josm.log
	fi

