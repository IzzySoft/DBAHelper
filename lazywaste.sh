#!/bin/bash
#####################################################################
# Find lazy sessions and list resources wasted by them
#####################################################################
# $Id$

# How many days a session must be inactive to be counted "lazy"?
MIN_LAZY_AGE=10
TOP_N_SESSIONS=5

echo "###############################################################################"
echo "# Lazy Session & Wastage lister         (c)2005 by Itzchak Rehberg & IzzySoft #"
echo "###############################################################################"
sqlplus -s "/as sysdba" <<EOF
 Set TERMOUT OFF
 Set SERVEROUTPUT On Size 1000000
 Set LINESIZE 300
 Set TRIMSPOOL On 
 Set FEEDBACK OFF
 Set Echo Off HEAD OFF
 DECLARE
   TTS VARCHAR(30);
   TSSPACE NUMBER;
   TSUSED NUMBER;
   PGAWASTED NUMBER;
   SESSUM NUMBER;
   L_LINE VARCHAR2(255);
   CURSOR C_TopPGA IS
     SELECT DISTINCT a.username,a.osuser,a.sid,a.serial# serial,a.process,a.program,a.status,
	    SUM (ROUND (((c.pga_used_mem) / 1024 / 1024),2)) OVER (PARTITION BY SID) pga_used,
	    sysdate - a.last_call_et/60/60/24 last_active
       FROM v\$session a, v\$process c, v\$parameter p
      WHERE p.NAME = 'db_block_size'
        AND a.username IS NOT NULL
        AND a.paddr = c.addr 
	AND sysdate - a.last_call_et/60/60/24 < SYSDATE -$MIN_LAZY_AGE
	AND rownum < $TOP_N_SESSIONS +1
      ORDER BY pga_used DESC;
    CURSOR C_TopTMP IS
     SELECT DISTINCT a.username,a.osuser,a.sid,a.serial# serial,a.process,a.program,a.status,
	    SUM (ROUND (((b.blocks * p.value) / 1024 / 1024),2)) OVER (PARTITION BY SID) tmp_used,
	    sysdate - a.last_call_et/60/60/24 last_active
       FROM v\$session a, v\$sort_usage b, v\$parameter p
      WHERE p.NAME = 'db_block_size'
        AND a.username IS NOT NULL
        AND a.saddr = b.session_addr
	AND b.tablespace=TTS
	AND sysdate - a.last_call_et/60/60/24 < SYSDATE -$MIN_LAZY_AGE
	AND rownum < $TOP_N_SESSIONS +1
      ORDER BY tmp_used DESC;

 BEGIN
   -- Global wastage
   SELECT property_value INTO TTS FROM database_properties WHERE property_name='DEFAULT_TEMP_TABLESPACE';
   SELECT SUM(ROUND ((bytes/1024/1024), 2)) INTO TSSPACE FROM dba_temp_files WHERE tablespace_name=TTS;
   IF TSSPACE IS NULL THEN
     SELECT SUM(ROUND ((bytes/1024/1024), 2)) INTO TSSPACE FROM dba_data_files WHERE tablespace_name=TTS;
   END IF;
   SELECT COUNT(sid) INTO SESSUM FROM v\$session
    WHERE sysdate - last_call_et/60/60/24 < SYSDATE -$MIN_LAZY_AGE AND username IS NOT NULL;
   SELECT SUM (ROUND (((b.blocks * p.VALUE) / 1024 / 1024), 2)) INTO TSUSED
     FROM v\$session a, v\$sort_usage b, v\$parameter p
    WHERE p.NAME = 'db_block_size'
      AND a.username IS NOT NULL
      AND a.saddr = b.session_addr
      AND b.tablespace=TTS
      AND sysdate - a.last_call_et/60/60/24 < SYSDATE -$MIN_LAZY_AGE;
   SELECT SUM (ROUND((c.pga_used_mem/1024/1024),2))
     INTO PGAWASTED
     FROM v\$session a, v\$process c, v\$parameter p
    WHERE p.NAME = 'db_block_size'
      AND a.username IS NOT NULL
      AND a.paddr = c.addr
      AND sysdate - a.last_call_et/60/60/24 < SYSDATE -$MIN_LAZY_AGE;
   dbms_output.put_line('Size of Default Temp TS "'||TTS||'" is '||TSSPACE||' MB.');
   IF (SESSUM > 0) THEN
     dbms_output.put_line(SESSUM||' "lazy" sessions waste '||NVL(TSUSED,0)||' MB in temporary TS "'||TTS||'" and '||NVL(PGAWASTED,0)||' MB PGA.');
     -- Top N PGA waster
     L_LINE := 'TOP $TOP_N_SESSIONS PGA waster';
     dbms_output.put_line('+------------------------------------------------------------------------------+');
     dbms_output.put_line('|'||RPAD(LPAD(L_LINE,39+LENGTH(L_LINE)/2),78)||'|');
     dbms_output.put_line('+----------+----------+------------+----------------+---------+----------------+');
     dbms_output.put_line('|   User   |  OSUser  | SID/Serial |     Program    |   PGA   |   Last Active  |');
     dbms_output.put_line('+----------+----------+------------+----------------+---------+----------------+');
     FOR pga IN C_TopPGA LOOP
       L_LINE := '| '||RPAD(pga.username,8)||' | '||RPAD(pga.osuser,8)||' | '||
                 RPAD(pga.sid||'/'||pga.serial,10)||' | '||SUBSTR(pga.program,0,12)||'.. | '||
                 TO_CHAR(pga.pga_used,'90.00')||'M | '||TO_CHAR(pga.last_active,'YY-MM-DD HH24:MI')||' |';
       dbms_output.put_line(L_LINE);
     END LOOP;
     dbms_output.put_line('+----------+----------+------------+----------------+---------+----------------+');
     -- Top N SortSpace waster
     L_LINE := 'TOP $TOP_N_SESSIONS Temp Space waster';
     dbms_output.put_line('+------------------------------------------------------------------------------+');
     dbms_output.put_line('|'||RPAD(LPAD(L_LINE,39+LENGTH(L_LINE)/2),78)||'|');
     dbms_output.put_line('+----------+----------+------------+----------------+---------+----------------+');
     dbms_output.put_line('|   User   |  OSUser  | SID/Serial |     Program    | Temp TS |   Last Active  |');
     dbms_output.put_line('+----------+----------+------------+----------------+---------+----------------+');
     FOR pga IN C_TopTMP LOOP
       L_LINE := '| '||RPAD(pga.username,8)||' | '||RPAD(pga.osuser,8)||' | '||
                 RPAD(pga.sid||'/'||pga.serial,10)||' | '||SUBSTR(pga.program,0,12)||'.. | '||
                 TO_CHAR(pga.tmp_used,'90.00')||'M | '||TO_CHAR(pga.last_active,'YY-MM-DD HH24:MI')||' |';
       dbms_output.put_line(L_LINE);
     END LOOP;
     dbms_output.put_line('+----------+----------+------------+----------------+---------+----------------+');
   ELSE
     dbms_output.put_line('No "lazy" sessions found - no wasted resources to report.');
   END IF;
 EXCEPTION
   WHEN OTHERS THEN dbms_output.put_line('Error occured on '||TTS||': '||SQLERRM);
 END;
/
EOF
