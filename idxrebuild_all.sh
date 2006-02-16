#!/bin/bash
# $Id$
#
# =============================================================================
# Rebuilds all Indexes in a given TS
# -----------------------------------------------------------------------------
#                                                              Itzchak Rehberg
#
#
if [ -z "$1" ]; then
  SCRIPT=${0##*/}
  echo
  echo "============================================================================"
  echo "${SCRIPT}  (c) 2003-2006 by Itzchak Rehberg & IzzySoft (devel@izzysoft.de)"
  echo "----------------------------------------------------------------------------"
  echo "This script is intended to rebuild all indexes for a given TableSpace plus"
  echo "runs a coalesce on that TS 3 times during this process depending on the"
  echo "amount of indices/bytes processed. It starts with the smallest index to make"
  echo "use of the coalesced space for the bigger ones. First we try to rebuild"
  echo "online -- if that fails, we try without the online option (which by default"
  echo "is disabled; use the --force option to override). Indices using 1 extent"
  echo "only are ignored."
  echo "Please configure your user / passwd in the 'globalconf' file, then call this"
  echo "script using the following syntax:"
  echo "----------------------------------------------------------------------------"
  echo "Syntax: ${SCRIPT} <ORACLE_SID> [TS] [Options]"
  echo "  Options:"
  echo "     -c <alternative ConfigFile>"
  echo "     -p <Password>"
  echo "     -s <ORACLE_SID/Connection String for Target DB>"
  echo "     -u <username>"
  echo "     --force"
  echo "     --noadjust"
  echo "============================================================================"
  echo
  exit 1
fi

# =================================================[ Configuration Section ]===
# Adjust initial extent size according index size (if not called w/ "--noadjust"):
# small <= 256k; medium <= 5M; large <= 100M <= xxl
INIT_SMALL="64k"
NEXT_SMALL="64k"
INIT_MEDIUM="512k"
NEXT_MEDIUM="128k"
INIT_LARGE="10M"
NEXT_LARGE="1M"
INIT_XXL="100M"
NEXT_XXL="10M"
adjust=1 
force=0
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
version='0.1.8'
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
  SIZE_ALL NUMBER; -- bytes to process all together
  SIZE_DONE NUMBER; -- bytes already processed
  NUM_ALL NUMBER; -- count of indices to process all together
  NUM_DONE NUMBER; -- count of indices already processed
  COALA NUMBER; -- how many times we did coalesce
  ADJUST VARCHAR2(200); -- storage clause to adjust initial extent size

  CURSOR C_INDEX IS
    SELECT segment_name,owner,bytes
      FROM dba_segments
     WHERE tablespace_name=upper('$STS')
       AND segment_type='INDEX'
       AND extents>1
       AND owner NOT IN ('SYS','SYSTEM')
     ORDER BY bytes;
  CURSOR C_INDEX_ALL IS
    SELECT segment_name,owner,bytes
      FROM dba_segments
     WHERE segment_type='INDEX'
       AND extents>1
       AND owner NOT IN ('SYS','SYSTEM')
     ORDER BY bytes;

PROCEDURE moveidx (line IN VARCHAR2) IS
  TIMESTAMP VARCHAR2(20);
BEGIN
  SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
  dbms_output.put_line('+ '||TIMESTAMP||line||' ONLINE '||ADJUST);
  EXECUTE IMMEDIATE line||' ONLINE '||ADJUST;
EXCEPTION
  WHEN OTHERS THEN
    BEGIN
      IF ($force=1) THEN
        SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
        dbms_output.put_line('- '||TIMESTAMP||line||' '||ADJUST);
        EXECUTE IMMEDIATE line||' '||ADJUST;
      ELSE
        SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
        dbms_output.put_line('! '||TIMESTAMP||' Rebuild failed ('||SQLERRM||')');
      END IF;
    EXCEPTION
      WHEN OTHERS THEN
        BEGIN
          SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
          dbms_output.put_line('! '||TIMESTAMP||' Rebuild failed ('||SQLERRM||')');
        END;
    END;
END;

PROCEDURE do_coala(ts IN VARCHAR2) IS
  TIMESTAMP VARCHAR2(20);
  LLINE VARCHAR2(255);
BEGIN
  IF (COALA=0 AND (NUM_DONE>NUM_ALL/2 OR SIZE_DONE>SIZE_ALL/3)
   OR COALA=1 AND ((NUM_DONE>3*NUM_ALL/4) OR (SIZE_DONE>2*SIZE_ALL/3))
   OR COALA=2 AND (NUM_DONE=NUM_ALL OR SIZE_DONE=SIZE_ALL))
  THEN
    SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
    LLINE := 'ALTER TABLESPACE '||ts||' COALESCE';
    dbms_output.put_line('+ '||TIMESTAMP||' '||LLINE);
    EXECUTE IMMEDIATE LLINE;
    COALA := COALA +1;
  END IF;
EXCEPTION
  WHEN OTHERS THEN NULL;
END;

PROCEDURE adjust_clause (osize IN NUMBER) IS
BEGIN
  IF $adjust = 1 THEN
    IF osize < 262144 THEN
      ADJUST := 'STORAGE ( INITIAL $INIT_SMALL NEXT $NEXT_SMALL )';
    ELSIF osize < 5242880 THEN
      ADJUST := 'STORAGE ( INITIAL $INIT_MEDIUM NEXT $NEXT_MEDIUM )';
    ELSIF osize < 104857600 THEN
      ADJUST := 'STORAGE ( INITIAL $INIT_LARGE NEXT $NEXT_LARGE )';
    ELSE
      ADJUST := 'STORAGE ( INITIAL $INIT_XXL NEXT $NEXT_XXL )';
    END IF;
  ELSE
    ADJUST := '';
  END IF;
EXCEPTION
  WHEN OTHERS THEN ADJUST := '';
END;

BEGIN
  VERSION := '$version'; COALA := 0;
  SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
  IF NVL(LENGTH('$STS'),0) = 0 THEN
    L_LINE := '* '||TIMESTAMP||' Rebuilding all indices in Instance '||CHR(34)||'$ORACLE_SID'||CHR(34)||':';
    dbms_output.put_line(L_LINE);
    FOR Rec_INDEX IN C_INDEX_ALL LOOP
      adjust_clause(Rec_INDEX.bytes);
      L_LINE := ' ALTER INDEX "'||Rec_INDEX.owner||'"."'||Rec_INDEX.segment_name||
                '" REBUILD';
      moveidx(L_LINE);
    END LOOP;
  ELSE
    SELECT SUM(bytes), COUNT(segment_name) INTO SIZE_ALL,NUM_ALL FROM dba_segments WHERE segment_type='INDEX' AND tablespace_name=upper('$STS') AND extents>1 AND owner NOT IN ('SYS','SYSTEM');
    SIZE_DONE := 0; NUM_DONE := 0;
    L_LINE := '* '||TIMESTAMP||' Rebuilding all indices in TS $STS:';
    dbms_output.put_line(L_LINE);
    FOR Rec_INDEX IN C_INDEX LOOP
      adjust_clause(Rec_INDEX.bytes);
      L_LINE := ' ALTER INDEX "'||Rec_INDEX.owner||'"."'||Rec_INDEX.segment_name||
                '" REBUILD';
      moveidx(L_LINE);
      SIZE_DONE := SIZE_DONE + Rec_INDEX.bytes;
      NUM_DONE := NUM_DONE +1;
      do_coala('$STS');
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
