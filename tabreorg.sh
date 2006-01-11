#!/bin/bash
# $Id$
#
# =============================================================================
# Re-Organize chained tables   
# -----------------------------------------------------------------------------
#                                                              Itzchak Rehberg
#
#
version='0.0.8'
SCRIPT=${0##*/}
INTRO="\n==============================================================================\n"
INTRO="${INTRO}${SCRIPT} v${version}        (c) 2004-2005 by Itzchak Rehberg (devel@izzysoft.de)\n"
INTRO="${INTRO}------------------------------------------------------------------------------\n"

if [ -z "$1" ]; then
  printf "${INTRO}"
  echo "This script is intended to automatically reorganize all tables if the amount"
  echo "of chained/migrated rows exceeds a given treshhold (see globalconf)."
  echo "Call this script using the following syntax:"
  echo ------------------------------------------------------------------------------
  echo "Syntax: ${SCRIPT} <ORACLE_SID> [Options]"
  echo "  Options:"
  echo "     -c <alternative ConfigFile>"
  echo "     -o <Owner - check and reorg only this schema>"
  echo "     -p <Password>"
  echo "     -s <ORACLE_SID/Connection String for Target DB>"
  echo "     -t <temporary TS for reorg>"
  echo "     -u <username>"
  echo "     --nostats (ignores the chain count percentage = force reorg)"
  echo ==============================================================================
  echo
  exit 1
fi

# =================================================[ Configuration Section ]===
# Read the global config
BINDIR=${0%/*}
CONFIG=$BINDIR/globalconf
. $BINDIR/configure $* -f tabreorg
if [ -n "$TR_OWNER" ]; then
  CURSOR="C_TABO('$TR_OWNER')"
else
  CURSOR="C_TAB"
fi

# =====================================================[ Check the TS name ]===
if [ `echo "$TR_TMP" | tr "[a-z]" "[A-Z]"` == "TEMP" ] || [ -z "$TR_TMP" ]; then
  printf "${INTRO}"
  echo "! For optimal reorganization, you should specify a permanent TS to temporarily"
  echo "! hold the tables. This can be done within the configuration file or by using"
  echo "! the -t option on the command line."
#  exit 2
  TR_TMP=""
  ADJUST="FALSE"
  ONLINE=""
else
  ADJUST="TRUE"
  ONLINE="ONLINE"
fi

# ====================================================[ Script starts here ]===
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
  RC BOOLEAN;
  ADJUST BOOLEAN;

  CURSOR C_TAB IS
    SELECT owner,table_name,tablespace_name,pct_free,pct_used,
           num_rows,chain_cnt
      FROM all_tables
     WHERE nvl(DECODE(num_rows,0,0,100*chain_cnt/num_rows),0) >= $TR_CHAINPCT
       AND owner NOT IN ('SYS','SYSTEM')
       AND nvl(num_rows,0) >= $NUMROWS
       AND nvl(chain_cnt,0) >= $CHAINCNT;
  CURSOR C_TABO(OWN VARCHAR2) IS
    SELECT owner,table_name,tablespace_name,pct_free,pct_used,
           num_rows,chain_cnt
      FROM all_tables
     WHERE nvl(DECODE(num_rows,0,0,100*chain_cnt/num_rows),0) >= $TR_CHAINPCT
       AND owner=upper(OWN)
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

  FUNCTION movetab (OWN IN VARCHAR2, TAB IN VARCHAR2, TTS IN VARCHAR2) RETURN BOOLEAN IS
    line VARCHAR2(255);
    BEGIN
      line := ' ALTER TABLE '||OWN||'.'||TAB||' MOVE ';
      SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
      print('+ '||TIMESTAMP||line||'ONLINE ' ||TTS);
      EXECUTE IMMEDIATE line||'$ONLINE '||TTS;
      RETURN TRUE;
    EXCEPTION
      WHEN OTHERS THEN
        BEGIN
          SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
          print('- '||TIMESTAMP||SQLERRM);
          print('+ '||TIMESTAMP||line||TTS);
          EXECUTE IMMEDIATE line||tts;
          RETURN TRUE;
        EXCEPTION
          WHEN OTHERS THEN
            SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
            dbms_output.put_line('! '||TIMESTAMP||' TABLE MOVE failed for '||OWN||'.'||TAB||' ('||SQLERRM||')');
            RETURN FALSE;
        END;
    END;

  FUNCTION alttab (OWN IN VARCHAR2, TAB IN VARCHAR2, FREE IN NUMBER, USED IN NUMBER) RETURN BOOLEAN IS
    statement VARCHAR2(255);
    newval NUMBER;
    BEGIN
      newval := FREE + $TR_FREEINC;
      SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
      IF newval + USED < 90 THEN
        statement := 'ALTER TABLE '||OWN||'.'||TAB||' PCTFREE '||newval;
        print('+ '||TIMESTAMP||' '||statement);
        EXECUTE IMMEDIATE statement;
        SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
        IF newval + USED + $TR_USEDINC < 90 THEN
          newval := USED + $TR_USEDINC;
          statement := 'ALTER TABLE '||OWN||'.'||TAB||' PCTUSED '||newval;
          print('+ '||TIMESTAMP||' '||statement);
          EXECUTE IMMEDIATE statement;
        ELSE
          statement := ' Could not adjust PCTUSED for '||OWN||'.'||TAB||' - new values would exceed 100';
          dbms_output.put_line('- '||TIMESTAMP||statement);
          statement := ' PCTUSED: '||USED||', PCTFREE: '||FREE||', increase: $TR_USEDINC';
          print('- '||TIMESTAMP||statement);
        END IF;
        RETURN TRUE;
      ELSE
        statement := ' Could not adjust PCTFREE for '||OWN||'.'||TAB||' - new values would exceed 100';
        dbms_output.put_line('- '||TIMESTAMP||statement);
        statement := ' PCTUSED: '||USED||', PCTFREE: '||FREE||', increase: $TR_FREEINC';
        print('- '||TIMESTAMP||statement);
        RETURN FALSE;
      END IF;
    EXCEPTION
      WHEN OTHERS THEN
        SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
        dbms_output.put_line('! '||TIMESTAMP||' ALTER TABLE failed ('||SQLERRM||')');
        RETURN FALSE;
    END;

BEGIN
  VERSION := '$version';
  ADJUST := $ADJUST;
  SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
  L_LINE := '* '||TIMESTAMP||' TabReorg v'||VERSION||' launched'||CHR(10)||
            '# '||TIMESTAMP||' CmdLine: "$ARGS"';
  dbms_output.put_line(L_LINE);
  FOR rec IN $CURSOR LOOP
    SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
    dbms_output.put_line('~ '||TIMESTAMP||' Processing '||rec.owner||'.'||rec.table_name);
    RC := movetab(rec.owner,rec.table_name,'$TR_TMP');
    IF RC THEN
      IF ADJUST THEN
        RC := alttab(rec.owner,rec.table_name,NVL(rec.pct_free,10),NVL(rec.pct_used,40));
        RC := movetab(rec.owner,rec.table_name,rec.tablespace_name);
      END IF;
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
