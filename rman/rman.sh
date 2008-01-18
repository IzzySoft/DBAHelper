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
typeset -i SILENT=0
YESTOALL=0
NOHEAD=0

. ${BINDIR}/rmanrc

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
  echo "RMAN wrapper            (c) 2007-2008 by Itzchak Rehberg (devel@izzysoft.de)"
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
  echo "     --dryrun		Don't do anything, just show what would be done"
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
#-----------------------------------------------[ Show progress (or don't) ]---
function say {
  [ $SILENT -lt 3 ] && echo -e "$1"
}

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
    say "${blue}* Process canceled.$NC"
    exit 0
  }
  echo
}

#---------------------------------------[ Normal exit after completed work ]---
function finito {
  say "${blue}Task completed.$NC"
  exit 0
}

#------------------------------------------[ Display introductional header ]---
function header {
  [ $NOHEAD -eq 0 ] && {
    [ $SILENT -lt 3 ] && clear
    say "${blue}RMAN Wrapper Script"
    say "-------------------${NC}"
    say
    if [ $DRYRUN -eq 0 ]; then
      say "Running $CMD"
    else
      say "Running $CMD (Dryrun)"
    fi
  }
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
    say "${blue}The configuration file has been changed (or never run before), so we may"
    say "need to configure the RMAN settings. Running the configuration commands now:$NC"
    ${RMANCONN} < $CONFIG | tee -a $LOGFILE
    touch ~/.rman_configured
  }
}

#---------------------------------[ Run or display CMD depending on DRYRUN ]---
# $1 - CMD
# $2 - Scriptfile to display when in dryrun
function runcmd {
  if [ $DRYRUN -eq 0 ]; then
    case $SILENT in
      0) cmd="$1";;
      1) cmd="$1 > /dev/null";;
      2) cmd="$1 &> /dev/null";;
    esac
    eval $cmd
  else
    SILENT=0
    say "${blue}Running command: ${NC}$1"
    [ -n "$2" ] && {
      say "${blue}Scriptfile content:$NC"
      cat $2
    }
  fi
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
    --dryrun)  DRYRUN=1;;
    --force-configure) CONFIGUREOPTS=force;;
    --yestoall) YESTOALL=1;;
    --noheader) NOHEAD=1;;
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
header
case "$CMD" in
  create_standby)
    # Introductional information
    say "${blue}In order to create a standby database, we first need some data."
    say "Please make sure that:"
    echo
    say "- you run this script on the host of your PRIMARY database"
    say "- your primary database is up and running (opened or mounted)"
    say "- on the host of your standby database, ALL necessary directories"
    say "  (for datafiles, logs, etc) are created and have the correct permissions"
    say "- either the directory structure is the same on both databases,"
    say "  or you took care for the changed names in your init.ora file"
    say "  (DB_FILE_NAME_CONVERT, LOG_FILE_NAME_CONVERT). In the latter case,"
    say "  please remove the 'NOFILENAMECHECK' option from the copy command"
    say "  in the rman.create_standby file."
    say "- you checked the _DEST and _PATH statements in the init.ora file"
    say "  of both databases (at this time, most important on the standby)"
    echo
    echo -en "Are this conditions ALL met (y/n)? $NC"
    yesno
    stayorgo
    # Forced Logging
    say "${blue}In order to protect direct writes, which are unlogged and thus would not"
    say "be propagated to the standby database, you need to have forced logging enabled"
    echo -en "on the master (primary) database. Shall we do this now (y/n)? $NC"
    yesno
    [ "$res" = "y" ] && {
      echo "ALTER DATABASE FORCE LOGGING;">$TMPFILE.sql
      runcmd "sqlplus / as sysdba <$TMPFILE.sql" | tee -a "$LOGFILE"
      rm -f $TMPFILE.sql
    }
    echo
    # Make sure we have all backups + controlfile available
    say "${blue}Did you create the control file for the standby database (y/n)?"
    echo -en "(If you are not sure, you did not) $NC"
    yesno
    [ "$res" = "n" ] && {
      say "${blue}So we create the control file now:$NC"
      echo "BACKUP CURRENT CONTROLFILE FOR STANDBY;">$TMPFILE
      $RMANCONN <$TMPFILE | tee -a "$LOGFILE"
      [ $? -ne 0 ] && {
        say "${red}Some error occured creating the standby controlfile - aborting.$NC"
        exit 1
      }
    }
    echo -en "${blue}We also need a full database backup. You want to create one now (y/n)? $NC"
    yesno
    [ "$res" = "y" ] && {
      $0 backup_daily
      say "${blue}If the backup was made successfully, we can continue creating the"
      say "Standby Database. If there have been errors (ignore the"
      say "'RMAN-20207: UNTIL TIME or RECOVERY WINDOW is before RESETLOGS time' on a"
      say "database you just created within that time), this is the time to abort."
      echo -en "Continue (y/n)? "
      yesno
      stayorgo
    } || echo
    # Last hints about availability master/client (mount/nomount)
    say "${blue}Now, please make sure that:"
    say "- you started the (not yet existing) standby database NOMOUNT using the"
    say "  adjusted init.ora"
    say "- the backup files are LOCALLY available on the standby machine (you may"
    say "  need to copy them there)"
    say "- you can reach your standby database from the primary host via"
    say "  Oracle Net (configured in tnsnames.ora / Oracle Names / ...)"
    echo
    echo -en "Are this conditions ALL met (y/n)? $NC"
    yesno
    stayorgo
    # Query standby data from user
    say "${blue}Please specify the standby database:$NC"
    read -p "TNS name       : " tnsname
    read -s -p "SYS password   : " syspwd
    echo
    read -s -p "Repeat password: " syspwd2
    echo
    [ "$syspwd" != "$syspwd2" ] && {
      say "${red}The entered passwords are not identical - aborting!$NC"
      exit 1
    }
    # Test Oracle Net for specified standby tns name
    dummy=`tnsping $tnsname`
    [ $? -ne 0 ] && {
      say "${red}The specified database is not available via Oracle Net - aborting!$NC"
      exit 1
    }
    # Creating the standby database
    say "${blue}Creating the standby database now...$NC"
    RMANCONN="$RMANCONN auxiliary sys/$syspwd@$tnsname"
    runcmd "$RMANCONN < $BINDIR/rman.$CMD" | tee -a "$LOGFILE"
    # Final notes
    say "${blue}If there have been no errors displayed: Congratulations, your new standby"
    say "database should be ready! However, there is some work left to you (and to your"
    say "decision):"
    say "- you need to start managed recovery on the standby database"
    say "- you need to make sure that this step is done automatically on server start"
    say "- you should make sure that the master is feeding your standby with redo"
    say
    # Optionally start managed recovery
    echo -en "Do you want to start managed recovery on the standby DB now (y/n)? $NC"
    yesno
    [ "$res" = "y" ] && {
      echo "ALTER DATABASE RECOVER MANAGED STANDBY DATABASE DISCONNECT;">$TMPFILE.sql
      runcmd "sqlplus sys/$syspwd@$tnsname as sysdba <$TMPFILE.sql" | tee -a "$LOGFILE"
      rm -f $TMPFILE.sql
    }
    echo
    finito
    ;;
  backup_daily|validate|crosscheck)
    runcmd "${RMANCONN} < $TMPFILE | tee -a $LOGFILE"
    ;;
  cleanup_expired)
    runcmd "${RMANCONN} < $TMPFILE | tee -a $LOGFILE"
    say "${blue}The long list on top shows the process of crosschecking. At the end of the"
    say "crosscheck, tables are displayed listing the expired objects, i.e. those are no"
    say "longer available on the disks, but still in the catalog/controlfile. To keep the"
    say "records small (especially when you are not using a catalog DB but the control files"
    say "to record your backups), we can purge them from the catalog/controlfile. Since they"
    say "do not exist anymore, those records are useless.$NC"
    echo -en "${blue}Do you want to purge the expired records now (y/n)? $NC"
    yesno
    if [ "$res" = "y" ]; then
      say "${blue}Purging catalog/controlfile:$NC"
      cat $BINDIR/rman.${CMD}_doit > $TMPFILE
      echo exit >> $TMPFILE
      runcmd "${RMANCONN} < $TMPFILE | tee -a $LOGFILE" "$TMPFILE"
    else
      say "${blue}Skipping purge process for expired records.$NC"
    fi
    finito
    ;;
  cleanup_obsolete)
    say "${blue}Going to list obsolete files:$NC"
    runcmd "${RMANCONN} < $TMPFILE | tee -a $LOGFILE" "$TMPFILE"
    say "${blue}Above tables list the obsolete files - i.e. those which are outdated"
    say "according to your retention policy. To free diskspace (and keep your records"
    say "small especially when not using a catalog DB), you can purge them now, i.e."
    say "removing them from the disk and catalog/controlfile.$NC"
    echo -en "${blue}Do you want to purge the obsolete files and records now (y/n)? $NC"
    yesno
    if [ "$res" = "y" ]; then
      say "${blue}Purging files and catalog/controlfile:$NC"
      cat $BINDIR/rman.${CMD}_doit > $TMPFILE
      echo exit >> $TMPFILE
      runcmd "${RMANCONN} < $TMPFILE | tee -a $LOGFILE" "$TMPFILE"
    else
      say "${blue}Skipping purge process for obsolete files and records.$NC"
    fi
    finito
    ;;
  block_recover)
    say "${blue}* You asked for a block recovery. Please provide the required data"
    say "  (you probably find them either in the application which alerted you about"
    say "  the problem, or at least in the alert log. Look out for a message like$NC"
    say "    ORA-1578: ORACLE data block corrupted (file # 6, block # 1234)"
    readnr "Please enter the file #"
    fileno=$nr
    readnr "Please enter the block #"
    blockno=$nr
    echo -en "  ${blue}Going to recover block # $blockno for file # $fileno. Continue (y/n)?$NC "
    yesno
    stayorgo
    echo "BLOCKRECOVER DATAFILE $fileno BLOCK $blockno;" > $TMPFILE
    echo exit >> $TMPFILE
    runcmd "${RMANCONN} < $TMPFILE | tee -a $LOGFILE"
    finito
    ;;
  recover)
    say "${blue}* Test whether a fast recovery is possible:$NC"
    runcmd "${RMANCONN} < $TMPFILE | tee -a $LOGFILE"
    say "${blue}Please check above output for errors. A line like$NC"
    say "  ORA-01124: cannot recover data file 1 - file is in use or recovery"
    say "${blue}means the database is still up and running, and you rather should check"
    say "the alert log for what is broken and e.g. recover that tablespace"
    say "explicitly with \"${0##*/} recover_ts\". Don't continue in this case;"
    say "it would fail either.$NC"
    echo -en "${blue}Continue with the recovery (y/n)?$NC "
    yesno
    stayorgo
    say "${blue}OK, so we go to do a 'Fast Recovery' now, stand by...$NC"
    cat $BINDIR/rman.${CMD}_doit >$TMPFILE
    echo exit >> $TMPFILE
    echo -e "${red}${blink}Running the recover process - don't interrupt now!$NC"
    runcmd "${RMANCONN} < $TMPFILE | tee -a $LOGFILE"
    finito
    ;;
  restore_full)
    say "${blue}* Verify backup and show what WOULD be done:$NC"
    runcmd "${RMANCONN} < $TMPFILE | tee -a $LOGFILE"
    echo -en "${blue}Above actions will be taken if you continue. Are you sure (y/n)?$NC "
    yesno
    stayorgo
    say "${blue}You decided to restore the database '$ORACLE_SID' from the displayed backup."
    say "Hopefully, you've been studying the output carefully - in case some data may"
    say "not be recoverable, it should have been displayed. Otherwise, you may not be"
    say "able to restore to the latest state (some of the last transactions may be lost"
    say "then). Last chance to abort, so:$NC"
    echo -en "${red}Are you really sure to run the restore process (y/n)?$NC "
    yesno
    stayorgo
    cat $BINDIR/rman.${CMD}_doit >$TMPFILE
    echo exit >> $TMPFILE
    echo -e "${red}${blink}Running the restore - don't interrupt now!$NC"
    runcmd "${RMANCONN} < $TMPFILE | tee -a $LOGFILE"
    finito
    ;;
  restore_ts)
    say "${blue}* Verify backup and show what WOULD be done:$NC"
    read -p "Specify the tablespace to restore: " tsname
    echo -en "${blue}About to restore/recover tablespace '$tsname'. Is this OK (y/n)? $NC"
    yesno
    stayorgo
    say "${blue}* Verify backup and show what WOULD be done:$NC"
    echo "RESTORE TABLESPACE $tsname PREVIEW SUMMARY;">>$TMPFILE
    echo "RESTORE TABLESPACE $tsname VALIDATE;">>$TMPFILE
    echo "exit">>$TMPFILE
    runcmd "${RMANCONN} < $TMPFILE | tee -a $LOGFILE" "$TMPFILE"
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
    runcmd "${RMANCONN} < $TMPFILE | tee -a $LOGFILE"
    finito
    ;;
  restore_temp)
    echo -en "${blue}You are going to recreate the lost TEMP tablespace. Is that correct (y/n)?$NC "
    yesno
    stayorgo
    say "${blue}Please confirm the data for the temporary tablespace:"
    echo -en "* Name (${TEMPTS_NAME}): $NC"
    read input
    [ -n "$input" ] && TEMPTS_NAME=$input
    echo -en "${blue}Filename (${TEMPTS_FILE}): $NC"
    read input
    [ -n "$input" ] && TEMPTS_FILEE=$input
    echo -en "${blue}Size (${TEMPTS_SIZE}): $NC"
    read input
    [ -n "$input" ] && TEMPTS_SIZE=$input
    echo -en "${blue}AutoExtend (${TEMPTS_AUTOEXTEND}): $NC"
    read input
    [ -n "$input" ] && TEMPTS_AUTOEXTEND=$input
    say "${blue}Recreating temporary tablespace, stand by...$NC"
    echo "ALTER DATABASE DEFAULT TEMPORARY TABLESPACE system;">$TMPFILE
    echo "DROP TABLESPACE ${TEMPTS_NAME};">>$TMPFILE
    echo "CREATE TEMPORARY TABLESPACE ${TEMPTS_NAME} TEMPFILE '${TEMPTS_FILE}' REUSE SIZE ${TEMPTS_SIZE} AUTOEXTEND ${TEMPTS_AUTOEXTEND};">>$TMPFILE
    echo "ALTER DATABASE DEFAULT TEMPORARY TABLESPACE ${TEMPTS_NAME};">>$TMPFILE
    echo "exit">>$TMPFILE
    runcmd "sqlplus / as sysdba <$TMPFILE" "$TMPFILE"
    finito
    ;;
  force_clean)
    say "${blue}Checking for obsolete level x backups (not having a parent full backup):$NC"
    say "${blue}* Obtaining info about oldest available full backup...$NC"
    #
    # obtaining oldest available full backup
    echo "LIST COPY OF DATABASE;" | $RMANCONN > $TMPFILE
    while read line; do
      status=`echo $line | awk '{ print $3 }'`
      [ "$status" != "A" ] && continue
      fkey=`echo $line | awk '{ print $1 }'`
      break
    done<$TMPFILE
    if [ -z "$fkey" ]; then
      echo -e "${red}Looks like you don't have any full backup!$NC"
      echo -e "${blue}Suggest you make some backups before purging them :)$NC"
      exit 1
    fi
    #
    # Check database for backups older than the latest full backup (copy)
    say "${blue}* Checking database for backups older than this...$NC"
    echo "SET HEAD OFF FEEDBACK OFF LINES 6000 PAGES 0 TRIMSPOOL ON">$TMPFILE
    echo "SELECT bs_key,handle,size_bytes_display,TO_CHAR(completion_time,'YYYY-MM-DD HH24:MI') datum FROM v\$backup_piece_details WHERE start_time < (SELECT MIN(min_checkpoint_time) FROM v\$backup_copy_summary);">>$TMPFILE
    sqlplus -s / as sysdba<$TMPFILE>out.$$
    typeset i idx=0
    while read line; do
      key=`echo $line | awk '{print $1}'`
      [ -n "$key" ] && {
        obskey[$idx]=$key
	obsfile[$idx]=`echo $line | awk '{print $2}'`
	obssize[$idx]=`echo $line | awk '{print $3}'`
        datum[${bskey[$key]}]=`echo $line | awk '{ print $4" "$5 }'`
	bskey[$key]=$idx
	let idx=$idx+1
      }
    done<out.$$
    rm -f out.$$
    #
    # Compare collected info with RMAN backup summary
    say "${blue}* Synchronizing collected information with RMAN information...$NC"
    echo "LIST BACKUP SUMMARY;" | $RMANCONN > $TMPFILE
    typeset i idx=0
    while read line; do
      key=`echo $line | awk '{ print $1 }'`
      [[ ${key:0:1} == [0-9] ]] || continue;
      [ $key -gt $fkey ] && break
      levl=`echo $line | awk '{ print $3 }'`
      level[${bskey[$key]}]=$levl
      if [ "$levl" = "F" ]; then
        desc[${bskey[$key]}]="Full backup of datafile or control file"
	type[${bskey[$key]}]="full"
      elif [ "$levl" = "0" ]; then
        desc[${bskey[$key]}]="Incremental base backup (level 0)"
	type[${bskey[$key]}]="full"
      else
        desc[${bskey[$key]}]="Incremental backup (level $levl)"
	type[${bskey[$key]}]="inc"
      fi
    done<$TMPFILE
    #
    # Presenting results and asking for actions
    if [ ${#obskey[*]} -gt 0 ]; then
      say "First full backup (datafile copy) has key ${fkey}."
      say "Following orphaned/older backups were found:"
      say
      idx=0
      echo "Key   Date             Size     Description"
      echo "------------------------------------------------"
      while [ $idx -lt ${#obskey[*]} ]; do
        printf "%5i %-16s %8s %-30s\n" ${obskey[$idx]} "${datum[$idx]}" ${obssize[$idx]} "${desc[$idx]}"
	let idx=$idx+1
      done
      say
      echo -en "${blue}You want to purge ALL these orphans (y/n)? $NC"
      yesno
      if [ "$res" != "y" ]; then
        echo -en "${blue}What do you want to purge: (F)ull (incl. level 0), (I)ncremental, or (N)one? "
	read -n 1 -p "" ready
        echo
        lva=`echo $ready|tr [:upper:] [:lower:]`
      else
        lva='a'
      fi
      #
      # Running the purge process
      if [[ $lva == [afi] ]]; then
        case "$lva" in
	  a) say "${blue}Purging orphaned backups...$NC";;
	  f) say "${blue}Purging old full backups...$NC";;
	  i) say "${blue}Purging orphaned incremental backups...$NC"
	esac
        cat /dev/null > $TMPFILE
        idx=0
        while [ $idx -lt ${#obskey[*]} ]; do
	  purgeit=0
	  case "$lva" in
	    f) [ "${level[$idx]}" = 'F' ] && purgeit=1;;
	    i) [[ ${level[$idx]} == [0-9] ]] && purgeit=1;;
	    a) purgeit=1;;
	  esac
          [ $purgeit -eq 1 ] && echo "DELETE NOPROMPT BACKUPSET ${obskey[$idx]};" >> $TMPFILE
          let idx=$idx+1
        done
        runcmd "${RMANCONN} < $TMPFILE | tee -a $LOGFILE"
      else
        say "${blue}* Skipping removal of orphaned backups.$NC"
      fi
    elif [ -n "$key" ]; then
      say "First full backup has key ${fkey}. We found no older backups."
    fi
    #
    # Checking whether to purge archive logs as well
    echo -e "${blue}Shall we also look for forgotten archive logs, i.e. those completed"
    echo -en "before the first full backup was started (y/n)? $NC"
    yesno
    stayorgo
    echo "SET HEAD OFF">$TMPFILE
    echo "SELECT TO_CHAR(start_time,'YYYY-MM-DD HH24:MI:SS') FROM v\$backup_piece_details WHERE bs_key=$fkey;">>$TMPFILE
    fdat=`sqlplus -s / as sysdba<$TMPFILE`
    fdat=`echo $fdat|sed 's/\n//g'`
    runcmd "echo \"DELETE NOPROMPT ARCHIVELOG ALL COMPLETED BEFORE \\\"TO_DATE('$fdat','YYYY-MM-DD HH24:MI:SS')\\\";\"|${RMANCONN} | tee -a $LOGFILE"
    finito
    ;;
  move_fra)
    say "${blue}Move Flash Recovery Area to a new location:$NC"
    res="`echo \"set head off
        select value from v\\$parameter where name='db_recovery_file_dest';\"|sqlplus -s '/ as sysdba'|sed -n '/^\/.*/p'`"
    say
    echo -en "${blue}Current location of the FRA ($res): $NC"
    read oldfra
    [ -z "$oldfra" ] && oldfra="$res"
    echo -en "${blue}New location of the FRA: $NC"
    read newfra
    [ ! -d "$newfra" ] && {
      say "${blue}You specified '$newfra' as new location."
      echo -en "This directory does not exist. Create it (y/n) ? $NC"
      yesno
      [ "$res" != "y" ] && {
        say "${red}Sorry - in this case we cannot do anything for you.$NC"
	finito
      }
      runcmd "mkdir -p \"$newfra\""
    }
    echo
    say "${blue}Altering the database to use the new destination. Which database"
    echo -en "(ORACLE_SID) should we alter ($ORACLE_SID)? $NC"
    read res
    [ -n "$res" ] && export ORACLE_SID=$res
    say "${blue}Altering $ORACLE_SID to use $newfra as new recovery area...$NC"
    runcmd "echo \"ALTER SYSTEM SET DB_RECOVERY_FILE_DEST='$newfra';\"|sqlplus -s '/ as sysdba'"
    say
    echo -en "${blue}If there where no errors, we can continue. Should we (y/n)? $NC"
    yesno
    stayorgo
    say "${blue}Moving the files from the old FRA to the new one...$NC"
    oldfra=`echo $oldfra|sed 's/ /\\\ /'`
    newfra=`echo $newfra|sed 's/ /\\\ /'`
    echo "mv $oldfra/* $newfra"
    runcmd "mv $oldfra/* $newfra"
    echo -en "${blue}If there where no errors, we can continue. Should we (y/n)? $NC"
    yesno
    stayorgo
    say "${blue}Now we must update our 'catalog' (controlfile) with the changed"
    say "location. Therefore we first unregister the old one, and then register"
    say "the new - so do not get a shock and think all your files are gone, as"
    say "it may look like this at first (since RMAN looks at the old location)."
    say
    say "=> Unregistering the old location now...$NC"
    sleep 1
    [ $DRYRUN -eq 0 ] && res="" || res="--dryrun"
    $0 crosscheck --noheader $res
    $0 cleanup_expired --noheader $res
    say "${blue}=> Registering the new location...$NC"
    sleep 1
    echo "CATALOG RECOVERY AREA NOPROMPT;">$TMPFILE
    echo "exit">>$TMPFILE
    runcmd "${RMANCONN} <$TMPFILE" "$TMPFILE"
    say "${blue}If there have been no errors, you successfully moved your FRA"
    say "to the new location. Congratulations!$NC"
    ;;
  *)
    help
    exit 1
    ;;
esac

rm -f $TMPFILE
