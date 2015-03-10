-- Moving all segments from one tablespace to another
-- 
DECLARE
  v_dry_mode BOOLEAN := FALSE;      -- in dry_mode code is only generated and dbms_output'ed
  v_owner VARCHAR2(30)  := 'SCHEMA_OWNER'; -- for index check/rebuild and schema stats only
  v_stats_granularity VARCHAR2(50) := 'DEFAULT'; -- DEFAULT | SUBPARTITION | PARTITION | GLOBAL | ALL
  v_stats_cascade BOOLEAN := TRUE; -- include index stats
  tbs_src  VARCHAR2(30) := 'TS_ORIG';
  tbs_dest VARCHAR2(30) := 'TS_MIG';
  tbs_idx  VARCHAR2(30) := 'TS_IDX'; -- tablespace where the indexes *should* be (moved to)
  stmt VARCHAR2(4000);

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
          do_sql('ALTER INDEX '||rec.owner||'.'||rec.index_name||' MODIFY DEFAULT ATTRIBUTES TABLESPACE '||tbs_idx);
        EXCEPTION
          WHEN OTHERS THEN
            dbms_output.put_line(SQLERRM);
        END;
      END LOOP;
    EXCEPTION
      WHEN OTHERS THEN
        dbms_output.put_line('ERROR in modify_defaults(): '||SQLERRM);
    END;

  -- Move sub-partitions
  PROCEDURE move_subparts IS
    CURSOR c_obj IS
      SELECT table_owner, table_name, partition_name, subpartition_name
        FROM all_tab_subpartitions
       WHERE tablespace_name = tbs_src;
    BEGIN
      FOR rec IN c_obj LOOP
        stmt := 'ALTER TABLE '||rec.table_owner||'.'||rec.table_name||
                ' MOVE SUBPARTITION '||rec.subpartition_name||
                ' TABLESPACE '||tbs_dest;
        BEGIN
          do_sql(stmt);
        EXCEPTION
          WHEN OTHERS THEN
            dbms_output.put_line(SQLERRM);
        END;
      END LOOP;
    EXCEPTION
      WHEN OTHERS THEN
        dbms_output.put_line('ERROR in move_subparts(): '||SQLERRM);
    END;

  -- Move partitions
  PROCEDURE move_parts IS
    CURSOR c_obj IS
      SELECT table_owner, table_name, partition_name
        FROM all_tab_partitions
       WHERE tablespace_name = tbs_src
         AND subpartition_count = 0;
    BEGIN
      FOR rec IN c_obj LOOP
        stmt := 'ALTER TABLE '||rec.table_owner||'.'||rec.table_name||
                ' MOVE PARTITION '||rec.partition_name||
                ' TABLESPACE '||tbs_dest;
        BEGIN
          do_sql(stmt);
        EXCEPTION
          WHEN OTHERS THEN
            dbms_output.put_line(SQLERRM);
        END;
      END LOOP;
    EXCEPTION
      WHEN OTHERS THEN
        dbms_output.put_line('ERROR in move_parts(): '||SQLERRM);
    END;

  -- Move tables
  PROCEDURE move_tables IS
    CURSOR c_obj IS
      SELECT owner, table_name
        FROM all_tables
       WHERE tablespace_name = tbs_src
         AND partitioned = 'NO';
    BEGIN
      FOR rec IN c_obj LOOP
        stmt := 'ALTER TABLE '||rec.owner||'.'||rec.table_name||
                ' MOVE TABLESPACE '||tbs_dest;
        BEGIN
          do_sql(stmt);
        EXCEPTION
          WHEN OTHERS THEN
            dbms_output.put_line(SQLERRM);
        END;
      END LOOP;
    EXCEPTION
      WHEN OTHERS THEN
        dbms_output.put_line('ERROR in move_tables(): '||SQLERRM);
    END;

  -- ---------------------------------= [ INDEXES ]=--
  -- Rebuild possibly broken index subpartitions
  PROCEDURE rebuild_subidx(p_tbs VARCHAR2) IS
    CURSOR c_obj IS
      SELECT index_name, subpartition_name, tablespace_name
        FROM all_ind_subpartitions
       WHERE index_owner = v_owner
         AND status <> 'USABLE';
    CURSOR c_obj2 IS
      SELECT index_name, subpartition_name, tablespace_name
        FROM all_ind_subpartitions
       WHERE index_owner = v_owner
         AND tablespace_name = p_tbs;
    BEGIN
      IF p_tbs = tbs_idx THEN -- final rebuild
        FOR rec IN c_obj LOOP
          BEGIN
            do_sql('ALTER INDEX '||v_owner||'.'||rec.index_name||' REBUILD SUBPARTITION '||rec.subpartition_name||' TABLESPACE '||tbs_idx);
          EXCEPTION
            WHEN OTHERS THEN
              dbms_output.put_line(SQLERRM);
          END;
        END LOOP;
      ELSE -- pre-check: move indexes to correct TBS
        FOR rec IN c_obj2 LOOP
          BEGIN
            do_sql('ALTER INDEX '||v_owner||'.'||rec.index_name||' REBUILD SUBPARTITION '||rec.subpartition_name||' TABLESPACE '||tbs_idx);
          EXCEPTION
            WHEN OTHERS THEN
              dbms_output.put_line(SQLERRM);
          END;
        END LOOP;
      END IF;
    EXCEPTION
      WHEN OTHERS THEN
        dbms_output.put_line('ERROR in rebuild_subidx(): '||SQLERRM);
    END;

  -- Rebuild possibly broken index partitions
  PROCEDURE rebuild_partidx(p_tbs VARCHAR2) IS
    CURSOR c_obj IS
      SELECT index_name, partition_name
        FROM all_ind_partitions
       WHERE index_owner = v_owner
         AND status <> 'USABLE'
         AND subpartition_count = 0;
    CURSOR c_obj2 IS
      SELECT index_name, partition_name
        FROM all_ind_partitions
       WHERE index_owner = v_owner
         AND tablespace_name = p_tbs
         AND subpartition_count = 0;
    BEGIN
      IF p_tbs = tbs_idx THEN -- final rebuild
        FOR rec IN c_obj LOOP
          BEGIN
            do_sql('ALTER INDEX '||v_owner||'.'||rec.index_name||' REBUILD PARTITION '||rec.partition_name||' TABLESPACE '||tbs_idx);
          EXCEPTION
            WHEN OTHERS THEN
              dbms_output.put_line(SQLERRM);
          END;
        END LOOP;
      ELSE -- pre-check: move indexes to correct TBS
        FOR rec IN c_obj2 LOOP
          BEGIN
            do_sql('ALTER INDEX '||v_owner||'.'||rec.index_name||' REBUILD PARTITION '||rec.partition_name||' TABLESPACE '||tbs_idx);
          EXCEPTION
            WHEN OTHERS THEN
              dbms_output.put_line(SQLERRM);
          END;
        END LOOP;
      END IF;
    EXCEPTION
      WHEN OTHERS THEN
        dbms_output.put_line('ERROR in rebuild_partidx(): '||SQLERRM);
    END;

  -- Rebuild possibly broken indexes
  PROCEDURE rebuild_idx(p_tbs VARCHAR2) IS
    CURSOR c_obj IS
      SELECT index_name
        FROM all_indexes
       WHERE owner = v_owner
         AND status <> 'VALID'
         AND partitioned = 'NO';
    CURSOR c_obj2 IS
      SELECT index_name
        FROM all_indexes
       WHERE owner = v_owner
         AND tablespace_name = p_tbs
         AND partitioned = 'NO';
    BEGIN
      IF p_tbs = tbs_idx THEN -- final rebuild
        FOR rec IN c_obj LOOP
          BEGIN
            do_sql('ALTER INDEX '||v_owner||'.'||rec.index_name||' REBUILD'||' TABLESPACE '||tbs_idx);
          EXCEPTION
            WHEN OTHERS THEN
              dbms_output.put_line(SQLERRM);
          END;
        END LOOP;
      ELSE -- pre-check: move indexes to correct TBS
        FOR rec IN c_obj2 LOOP
          BEGIN
            do_sql('ALTER INDEX '||v_owner||'.'||rec.index_name||' REBUILD'||' TABLESPACE '||tbs_idx);
          EXCEPTION
            WHEN OTHERS THEN
              dbms_output.put_line(SQLERRM);
          END;
        END LOOP;
      END IF;
    EXCEPTION
      WHEN OTHERS THEN
        dbms_output.put_line('ERROR in rebuild_idx(): '||SQLERRM);
    END;

BEGIN
  -- modify table/index default attributes so new partitions are created in the correct TBS
  modify_defaults();
  -- move indexes which are in the wrong tablespace
  rebuild_subidx(tbs_src);
  rebuild_partidx(tbs_src);
  rebuild_idx(tbs_src);
  -- now move all (sub)partitions and tables to the new TBS
  move_subparts(); -- 7
  move_parts(); -- 5094
  move_tables(); -- 12
  -- fix up all index ((sub)partititions) which got invalidated
  rebuild_subidx(tbs_idx);
  rebuild_partidx(tbs_idx);
  rebuild_idx(tbs_idx);
  -- update statistics
  dbms_stats.gather_schema_stats(
    ownname => v_owner,
    estimate_percent => 10,
    granularity => v_stats_granularity,
    cascade => v_stats_cascade
  );
EXCEPTION
  WHEN OTHERS THEN
    dbms_output.put_line('ERROR in main: '||SQLERRM);
END;
/
