#!/bin/bash
# $Id$
#
# =============================================================================
# Analyze Objects for a given schema
# -----------------------------------------------------------------------------
#                                                              Itzchak Rehberg
#
if [ -z "$3" ]; then
  SCRIPT=${0##*/}
  echo
  echo ============================================================================
  echo "${SCRIPT}       (c) 2003 by Itzchak Rehberg & IzzySoft (devel@izzysoft.de)"
  echo ----------------------------------------------------------------------------
  echo This script is intended to analyze objects for a given schema. First
  echo configure your SYS user / passwd inside this script, then echo call this
  echo script using the following syntax:
  echo ----------------------------------------------------------------------------
  echo "Syntax: ${SCRIPT} <ORACLE_SID> <Schema> <ObjectType>"
  echo ----------------------------------------------------------------------------
  echo "where <ObjectType> is either TABLE, INDEX or ALL."
  echo ============================================================================
  echo
  exit 1
fi

# =================================================[ Configuration Section ]===
# Eval params
export ORACLE_SID=$1
SCHEMA=$2
OBJECTTYPE=$3
# login information
user=sys
password="pyha#"
# name of the file to write the log to (or 'OFF' for no log). This file will
# be overwritten without warning!
SPOOL="analobj__$1-$2-$3.spool"
# restrictions: what are the minimal settings to display?
NUMROWS=1000
CHAINCNT=10
# estimate or compute statistics?
CALCSTAT="COMPUTE"
# ====================================================[ Script starts here ]===
version='0.1.0'
#cat >dummy.out<<EOF
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
 statement varchar2(300);
 antab NUMBER; anidx NUMBER;
 L_LINE VARCHAR2(255);
 CURSOR cur IS
  SELECT owner,table_name
    FROM all_tables
   WHERE owner=UPPER('$SCHEMA');
 CURSOR icur IS
  SELECT owner,index_name
    FROM all_indexes
   WHERE owner=UPPER('$SCHEMA');
 CURSOR res IS
   SELECT RPAD(table_name,30) tablename,
          LPAD(TO_CHAR(num_rows,'9,999,999,990'),15) num_rows,
          LPAD(TO_CHAR(chain_cnt,'99,990'),7) chains,
          LPAD(TO_CHAR(100*chain_cnt/num_rows,'990.0'),6) pct
     FROM dba_tables
    WHERE owner     = UPPER('$SCHEMA')
      AND num_rows  > $NUMROWS
      AND chain_cnt > $CHAINCNT
    ORDER BY table_name;
BEGIN
 IF LOWER('$OBJECTTYPE') = 'all' THEN
   antab := 1; anidx := 1;
 ELSE
   IF LOWER('$OBJECTTYPE') = 'table' THEN
     antab := 1; anidx := 0;
   ELSE
     antab := 0; anidx := 1;
   END IF;
 END IF;
  dbms_output.put_line(CHR(10)||'$CALCSTAT statistics for $OBJECTTYPE on $SCHEMA...'||CHR(10));
  IF antab = 1 THEN
    FOR rec IN cur LOOP
      statement := 'ANALYZE TABLE '||rec.owner||'.'||rec.table_name||' $CALCSTAT STATISTICS';
	  EXECUTE IMMEDIATE statement;
    END LOOP;
    L_LINE := 'List of tables with chained/migrated rows for schema "$SCHEMA", which '||CHR(10)||
              'have at least "$NUMROWS lines" and "$CHAINCNT chains":'||CHR(10);
    dbms_output.put_line(L_LINE);
    dbms_output.put_line( '+--------------------------------+-----------------+---------+-------+' );
    dbms_output.put_line( '| Table                          | Rows            | Chains  | %     |' );
    dbms_output.put_line( '+--------------------------------+-----------------+---------+-------+' );
    FOR rec IN res LOOP
      dbms_output.put_line('| '||rec.tablename||' | '||rec.num_rows||' | '||rec.chains||' |'||rec.pct||' |');
    END LOOP;
    dbms_output.put_line( '+--------------------------------+-----------------+---------+-------+' );
    dbms_output.put_line(CHR(10));
  END IF;
  IF anidx = 1 THEN
    FOR rec IN icur LOOP
      statement := 'ANALYZE INDEX '||rec.owner||'.'||rec.index_name||' COMPUTE STATISTICS';
	  EXECUTE IMMEDIATE statement;
    END LOOP;
  END IF;
END;
/
