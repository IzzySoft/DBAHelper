COLUMN owner FOR A10
COLUMN segment_name FOR A20
SET PAGES 0
SET LINES 120

PROMPT Remains in dba_segments
SELECT owner, segment_name, partition_name, segment_type, round(bytes/power(1024,3),2) AS gbytes
  FROM dba_segments
 WHERE tablespace_name = 'TS_ORIG';

PROMPT Remains in dba_extents
SELECT owner, segment_name, partition_name, segment_type, round(bytes/power(1024,3),2) AS gbytes
  FROM dba_extents
 WHERE tablespace_name = 'TS_ORIG';
