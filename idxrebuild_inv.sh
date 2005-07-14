#!/bin/bash
# $Id$
#
# =============================================================================
# Rebuilds all invalid Indexes in a given TS
# -----------------------------------------------------------------------------
#                                                              Itzchak Rehberg
#
#
if [ -z "$1" ]; then
  SCRIPT=${0##*/}
  echo
  echo "============================================================================"
  echo "${SCRIPT}  (c) 2003-2005 by Itzchak Rehberg & IzzySoft (devel@izzysoft.de)"
  echo "----------------------------------------------------------------------------"
  echo "This script is intended to rebuild all invalid indexes for a given"
  echo "TableSpace. First configure your SYS user / passwd in the 'globalconf' file,"
  echo "then call this script using the following syntax:"
  echo "----------------------------------------------------------------------------"
  echo "Syntax: ${SCRIPT} <ORACLE_SID> [TS] [Options]"
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
param2=`echo $2|cut -c1-1`
if [ "$param2" != "-" -a -n "$2" ]; then
  STS=$2
  suff="$1-$2"
else
  suff="$1-all"
fi
# Read the global config
BINDIR=${0%/*}
CONFIG=$BINDIR/globalconf
. $BINDIR/configure $* -f idxrebuild -x $suff

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

  CURSOR C_INDEX IS
    SELECT index_name,owner
      FROM all_indexes
     WHERE tablespace_name=upper('$STS')
       AND status NOT IN ('VALID','N/A');
  CURSOR C_INDEX_ALL IS
    SELECT index_name,owner
      FROM all_indexes
     WHERE status NOT IN ('VALID','N/A');

PROCEDURE moveidx (line IN VARCHAR2) IS
  TIMESTAMP VARCHAR2(20);
BEGIN
  SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
  dbms_output.put_line('+ '||TIMESTAMP||line);
  EXECUTE IMMEDIATE line;
EXCEPTION
  WHEN OTHERS THEN
    BEGIN
      SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
      dbms_output.put_line('! '||TIMESTAMP||' Rebuild failed ('||SQLERRM||')');
    END;
END;

BEGIN
  VERSION := '$version';
  SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
  IF NVL(LENGTH('$STS'),0) = 0 THEN
    L_LINE := '* '||TIMESTAMP||' Rebuilding all invalid indices in Instance "$ORACLE_SID":';
    dbms_output.put_line(L_LINE);
    FOR Rec_INDEX IN C_INDEX_ALL LOOP
      L_LINE := ' ALTER INDEX "'||Rec_INDEX.owner||'"."'||Rec_INDEX.index_name||
                '" REBUILD';
      moveidx(L_LINE);
    END LOOP;
  ELSE
    L_LINE := '* '||TIMESTAMP||' Rebuilding all invalid indices in TS $STS:';
    dbms_output.put_line(L_LINE);
    FOR Rec_INDEX IN C_INDEX LOOP
      L_LINE := ' ALTER INDEX "'||Rec_INDEX.owner||'"."'||Rec_INDEX.index_name||
                '" REBUILD';
      moveidx(L_LINE);
    END LOOP;
  END IF;
  SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
  L_LINE := '* '||TIMESTAMP||' IdxRebuild v'||VERSION||' exiting normally.';
  dbms_output.put_line(L_LINE);
EXCEPTION
  WHEN OTHERS THEN
    SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
    dbms_output.put_line('! '||TIMESTAMP||' Something weird happened ('||SQLERRM||')');
    dbms_output.put_line('! '||TIMESTAMP||' IdxRebuild v'||VERSION||' crashed normally.');
END;
/

SPOOL off

EOF
