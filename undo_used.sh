#!/bin/bash
# =============================================================================
# List up undo records used by current processes to identify the "eaters"
# -----------------------------------------------------------------------------
# No parameters required - simply run the script
# =============================================================================
# $Id$

#--------------------------------------------------------------[ Say Hello ]---
echo "################################################################################"
echo "# Current processes undo usage lister   (c) 2008 by Itzchak Rehberg & IzzySoft #"
echo "################################################################################"

#-------------------------------------------------------------[ Pre-Checks ]---
[ -z "$ORACLE_SID" ] && {
  echo "The environment variable ORACLE_SID is not set - so I don't know what"
  echo "database to investigate - sorry!"
  sleep 1
  exit 1
}

#---------------------------------------------------------------[ Main Job ]---
echo "################################################################################"
echo "# Current processes undo usage lister   (c) 2008 by Itzchak Rehberg & IzzySoft #"
echo "################################################################################"
sqlplus -s "/as sysdba" <<EOF
 Set TERMOUT OFF
 Set SERVEROUTPUT ON
 Set LINESIZE 300
 Set TRIMSPOOL ON
 Set FEEDBACK OFF
 Set Echo Off HEAD OFF
 DECLARE
   L_LINE VARCHAR2(255);
   ONAME VARCHAR2(15);
   CURSOR c_us IS
     SELECT
       substr(a.os_user_name,1,8) os_user,
       substr(a.oracle_username,1,8) db_user,
       substr(b.owner,1,10) schema,
       b.object_name object,
       substr(b.object_type,1,7) typ,
       substr(c.segment_name,1,9) rbs,
       substr(d.used_urec,1,10) recs
     FROM
       v\$locked_object a, dba_objects b, dba_rollback_segs c,
       v\$transaction d, v\$session e
     WHERE
       a.object_id = b.object_id and a.xidusn = c.segment_id
       and a.xidusn = d.xidusn and a.xidslot = d.xidslot
       and d.addr = e.taddr;
 BEGIN
   L_LINE := 'Undo Space Used by current transactions';
   dbms_output.put_line('+------------------------------------------------------------------------------+');
   dbms_output.put_line('|'||RPAD(LPAD(L_LINE,39+LENGTH(L_LINE)/2),78)||'|');
   dbms_output.put_line('+----------+----------+------------+----------------+---------+---------+------+');
   dbms_output.put_line('|   User   |  OSUser  |   Schema   |     Object     |   Typ   |   RBS   | Recs |');
   dbms_output.put_line('+----------+----------+------------+----------------+---------+---------+------+');
   FOR r IN c_us LOOP
     IF LENGTH(r.object)>14 THEN
       ONAME := SUBSTR(r.object,1,12)||'..';
     ELSE
       ONAME := r.object;
     END IF;
     L_LINE := '| '||RPAD(r.db_user,8)||' | '||RPAD(r.os_user,8)||' | '||
                 RPAD(r.schema,10)||' | '||RPAD(ONAME,14)||' | '||
                 RPAD(r.typ,7)||' |'||RPAD(r.rbs,9)||'| '||
                 LPAD(r.recs,4)||' |';
     dbms_output.put_line(L_LINE);
   END LOOP;
   dbms_output.put_line('+----------+----------+------------+----------------+---------+---------+------+');
 EXCEPTION
   WHEN NO_DATA_FOUND THEN
     L_LINE := 'There is no undo space used by current processes.';
     dbms_output.put_line('|'||RPAD(LPAD(L_LINE,39+LENGTH(L_LINE)/2),78)||'|');
     dbms_output.put_line('+------------------------------------------------------------------------------+');
   WHEN OTHERS THEN
     L_LINE := SQLERRM;
     dbms_output.put_line('|'||RPAD(LPAD(L_LINE,39+LENGTH(L_LINE)/2),78)||'|');
     dbms_output.put_line('+------------------------------------------------------------------------------+');
 END;
 /
EOF
