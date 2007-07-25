#!/bin/bash
###############################################################################
# RMAN wrapper
# Sets up the RMAN scripts for the specified task
###############################################################################
# $Id$

#===============================================[ Setup Script environment ]===
if [ -z "${TERM}" ]; then				# Running via Cron job
  [ -f ~/.bashrc ] && . ~/.bashrc			# Get Oracle environment
fi

#---------------------------------------------------------------[ Settings ]---
BINDIR=${0%/*}
LOGDIR=/local/database/a01/${ORACLE_SID}/dump/log
TMPFILE=/tmp/rman.$$

#-----------------------------------------------------------------[ Colors ]---
if [ -n "${TERM}" ]; then
  red='\e[0;31m'
  blue='\e[0;34m'
  blink='\E[5m'
  NC='\e[0m'              # No Color
fi

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
  echo "     block_recover      Recover corrupt block in datafile"
  echo "     validate           Validate (online) database files"
  echo "     crosscheck         Validates backup availability and integrity"
  echo "     recover		Fast Recover database (if possible)"
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
    echo -e "${blue}* Restore canceled.$NC"
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

function readnr {
  echo -en "  ${blue}$1:$NC "
  read nr
  [ -z "$nr" ] && {
    echo -en "  ${blue}You didn't enter anything. Do you want to abort (y/n)?$NC "
    yesno
    if [ "$res" != "y" ]; then res=y; else res=n; fi
    stayorgo
    readnr "$1"
  }
  testnr=`echo $nr | sed 's/[0-9]//g'`
  [ -n "$testnr" ] && {
    echo -e "  ${blue}Only digits are allowed here!$NC"
    readnr "$1"
  }
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
  block_recover)
    header
    echo -e "${blue}* You asked for a block recovery. Please provide the required data"
    echo -e "  (you probably find them either in the application which alerted you about"
    echo -e "  the problem, or at least in the alert log. Look out for a message like$NC"
    echo "    ORA-1578: ORACLE data block corrupted (file # 6, block # 1234)"
    readnr "Please enter the file #"
    fileno=$nr
    readnr "Please enter the block #"
    blockno=$nr
    echo -en "  ${blue}Going to recover block # $blockno for file # $fileno. Continue (y/n)?$NC "
    yesno
    stayorgo
    cat $CONFIG > $TMPFILE
    echo "BLOCKRECOVER DATAFILE $fileno BLOCK $blockno;" >> $TMPFILE
    ${RMANCONN} < $TMPFILE | tee -a $LOGFILE
    ;;
  recover)
    header
    echo -e "${blue}* Test whether a fast recovery is possible:$NC"
    ${RMANCONN} < $TMPFILE | tee -a $LOGFILE
    echo -e "${blue}Please check above output for errors. A line like$NC"
    echo "  ORA-01124: cannot recover data file 1 - file is in use or recovery"
    echo -e "${blue}means the database is still up and running, and you rather should check"
    echo -e "the alert log for what is broken and e.g. recover that tablespace"
    echo -e "explicitly with \"${0##*/} recover_ts\". Don't continue in this case;"
    echo -e "it would fail either."
    echo -en "Continue with the recovery (y/n)?$NC "
    yesno
    stayorgo
    echo -e "${blue}OK, so we go to do a 'Fast Recovery' now, stand by...$NC"
    cat $CONFIG >$TMPFILE
    cat $BINDIR/rman.${CMD}_doit >>$TMPFILE
    echo -e "${red}${blink}Running the recover process - don't interrupt now!$NC"
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
    echo "CREATE TEMPORARY TABLESPACE temp TEMPFILE '/local/database/a01/${ORACLE_SID}/dbf/temp01.dbf' REUSE SIZE 512 M AUTOEXTEND OFF;">>$TMPFILE
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
