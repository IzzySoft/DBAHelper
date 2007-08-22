#!/bin/bash
###############################################################################
# RMAN wrapper
# Sets up the RMAN scripts for the specified task
###############################################################################
# $Id$

#===============================================[ Setup Script environment ]===
if [ -z "${ORACLE_HOME}" ]; then			# Running via Cron job
  [ -f ~/.bashrc ] && . ~/.bashrc			# Get Oracle environment
fi

#---------------------------------------------------------------[ Settings ]---
BINDIR=${0%/*}
LOGDIR=/local/database/a01/${ORACLE_SID}/dump/log
TMPFILE=/tmp/rman.$$
CONFIGUREOPTS=
YESTOALL=0

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
  echo "============================================================================"
  echo "RMAN wrapper                 (c) 2007 by Itzchak Rehberg (devel@izzysoft.de)"
  echo "----------------------------------------------------------------------------"
  echo This script is intended to generate a HTML report for the Oracle StatsPack
  echo collected statistics. Look inside the script header for closer details, and
  echo check for the configuration there as well.
  echo ----------------------------------------------------------------------------
  echo "Syntax: ${SCRIPT} <Command> [Options]"
  echo "  Commands:"
  echo "     backup_daily       Run the daily backup"
  echo "     block_recover      Recover corrupt block in datafile"
  echo "     cleanup_expired	Cleanup non existing files from catalog/controlfile"
  echo "     cleanup_obsolete	Cleanup outdated files from disk and"
  echo "			catalog/controlfile"
  echo "     crosscheck         Validates backup availability and integrity"
  echo -e "     force_clean	Clean pseudo-orphans. ${red}USE WITH CARE! *$NC"
  echo "     recover		Fast Recover database (if possible)"
  echo "     restore_full       Restore the complete DB from backup"
  echo "     restore_ts         Restore a single tablespace from backup"
  echo "     restore_temp       Restore (Re-Create) the TEMP tablespace"
  echo "     validate           Validate (online) database files"
  echo "  Options:"
  echo "     -c <alternate ConfigFile>"
  echo "     -l <Log File Name>"
  echo "     -p <Password>"
  echo "     -r <ORACLE_SID/Connection String for Catalog DB (Repository)>"
  echo "     -u <username>"
  echo "     --force-configure	Force the configure script to run"
  echo -e "     --yestoall		Assume 'yes' to all questions. ${red}Use with care!$NC"
  echo "  Example: Do the daily backup, using the config file /etc/dummy.conf:"
  echo "    ${SCRIPT} backup_daily -c /etc/dummy.conf"
  echo "  Example: Restore local DB using catalog:"
  echo "    ${SCRIPT} restore_full -r catman/catpass@catdb"
  echo
  echo -e "${red}*$NC Work around some Oracle bugs. See documentation for details."
  echo ============================================================================
  echo
}

#=======================================================[ Helper functions ]===
#------------------[ Read one char user input and convert it to lower case ]---
function yesno {
  if [ $YESTOALL -gt 0 ]; then
    res='y'
  else
    read -n 1 -p "" ready
    echo
    res=`echo $ready|tr [:upper:] [:lower:]`
  fi
}

#----------------------------------[ Quit if user not entered y|Y at yesno ]---
function stayorgo {
  [ "$res" != "y" ] && {
    echo -e "${blue}* Process canceled.$NC"
    exit 0
  }
  echo
}

#---------------------------------------[ Normal exit after completed work ]---
function finito {
  echo -e "${blue}Task completed.$NC"
  exit 0
}

#------------------------------------------[ Display introductional header ]---
function header {
  clear
  echo -e "${blue}RMAN Wrapper Script"
  echo -e "-------------------${NC}"
  echo
  echo Running $CMD
}

#--------------------------[ Read user input and make sure it is numerical ]---
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

#-------------------------------[ Run RMAN configure script only if needed ]---
function runconfig {
  local CONFIGURED=0
  [ "$1" != "force" ] &&
    [ -f ~/.rman_configured ] && {
      [ ~/.rman_configured -nt $CONFIG ] && CONFIGURED=1
    }
  [ $CONFIGURED -eq 0 ] && {
    echo -e "${blue}The configuration file has been changed (or never run before), so we may"
    echo -e "need to configure the RMAN settings. Running the configuration commands now:$NC"
    ${RMANCONN} < $CONFIG | tee -a $LOGFILE
    touch ~/.rman_configured
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
    --force-configure) CONFIGUREOPTS=force;;
    --yestoall) YESTOALL=1;;
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

[ -f $BINDIR/rman.$CMD ] && {
  cat $BINDIR/rman.$CMD >$TMPFILE
  echo exit >>$TMPFILE
}

#--------------------------------------[ Check if configuration has to run ]---
runconfig $CONFIGOPTS

#==============================================================[ Say Hello ]===
case "$CMD" in
  backup_daily|validate|crosscheck)
    header
    ${RMANCONN} < $TMPFILE | tee -a $LOGFILE
    ;;
  cleanup_expired)
    header
    ${RMANCONN} < $TMPFILE | tee -a $LOGFILE
    echo -e "${blue}The long list on top shows the process of crosschecking. At the end of the"
    echo -e "crosscheck, tables are displayed listing the expired objects, i.e. those are no"
    echo -e "longer available on the disks, but still in the catalog/controlfile. To keep the"
    echo -e "records small (especially when you are not using a catalog DB but the control files"
    echo -e "to record your backups), we can purge them from the catalog/controlfile. Since they"
    echo -e "do not exist anymore, those records are useless."
    echo -en "Do you want to purge those records now (y/n)? $NC"
    yesno
    if [ "$res" = "y" ]; then
      echo -e "${blue}Purging catalog/controlfile:$NC"
      cat $BINDIR/rman.${CMD}_doit > $TMPFILE
      echo exit >> $TMPFILE
      ${RMANCONN} < $TMPFILE | tee -a $LOGFILE
    else
      echo -e "${blue}Skipping purge process for expired records.$NC"
    fi
    finito
    ;;
  cleanup_obsolete)
    echo -e "${blue}Going to list obsolete files:$NC"
    ${RMANCONN} < $TMPFILE | tee -a $LOGFILE
    echo -e "${blue}Above tables list the obsolete files - i.e. those which are outdated"
    echo -e "according to your retention policy. To free diskspace (and keep your records"
    echo -e "small especially when not using a catalog DB), you can purge them now, i.e."
    echo -e "removing them from the disk and catalog/controlfile."
    echo -en "Do you want to purge those files and records now (y/n)? $NC"
    yesno
    if [ "$res" = "y" ]; then
      echo -e "${blue}Purging files and catalog/controlfile:$NC"
      cat $BINDIR/rman.${CMD}_doit > $TMPFILE
      echo exit >> $TMPFILE
      ${RMANCONN} < $TMPFILE | tee -a $LOGFILE
    else
      echo -e "${blue}Skipping purge process for obsolete files and records.$NC"
    fi
    finito
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
    echo "BLOCKRECOVER DATAFILE $fileno BLOCK $blockno;" > $TMPFILE
    echo exit >> $TMPFILE
    ${RMANCONN} < $TMPFILE | tee -a $LOGFILE
    finito
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
    cat $BINDIR/rman.${CMD}_doit >$TMPFILE
    echo exit >> $TMPFILE
    echo -e "${red}${blink}Running the recover process - don't interrupt now!$NC"
    ${RMANCONN} < $TMPFILE | tee -a $LOGFILE
    finito
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
    cat $BINDIR/rman.${CMD}_doit >$TMPFILE
    echo exit >> $TMPFILE
    echo -e "${red}${blink}Running the restore - don't interrupt now!$NC"
    ${RMANCONN} < $TMPFILE | tee -a $LOGFILE
    finito
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
    echo "SQL 'ALTER TABLESPACE ${tsname} OFFLINE IMMEDIATE';">$TMPFILE
    echo "RESTORE TABLESPACE ${tsname};">>$TMPFILE
    echo "RECOVER TABLESPACE ${tsname};">>$TMPFILE
    echo "SQL 'ALTER TABLESPACE $tsname ONLINE';">>$TMPFILE
    echo "exit">>$TMPFILE
    echo -e "${red}${blink}Running the restore - don't interrupt now!$NC"
    ${RMANCONN} < $TMPFILE | tee -a $LOGFILE
    finito
    ;;
  restore_temp)
    header
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
    finito
    ;;
  force_clean)
    header
    echo -e "${blue}RMAN forgot to purge your obsolete level x backups? Yeah, it's buggy..."
    echo -e "Let's see if we find any level x backups not having a parent full backup:$NC"
    echo "LIST BACKUP SUMMARY;" | $RMANCONN > $TMPFILE
    typeset i idx=0
    while read line; do
      level=`echo $line | awk '{ print $3 }'`
      key=`echo $line | awk '{ print $1 }'`
      [ "$level" != "F" ] && {
        [ ${#level} -eq 1 ] && {
          obskey[$idx]=$key
	  obslvl[$idx]=$level
	  let idx=$idx+1
	}
        key=
        continue
      }
      break;
    done<$TMPFILE
    if [ ${#obskey[*]} -gt 0 ]; then
      echo "First full backup has key ${key}. Following orphaned backups were found:"
      idx=0
      while [ $idx -lt ${#obskey[*]} ]; do
        echo "- ${obskey[$idx]} : Level ${obslvl[$idx]}"
	let idx=$idx+1
      done
      echo -e "${blue}You want to purge these ghosts (y/n)? $NC"
      yesno
      stayorgo
      echo -e "${blue}Purging orphaned cumulative backup sets..."
      cat /dev/null > $TMPFILE
      idx=0
      while [ $idx -lt ${#obskey[*]} ]; do
        echo "DELETE NOPROMPT BACKUPSET ${obskey[$idx]};" >> $TMPFILE
	let idx=$idx+1
      done
      ${RMANCONN} < $TMPFILE | tee -a $LOGFILE
    elif [ -n "$key" ]; then
      echo "First full backup has key ${key}. We found no orphaned level x backups."
    else
      echo -e "${red}Looks like you don't have any full backup!$NC"
      echo -e "${blue}Suggest you make some backups before purging them :)$NC"
      exit 0
    fi
    echo -e "${blue}Shall we also look for forgotten archive logs, i.e. those completed"
    echo -en "before the first full backup was started (y/n)? $NC"
    yesno
    stayorgo
    echo "SET HEAD OFF">$TMPFILE
    echo "SELECT TO_CHAR(start_time,'YYYY-MM-DD HH24:MI:SS') FROM v\$backup_piece_details WHERE bs_key=$key;">>$TMPFILE
    fdat=`sqlplus -s / as sysdba<$TMPFILE`
    fdat=`echo $fdat|sed 's/\n//g'`
    echo "DELETE NOPROMPT ARCHIVELOG COMPLETED BEFORE TO_DATE('$fdat','YYYY-MM-DD HH24:MI:SS');"|${RMANCONN} | tee -a $LOGFILE
    finito
    ;;
  *)
    help
    exit 1
    ;;
esac

rm -f $TMPFILE
