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

[ -e /etc/rmanrc ] && . /etc/rmanrc
[ -e ${BINDIR}/rmanrc ] && . ${BINDIR}/rmanrc

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
  echo "Syntax: ${SCRIPT} [<Command> [Options]]"
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
  echo "     -h, --help, -?	Display this help screen and exit"
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
  rm -f $TMPFILE.sql
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

#--------------------------------------------------[ Check the environment ]---
[ -z "`which rman`" -o -z "`which sqlplus`" ] && {
  [ -n "$ORACLE_HOME" ] && export PATH=$ORACLE_HOME/bin:$PATH
  [ -z "`which rman`" -o -z "`which sqlplus`" ] && {
    BACKTITLE="RMan Wrapper"
    message "${red}Could not find the rman and/or sqlplus executable!$NC
            \nPlease verify that you are on the machine where your database software
            is installed and your database is running on. If so, also check your
            environment settings - escpecially that you correctly setup your
            \$ORACLE_HOME and \$PATH variables (the latter one must include the
            Oracle binaries path, i.e. \$ORACLE_HOME/bin)."
    abort
  }
}

#-------------------------------------------------------------[ Disclaimer ]---
[ -z "$DISCLAIMER" ] && {
  disclaimer
  echo "DISCLAIMER=DONE">>${BINDIR}/rmanrc
}

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

#------------------------------------------------[ Setup the script to run ]---
if [ -z "$CATALOG" ]; then
  RMANCONN="rman target $username/$passwd"
else
  RMANCONN="rman target $username/$passwd catalog ${CATALOG}"
fi

#==================================================================[ Menus ]===
#----------------------------------------------------[ Display Backup Menu ]---
function backupmenu() {
  BACKTITLE="RMan Wrapper"
  WINTITLE="Backup Menu"
  items=("Please select the action to process:"
         1 "Daily Backup" "Create the \Zbdaily backup\Zn "
         2 "Validate Backup" "Validate existing backups"
         3 "Crosscheck" "Check catalog against existing files"
         4 "Cleanup Obsolete" "Purge backups according to your \ZbRetention Policy\Zn "
         5 "Cleanup Expired" "Purge files \Zbexpired\Zn by crosscheck"
         0 "Back to Main Menu" "Go back to the \ZbMain Menu\Zn ")
  menu "${items[@]}"
  case "$res" in
    1) CMD="backup_daily";;
    2) CMD="validate";;
    3) CMD="crosscheck";;
    4) CMD="cleanup_obsolete";;
    5) CMD="cleanup_expired";;
    0) return;;
  esac
  yesno "Activate Testmode (aka DryRun - just show what would be done, but do not change anything)?"
  [ $? -eq 0 ] && DRYRUN=1
}

#---------------------------------------------------[ Display Restore Menu ]---
function restoremenu() {
  BACKTITLE="RMan Wrapper"
  WINTITLE="Restore Menu"
  items=("Please select the action to process:"
         1 "Recover" "\ZbRecover\Zn database after a crash (does \Zunot\Zn include Restore from Backup!)"
         2 "Restore Controlfile" "Restore a \Zblost controlfile\Zn from multiplex or backup"
         3 "Full Restore" "Restore the \Zbcomplete database\Zn from backup"
         4 "Restore TS" "Restore a \Zbsingle tablespace\Zn from backup"
         5 "Restore Temp" "Restore the \Zbtemporary\Zn tablespace \Zufrom scratch\Zn "
         6 "Block Recover" "Recover a \Zbcorrupted block\Zn in some datafile"
         0 "Back to Main Menu" "Go back to the \ZbMain Menu\Zn ")
  menu "${items[@]}"
  case "$res" in
    1) CMD="recover";;
    2) CMD="restore_ctl";;
    3) CMD="restore_full";;
    4) CMD="restore_ts";;
    5) CMD="restore_temp";;
    6) CMD="block_recover";;
    0) return;;
  esac
  yesno "Activate Testmode (aka DryRun - just show what would be done, but do not change anything)?"
  [ $? -eq 0 ] && DRYRUN=1
}

#---------------------------------------------------[ Display Restore Menu ]---
function miscmenu() {
  BACKTITLE="RMan Wrapper"
  WINTITLE="Miscellaneous Menu"
  items=("Please select the action to process:"
         1 "Move FRA" "Move the \ZbFlash Recovery Area\Zn to a new location"
         2 "Create Standby" "Create a \ZbStandby Database\Zn for the current instance"
         3 "SwitchOver" "Let your primary and standby database \Zbswitch their roles\Zn "
         0 "Back to Main Menu" "Go back to the \ZbMain Menu\Zn ")
  menu "${items[@]}"
  case "$res" in
    1) CMD="move_fra";;
    2) CMD="create_standby";;
    3) CMD="switchover";;
    0) return;;
  esac
  yesno "Activate Testmode (aka DryRun - just show what would be done, but do not change anything)?"
  [ $? -eq 0 ] && DRYRUN=1
}

#------------------------------------------------------[ Display Main Menu ]---
function showmenu() {
  BACKTITLE="RMan Wrapper"
  WINTITLE="Main Menu"
  while [ 1 -eq 1 ]; do
    items=("Please select a submenu:"
           1 "Backup Maintenance" "Create/Validate/Cleanup your Backups"
           2 "Restauration" "\ZbRestore/Recover\Zn database (objects)"
           3 "Miscellaneous" "Move FRA, Create Standby, Switchover..."
           X "Exit" "Do nothing - just get me outa here!")
    menu "${items[@]}"
    case "$res" in
      1) backupmenu;;
      2) restoremenu;;
      3) miscmenu;;
      x|X) finito;;
    esac
    [ -n "$CMD" ] && return
  done
}

#=========================================================[ Process action ]===
# pass "$CMD" to this
function action() {
  [ -z "$LOGFILE" ] && LOGFILE="${LOGDIR}/rman_${1}-`date +\"%Y%m%d_%H%M%S\"`"
  case "$1" in
    create_standby)
      BACKTITLE="RMan Wrapper: Create Standby Database"
      runconfig $CONFIGUREOPTS
      . ${BINDIR}/mods/create_standby.sub
      finito
      ;;
    switchover)
      BACKTITLE="RMan Wrapper: SwitchOver between Standby and Primary"
      . ${BINDIR}/mods/switchover.sub
      finito
      ;;
    validate)
      BACKTITLE="RMan Wrapper: Validation"
      runconfig $CONFIGUREOPTS
      waitmessage "Running Validate..."
      cat ${BINDIR}/rman.$CMD >$TMPFILE
      echo "exit">>$TMPFILE
      runcmd "${RMANCONN} < $TMPFILE | tee -a $LOGFILE" $TMPFILE "Progress of Validation:"
      finito
      ;;
    crosscheck)
      BACKTITLE="RMan Wrapper: CrossCheck"
      runconfig $CONFIGUREOPTS
      waitmessage "Cross-Checking files..."
      cat ${BINDIR}/rman.$CMD >$TMPFILE
      echo "exit">>$TMPFILE
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
      . ${BINDIR}/mods/block_recover.sub
      finito
      ;;
    recover)
      BACKTITLE="RMan Wrapper: Recover"
      . ${BINDIR}/mods/recover.sub
      finito
      ;;
    restore_ctl)
      BACKTITLE="RMan Wrapper: Restore lost controlfiles"
      . ${BINDIR}/mods/restore_ctl.sub
      finito
      ;;
    restore_full)
      BACKTITLE="RMan Wrapper: Full Restore"
      . ${BINDIR}/mods/restore_full.sub
      finito
      ;;
    restore_ts)
      BACKTITLE="RMan Wrapper: Tablespace Restore"
      . ${BINDIR}/mods/restore_ts.sub
      finito
      ;;
    restore_temp)
      BACKTITLE="RMan Wrapper: Restoring TEMP Tablespace"
      . ${BINDIR}/mods/restore_temp.sub
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
}

case "$CMD" in
  help|--help|-h|-?|?)
    help
    exit 1
    ;;
esac
[ -z "$CMD" ] && showmenu
action "$CMD"


rm -f $TMPFILE
