## What are these scripts for?
In short: To move all objects stored in one tablespace to another.

You probably know the situation: over time, a tablespace has been extended again
and again, finally reaching a phantastic size. Disk space gets rare, so you
pushed the data-holder to a cleanup. The data-holder discovered more than half
of the data were stale and could be deleted – and that he did. Now you're left
with a Dutch cheese: you want to regain the unused space, but that's not as
simple as `ALTER TABLESPACE SHRINK`; the way our luck goes, the last used bit is
exactly at the very end of the data file(s).

Instead of figuring out which bit that is, easiest way is to create a new
tablespace, move all objects over, and drop the old one. As a side-effect, all
tables are re-organized (and probably got smaller again by 10 to 25% that way),
indexes are rebuilt, and everything got faster.


## Why five scripts?
Steps have to be performed with different logins. Only the DBA should create
tablespaces and assign them (incl. quotas), data should be dealt with by its
owner (especially if you've got database vault active), and then again the DBA
must take care for dropping the old and renaming the new tablespace – after
having made sure it's safe to do so. Finally, we have to work around some Oracle
bug: though according to documentation, renaming a tablespace should be
transparent to the tables occupying it – that doesn't apply to partitioned
tables; their default tablespace attribute gets hosed.

So we have five scripts altogether, to be run in the given order:

* `01_dba_newtablespace.sql`: DBA preparing the new tablespace
* `02_owner_movesegments.sql`: schema owner moving all objects over
* `03_dba_check_remains.sql`: DBA checks whether anything remained in the
  original tablespace – or it's safe to be dropped
* `04_dba_cleanuptablespaces.sql`: DBA drops the original TS, and renames
  the new one to replace it.
* `05_owner_adjust.sql`: Working around an Oracle bug, the owner finally has to
  modify the default tablespace attribute of partitioned tables again


## Pre-Conditions
These scripts go with some assumption: that the tablespace is assigned to a
single schema owner, and not shared among multiple data owners.


## Adjustments needed
Some configuration to reflect your situation. In all four files, check for
the following and replace it with values matching your installation:

* `ts_mig`: As that's a "temporary name", you can let it stand as-is
* `ts_orig`: the original tablespace to be "cleaned up"
* `ts_idx`: a tablespace where all indexes should go to. Can be the same
  as `ts_mig`, or a separate one – but *must not* be identical with `ts_orig`
* `schema_owner`: as the name says. That's used for indexes and gathering
  schema stats in the end.
* and of course the file size for the new tablespace in `01_dba_newtablespace.sql`

Remember all those are "Oracle object names", so spell them UPPERCASE.


## What will the main script do?
Sure you can read PL/SQL, but in short these are the steps performed:

1. modify table/index default attributes so new partitions are created in the
   correct TBS. We do this at the very start, so in case new partitions are
   added while we are migrating, they already go to the correct place.
1. move indexes which are in the wrong tablespace.  
   This just affects indexes which are not already stored in `ts_idx`.
1. move all (sub)partitions and tables to the new TBS
1. fix up all index ((sub)partititions) which got invalidated.  
   Other than in step 2, this affects all indexes and index (sub)partitions
   which are not 'VALID' or 'USABLE' – i.e. which got invalidated during
   table move.
1. update statistics  
   uses `dbms_stats.gather_schema_stats` with the configured percentage for
   `estimate statistics` and, again depending on configuration, cascades to
   gather stats for the indexes as well.
