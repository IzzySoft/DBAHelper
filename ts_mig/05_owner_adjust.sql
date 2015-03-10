-- Moving all segments from one tablespace to another
-- 
DECLARE
  v_dry_mode BOOLEAN := FALSE;      -- in dry_mode code is only generated and dbms_output'ed
  tbs_src  VARCHAR2(30) := 'TS_ORIG';

  -- Either run the SQL directly or just generate the SQL to dbms_output
  PROCEDURE do_sql(p_sql VARCHAR2) IS
    datum VARCHAR2(20);
  BEGIN
    IF v_dry_mode THEN
      dbms_output.put_line(p_sql||';');
    ELSE
      SELECT TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') INTO datum FROM DUAL;
      dbms_output.put_line('-- '||datum||':'||CHR(10)||p_sql||';');
      EXECUTE IMMEDIATE p_sql;
    END IF; 
  END;

  -- Modify table and index default attributes to go to new tablespace
  PROCEDURE modify_defaults IS
    CURSOR c_obj IS
      SELECT owner, table_name
        FROM all_tables
       WHERE tablespace_name = tbs_src
         AND partitioned = 'YES';
    CURSOR c_obj2 IS
      SELECT owner, index_name
        FROM all_indexes
       WHERE tablespace_name = tbs_src;
    BEGIN
      FOR rec IN c_obj LOOP
        BEGIN
          do_sql('ALTER TABLE '||rec.owner||'.'||rec.table_name||' MODIFY DEFAULT ATTRIBUTES TABLESPACE '||tbs_dest);
        EXCEPTION
          WHEN OTHERS THEN
            dbms_output.put_line(SQLERRM);
        END;
      END LOOP;
      FOR rec IN c_obj2 LOOP
        BEGIN
          do_sql('ALTER INDEX '||rec.owner||'.'||rec.index_name||' MODIFY DEFAULT ATTRIBUTES TABLESPACE '||tbs_src);
        EXCEPTION
          WHEN OTHERS THEN
            dbms_output.put_line(SQLERRM);
        END;
      END LOOP;
    EXCEPTION
      WHEN OTHERS THEN
        dbms_output.put_line('ERROR in modify_defaults(): '||SQLERRM);
    END;

BEGIN
  -- modify table/index default attributes so new partitions are created in the correct TBS
  modify_defaults();
EXCEPTION
  WHEN OTHERS THEN
    dbms_output.put_line('ERROR in main: '||SQLERRM);
END;
/
