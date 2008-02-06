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
CONFIGUREOPTS=
DRYRUN=0
ALLDBS=0
typeset -i SILENT=0
YESTOALL=0
NOHEAD=0
CONFIGSTATEFILE="~/.rman_configured"
[ -z "$USEDIALOG" ] && USEDIALOG=0

. ${BINDIR}/rmanrc

#-----------------------------------------------------------[ Display help ]---
function help {
  local red='\e[0;31m'
  local NC='\e[0m'
  SCRIPT=${0##*/}
  echo
  echo "============================================================================"
  echo "RMAN wrapper            (c) 2007-2008 by Itzchak Rehberg (devel@izzysoft.de)"
  echo "----------------------------------------------------------------------------"
  echo "This script is intended as a wrapper to Oracles Recovery Manager (RMAN)."
  echo "Configuration can be done in the files rmanrc (for the script itself) plus"
  echo "rman[_\$ORACLE_SID].conf (database specific). See the manual for details."
  echo ----------------------------------------------------------------------------
  echo "Syntax: ${SCRIPT} <Command> [Options]"
  echo "  Commands:"
  echo "     backup_daily       Run the daily backup"
  echo "     block_recover      Recover corrupt block in datafile"
  echo "     cleanup_expired	Cleanup non existing files from catalog/controlfile"
  echo "     cleanup_obsolete	Cleanup outdated files from disk and"
  echo "			catalog/controlfile"
  echo "     create_standby     Create a standby database from a running instance"
  echo "     crosscheck         Validates backup availability and integrity"
  echo -e "     force_clean	Clean pseudo-orphans. ${red}USE WITH CARE! *$NC"
  echo "     move_fra		Move Recovery Area to new disk location"
  echo "     recover		Fast Recover database (if possible)"
  echo "     restore_full       Restore the complete DB from backup"
  echo "     restore_ts         Restore a single tablespace from backup"
  echo "     restore_temp       Restore (Re-Create) the TEMP tablespace"
  echo "     validate           Validate (online) database files"
  echo "  Options:"
  echo "     -c <alternate ConfigFile>"
  echo "     -l <Log File Name>"
  echo "     -p <Password>"
  echo "     -q Be quiet (repeat up to 3 times)"
  echo "     -r <ORACLE_SID/Connection String for Catalog DB (Repository)>"
  echo "     -u <username>"
  echo "     --all              backup_daily/cleanup_obsolete: All databases (checked by"
  echo "                        existing rman_\$ORACLE_SID.conf files)"
  echo "     --dryrun		Don't do anything, just show what would be done"
  echo "     --force-configure	Force the configure script to run"
  echo "     --[no]dialog       Force the script to [not] use the dialog interface"
  echo -e "     --yestoall		Assume 'yes' to all questions. ${red}Use with care!$NC"
  echo "  Example: Do the daily backup, using the config file /etc/dummy.conf:"
  echo "    ${SCRIPT} backup_daily -c /etc/dummy.conf"
  echo "  The same for a Cron job (ask no questions, make no output):"
  echo "    ${SCRIPT} backup_daily -c /etc/dummy.conf -q -q -q --yestoall"
  echo "  Example: Restore local DB using catalog:"
  echo "    ${SCRIPT} restore_full -r catman/catpass@catdb"
  echo
  echo -e "${red}*$NC Work around some bugs/misconfiguration. See documentation for details."
  echo ============================================================================
  echo
}

#=======================================================[ Helper functions ]===
function cleanup() {
  rm -f $TMPFILE
  rm -f $SPOOLFILE
}

#---------------------------------------[ Normal exit after completed work ]---
function finito {
  cleanup
  echo "Task completed."
  exit 0
}

#-------------------------------------------------[ Cancel / Exit on Error ]---
function abort {
  cleanup
  echo "Process canceled. Goodbye!"
  exit 1
}

#--------------------------[ Read user input and make sure it is numerical ]---
function readnr {
  readval "$1:"
  nr="$res"
  [ -z "$nr" ] && {
    yesno "You didn't enter anything. Do you want to abort?"
    [ $? == 0 ] && abort
    readnr "$1"
  }
  testnr=`echo $nr | sed 's/[0-9]//g'`
  [ -n "$testnr" ] && {
    alert "Only digits are allowed here!"
    readnr "$1"
  }
}

#-------------------------------------------------------[ Set config names ]---
function setconfig {
  if [ -n "$1" ]; then
    CONFIGSTATEFILE="$HOME/.rman_configured_$1"
  else
    CONFIGSTATEFILE="$HOME/.rman_configured"
  fi
}

#-------------------------------[ Run RMAN configure script only if needed ]---
function runconfig {
  local CONFIGURED=0
  [ "$1" != "force" ] &&
    [ -f ${CONFIGSTATEFILE} ] && {
      [ ${CONFIGSTATEFILE} -nt $CONFIG ] && CONFIGURED=1
    }
  [ $CONFIGURED -eq 0 ] && {
    waitmessage "The configuration file has been changed (or never run before), so we may need to configure the RMAN settings. Running the configuration commands now:"
    ${RMANCONN} < $CONFIG | tee -a $LOGFILE
    eval "touch ${CONFIGSTATEFILE}"
  }
}

#=============================================================[ Do the job ]===
#-------------------------------------------[ process command line options ]---
CMD=$1
while [ "$1" != "" ] ; do
  case "$1" in
    -c) shift; CONFIG=$1;;
    -l) shift; LOGFILE=$1;;
    -p) shift; passwd=$1;;
    -q) [ $SILENT -lt 3 ] && let SILENT=$SILENT+1;;
    -r) shift; CATALOG=$1;;
    -u) shift; username=$1;;
    --all) ALLDBS=1;;
    --dryrun)  DRYRUN=1;;
    --force-configure) CONFIGUREOPTS=force;;
    --yestoall) YESTOALL=1;;
    --noheader) NOHEAD=1;;
    --nodialog) USE_DIALOG=0;;
    --dialog)   USE_DIALOG=1;;
  esac
  shift
done

[ -n "$USE_DIALOG" ] && USEDIALOG=$USE_DIALOG
[ -z "$USEDIALOG" ] && USEDIALOG=0
. ${BINDIR}/mods/global.lib

#---------------------------------------[ check for the config file to use ]---
[ -z "$CONFIG" ] && {
  if [ -e $BINDIR/rman_$ORACLE_SID.conf ]; then
    CONFIG=$BINDIR/rman_$ORACLE_SID.conf
    setconfig $ORACLE_SID
  else
    setconfig
    CONFIG=$BINDIR/rman.conf
  fi
}
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

#==============================================================[ Say Hello ]===
case "$CMD" in
  create_standby)
    BACKTITLE="RMan Wrapper: Create Standby Database"
    runconfig $CONFIGUREOPTS
    . ${BINDIR}/mods/create_standby.sub
    finito
    ;;
  validate)
    BACKTITLE="RMan Wrapper: Validation"
    runconfig $CONFIGUREOPTS
    waitmessage "Running Validate..."
    runcmd "${RMANCONN} < $TMPFILE | tee -a $LOGFILE" $TMPFILE "Progress of Validation:"
    finito
    ;;
  crosscheck)
    BACKTITLE="RMan Wrapper: CrossCheck"
    runconfig $CONFIGUREOPTS
    waitmessage "Cross-Checking files..."
    runcmd "${RMANCONN} < $TMPFILE | tee -a $LOGFILE" $TMPFILE "CrossChecking Progress:"
    finito
    ;;
  backup_daily)
    BACKTITLE="RMan Wrapper: Daily Backup"
    [ $ALLDBS -eq 0 ] && runconfig $CONFIGUREOPTS
    . ${BINDIR}/mods/backup_daily.sub
    finito
    ;;
  cleanup_expired)
    BACKTITLE="RMan Wrapper: Cleanup expired backups"
    runconfig $CONFIGUREOPTS
    . ${BINDIR}/mods/cleanup_expired.sub
    finito
    ;;
  cleanup_obsolete)
    BACKTITLE="RMan Wrapper: Cleanup obsolete backups"
    . ${BINDIR}/mods/cleanup_obsolete.sub
    finito
    ;;
  block_recover)
    BACKTITLE="RMan Wrapper: Block Recovery"
    message "You asked for a block recovery. Please provide the required data
            (you probably find them either in the application which alerted you about
             the problem, or at least in the alert log. Look out for a message like\n
            \n  ORA-1578: ORACLE data block corrupted (file # 6, block # 1234)"
    readnr "Please enter the file #"
    fileno=$nr
    readnr "Please enter the block #"
    blockno=$nr
    yesno "Going to recover block # $blockno for file # $fileno. Continue?"
    [ $? -ne 0 ] && abort
    echo "BLOCKRECOVER DATAFILE $fileno BLOCK $blockno;" > $TMPFILE
    echo exit >> $TMPFILE
    runcmd "${RMANCONN} < $TMPFILE | tee -a $LOGFILE" "$TMPFILE" "Recovering block# $blockno of file# $fileno..."
    finito
    ;;
  recover)
    BACKTITLE="RMan Wrapper: Recover"
    message "Please check following output for errors. A line like
            \n${red}  ORA-01124: cannot recover data file 1 - file is in use or recovery${NC}
            \nmeans the database is still up and running, and you rather should check
            the alert log for what is broken and e.g. recover that tablespace
            explicitly with \"${0##*/} recover_ts\". Don't continue in this case;
            it would fail either."
    waitmessage "Test whether a fast recovery is possible..."
    runcmd "${RMANCONN} < $TMPFILE | tee -a $LOGFILE" "$TMPFILE" "Running recovery test:"
    yesno "If there was any error - especially ORA-01124 - shown, you should
           better abort now. Your decision, so: Continue with the recovery?"
    [ $? -ne 0 ] && abort
    waitmessage "OK, so we go to do a 'Fast Recovery' now, stand by..."
    cat $BINDIR/rman.${CMD}_doit >$TMPFILE
    echo exit >> $TMPFILE
    waitmessage "${red}${blink}Running the recover process - don't interrupt now!$NC"
    runcmd "${RMANCONN} < $TMPFILE | tee -a $LOGFILE" "$TMPFILE" "${red}Recovery running - DO NOT INTERRUPT!$NC"
    finito
    ;;
  restore_full)
    BACKTITLE="RMan Wrapper: Full Restore"
    waitmessage "Verifying backup, please wait..."
    runcmd "${RMANCONN} < $TMPFILE | tee -a $LOGFILE" "$TMPFILE"
    WINTITLE="Please check the following actions:"
    textbox "$SPOOLFILE"
    WINTITLE="Please confirm:"
    yesno "Shall we execute the actions from previous screen?"
    [ $? -ne 0 ] && abort
    yesno "You decided to restore the database '$ORACLE_SID' from the displayed
           backup. Hopefully, you studied the output carefully - in case some
           data may not be recoverable, it should have been displayed. Otherwise,
           you may not be able to restore to the latest state - some of the last
           transactions may be lost. This is your last chance to abort, so:\n
           \n${red}Are you really sure to run the restore process?${NC}"
    [ $? -ne 0 ] && abort
    cat $BINDIR/rman.${CMD}_doit >$TMPFILE
    echo exit >> $TMPFILE
    WINTITLE="Restoring"
    waitmessage "${red}${blink}Running the restore - don't interrupt now!$NC"
    runcmd "${RMANCONN} < $TMPFILE | tee -a $LOGFILE" "$TMPFILE" "${red}Running full Restore - DO NOT INTERRUPT!$NC"
    finito
    ;;
  restore_ts)
    BACKTITLE="RMan Wrapper: Tablespace Restore"
    WINTITLE="Specify details"
    readval "Specify the tablespace to restore: "
    tsname=$res
    yesno "About to restore/recover tablespace '$tsname'. Is this OK?"
    [ $? -ne 0 ] && abort
    WINTITLE="Verifying..."
    waitmessage "Verifying backup, please wait..."
    echo "RESTORE TABLESPACE $tsname PREVIEW SUMMARY;">>$TMPFILE
    echo "RESTORE TABLESPACE $tsname VALIDATE;">>$TMPFILE
    echo "exit">>$TMPFILE
    runcmd "${RMANCONN} < $TMPFILE | tee -a $LOGFILE" "$TMPFILE"
    WINTITLE="Result from verification - please check carefully!"
    textbox "$SPOOLFILE"
    yesno "Should we continue to recover tablespace '$tsname'?"
    [ $? -ne 0 ] && abort
    echo "SQL 'ALTER TABLESPACE ${tsname} OFFLINE IMMEDIATE';">$TMPFILE
    echo "RESTORE TABLESPACE ${tsname};">>$TMPFILE
    echo "RECOVER TABLESPACE ${tsname};">>$TMPFILE
    echo "SQL 'ALTER TABLESPACE $tsname ONLINE';">>$TMPFILE
    echo "exit">>$TMPFILE
    waitmessage "${red}${blink}Running the restore - don't interrupt now!$NC"
    runcmd "${RMANCONN} < $TMPFILE | tee -a $LOGFILE" "$TMPFILE" "Restoring tablespace $tsname:"
    finito
    ;;
  restore_temp)
    BACKTITLE="RMan Wrapper: Restoring TEMP Tablespace"
    yesno "You are going to recreate the lost TEMP tablespace. Is that correct?"
    [ $? -ne 0 ] && abort
    WINTITLE="TEMP tablespace specification"
    readval "TS Name (${TEMPTS_NAME}):"
    [ -n "$res" ] && TEMPTS_NAME=$res
    readval "Filename (${TEMPTS_FILE}):"
    [ -n "$res" ] && TEMPTS_FILEE=$res
    readval "Size (${TEMPTS_SIZE}):"
    [ -n "$res" ] && TEMPTS_SIZE=$res
    readval "AutoExtend (${TEMPTS_AUTOEXTEND}):"
    [ -n "$res" ] && TEMPTS_AUTOEXTEND=$res
    echo "ALTER DATABASE DEFAULT TEMPORARY TABLESPACE system;">$TMPFILE
    echo "DROP TABLESPACE ${TEMPTS_NAME};">>$TMPFILE
    echo "CREATE TEMPORARY TABLESPACE ${TEMPTS_NAME} TEMPFILE '${TEMPTS_FILE}' REUSE SIZE ${TEMPTS_SIZE} AUTOEXTEND ${TEMPTS_AUTOEXTEND};">>$TMPFILE
    echo "ALTER DATABASE DEFAULT TEMPORARY TABLESPACE ${TEMPTS_NAME};">>$TMPFILE
    echo "exit">>$TMPFILE
    WINTITLE="About to execute the following script (Crtl-C to abort):"
    textbox $TMPFILE
    WINTITLE="TEMP tablespace creation"
    waitmessage "Recreating temporary tablespace, stand by..."
    runcmd "sqlplus / as sysdba <$TMPFILE" "$TMPFILE" "Creating Tablespace:"
    finito
    ;;
  force_clean)
    BACKTITLE="RMan Wrapper: Force Cleanup"
    runconfig $CONFIGUREOPTS
    . ${BINDIR}/mods/force_clean.sub
    finito
    ;;
  move_fra)
    BACKTITLE="RMan Wrapper: Moving the Flash Recovery Area"
    . ${BINDIR}/mods/move_fra.sub
    finito
    ;;
  *)
    help
    exit 1
    ;;
esac

rm -f $TMPFILE
