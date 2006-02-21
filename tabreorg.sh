#!/bin/bash
# $Id$
#
# =============================================================================
# Re-Organize chained tables   
# -----------------------------------------------------------------------------
#                                                              Itzchak Rehberg
#
#
version='0.1.0'
SCRIPT=${0##*/}
INTRO="\n==============================================================================\n"
INTRO="${INTRO}${SCRIPT} v${version}        (c) 2004-2006 by Itzchak Rehberg (devel@izzysoft.de)\n"
INTRO="${INTRO}------------------------------------------------------------------------------\n"

if [ -z "$1" ]; then
  printf "${INTRO}"
  echo "This script is intended to automatically reorganize all tables if the amount"
  echo "of chained/migrated rows exceeds a given treshhold (see globalconf). First,"
  echo "configure your user / password in the 'globalconf' file, then call this"
  echo "script using the following syntax:"
  echo ------------------------------------------------------------------------------
  echo "Syntax: ${SCRIPT} <ORACLE_SID> [Options]"
  echo "  Options:"
  echo "     -c <alternative ConfigFile>"
  echo "     -o <Owner - check and reorg only this schema>"
  echo "     -p <Password>"
  echo "     -s <ORACLE_SID/Connection String for Target DB>"
  echo "     -u <username>"
  echo "     --noanalyze : ignores the chain count percentage = force reorg"
  echo "     --force     : force rebuild even if MOVE ONLINE fails."
  echo "                   You need this to reorg non-IOT tables."
  echo ==============================================================================
  echo
  exit 1
fi

# =================================================[ Configuration Section ]===
adjust=1
analyze=1
force=0
# Read the global config
BINDIR=${0%/*}
CONFIG=$BINDIR/globalconf
. $BINDIR/configure $* -f tabreorg
if [ -n "$TR_OWNER" ]; then
  CURSOR="C_TABO('$TR_OWNER')"
else
  CURSOR="C_TAB"
fi

# ====================================================[ Script starts here ]===
printf "${INTRO}"
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
  RC BOOLEAN;
  DO_ADJUST BOOLEAN;
  ADJUST VARCHAR2(200); -- storage clause to adjust initial extent size
  OSIZE NUMBER;

  CURSOR C_TAB IS
    SELECT owner,table_name,tablespace_name,pct_free,pct_used,
           num_rows,chain_cnt
      FROM all_tables
     WHERE nvl(DECODE(num_rows,0,0,100*chain_cnt/num_rows),0) >= $TR_CHAINPCT
       AND owner NOT IN ('SYS','SYSTEM')
       AND temporary = 'N'
       AND nvl(num_rows,0) >= $NUMROWS
       AND nvl(chain_cnt,0) >= $CHAINCNT;
  CURSOR C_TABO(OWN VARCHAR2) IS
    SELECT owner,table_name,tablespace_name,pct_free,pct_used,
           num_rows,chain_cnt
      FROM all_tables
     WHERE nvl(DECODE(num_rows,0,0,100*chain_cnt/num_rows),0) >= $TR_CHAINPCT
       AND owner=upper(OWN)
       AND temporary = 'N'
       AND nvl(num_rows,0) >= $NUMROWS
       AND nvl(chain_cnt,0) >= $CHAINCNT;

  PROCEDURE print (line IN VARCHAR2) IS
    BEGIN
      IF $LOGALL = 1 THEN
        dbms_output.put_line(line);
      END IF;
    EXCEPTION
      WHEN OTHERS THEN NULL;
    END;

  PROCEDURE get_bytes (OWN IN VARCHAR2, TAB IN VARCHAR2) IS
    BEGIN
      SELECT SUM(bytes) INTO OSIZE
        FROM dba_segments
       WHERE owner=OWN AND segment_name=TAB AND segment_type='TABLE';
    EXCEPTION
      WHEN OTHERS THEN OSIZE := NULL;
    END;

  PROCEDURE adjust_clause IS
    BEGIN
      IF OSIZE IS NULL THEN
        ADJUST := '';
      ELSIF OSIZE < 262144 THEN
        ADJUST := 'STORAGE ( INITIAL $INIT_SMALL NEXT $NEXT_SMALL )';
      ELSIF OSIZE < 5242880 THEN
        ADJUST := 'STORAGE ( INITIAL $INIT_MEDIUM NEXT $NEXT_MEDIUM )';
      ELSIF OSIZE < 104857600 THEN
        ADJUST := 'STORAGE ( INITIAL $INIT_LARGE NEXT $NEXT_LARGE )';
      ELSE
        ADJUST := 'STORAGE ( INITIAL $INIT_XXL NEXT $NEXT_XXL )';
      END IF;
    EXCEPTION
      WHEN OTHERS THEN ADJUST := '';
  END;

  FUNCTION movetab (OWN IN VARCHAR2, TAB IN VARCHAR2) RETURN BOOLEAN IS
    line VARCHAR2(255);
    BEGIN
      line := ' ALTER TABLE '||OWN||'.'||TAB||' MOVE ';
      SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
      print('+ '||TIMESTAMP||line||'ONLINE '||ADJUST);
      EXECUTE IMMEDIATE line||'ONLINE '||ADJUST;
      RETURN TRUE;
    EXCEPTION
      WHEN OTHERS THEN
        BEGIN
          SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
          IF ($force = 1) THEN
            print('- '||TIMESTAMP||SQLERRM);
            print('+ '||TIMESTAMP||line||ADJUST);
            EXECUTE IMMEDIATE line||' '||ADJUST;
            RETURN TRUE;
          ELSE
            dbms_output.put_line('! '||TIMESTAMP||' TABLE MOVE failed for '||OWN||'.'||TAB||' ('||SQLERRM||')');
            RETURN FALSE;
          END IF;
        EXCEPTION
          WHEN OTHERS THEN
            SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
            dbms_output.put_line('! '||TIMESTAMP||' TABLE MOVE failed for '||OWN||'.'||TAB||' ('||SQLERRM||')');
            RETURN FALSE;
        END;
    END;

  PROCEDURE alttab (OWN IN VARCHAR2, TAB IN VARCHAR2, FREE IN NUMBER, USED IN NUMBER) IS
    statement VARCHAR2(255);
    newval NUMBER;
    BEGIN
      newval := FREE + $TR_FREEINC;
      SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
      IF newval + USED < 90 THEN
        IF ADJUST IS NOT NULL THEN
         ADJUST := ADJUST||' ';
        END IF;
        ADJUST := ADJUST||'PCTFREE '||newval;
        IF newval + USED + $TR_USEDINC < 90 THEN
          newval := USED + $TR_USEDINC;
          ADJUST := ADJUST||' PCTUSED '||newval;
        ELSE
          statement := ' Could not adjust PCTUSED for '||OWN||'.'||TAB||' - new values would exceed 100';
          dbms_output.put_line('- '||TIMESTAMP||statement);
          statement := ' PCTUSED: '||USED||', PCTFREE: '||FREE||', increase: $TR_USEDINC';
          print('- '||TIMESTAMP||statement);
        END IF;
      ELSE
        statement := ' Could not adjust PCTFREE for '||OWN||'.'||TAB||' - new values would exceed 100';
        dbms_output.put_line('- '||TIMESTAMP||statement);
        statement := ' PCTUSED: '||USED||', PCTFREE: '||FREE||', increase: $TR_FREEINC';
        print('- '||TIMESTAMP||statement);
      END IF;
    EXCEPTION
      WHEN OTHERS THEN
        dbms_output.put_line('! '||TIMESTAMP||' Weird situation ('||SQLERRM||')');
    END;

BEGIN
  VERSION := '$version';
  IF ($adjust = 1) THEN
    DO_ADJUST := TRUE;
  ELSE
    DO_ADJUST := FALSE;
  END IF;
  SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
  L_LINE := '* '||TIMESTAMP||' TabReorg v'||VERSION||' launched'||CHR(10)||
            '# '||TIMESTAMP||' CmdLine: "$ARGS"';
  dbms_output.put_line(L_LINE);
  FOR rec IN $CURSOR LOOP
    SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
    dbms_output.put_line('~ '||TIMESTAMP||' Processing '||rec.owner||'.'||rec.table_name);
    IF DO_ADJUST THEN
      get_bytes(rec.owner,rec.table_name);
      adjust_clause();
      IF ($analyze = 1) THEN
        alttab(rec.owner,rec.table_name,NVL(rec.pct_free,10),NVL(rec.pct_used,40));
      END IF;
      RC := movetab(rec.owner,rec.table_name);
    END IF;
  END LOOP;
  SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
  dbms_output.put_line('* '||TIMESTAMP||' TabReorg v'||VERSION||' exiting normally.');
EXCEPTION
  WHEN OTHERS THEN
    SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
    dbms_output.put_line('! '||TIMESTAMP||' Something weird happened ('||SQLERRM||')');
    dbms_output.put_line('! '||TIMESTAMP||' TabReorg v'||VERSION||' crashed normally.');
END;
/

SPOOL off

EOF
