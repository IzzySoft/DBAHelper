#!/bin/bash
# $Id$
#
# =============================================================================
# Reverse engineer the createdb.sql from a running database
# -----------------------------------------------------------------------------
#                                                              Itzchak Rehberg
#
if [ -z "$1" ]; then
  SCRIPT=${0##*/}
  echo
  echo "============================================================================"
  echo "${SCRIPT}    (c) 2000 E Augustine"
  echo "             (c) 2002-2005 by Itzchak Rehberg & IzzySoft (devel@izzysoft.de)"
  echo "----------------------------------------------------------------------------"
  echo "This script is intended to reverse-engineer the scripts to create a database"
  echo "from a running instance. It is in no way certified or even complete, so use "
  echo "it on your own risk! If encountering any problems, please drop a note to the"
  echo "developer using the address above."
  echo "Use the script with the following syntax on the machine the instance is"
  echo "running at:"
  echo "----------------------------------------------------------------------------"
  echo "Syntax: ${SCRIPT} <ORACLE_SID>"
  echo "============================================================================"
  echo
  exit 1
fi

#set -x
export ORACLE_SID=$1

# =================================================[ Configuration Section ]===

DBSPOOL="${ORACLE_SID}_createDB"
USERSPOOL="${ORACLE_SID}_users"
ROLESPOOL="${ORACLE_SID}_roles"
SYSGRANTS="${ORACLE_SID}_sys_grants"
OBJGRANTS="${ORACLE_SID}_obj_grants"
SYNONYMS="${ORACLE_SID}_pub_synonyms"

# =================================================[ PL/SQL Print function ]===
printfunc=`cat << ENDPRINT
  FUNCTION strpos (str IN VARCHAR2,needle IN VARCHAR2,startpos NUMBER) RETURN NUMBER IS
    pos NUMBER; strsub VARCHAR2(255);
    BEGIN
      strsub := SUBSTR(str,1,255);
      pos    := INSTR(strsub,needle,startpos);
      return pos;
    END;

  PROCEDURE print(line IN VARCHAR2) IS
    pos NUMBER;
    BEGIN
      dbms_output.put_line(line);
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLERRM LIKE '%ORU-10028%' THEN
          pos := strpos(line,' ',-1);
	  print(SUBSTR(line,1,pos));
	  pos := pos +1;
	  print(SUBSTR(line,pos));
	ELSE
          dbms_output.put_line('-- *!* Problem in print() *!*');
	END IF;
    END;
ENDPRINT`

# ===========================================================[ Do the job! ]===

sqlplus -s "/as sysdba" <<EOF

Rem  Filename : Generate_createdb.sh
Rem  Purpose  : To reverse engineer the createdb.sql from a running database
Rem  Syntax   : Generate_createdb.sh <instance name>
Rem	        produces an output called createdb_$ORACLE_SID.sql
Rem
Rem  Notes    : Developed and tested on Oracle 7.3.3 for Solaris
Rem             (some cursory tests on Oracle 8.1.7 for Solaris and Linux done
Rem             by A I Rehberg, but this script is not certified in any way).
Rem		Runs ONLY catproc.sql, catalog.sql, catdbsyn.sql and pubbld.sql
Rem		Non UNIX databases may need small modifications to the paths
Rem		of called scripts i.e. catalog.sql, catproc.sql ... 
Rem             You will have to review the resulting script and apply some
Rem             corrections/additions/changes to it before it will actually
Rem             do what you expect from it - but it at least gives you a good
Rem             basis to start with!
Rem
Rem  Not done : - resource consumer groups are not catered for
Rem             - account locks not catered for
Rem
Rem  History  : 20-01-2000 E Augustine 	Created
Rem		14-02-2000 E Augustine	
Rem 		 - Database is created in NOARCHIVELOG and then altered
Rem		   to ARCHIVELOG if originally configured in ARCHIVELOG.
Rem		09-04-2002 A I Rehberg       Additions on Oracle 8i
Rem              - AutoExtending datafiles recognized now
Rem              - TableSpaces for SYS and SYSTEM read from DB
Rem                (instead of being hardcoded)
Rem              - User Accounts now also extracted (passwords are set to the
Rem                user name since they can't be read from DB)
Rem              - Grants are extracted now for users as well as roles
Rem              - Profiles are catered for
Rem              - Dropped the hardcoded creation of user OPS$ORACLE
Rem		12-04-2002 D Kapfer         Shell Scripting & more
Rem              - Embedded the generator in a bash script to support
Rem                Environment variables
Rem              - created work-around for "MaxExtents Unlimited" problem
Rem                (Oracle just stores this value as a high integer)
Rem              - location of executed scripts now based on $ORACLE_HOME
Rem              - added execution of catdbsyn.sql and pubbld.sql
Rem		14-04-2002 A I Rehberg       Small fixes
Rem              - catproc.sql was not executed (added it now)
Rem              - some statements had wrong syntax (fixed)
Rem		23-04-2002 A I Rehberg       Small additions
Rem              - added "Extent Management", "[No]Logging" and "Minimum Extent"
Rem                clauses to "Create TableSpace" statements
Rem             28-06-2005 A I Rehberg       Marginal changes plus re-structuring
Rem              - replaced svrmgrl by sqlplus (svrmgrl not available anymore with
Rem                Oracle v9+)
Rem              - replaced "connect internal" by "/as sysdba" (same reason)
Rem              - changed shell to /bin/bash
Rem              - splitted up output to multiple spool files to a) separate tasks
Rem                (technical DB, users, grants etc) and b) work around the limit of
Rem                dbms_output generated files (which is 1MB) for large DBs with many
Rem                users/grants
Rem             29-06-2005 A I Rehberg       Minor bugfixes
Rem              - fixed syntax error in created script for tablespace storage
Rem                (with locally managed TS, next and pctincrease have been
Rem                empty in some cases; now we substitute initial resp. 0)
Rem              - script now prints is syntax when called w/o parameters
Rem		05-10-2005 A I Rehberg
Rem		 - Default Storage parameters for Tablespaces are now only generated
Rem                for dictionary managed TS (causes errors on creating locally managed TS)
Rem              - Temporary TS statement is now also created
Rem		 - Rollback Segments are no longer created (and "altered online") when
Rem		   database is in auto undo mode
Rem		 - added export of public synonyms and database links (not owned by SYS or SYSTEM).
Rem		 - Now also creating roles
Rem		 - CREATE USERS are now done with the correct password (using the undocumented
Rem		   "identified by values" feature), same applies to the ALTER USER for the
Rem                admin accounts (SYS and SYSTEM)
Rem              - moved the bootstrapping stuff to the end of the createDB script, since catproc
Rem                stops the SPOOLing (and thus the created log stops after it)


Set TERMOUT OFF
Set SERVEROUTPUT On Size 1000000
Set LINESIZE 300
Set TRIMSPOOL On 
Set FEEDBACK OFF
Set Echo Off
Spool ${DBSPOOL}.sql

Declare

	-- Non SYSTEM Tablespaces are created explicitly. 
	Cursor C_Tablespaces Is
	Select Distinct TABLESPACE_NAME From DBA_DATA_FILES 
	 Where TABLESPACE_NAME Not Like 'SYSTEM%'
	Union
 	Select Distinct TABLESPACE_NAME From DBA_TEMP_FILES;

	-- All files for a tablespace.
	Cursor C_Datafiles ( P_TS Varchar2 ) Is
	Select * From DBA_DATA_FILES 
	 Where TABLESPACE_NAME = P_TS
	Union
	Select * From DBA_TEMP_FILES
	 Where TABLESPACE_NAME = P_TS;

	-- Profile information
	Cursor C_Profiles Is
	Select Distinct PROFILE
	 From  DBA_PROFILES
	 Where PROFILE <> 'DEFAULT';
	Cursor C_Profile_Info (PROF In Varchar2) Is
	Select PROF,RESOURCE_NAME,LIMIT
	 From  DBA_PROFILES
	 Where PROFILE=PROF;
	 
	-- Administrative User information
	Cursor C_Admin_Info Is
	Select USERNAME,DEFAULT_TABLESPACE,TEMPORARY_TABLESPACE,PASSWORD
	 From  DBA_USERS
	 Where lower(USERNAME) In ('sys','system')
	 Order By USER_ID;

	-- Tablespace information
	Cursor C_Tablespace_Info ( P_TS Varchar2 ) Is
	Select * From DBA_TABLESPACES
	 Where TABLESPACE_NAME = P_TS;

	-- SYSTEM rollback segment is created implicitly hence not selected.
	Cursor C_Rollback_Segs ( P_TS Varchar2 ) Is
	Select * From DBA_ROLLBACK_SEGS 
	 Where TABLESPACE_NAME = P_TS 
	   And SEGMENT_NAME <> 'SYSTEM'
	 Order By SEGMENT_ID;

        Cursor C_Rollback_Online Is
        Select SEGMENT_NAME
         From  dba_rollback_segs
	 Where SEGMENT_NAME <> 'SYSTEM'
	 Order By SEGMENT_ID;

 	Cursor C_Logfile ( L_GROUP_NUM In Varchar2 ) Is
        Select A.Group#, A.Bytes, A.Members, B.Member
          From V\$LOG A, V\$LOGFILE B
         Where A.Group# = B.Group#
           And A.Group# = L_GROUP_NUM
        Order By A.Group#; 

	FirstTime	Boolean;
 	L_LINE 		Varchar2(2000);		-- A line to output
	L_SID		Varchar2(20);		-- Oracle Database Name 
	L_LOGMODE	Varchar2(50);		-- Archivelog or not
	L_UNDOMODE      Varchar2(50);		-- Automatic Undo?
	L_CHRSET	Varchar2(50);		-- NLS character set
	L_GROUPS	Number(9);		-- Nos of Log Groups
	L_LOGSIZE	Number(9);		-- Logfile size
	L_MEMBERS	Number(9);		-- Nos Members per Group
	L6		Varchar2(9);		-- 6 spaces
	L4		Varchar2(9);		-- 4 spaces
	L2		Varchar2(9);		-- 2 spaces
	L_MAXEXTENTS    Varchar2(20);           -- DKapfer required for 'Unlimited'

$printfunc

Begin
	L2 := '  ';
	L4 := L2||L2;
	L6 := L2||L4;
	
	L_LINE := 'Connect "/as sysdba"'||Chr(10)||
		  'Set TERMOUT On ECHO On'||Chr(10)||
		  'Spool ${DBSPOOL}.log'||Chr(10)||
		  'Startup nomount'||Chr(10); 
 
	print(L_LINE);

	Select NAME, LOG_MODE 
 	  Into L_SID, L_LOGMODE 
	  From V\$DATABASE;

	Select Lower(VALUE) Into L_UNDOMODE
	  From V\$PARAMETER
	  Where Lower(NAME)='undo_management';

	Select VALUE Into L_CHRSET 
   	  From V\$NLS_PARAMETERS
	 Where Upper(PARAMETER) = 'NLS_CHARACTERSET';

	Select Max(GROUP#), Max(MEMBERS), Max(BYTES)/1024
          Into L_GROUPS, L_MEMBERS, L_LOGSIZE
          From V\$LOG;

	L_LINE := 'Create Database "'|| L_SID ||'"'|| Chr(10)||
	         L4||'Maxlogfiles    '||To_Char(L_GROUPS*L_MEMBERS*4)||Chr(10)||
	         L4||'Maxlogmembers  '||To_Char(L_MEMBERS*2)||Chr(10)||
		 L4||'Maxloghistory  160'||Chr(10)||
		 L4||'Maxdatafiles   255'||Chr(10)||
		 L4||'Maxinstances   1'||Chr(10)||
		 L4||'NOARCHIVELOG'||Chr(10)||
		 L4||'Character Set  "'||L_CHRSET||'"'||Chr(10)||
		 L4||'Datafile';

	print(L_LINE);

	--
	-- Get the datafiles for the SYSTEM tablespace
	--
	FirstTime := TRUE;
	For Rec_Datafiles In C_Datafiles ( 'SYSTEM' ) Loop
	  If FirstTime Then
	     FirstTime := FALSE;
	     L_LINE := '	';
	  Else
	     L_LINE := L_LINE||' ,'||Chr(10)||'	';
 	  End If;
	  L_LINE := L_LINE||
			 ''''||Rec_Datafiles.FILE_NAME||''''||' Size '||
		         To_Char(Rec_Datafiles.BYTES/1024)||' K';
	  If Rec_Datafiles.AUTOEXTENSIBLE = 'YES' Then
	     L_LINE := L_LINE||' Autoextend On';
	  End If;
        End Loop;
	L_LINE := L_LINE || Chr(10) || L4 || 'Logfile ';
	print(L_LINE);

	--
	-- Create the LOGFILE bits ...
	--
	FirstTime := TRUE;	-- For groups
	For L_INDEX In 1.. L_GROUPS Loop
	    If FirstTime Then
	      FirstTime := FALSE;	-- For groups
	      L_LINE := '	 Group '|| To_Char(L_INDEX) || ' (';
	    Else
	      L_LINE := '	,Group '|| To_Char(L_INDEX) || ' (';
	    End If;
	    FirstTime := TRUE;	-- For members
	    For Rec_Logfile In C_Logfile ( L_INDEX ) Loop
	      If FirstTime Then
		FirstTime := FALSE;  -- For members
	      Else
		L_LINE := L_LINE ||Chr(10)||L6||L2||'	 ,';
	      End If;
	      L_LINE := L_LINE||''''||Rec_Logfile.MEMBER||'''';
	    End Loop;   
	    L_LINE := L_LINE || Chr(10)||L6||L2||
				'	 ) Size '||To_Char(L_LOGSIZE)||' K ';
	    print(L_LINE);
	End Loop;

	--
	-- The Rollback segments in the SYSTEM tablespace 
	--
        For Rec_RBS In C_Rollback_Segs ('SYSTEM') Loop
          L_LINE := 'Create Rollback Segment '||Rec_RBS.SEGMENT_NAME||
		   	 Chr(10)||'  Tablespace '||
			 Rec_RBS.TABLESPACE_NAME||
			 Chr(10)||'  '||'Storage (';
          if Rec_RBS.MAX_EXTENTS > 2000000000  or Rec_RBS.MAX_EXTENTS is null then  /* DKapfer */
            L_MAXEXTENTS := 'Unlimited';
          else  			 
            L_MAXEXTENTS := To_Char(Rec_RBS.MAX_EXTENTS);
          end if;  
	  L_LINE := L_LINE||Chr(10)||'    Initial     '||
			     To_Char(Rec_RBS.INITIAL_EXTENT/1024)||' K'||
			 Chr(10)||'    Next        '||
			     To_Char(Rec_RBS.NEXT_EXTENT/1024)||' K'||
			 Chr(10)||'    Minextents  '||
			     To_Char(Rec_RBS.MIN_EXTENTS)||
			 Chr(10)||'    Maxextents  '||
			      L_MAXEXTENTS  ||            /* DKapfer */
			  --  Rec_RBS.MAX_EXTENTS||       /* DKapfer */
			 Chr(10)||'    Optimal     '||
			     To_Char(Rec_RBS.MIN_EXTENTS * 
				     Rec_RBS.NEXT_EXTENT/1024)||' K'||Chr(10)
			 ||'          )'||Chr(10)||'/'||Chr(10)
			 ;
	  print(L_LINE);
        End Loop;


	--
	-- Create all other tablespaces ...
	--
	For Rec_Tablespaces In C_Tablespaces Loop
	  L_LINE := 'Create Tablespace '||Rec_Tablespaces.TABLESPACE_NAME;
	  print(L_LINE);
	  FirstTime := TRUE;
	  For Rec_Datafiles In 
		C_Datafiles ( Rec_Tablespaces.TABLESPACE_NAME ) Loop
	    If FirstTime Then
	 	FirstTime := FALSE;
		L_LINE := ' Datafile ';
	    Else
	 	L_LINE := '	,';
 	    End If;
	    L_LINE := L_LINE||''''||Rec_Datafiles.FILE_NAME||''''||
			 ' Size '||
		         To_Char(Rec_Datafiles.BYTES/1024)||' K';
	    If Rec_Datafiles.AUTOEXTENSIBLE = 'YES' Then
	       L_LINE := L_LINE||' Autoextend On';
	    End If;
	    print(L_LINE);
	  End Loop;

	  For Rec_TS_Info In 
		C_Tablespace_Info( Rec_Tablespaces.TABLESPACE_NAME ) Loop
            if Rec_TS_Info.MAX_EXTENTS > 2000000000 or Rec_TS_Info.MAX_EXTENTS is null then  /* DKapfer */
              L_MAXEXTENTS := 'Unlimited';
            else  			 
              L_MAXEXTENTS := To_Char(Rec_TS_Info.MAX_EXTENTS);
            end if;  
            if Rec_TS_Info.EXTENT_MANAGEMENT = 'DICTIONARY' then
		    L_LINE :='    Default Storage ( '||
			Chr(10)||'    Initial     '||
			     To_Char(Rec_TS_Info.INITIAL_EXTENT/1024)||' K'||
			Chr(10)||'    Next        '||
			     To_Char(NVL(Rec_TS_Info.NEXT_EXTENT/1024,Rec_TS_Info.INITIAL_EXTENT/1024))||' K'||
			Chr(10)||'    Minextents  '||
			     To_Char(Rec_TS_Info.MIN_EXTENTS)||
			Chr(10)||'    Maxextents  '||
			      L_MAXEXTENTS  ||            /* DKapfer */
			  --  Rec_TS_Info.MAX_EXTENTS||   /*DKapfer*/
			Chr(10)||'    Pctincrease '||
			     To_Char(NVL(Rec_TS_Info.PCT_INCREASE,0))||
			Chr(10)||
			'                )'
			;
	    end if;
	    L_LINE := L_LINE||Chr(10)||' '||
	              'Extent Management '||Rec_TS_Info.EXTENT_MANAGEMENT||chr(10);
	    L_LINE := L_LINE||' '||Rec_TS_Info.LOGGING||Chr(10);
	    L_LINE := L_LINE||' Minimum Extent '||Rec_TS_Info.MIN_EXTLEN;
	    L_LINE := L_LINE||Chr(10)||' '||
			Rec_TS_Info.CONTENTS||Chr(10)||'/'||Chr(10)||Chr(10);
	    print(L_LINE);
	  End Loop;
	
	  -- 
	  -- Create all Rollback segments in the tablespace being created ...
	  --
	  If L_UNDOMODE != 'auto' Then
	    For Rec_RBS In C_Rollback_Segs (Rec_Tablespaces.TABLESPACE_NAME) Loop
	      L_LINE := 'Create Rollback Segment '||Rec_RBS.SEGMENT_NAME||
		   	   Chr(10)||'  Tablespace '||
			   Rec_RBS.TABLESPACE_NAME||
			   Chr(10)||'  '||'Storage (';
              if Rec_RBS.MAX_EXTENTS > 2000000000 or Rec_RBS.MAX_EXTENTS is null then  /* DKapfer */
                L_MAXEXTENTS := 'Unlimited';
              else  			 
                L_MAXEXTENTS := To_Char(Rec_RBS.MAX_EXTENTS);
              end if; 
	      L_LINE := L_LINE||Chr(10)||'    Initial     '||
			       To_Char(Rec_RBS.INITIAL_EXTENT/1024)||' K'||
			   Chr(10)||'    Next        '||
			       To_Char(Rec_RBS.NEXT_EXTENT/1024)||' K'||
			   Chr(10)||'    Minextents  '||
			       To_Char(Rec_RBS.MIN_EXTENTS)||
			   Chr(10)||'    Maxextents  '||
			        L_MAXEXTENTS  ||            /* DKapfer */
			   --   Rec_RBS.MAX_EXTENTS||       /* DKapfer */
			   Chr(10)||'    Optimal     '||
			       To_Char(Rec_RBS.MIN_EXTENTS * 
				       Rec_RBS.NEXT_EXTENT/1024)||' K'||Chr(10)
			   ||'          )'||Chr(10)||'/'||Chr(10)
			   ;
	      print(L_LINE);
            End Loop;
          End If;
	End Loop;

        -- 
        -- Alter all Rollback segments Online ...
        --
        If L_UNDOMODE != 'auto' Then
          For Rec_RBSO In C_Rollback_Online Loop
            L_LINE := 'Alter Rollback Segment '||Rec_RBSO.SEGMENT_NAME||' Online;';
	    print(L_LINE);
          End Loop;
	  L_LINE := Chr(10);
	  print(L_LINE);
	End If;

	--
	-- Get the profiles information
	--
	For Rec_Prof In C_Profiles Loop
	  L_LINE := 'Create Profile '||Rec_Prof.PROFILE
	    ||' Limit SESSIONS_PER_USER Default;';
	  print(L_LINE);
	  For Rec_ProfData In C_Profile_Info (Rec_Prof.PROFILE) Loop
	    L_LINE := 
	      'Alter Profile '||Rec_ProfData.PROF||' LIMIT '
	      ||Rec_ProfData.RESOURCE_NAME||' '
	      ||Rec_ProfData.LIMIT||';';
	    print(L_LINE);
	  End Loop;
	  L_LINE := Chr(10);
	  print(L_LINE);
	End Loop;

	--
	-- Get the data for the Admins
	--
	FirstTime := TRUE;
	For Rec_AdminData In C_Admin_Info Loop

	  If FirstTime Then
	     FirstTime := FALSE;
	     L_LINE := '';
	  Else
	     L_LINE := L_LINE||Chr(10);
 	  End If;

	  L_LINE := L_LINE||
	    'Alter User '||Rec_AdminData.USERNAME||Chr(10)||L4
	    ||'Identified By Values '''||Rec_AdminData.PASSWORD||''''||Chr(10)||L4
	    ||'Default Tablespace '||Rec_AdminData.DEFAULT_TABLESPACE||Chr(10)||L4
	    ||'Temporary Tablespace '||Rec_AdminData.TEMPORARY_TABLESPACE||';'
	    ||Chr(10)||'/'||Chr(10);
	End Loop;
	
	L_LINE := L_LINE||Chr(10);
	print(L_LINE);

	--
	-- The bootstrapping stuff ... 
	--
	L_LINE := '/'||Chr(10)||Chr(10)||
		     'Set TERMOUT Off ECHO Off'||Chr(10)||
		     '@${ORACLE_HOME}/rdbms/admin/catalog.sql'||Chr(10)||
		     '@${ORACLE_HOME}/rdbms/admin/catproc.sql'||Chr(10)||
		     'Set TERMOUT On ECHO On'||Chr(10)||Chr(10);
	print(L_LINE);

        --
        -- Catalog
        --
	L_LINE := 'Connect System/Manager'||Chr(10)||
		  'Set TERMOUT Off ECHO Off'||Chr(10)||
		  '@${ORACLE_HOME}/rdbms/admin/catdbsyn'||Chr(10)||  /*DKapfer*/
		  '@${ORACLE_HOME}/sqlplus/admin/pupbld'||Chr(10)||  /*DKapfer*/
		  'Set TERMOUT On ECHO On'||Chr(10);

	print(L_LINE);

        --
        -- ArcLog
        --
	L_LINE := 'Connect "/as sysdba"'||Chr(10)||
		  'Shutdown'||Chr(10)||
		  'Startup'||Chr(10)||Chr(10);

	print(L_LINE);

	If L_LOGMODE = 'ARCHIVELOG' Then
	  L_LINE := 'Shutdown immediate'||Chr(10)||
                    'Startup Mount'||Chr(10)||
                    'Alter Database ARCHIVELOG;'||Chr(10)||
                    'Alter Database Open;'||Chr(10);
	  print(L_LINE);
	End If;

        --
        -- Finish System File. User Info will go to separate file
        --
	L_LINE := 'Spool Off'||Chr(10)||Chr(10)||
	          '--'||Chr(10)||'-- Other scripts to run (comment out unwanted ones here)'||
	          Chr(10)||'--';
	print(L_LINE);
	L_LINE := '@${USERSPOOL}.sql'||Chr(10)||
	          '@${ROLESPOOL}.sql'||Chr(10)||
	          '@${SYSGRANTS}.sql'||Chr(10)||
	          '@${OBJGRANTS}.sql'||Chr(10)||
	          'Exit'||Chr(10);
	print(L_LINE);
End;
/
Spool Off

-- ===============================================[ User Data Part ]===

Spool ${USERSPOOL}.sql
Declare
	-- User information
	Cursor C_User_Info Is
	Select USERNAME,DEFAULT_TABLESPACE,TEMPORARY_TABLESPACE,PROFILE,ACCOUNT_STATUS,PASSWORD
	 From  DBA_USERS
	 Where lower(USERNAME) Not In ('sys','system','outln','dbsnmp')
	 Order By USER_ID;

	-- Tablespace Quota information
	Cursor C_Quota_Info Is
	Select * From DBA_TS_QUOTAS
	 Order By USERNAME;

 	L_LINE 		Varchar2(2000);		-- A line to output
	L6		Varchar2(9);		-- 6 spaces
	L4		Varchar2(9);		-- 4 spaces
	L2		Varchar2(9);		-- 2 spaces

$printfunc

Begin
   print('Spool createusers_${ORACLE_SID}.log');
	--
	-- Get the data for the other users
	--
	For Rec_UserData In C_User_Info Loop

	  L_LINE :=
	    'Create User '||Rec_UserData.USERNAME
	    ||' Identified By Values '''||Rec_UserData.PASSWORD||''''||Chr(10)||L4
	    ||'Default Tablespace '||Rec_UserData.DEFAULT_TABLESPACE||Chr(10)||L4
	    ||'Temporary Tablespace '||Rec_UserData.TEMPORARY_TABLESPACE||Chr(10)||L4
	    ||'Profile '||Rec_UserData.PROFILE
	    ||';'||Chr(10)||'/'||Chr(10);
	  print(L_LINE);
	End Loop;
	
	For Rec_Quota In C_Quota_Info Loop
	  L_LINE := 'Alter User '||Rec_Quota.USERNAME||' Quota ';
	  If Rec_Quota.MAX_BYTES = -1 Then
	    L_LINE := L_LINE||'Unlimited On ';
	  Else
	    L_LINE := L_LINE||Rec_Quota.MAX_BYTES||' On ';
	  End If;
	  L_LINE := L_LINE||Rec_Quota.TABLESPACE_NAME||';';
	  print(L_LINE);
	End Loop;
	L_LINE := '/'||Chr(10)||Chr(10);
	print(L_LINE);

	L_LINE := 'Spool Off'||Chr(10);

	print(L_LINE);
End;
/
Spool Off

-- ===============================================[ User Role Grants Part ]===

Spool ${ROLESPOOL}.sql

Declare
        -- Role information
        Cursor C_Roles Is
        Select * From DBA_ROLES;
	Cursor C_Role_Info Is
	Select * From DBA_ROLE_PRIVS
	 Where lower(GRANTEE) Not In ('sys','system','outln','dbsnmp')
	 Order By GRANTEE;

 	L_LINE 		Varchar2(2000);		-- A line to output
	L6		Varchar2(9);		-- 6 spaces
	L4		Varchar2(9);		-- 4 spaces
	L2		Varchar2(9);		-- 2 spaces

$printfunc

Begin	
   print('Spool ${ROLESPOOL}.log');
   print('--'||Chr(10)||'-- Creating Roles'||Chr(10)||'--');
   For R_R In C_Roles Loop
     L_LINE := 'CREATE ROLE '||R_R.ROLE;
     If R_R.PASSWORD_REQUIRED = 'GLOBAL' Then
       L_LINE := L_LINE||' IDENTIFIED GLOBALLY';
     End If;
     If R_R.PASSWORD_REQUIRED = 'YES' Then
       L_LINE := L_LINE||' IDENTIFIED BY '||R_R.ROLE;
     End If;
     print(L_LINE||';');
   End Loop;
   print(Chr(10)||'--'||Chr(10)||'-- Granting Roles'||Chr(10)||'--');
   For Rec_Role In C_Role_Info Loop
     L_LINE := 'GRANT '||Rec_Role.GRANTED_ROLE
       ||' To '||Rec_Role.GRANTEE;
     If Rec_Role.ADMIN_OPTION = 'YES' Then
       L_LINE := L_LINE||' With Admin Option';
     End If;
     L_LINE := L_LINE||';';
     print(L_LINE);
   End Loop;
   L_LINE := '/'||Chr(10)||Chr(10);
   print(L_LINE);
   L_LINE := 'Spool Off'||Chr(10);
   print(L_LINE);
End;
/
Spool Off


-- ===============================================[ User System Grants Part ]===

Spool ${SYSGRANTS}.sql

Declare
        -- System Privileges
	Cursor C_SysPriv_Info Is
	Select * from DBA_SYS_PRIVS
	 Where lower(GRANTEE) Not In ('sys','system','outln','dbsnmp','connect','dba','exp_full_database','imp_full_database','recovery_catalog_owner','resource','snmpagent','aq_administrator_role','aq_user_role','hs_admin_role','plustrace','tkprofer','ck_oracle_repos_owner')
	 Order By GRANTEE;

 	L_LINE 		Varchar2(2000);		-- A line to output
	L6		Varchar2(9);		-- 6 spaces
	L4		Varchar2(9);		-- 4 spaces
	L2		Varchar2(9);		-- 2 spaces

$printfunc

Begin
   print('Spool ${SYSGRANTS}.log');
	For Rec_SysPriv In C_SysPriv_Info Loop
	  L_LINE := 'GRANT '||Rec_SysPriv.Privilege
	    ||' To '||Rec_SysPriv.GRANTEE;
	  If Rec_SysPriv.ADMIN_OPTION = 'YES' Then
	    L_LINE := L_LINE||' With Admin Option';
	  End If;
	  L_LINE := L_LINE||';';
	  print(L_LINE);
	End Loop;
	L_LINE := '/'||Chr(10)||Chr(10);
	print(L_LINE);

	L_LINE := 'Spool Off'||Chr(10);

	print(L_LINE);
End;
/
Spool Off

-- ===============================================[ User Object Grants Part ]===

Spool ${OBJGRANTS}.sql
Declare
        -- Object Privileges (only those on sys/systems objects; all others
	-- are provided by exp/imp the schemes)
	Cursor C_TabPriv_Info Is
	Select * From DBA_TAB_PRIVS
	 Where lower(GRANTOR) In ('public','sys','system')
	   And GRANTEE Not In (Select ROLE From DBA_ROLES)
	   And lower(GRANTEE) Not In ('sys','system')
	 Order By GRANTEE,TABLE_NAME;

 	L_LINE 		Varchar2(2000);		-- A line to output
	L6		Varchar2(9);		-- 6 spaces
	L4		Varchar2(9);		-- 4 spaces
	L2		Varchar2(9);		-- 2 spaces

$printfunc
	
Begin
   print('Spool ${OBJGRANTS}.log');
	For Rec_TabPriv In C_TabPriv_Info Loop
	  L_LINE := 'GRANT '||Rec_TabPriv.PRIVILEGE
	    ||' On '||Rec_TabPriv.GRANTOR||'.'||Rec_TabPriv.TABLE_NAME
	    ||' To '||Rec_TabPriv.GRANTEE;
	  If Rec_TabPriv.GRANTABLE = 'YES' Then
	    L_LINE := L_LINE||' With Grant Option';
	  End If;
	  L_LINE := L_LINE||';';
	  print(L_LINE);
	End Loop;
	L_LINE := '/'||Chr(10)||Chr(10);
	print(L_LINE);

	L_LINE := 'Spool Off'||Chr(10);

	print(L_LINE);
End;
/
Spool Off

-- ===============================================[ Public Synonyms/DB_Links Part ]===

Spool ${SYNONYMS}.sql
Declare
	Cursor C_PubSyns Is
	Select * From DBA_SYNONYMS
         Where owner='PUBLIC'
           And table_owner Not In ('SYS','SYSTEM');
        Cursor C_Links Is
         Select u.name owner,l.name name,l.userid userid,l.password password,l.host host
           From sys.link$ l, sys.user$ u
          Where l.owner# = u.user#
          Order By l.name;

 	L_LINE 		Varchar2(2000);		-- A line to output
	L6		Varchar2(9);		-- 6 spaces
	L4		Varchar2(9);		-- 4 spaces
	L2		Varchar2(9);		-- 2 spaces

$printfunc
	
Begin
   print('Spool ${SYNONYMS}.log');
   print('');
   L_LINE := '--'||Chr(10)||'-- Creating public DB Links'||Chr(10)||'--';
   print(L_LINE);
   For Rec_Li in C_Links Loop
     If Rec_Li.owner = 'PUBLIC' Then
       L_LINE := 'CREATE PUBLIC DATABASE LINK '||Rec_Li.name||' CONNECT TO '||
                 Rec_Li.userid||' IDENTIFIED BY "'||Rec_Li.password||'" USING '''||
                 Rec_Li.host||''';';
     Else
       print('-- Private link for '||Rec_Li.owner||':');
       L_LINE := '-- CREATE DATABASE LINK '||Rec_Li.name;
       If Rec_Li.userid Is Not Null Then
         L_LINE := L_LINE||' CONNECT TO '||Rec_Li.userid||' IDENTIFIED BY "'||Rec_Li.password||'"';
       End If;
       L_LINE := L_LINE||' USING '''||Rec_Li.host||''';';
     End If;
     print(L_LINE);
   End Loop;
   
   L_LINE := Chr(10)||'--'||Chr(10)||'-- Creating public DB Links'||Chr(10)||'--';
   print(L_LINE);
	For Rec_Syn In C_PubSyns Loop
	  L_LINE := 'CREATE PUBLIC SYNONYM '||Rec_Syn.SYNONYM_NAME||' For '||
	            Rec_Syn.TABLE_OWNER||'.'||Rec_Syn.TABLE_NAME;
	  If Rec_Syn.DB_LINK Is Not Null Then
	    L_LINE := L_LINE||'@'||Rec_Syn.DB_LINK;
	  End If;
	  L_LINE := L_LINE||';';
	  print(L_LINE);
	End Loop;
	L_LINE := '/'||Chr(10)||Chr(10);
	print(L_LINE);

	L_LINE := 'Spool Off'||Chr(10);

	print(L_LINE);
End;
/
Spool Off


Exit

EOF

echo "Reverse engineering of DBCreate Sripts for $ORACLE_SID finished."

exit 0
