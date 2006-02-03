#!/bin/bash
# $Id$
#
# =============================================================================
# Move Tables to a different TS
# -----------------------------------------------------------------------------
#                                                              Itzchak Rehberg
#
#
if [ -z "$3" ]; then
  SCRIPT=${0##*/}
  echo
  echo "============================================================================"
  echo "${SCRIPT}  (c) 2003-2006 by Itzchak Rehberg & IzzySoft (devel@izzysoft.de)"
  echo "----------------------------------------------------------------------------"
  echo "This script is intended to move all tables from one tablespace into another"
  echo "TableSpace. First configure your user / passwd in the 'globalconf' file,"
  echo "then call this script using the following syntax:"
  echo "----------------------------------------------------------------------------"
  echo "Syntax: ${SCRIPT} <ORACLE_SID> <SourceTS> <TargetTS> [Options]"
  echo "  Options:"
  echo "     -c <alternative ConfigFile>"
  echo "     -p <Password>"
  echo "     -s <ORACLE_SID/Connection String for Target DB>"
  echo "     -u <username>"
  echo "     --force"
  echo "----------------------------------------------------------------------------"
  echo "The table is first tried to be moved with the ONLINE option (i.e., it is"
  echo "still available to the users during the move process). If this, however,"
  echo "fails, an error message is written to the log. Following this, a table move"
  echo "without the ONLINE option is tried only if you specified the '--force'"
  echo "command line option."
  echo "============================================================================"
  echo
  exit 1
fi

# =================================================[ Configuration Section ]===
# Eval params
STS=$2
TTS=$3
# Read the global config
BINDIR=${0%/*}
CONFIG=$BINDIR/globalconf
. $BINDIR/configure $* -f tabmov

# ====================================================[ Script starts here ]===
version='0.1.5'
$ORACLE_HOME/bin/sqlplus -s /NOLOG <<EOF

CONNECT $user/$password@$ORACLE_CONNECT
Set TERMOUT ON
Set SCAN OFF
Set SERVEROUTPUT On Size 1000000
Set LINESIZE 300
Set TRIMSPOOL On 
Set FEEDBACK OFF
Set Echo Off
SPOOL $SPOOL

DECLARE
  L_LINE VARCHAR(4000);
  TIMESTAMP VARCHAR2(20);
  VERSION VARCHAR2(20);

  CURSOR C_TAB IS
    SELECT table_name,owner
      FROM all_tables
     WHERE lower(tablespace_name)=lower('$STS');

PROCEDURE movetab (line IN VARCHAR2, tts IN VARCHAR2) IS
BEGIN
  SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
  dbms_output.put_line('+ '||TIMESTAMP||line|| 'ONLINE ' ||tts);
  EXECUTE IMMEDIATE line||'ONLINE '||tts;
EXCEPTION
  WHEN OTHERS THEN
    BEGIN
      SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
      dbms_output.put_line('- '||TIMESTAMP||SQLERRM);
      IF ($force=1) THEN
        dbms_output.put_line('+ '||TIMESTAMP||line||tts);
        dbms_output.put_line(line||tts);
        EXECUTE IMMEDIATE line||tts;
      END IF;
    EXCEPTION
      WHEN OTHERS THEN
        SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
        dbms_output.put_line('! '||TIMESTAMP||' ALTER TABLE failed ('||SQLERRM||')');
    END;
END;

BEGIN
  VERSION := '$version';
  SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
  L_LINE := '* '||TIMESTAMP||' Moving all tables from TS $STS to TS $TTS:';
  dbms_output.put_line(L_LINE);
  FOR Rec_Tab IN C_TAB LOOP
    L_LINE := ' ALTER TABLE "'||Rec_Tab.owner||'"."'||Rec_Tab.table_name||
              '" MOVE ';
    movetab(L_LINE,'TABLESPACE $TTS');
  END LOOP;
  SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
  dbms_output.put_line('* '||TIMESTAMP||' TabMove v'||VERSION||' exiting normally.');
EXCEPTION
  WHEN OTHERS THEN
    SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
    dbms_output.put_line('! '||TIMESTAMP||' Something weird happened ('||SQLERRM||')');
    dbms_output.put_line('! '||TIMESTAMP||' TabMove v'||VERSION||' crashed normally.');
END;
/

SPOOL off

EOF
