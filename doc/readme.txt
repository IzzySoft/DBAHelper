# =============================================================================
# Oracle DBA Helpers       (c) 2002-2008 by IzzySoft (devel AT izzysoft DOT de)
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Little helper scripts to ease the DBA's every day work
# =============================================================================

Contents
--------

1) Copyright and warranty
2) Requirements
3) Limitations
4) Scripts in this package and their usage
5) Installation

===============================================================================

1) Copyright and Warranty
-------------------------

These little programs are (c)opyrighted by Andreas Itzchak Rehberg
(devel AT izzysoft DOT de) and protected by the GNU Public License Version 2
(GPL). It comes AS-IS, and no warranty is given - use it ON YOUR OWN RISK.
For details on the License see the file LICENSE in this directory. The
contents of this archive may only be distributed all together.

===============================================================================

2) Requirements
---------------

Since these are scripts for the Oracle DBA, it implies one simple requirement:
an Oracle Database to work on. Additionally, you must have a shell available -
what implies that you run a *NIX operating system. Tested on RedHat Linux with
the bash shell v2.

===============================================================================

3) Limitations
--------------

I tested most of the scripts with Oracle v8.1.7, v9.0.1, v9.2 and v10.2 ("most
of" means, not all scripts are tested with all versions of Oracle). Basically,
they should work with any version (except for the scripts marked with a special
version below in "Scripts in this package") - but I cannot promise this
(reports are welcome). So far, no limitations are known - except that it will
probably work on Oracle databases only :-)

===============================================================================

4) Scripts in this package and their usage
------------------------------------------

For the syntax of all scripts, just see within their header - or run them
without any argument, so they will show it.

  Script               | Intention
  ---------------------+-------------------------------------------------------
  ExportOracleDB       | Wrapper to EXP for full DB export with default
                       | parameters (overwrite on command line) and optional
                       | compression of the resulting dump file
  Generate_createdb.sh | Reverse engineer the database creation script from a
                       | running instance (configuration within the script)
  analobj.sh           | Analyzes Objects for a given schema and outputs an
                       | ASCII report on chained/migrated rows.
  idxmove.sh           | Moves indices from one tablespace to another
  idxrebuild_inv.sh    | Rebuilds all INVALID indices in a given tablespace
  idxrebuild_all.sh    | Rebuilds all indices in a given tablespace having more
                       | than 1 extent, starting with the smallest and in between
                       | executing ALTER TABLESPACE..COALESCE to re-gain unused
                       | space best
  lazywaste.sh         | Show resources wasted by "lazy" sessions
  sqltune              | Run an SQL Tuning Advisor Task and display results (10g+)
  tabmove.sh           | Moves tables from one tablespace to another
  tabreorg.sh          | Reorganizes fragmented tables (chained rows)
  undo_used.sh         | list up undo records used by current processes
  rman/rman.sh         | Wrapper to rman (10g+)

All scripts run via Sql*Plus and use its SPOOL command to log their activities.

===============================================================================

5) Installation
---------------

1. Put all scripts into any directory you like. Make sure to keep them together
   with the "globalconf" file.
2. Edit the "globalconf" file for the database user and password to use by most
   scripts. We have to do so - no "CONNECT /" will work with remote databases
   for security reasons (although there is a way to do so, this is not
   recommended)
3. In the rman/rmanrc file you will wish to adjust the LOGDIR. Give the RMAN
   wrapper its own log directory - it will create a separate logfile for each
   run and action.
4. See the other options whether you need to adjust anything else. Usually
   there's no need for. Don't change things you are not sure about (or be aware
   of side effects ;)

The "globalconf" and "rman/rmanrc" files should be the only one you need to edit.
All options that are user-configurable (and not auto-adjusted or calculated by
the scripts themselves) are now provided here - if not stated differently in the
documentation (see doc/html/*), which may be more up-to-date than this document.
Since this config file will be executed as Shell script, we have to stick to
Shell syntax here. Amongst other things this means: no blanks next to the "="
sign, or the value given will not be assigned to the variable.

Provided that your Oracle environment is set up properly, you should now be
able to run the scripts.

Have fun!
Izzy.
