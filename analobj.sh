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
  echo "============================================================================"
  echo "${SCRIPT}  (c) 2003-2006 by Itzchak Rehberg & IzzySoft (devel@izzysoft.de)"
  echo "----------------------------------------------------------------------------"
  echo "This script is intended to analyze objects for a given schema and/or print a"
  echo "list of tables with chained rows, where the ratio exceeds the configured"
  echo "threshold. First configure your user / passwd in the 'globalconf' file, then"
  echo "call this script using the following syntax:"
  echo "----------------------------------------------------------------------------"
  echo "Syntax: ${SCRIPT} <ORACLE_SID> <Schema> <ObjectType> [Options]"
  echo "  Options:"
  echo "     -c <alternative ConfigFile>"
  echo "     -l <LOGALL value (0|1)>"
  echo "     -p <Password>"
  echo "     -s <ORACLE_SID/Connection String for Target DB>"
  echo "     -u <username>"
  echo "     --noanalyze"
  echo "----------------------------------------------------------------------------"
  echo "where <ObjectType> is either TABLE, INDEX or ALL. The '--noanalyze' option"
  echo "you may want to specify if you think your statistics are recent enough, and"
  echo "you just quickly want the 'chained list'."
  echo "============================================================================"
  echo
  exit 1
fi

# =================================================[ Configuration Section ]===
# Eval params
SCHEMA=$2
OBJECTTYPE=$3

# Set defaults
analyze=1

# Read the global config
BINDIR=${0%/*}
CONFIG=$BINDIR/globalconf
. $BINDIR/configure $* -f analobj

# Setup connect string
if [ -z "${user}${password}${ORACLE_CONNECT}" ]; then
  CONN='CONNECT / as sysdba'
else
  CONN="CONNECT $user/${password}$ORACLE_CONNECT"
fi

# ====================================================[ Script starts here ]===
version='0.1.7'
#cat >dummy.out<<EOF
$ORACLE_HOME/bin/sqlplus -s /NOLOG <<EOF

$CONN
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
 analyze NUMBER;
 L_LINE VARCHAR2(255);
 TIMESTAMP VARCHAR2(20);
 VERSION VARCHAR2(20);
 LOGALL NUMBER;
 height        index_stats.height%TYPE := 0;
 lf_rows       index_stats.lf_rows%TYPE := 0;
 del_lf_rows   index_stats.del_lf_rows%TYPE := 0;
 distinct_keys index_stats.distinct_keys%TYPE := 0;
 CURSOR cur IS
  SELECT owner,table_name
    FROM all_tables
   WHERE owner=UPPER('$SCHEMA');
 CURSOR icur IS
  SELECT owner,index_name,index_type,table_name
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
 CURSOR ires IS
   SELECT i.owner,i.index_name,i.blevel,i.clustering_factor,t.num_rows,t.blocks
     FROM dba_tables t, dba_indexes i
    WHERE t.owner = UPPER('$SCHEMA')
      AND t.owner = i.table_owner
      AND t.table_name = i.table_name
      AND ( i.blevel > 1 OR i.clustering_factor > (t.num_rows + t.blocks)*2/3 )
      AND i.leaf_blocks > 1;
 PROCEDURE anobj(statement VARCHAR2, ttype VARCHAR2, tname VARCHAR2) IS
   BEGIN
     EXECUTE IMMEDIATE statement;
   EXCEPTION
     WHEN OTHERS THEN
       SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
       L_LINE := '! '||TIMESTAMP||' Analyzing '||ttype||' "'||tname||
                 ' failed ('||SQLERRM||')';
       dbms_output.put_line(L_LINE);
   END;
BEGIN
 VERSION := '$version';
 LOGALL := $LOGALL;
 analyze := $analyze;
 IF LOWER('$OBJECTTYPE') = 'all' THEN
   antab := 1; anidx := 1;
 ELSE
   IF LOWER('$OBJECTTYPE') = 'table' THEN
     antab := 1; anidx := 0;
   ELSE
     antab := 0; anidx := 1;
   END IF;
 END IF;
  SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
  L_LINE := CHR(10)||'* '||TIMESTAMP||
            ' Analyzing $OBJECTTYPE objects on $SCHEMA...'||CHR(10);
  dbms_output.put_line(L_LINE);
  IF antab = 1 THEN
    IF analyze = 1 THEN
      FOR rec IN cur LOOP
        statement := 'ANALYZE TABLE "'||rec.owner||'"."'||rec.table_name||'" $CALCSTAT STATISTICS';
        IF LOGALL = 1 THEN
          SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
          dbms_output.put_line('+ '||TIMESTAMP||' '||statement);
        END IF;
        anobj(statement,'table',rec.owner||'.'||rec.table_name);
      END LOOP;
    END IF;
    L_LINE := CHR(10)||'List of tables with chained/migrated rows for schema "$SCHEMA", which '||CHR(10)||
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
    IF analyze = 1 THEN
      dbms_output.put_line('Following indexes may need some investigation: If deleted entries are > 20%, or');
      dbms_output.put_line('the BLevel exceeds a value of 4, this is a possible rebuild candidate. If the');
      dbms_output.put_line('amount of distinct keys falls below 10%, you may consider making this a bitmap');
      dbms_output.put_line('index:'||CHR(10));
      dbms_output.put_line('+------------------------------+----------------+---------+------+------------+');
      dbms_output.put_line('|          Index Name          |   Index Type   |  % Del  | BLev | % Distinct |');
      dbms_output.put_line('+------------------------------+----------------+---------+------+------------+');
      FOR rec IN icur LOOP
        statement := 'ANALYZE INDEX "'||rec.owner||'"."'||rec.index_name||'" VALIDATE STRUCTURE';
        IF LOGALL = 1 THEN
          SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
          dbms_output.put_line('+ '||TIMESTAMP||' '||statement);
        END IF;
        anobj(statement,'index',rec.owner||'.'||rec.index_name);
	SELECT height, DECODE (lf_rows,0,1,lf_rows), del_lf_rows, 
               DECODE (distinct_keys,0,1,distinct_keys) 
          INTO height, lf_rows, del_lf_rows, distinct_keys
          FROM index_stats;
        IF ( height > 5 ) OR ( (del_lf_rows/lf_rows) > 0.2 ) THEN
	  L_LINE := '| '||RPAD(TRIM(SUBSTR(rec.index_name,1,28)),28)
	         ||' | '||RPAD(TRIM(SUBSTR(rec.index_type,1,14)),14)
	         ||' | '||LPAD(TRIM(TO_CHAR((del_lf_rows/lf_rows)*100,'990.99')),7)
		 ||' | '||LPAD(TRIM(height),4)
		 ||' | '||LPAD(TRIM(TO_CHAR(100-(lf_rows-distinct_keys)*100/lf_rows,'990.99')),10)||' |';
	  dbms_output.put_line(L_LINE);
	END IF;
      END LOOP;
      dbms_output.put_line('+------------------------------+----------------+---------+------+------------+');
    ELSE
      L_LINE := 'The following list is more like a guess - for more accurate results, run the'||CHR(10)
             || 'script without the "--noanalyze" option (and "analyze=1" in the head).'||CHR(10)
             || 'Considered a BLevel > 2 or a Clustering_Factor closer to the tables row count'||CHR(10)
             || 'than to the tables block count as indicators, these are possible Rebuild'||CHR(10)
             || 'candidates in the schema of ''$SCHEMA'':'||CHR(10);
      dbms_output.put_line(L_LINE);
      dbms_output.put_line( '+--------------------------------+------+-------------+-----------+-----------+' );
      dbms_output.put_line( '| Index                          | BLev | ClustFactor |  TabRows  | TabBlocks |' );
      dbms_output.put_line( '+--------------------------------+------+-------------+-----------+-----------+' );
      FOR rec IN ires LOOP
        L_LINE := '| '||RPAD(rec.index_name,30)||' | '||LPAD(rec.blevel,4)||' | '
               || LPAD(TRIM(TO_CHAR(rec.clustering_factor,'999,999,990')),11)||' | '
	       || LPAD(TRIM(TO_CHAR(rec.num_rows,'9,999,990')),9)||' | '
	       || LPAD(TRIM(TO_CHAR(rec.blocks,'9,999,990')),9)||' |';
        dbms_output.put_line(L_LINE);
      END LOOP;
      dbms_output.put_line( '+--------------------------------+------+-------------+-----------+-----------+' );
    END IF;
    dbms_output.put_line(CHR(10));
  END IF;
  SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
  dbms_output.put_line('* '||TIMESTAMP||' Analyze v'||VERSION||' completed.');
EXCEPTION
  WHEN OTHERS THEN
    SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO TIMESTAMP FROM DUAL;
    dbms_output.put_line('! '||TIMESTAMP||' Analyze failed ('||SQLERRM||')');
    dbms_output.put_line('! '||TIMESTAMP||' Analyze v'||VERSION||' crashed normally.');
END;
/

EOF

if [ "`echo $OBJECTTYPE|tr [:lower:] [:upper:]`" == "INDEX" ]; then
  grep '^| [A-Z]' $SPOOL |awk "{print \"ALTER INDEX $SCHEMA.\"\$2\" REBUILD;\"}">${SPOOL}.sql
fi
