#!/bin/sh
#shellcheck disable=SC3043,SC2155
#
# Component: tools
#
# Description:
#    Prints study information (content of storestate.rec and reference counters) to standard output.
#
# Usage:
#    printStudyInfo.sh <study instance uid>
#
# Last Updated     : $Author$
# Update Date Time : $Date$
# RCS File Name    : $RCSfile$
# RCS Revision     : $Revision$
# Locked by        : $Locker$
# Symbolic name    : $Name$
# State            : $State$
#

. $HOME/etc/setenv.sh

. $TOOLS_HOME/functions.shi

#
# Prints usage information
#
# [$1] - error message
#
# shellcheck disable=SC2120
usage_() {
	local errMsg="$1"
	[ -n "$errMsg" ] && echo "Error: $errMsg" >&2

	cat <<-EOFUSAGE
	  printStudyInfo.sh ${STUDY_USAGE_OPTS} [-R] [-S] [-T] [-D]

  ${STUDY_USAGE_DESC}

	    Output related options:
		 
	     -R        : print references
	     -S        : print storestate.rec file
	     -T        : print study table content
	     -D        : print directories

		 If no output related options specified, -D, -S and -T will be applied.
	EOFUSAGE

	[ -n "$errMsg" ] && exit 1

	exit 0
}

useDefault="true"
printReferences="false"
printStoreState="false"
printTableData="false"
printDirectories="false"

while getopts "${STUDY_ARGS}RSDT" OPT ; do
	case $OPT in
		R) printReferences="true" ; useDefault="false" ;;
		S) printStoreState="true" ; useDefault="false" ;;
		T) printTableData="true" ; useDefault="false" ;;
		D) printDirectories="true" ; useDefault="false" ;;
		*) if ! handleStudyArg_ ; then usage_ ; fi ;;
	esac
done

checkStudyArg_

#
# Prints study information
#
# $1 - study
#
printStudyInfo_()
{
	local study="$1"
	local studyDirectory=`getStudyDirectory_ $study`
	local cacheDirectory=`getStudyCacheDirectory_ $study`
	local processedDirectory=`getStudyProcessedDirectory_ $study`
	local ref
	local file

	if [ "$printDirectories" = "true" -o "$useDefault" = "true" ] ; then
		setIndentLevel_ 0
		printLineIndented_ "Study Directory: $studyDirectory"
		printLineIndented_ "Cache Directory: $cacheDirectory"
		printLineIndented_ "Processed Directory: $processedDirectory"
		if hasArchiveConfigured_ ; then
			printLineIndented_ "Archive Directory: `getArchiveDirectory_ $study`"
		fi
	fi

	if [ "$printStoreState" = "true" -o "$useDefault" = "true" ] ; then
		setIndentLevel_ 0
		printLineIndented_ "storestate.rec:"

		setIndentLevel_ "+4"
		if [ -f "$studyDirectory/.info/storestate.rec" ] ; then
			printFileIndented_ "$studyDirectory/.info/storestate.rec"
		else
			printLineIndented_ "!!! storestate.rec file does not exist !!!"
		fi
	fi

	if [ "$printReferences" = "true" ] ; then
		setIndentLevel_ 0
		
		printTextIndented_ "References:"
		setIndentLevel_ "+4"

		printTextIndented_ "STUDYDIR:"
		setIndentLevel_ "+4"
		for ref in `getStudyDirReferences_ "$study"` ; do
			printTextIndented_ "$ref"
		done
		setIndentLevel_ "-4"

		printTextIndented_ "STUDYDB:"
		setIndentLevel_ "+4"
		for ref in `getStudyDbReferences_ "$study"` ; do
			printTextIndented_ "$ref"
		done
		setIndentLevel_ "-4"

		printTextIndented_ "OBJECTFILE:"
		setIndentLevel_ "+4"
		for file in `[ -n "$studyDirectory" ] && ls $studyDirectory/`; do
			printTextIndented_ "$file"
			
			setIndentLevel_ "+4"
			for ref in `getObjectFileReferences_ "$study" "$file"` ; do
				printTextIndented_ "$ref"
			done
			setIndentLevel_ "-4"
		done
		setIndentLevel_ "-4"

		for file in `listObjectFileReferenceCounters_ "$study"` ; do
			[ -f "$studyDirectory/$file" ] && continue

			printTextIndented_ "MISSING FILE: $file"
			setIndentLevel_ "+4"
			for ref in `getObjectFileReferences_ "$study" "$file"` ; do
				printTextIndented_ "$ref"
			done
			setIndentLevel_ "-4"
		done
	fi

	if [ "$printTableData" = "true" -o "$useDefault" = "true" ] ; then
		setIndentLevel_ 0

		NumStudyEntries=`echo "select count(*) from Dcstudy where STYIUID='$study';" | $MYSQL_HOME/bin/mysql -N $DBNAME`
		NumObjectEntries=`echo "select count(*) from Dcobject where STYIUID='$study';" | $MYSQL_HOME/bin/mysql -N $DBNAME`
		NumReportEntries=`echo "select count(*) from Dcreport where SRCSTUDY='$study';" | $MYSQL_HOME/bin/mysql -N $DBNAME`

		echo "Study table entries: $NumStudyEntries; Object table entries: $NumObjectEntries; Report table entries: $NumReportEntries"

		echo "Study Data:"
		echo "select ACCNO, PNAME, MODALITY, STYDATETIME, STYDESCR, MAINST, REPORTST, FOLDER, Dcstudy_D as DELETED from Dcstudy where STYIUID='$study';" | $MYSQL_HOME/bin/mysql -E $DBNAME 
	fi
}

if isSingleStudy_ ; then
	printStudyInfo_ "`getStudies_`"
else
	for study in `getStudies_` ; do
		echo "==== $study ===="
		printStudyInfo_ "$study"
	done
fi

