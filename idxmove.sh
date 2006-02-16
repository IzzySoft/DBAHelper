#!/bin/bash
# $Id$
#
# =============================================================================
# Move Indexes to a different TS
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
  echo "This script is intended to move all indexes for one schema into a different"
  echo "TableSpace. First configure your user / passwd in the 'globalconf' file,"
  echo "then call this script using the following syntax:"
  echo "----------------------------------------------------------------------------"
  echo "Syntax: ${SCRIPT} <ORACLE_SID> <SourceTS> <TargetTS> [Options]"
  echo "  Options:"
  echo "     -c <alternative ConfigFile>"
  echo "     -p <Password>"
  echo "     -s <ORACLE_SID/Connection String for Target DB>"
  echo "     -u <username>"
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
. $BINDIR/configure $* -f idxmov

# ====================================================[ Script starts here ]===
version='0.1.7'
$ORACLE_HOME/bin/sqlplus -s /NOLOG <<EOF

CONNECT $user/${password}$ORACLE_CONNECT
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

  CURSOR C_INDEX IS
    SELECT index_name,owner
      FROM all_indexes
     WHERE (lower(index_type)='normal' OR lower(index_type)='bitmap')
       AND lower(tablespace_name)=lower('$STS');

PROCEDURE moveidx (line IN VARCHAR2) IS
  TIMESTAMP VARCHAR2(20);
BEGIN
  SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
  dbms_output.put_line('+ '||TIMESTAMP||line||' ONLINE');
  EXECUTE IMMEDIATE line||' ONLINE';
EXCEPTION
  WHEN OTHERS THEN
    BEGIN
      SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
      dbms_output.put_line('- '||TIMESTAMP||' '||SQLERRM);
      dbms_output.put_line(CHR(32)||' '||TIMESTAMP||' '||line);
      EXECUTE IMMEDIATE line;
    EXCEPTION
      WHEN OTHERS THEN
        SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
        dbms_output.put_line('! '||TIMESTAMP||' ALTER INDEX failed ('||SQLERRM||')');
    END;
END;

BEGIN
  VERSION := '$version';
  SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
  L_LINE := '* '||TIMESTAMP||' Moving all indices from TS $STS to TS $TTS:';
  dbms_output.put_line(L_LINE);
  FOR Rec_INDEX IN C_INDEX LOOP
    L_LINE := ' ALTER INDEX "'||Rec_INDEX.owner||'"."'||Rec_INDEX.index_name||
              '" REBUILD TABLESPACE $TTS';
    moveidx(L_LINE);
  END LOOP;
  SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
  L_LINE := '* '||TIMESTAMP||' IdxMove v'||VERSION||' exiting normally.';
  dbms_output.put_line(L_LINE);
EXCEPTION
  WHEN OTHERS THEN
    SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
    dbms_output.put_line('! '||TIMESTAMP||' Something weird happened ('||SQLERRM||')');
    dbms_output.put_line('! '||TIMESTAMP||' IdxMove v'||VERSION||' crashed normally.');
END;
/

SPOOL off

EOF
