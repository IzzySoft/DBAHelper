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
  echo ============================================================================
  echo "${SCRIPT}       (c) 2003 by Itzchak Rehberg & IzzySoft (devel@izzysoft.de)"
  echo ----------------------------------------------------------------------------
  echo This script is intended to move all indexes for one schema into a different 
  echo TableSpace. First configure your SYS user / passwd inside this script, then
  echo call this script using the following syntax:
  echo ----------------------------------------------------------------------------
  echo "Syntax: ${SCRIPT} <ORACLE_SID> <SourceTS> <TargetTS>"
  echo ============================================================================
  echo
  exit 1
fi

# =================================================[ Configuration Section ]===
# Eval params
export ORACLE_SID=$1
STS=$2
TTS=$3
# login information
user=sys
password="pyha#"
# name of the file to write the log to (or 'OFF' for no log). This file will
# be overwritten without warning!
SPOOL="tabmov__$1-$2-$3.spool"

# ====================================================[ Script starts here ]===
version='0.1.0'
$ORACLE_HOME/bin/sqlplus -s /NOLOG <<EOF

CONNECT $user/$password@$1
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

  CURSOR C_TAB IS
    SELECT table_name,owner
      FROM all_tables
     WHERE lower(tablespace_name)=lower('$STS');

PROCEDURE movetab (line IN VARCHAR2, tts IN VARCHAR2) IS
BEGIN
  dbms_output.put_line(line|| 'ONLINE ' ||tts);
  EXECUTE IMMEDIATE line||'ONLINE '||tts;
EXCEPTION
  WHEN OTHERS THEN
    dbms_output.put_line(line||tts);
    EXECUTE IMMEDIATE line||tts;
END;

BEGIN
  L_LINE := 'Moving all tables from TS $STS to TS $TTS:';
  dbms_output.put_line(L_LINE);
  FOR Rec_Tab IN C_TAB LOOP
    L_LINE := ' ALTER TABLE '||Rec_Tab.owner||'.'||Rec_Tab.table_name||
              ' MOVE ';
    movetab(L_LINE,'TABLESPACE $TTS');
  END LOOP;
  L_LINE := '...done.';
  dbms_output.put_line(L_LINE);
END;
/

SPOOL off

EOF
