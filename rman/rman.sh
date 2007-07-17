#!/bin/bash
###############################################################################
# RMAN wrapper
# Sets up the RMAN scripts for the specified task
###############################################################################
# $Id$

#===============================================[ Setup Script environment ]===
#---------------------------------------------------------------[ Settings ]---
LOGDIR=/opt/oradata/a01/${ORACLE_SID}/dump/log
TEMPTSLOC=/opt/oradata/a01/${ORACLE_SID}/dbf/temp01.dbf # Datafile for Temp TS
TEMPTSSIZE="512 M"                                      # Size of Temp TS

BINDIR=${0%/*}
TMPFILE=/tmp/rman.$$

#-----------------------------------------------------------------[ Colors ]---
red='\e[0;31m'
blue='\e[0;34m'
blink='\E[5m'
NC='\e[0m'              # No Color

#-----------------------------------------------------------[ Display help ]---
function help {
  SCRIPT=${0##*/}
  echo
  echo ============================================================================
  echo "RMAN wrapper                (c) 2007 by Itzchak Rehberg (devel@izzysoft.de)"
  echo ----------------------------------------------------------------------------
  echo This script is intended to generate a HTML report for the Oracle StatsPack
  echo collected statistics. Look inside the script header for closer details, and
  echo check for the configuration there as well.
  echo ----------------------------------------------------------------------------
  echo "Syntax: ${SCRIPT} <Command> [Options]"
  echo "  Commands:"
  echo "     backup_daily       Run the daily backup"
  echo "     validate           Validate (online) database files"
  echo "     crosscheck         Validates backup availability and integrity"
  echo "     restore_full       Restore the complete DB from backup"
  echo "     restore_ts         Restore a single tablespace from backup"
  echo "     restore_temp       Restore (Re-Create) the TEMP tablespace"
  echo "  Options:"
  echo "     -c <alternate ConfigFile>"
  echo "     -l <Log File Name>"
  echo "     -p <Password>"
  echo "     -r <ORACLE_SID/Connection String for Catalog DB (Repository)>"
  echo "     -u <username>"
  echo "  Example: Do the daily backup, using the config file /etc/dummy.conf:"
  echo "    ${SCRIPT} backup_daily -c /etc/dummy.conf"
  echo "  Example: Restore local DB using catalog:"
  echo "    ${SCRIPT} restore_full -r catman/catpass@catdb"
  echo ============================================================================
  echo
}

#------------------[ Read one char user input and convert it to lower case ]---
function yesno {
  read -n 1 -p "" ready
  echo
  res=`echo $ready|tr [:upper:] [:lower:]`
}

function stayorgo {
  [ "$res" != "y" ] && {
    echo "* Restore canceled."
    exit 0
  }
  echo
}

function header {
  clear
  echo -e "${blue}RMAN Wrapper Script"
  echo -e "-------------------${NC}"
  echo
  echo Running $CMD
}

#=============================================================[ Do the job ]===
#-------------------------------------------[ process command line options ]---
CMD=$1
while [ "$1" != "" ] ; do
  case "$1" in
    -r) shift; CATALOG=$1;;
    -u) shift; username=$1;;
    -p) shift; passwd=$1;;
    -c) shift; CONFIG=$1;;
    -l) shift; LOGFILE=$1;;
  esac
  shift
done

[ -z "$CONFIG" ] && CONFIG=$BINDIR/rman.conf
[ -z "$username" ] && SYSDBA="/ as sysdba"
[ -z "$LOGFILE" ] && LOGFILE="${LOGDIR}/rman_$CMD-`date +\"%Y%m%d_%H%M%S\"`"

#------------------------------------------------[ Setup the script to run ]---
if [ -z "$CATALOG" ]; then
  RMANCONN="rman target $username/$passwd"
else
  RMANCONN="rman target $username/$passwd catalog ${CATALOG}"
fi

cat $CONFIG > $TMPFILE
[ -f $BINDIR/rman.$CMD ] && {
  cat $BINDIR/rman.$CMD >>$TMPFILE
  echo exit >>$TMPFILE
}

#==============================================================[ Say Hello ]===
case "$CMD" in
  backup_daily|validate|crosscheck)
    header
    ${RMANCONN} < $TMPFILE | tee -a $LOGFILE
    ;;
  restore_full)
    header
    echo -e "${blue}* Verify backup and show what WOULD be done:$NC"
    ${RMANCONN} < $TMPFILE | tee -a $LOGFILE
    echo -en "${blue}Above actions will be taken if you continue. Are you sure (y/n)?$NC "
    yesno
    stayorgo
    echo -e "${blue}You decided to restore the database '$ORACLE_SID' from the displayed backup."
    echo -e "Hopefully, you've been studying the output carefully - in case some data may"
    echo -e "not be recoverable, it should have been displayed. Otherwise, you may not be"
    echo -e "able to restore to the latest state (some of the last transactions may be lost"
    echo -e "then). Last chance to abort, so:$NC"
    echo -en "${red}Are you really sure to run the restore process (y/n)?$NC "
    yesno
    stayorgo
    cat $CONFIG >$TMPFILE
    cat $BINDIR/rman.${CMD}_doit >>$TMPFILE
    echo -e "${red}${blink}Running the restore - don't interrupt now!$NC"
    ${RMANCONN} < $TMPFILE | tee -a $LOGFILE
    ;;
  restore_ts)
    header
    echo -e "${blue}* Verify backup and show what WOULD be done:$NC"
    read -p "Specify the tablespace to restore: " tsname
    echo -n "About to restore/recover tablespace '$tsname'. Is this OK (y/n)? "
    yesno
    stayorgo
    echo -e "${blue}* Verify backup and show what WOULD be done:$NC"
    echo "RESTORE TABLESPACE $tsname PREVIEW SUMMARY;">>$TMPFILE
    echo "RESTORE TABLESPACE $tsname VALIDATE;">>$TMPFILE
    echo "exit">>$TMPFILE
    ${RMANCONN} < $TMPFILE | tee -a $LOGFILE
    echo -e "${blue}Please check above output carefully for possible problems!$NC"
    echo -n "Should we continue to recover tablespace '$tsname' (y/n)? "
    yesno
    stayorgo
    cat $CONFIG > $TMPFILE
    echo "SQL 'ALTER TABLESPACE ${tsname} OFFLINE IMMEDIATE';">>$TMPFILE
    echo "RESTORE TABLESPACE ${tsname};">>$TMPFILE
    echo "RECOVER TABLESPACE ${tsname};">>$TMPFILE
    echo "SQL 'ALTER TABLESPACE $tsname ONLINE';">>$TMPFILE
    echo "exit">>$TMPFILE
    echo -e "${red}${blink}Running the restore - don't interrupt now!$NC"
    ${RMANCONN} < $TMPFILE | tee -a $LOGFILE
    ;;
  restore_temp)
    echo -en "${blue}You are going to recreate the lost TEMP tablespace. Is that correct (y/n)?$NC "
    yesno
    stayorgo
    echo -e "${blue}Recreating temporary tablespace, stand by...$NC"
    echo "ALTER DATABASE DEFAULT TEMPORARY TABLESPACE system;">$TMPFILE
    echo "DROP TABLESPACE temp;">>$TMPFILE
    echo "CREATE TEMPORARY TABLESPACE temp TEMPFILE '${TEMPTSLOC}' REUSE SIZE ${TEMPTSSIZE} AUTOEXTEND OFF;">>$TMPFILE
    echo "ALTER DATABASE DEFAULT TEMPORARY TABLESPACE TEMP;">$TMPFILE
    echo "exit">>$TMPFILE
    sqlplus / as sysdba <$TMPFILE
    ;;
  *)
    help
    exit 1
    ;;
esac

rm -f $TMPFILE
