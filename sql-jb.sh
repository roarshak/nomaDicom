#!/bin/sh
#
# Component: tools
#
# Description:
#    Executes a MySQL query in the imagemedical database
#
# Usage:
#      sql.sh <query> <mysql flags> 
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

query=$1
flag=$2

if [ -z "$query" ]; then
	cat <<-EOFUSAGE
		Executes a MySQL query in the $DBNAME database

		$0 <query> <flag>

		   \$1 - query (e.g \"select * from Target\")
		   \$2 - mysql flag ( -N for no header output, etc )
	EOFUSAGE

exit 0

fi

echo "$query" | $MYSQL_HOME/bin/mysql $flag $DBNAME
