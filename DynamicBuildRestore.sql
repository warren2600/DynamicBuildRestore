
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
SET ARITHABORT ON;
GO

/*******************************************************************************************

Author: Warren Estes
Email: warren@warrenestes.com
Blog: warrenestes.com

MIT License
Copyright (c) 2017 Warren Estes

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*******************************************************************************************/

DECLARE @onlyLastFull INT = 1; 
DECLARE @onlyLastDIFF INT = 0; 
DECLARE @CustomBAKSource INT = 0;
DECLARE @CustomBAKPath VARCHAR(500); -- New path for restore location (DR/DEV scenario)
DECLARE @CustomLOGSource INT = 0;
DECLARE @DRRecover INT = 0;
DECLARE @singleuser INT = 0;
DECLARE @TargetDataPath NVARCHAR(100);
DECLARE @TargetLogPath NVARCHAR(100);
DECLARE @STOPAT DATETIME = NULL;
DECLARE @CustomLOGPath VARCHAR(500); 
DECLARE @WithMove INT = 0;
DECLARE @SingleDB INT = 0;
DECLARE @SingleDBName NVARCHAR(50);
DECLARE @AppendUNCtoLogPath INT;
DECLARE @DEBUG INT = 0;
DECLARE @DBNameFolderLog INT = 0;
DECLARE @StatsValue INT = 10;


/*******************************************************************************************

 BEGIN ASSIGN CUSTOM VARIABLES  
 
 Adjust the values below to control how the restore script is built

*******************************************************************************************/
SET @onlyLastFull = 0; 
SET @onlyLastDIFF = 0; 
SET @DRRecover = 0; 
SET @singleuser = 0; 
SET @WithMove = 0; 
SET @TargetDataPath = 'D:\Data\'; 
SET @TargetLogPath = 'L:\Log\'; 
SET @SingleDB = 1; 
SET @SingleDBName = 'Demo1'; 																
SET @CustomBAKSource = 0; 
SET @CustomBAKPath = '\\share\sql\backups\root\'; 
SET @AppendUNCtoLogPath = 0; 
SET @CustomLOGSource = 0; 
SET @CustomLOGPath = 'R:\Restore';
SET @DBNameFolderLog = 0; -- appends dbname after the custom log path
--SET @STOPAT = '8/22/2017 10:00am' --not tested
SET @StatsValue = 10;
SET @DEBUG = 0; 
/*******************************************************************************************

	END ASSIGN CUSTOM VARIABLES  
	
	Don't alter below this for building restore script

*******************************************************************************************/


/* DECLARE ALL OTHER VARIABLES */
DECLARE @LASTFULL DATETIME;
DECLARE @LASTDIFF DATETIME;
DECLARE @LogChainStart DATETIME; --Set the start logchain Time (not LSN accurate)
DECLARE @LOGCOUNT INT = 0;
DECLARE @iCount INT = 0;
DECLARE @NoDiff INT = 0;
DECLARE @NoLogs INT = 0;
DECLARE @DBID INT;
DECLARE @DBNAME NVARCHAR(100);
DECLARE @RecoveryID INT;
DECLARE @Device_Name NVARCHAR(500);
DECLARE @SQL NVARCHAR(2000);
DECLARE @SQLt NVARCHAR(200);
DECLARE @DATAFile NVARCHAR(200);
DECLARE @LogFile NVARCHAR(200);
DECLARE @FileGroupCount INT;
DECLARE @DataFileCount INT = 0;
DECLARE @iDataFileCount INT = 0;
DECLARE @LogicalFileName NVARCHAR(200);
DECLARE @NDFCount INT = 0;
DECLARE @Recovery NVARCHAR(20) = '';
DECLARE @isNoRecovery NVARCHAR(20) = 'NORECOVERY;';
DECLARE @isRecovery NVARCHAR(20) = 'RECOVERY;';
DECLARE @LASTDIFFNAME NVARCHAR(500);
DECLARE @LogPhysicalname NVARCHAR(500);
DECLARE @Options INT = 0;
DECLARE @Message NVARCHAR(1000); --message to display in output
DECLARE @singleuserval INT = 4; -- constant value for bitwise
DECLARE @nodiffval INT = 8; -- constant value for bitwise
DECLARE @nologsval INT = 16; -- constant value for bitwise
DECLARE @SERVERNAME VARCHAR(50); -- Store serveranme from @@servername for Log UNC path
DECLARE @LogPhysical VARCHAR(500);



/* if set log unc path is needed we need to get the machien name from @@servername */
/* add string substring to take out machine\instance */
IF @AppendUNCtoLogPath = 1
BEGIN
    SET @SERVERNAME =
    (
        SELECT @@servername
    );
    --chekc for backslash which indicates a named instance
    IF PATINDEX('%\%', @SERVERNAME) > 1
    BEGIN
        SET @SERVERNAME =
        (
            SELECT LEFT(@SERVERNAME, (PATINDEX('%\%', @SERVERNAME)) - 1)
        );
    END;


    IF @CustomLOGSource = 1
       AND @AppendUNCtoLogPath = 1
    BEGIN
        --add @servername to start of log path
        SET @CustomLOGPath = '\\' + @SERVERNAME + '\' + @CustomLOGPath;
    END;

END;


/* BEGIN SCRIPT */

SET @Message
    = '/* AUTOMATIC RESTORE SCRIPT ' + CAST(GETDATE() AS NVARCHAR(100)) + ' FOR SERVER: ' + QUOTENAME(@@SERVERNAME)
      + '*/' + CHAR(10);
IF @DEBUG = 1
BEGIN
    SET @Message = @Message + '/*' + CHAR(10);
    SET @Message = @Message + 'Variables:' + CHAR(10);
    SET @Message = @Message + 'OnlyRestoreLastFULL = ' + CAST(@onlyLastFull AS NVARCHAR(2));
    SET @Message = @Message + ' | OnlyRestoreLastDIFF = ' + CAST(@onlyLastDIFF AS NVARCHAR(2));
    SET @Message = @Message + ' | SingleUser = ' + CAST(@singleuser AS NVARCHAR(2));
    SET @Message = @Message + ' | TargetDataPath = ' + QUOTENAME(CAST(@TargetDataPath AS NVARCHAR(20)));
    SET @Message = @Message + ' | TargetLogPath = ' + QUOTENAME(CAST(@TargetLogPath AS NVARCHAR(20))) + CHAR(10);
    SET @Message = @Message + '*/' + CHAR(10);
END;
PRINT @Message;


/* ADD closing folder path if not present in variable */
IF RIGHT(@TargetDataPath, 1) <> '\'
BEGIN
    SET @TargetDataPath = @TargetDataPath + '\';
END;
IF RIGHT(@TargetLogPath, 1) <> '\'
BEGIN
    SET @TargetLogPath = @TargetLogPath + '\';
END;
IF RIGHT(@CustomBAKPath, 1) <> '\'
BEGIN
    SET @CustomBAKPath = @CustomBAKPath + '\';
END;
IF RIGHT(@CustomLOGPath, 1) <> '\'
BEGIN
    SET @CustomLOGPath = @CustomLOGPath + '\';
END;



IF @SingleDB = 0
BEGIN
    DECLARE DBSToRestore CURSOR FAST_FORWARD FOR
    SELECT database_id,
           [name],
           recovery_model
    FROM sys.databases
    WHERE database_id > 4
    ORDER BY database_id;
END;
ELSE
BEGIN
    DECLARE DBSToRestore CURSOR FAST_FORWARD FOR
    SELECT database_id,
           [name],
           recovery_model
    FROM sys.databases
    WHERE [name] = @SingleDBName;
END;

OPEN DBSToRestore;
FETCH NEXT FROM DBSToRestore
INTO @DBID,
     @DBNAME,
     @RecoveryID;
WHILE @@FETCH_STATUS = 0
BEGIN

IF @STOPAT IS NOT NULL
BEGIN
	IF @RecoveryID = 3
		BEGIN
			PRINT 'RECOVERY MODEL IS SIMPLE IGNORING @STOPAT'
		END
END
    /* assigning variables and counts */
    SET @NDFCount = 0;
    SET @iDataFileCount = 1;
    SET @LASTDIFF = '1/1/1900';
    SET @iCount = 0;
    SET @NoDiff = 0;
    SET @NoLogs = 0;
    SET @LOGCOUNT = 0;
    SET @Options = 0;
    SET @Recovery = @isNoRecovery; --set default to norecovery
    SET @Message = '';

    
 /*
options bitwise value meaning
onlylastfull = 1
onlylastdiff = 2
onlysingleuser = 4
nodiffs = 8
nologs = 16
*/

    /* assign first bit values of user set options */
    IF @onlyLastFull = 1
    BEGIN
        SET @Options += 1;
    END;

    IF @onlyLastDIFF = 1
    BEGIN
        SET @Options += 2;
    END;

    IF @singleuser = 1
    BEGIN
        SET @Options += 4;
    END;

    /* Get last full backup */
    SET @Device_Name =
    (
        SELECT bk.physical_device_name
        FROM
        (
            SELECT ROW_NUMBER() OVER (PARTITION BY B.database_name ORDER BY backup_start_date DESC) AS RowNumber,
                   B.database_name,
                   physical_device_name,
                   backup_start_date
            FROM msdb.dbo.backupset B
                INNER JOIN msdb.dbo.backupmediafamily M
                    ON B.media_set_id = M.media_set_id
            WHERE B.type = 'd'
                  AND B.database_name = @DBNAME
        ) bk
        WHERE bk.RowNumber = 1
    );


    /* Insert all backups into table */

    IF OBJECT_ID('tempdb..#BackupHistory') IS NOT NULL
    BEGIN
        DROP TABLE #BackupHistory;
    END;

    CREATE TABLE #BackupHistory
    (
        id INT IDENTITY(1, 1),
        dbname VARCHAR(100),
        backup_start_date DATETIME,
        backup_type CHAR(1),
        first_lsn NUMERIC(25, 0),
        Last_lsn NUMERIC(25, 0),
        database_backup_lsn NUMERIC(25, 0),
        physical_device_name VARCHAR(1000)
    );

    INSERT INTO #BackupHistory
    SELECT B.database_name,
           B.backup_start_date,
           B.type,
           B.first_lsn,
           B.last_lsn,
           B.database_backup_lsn,
           RTRIM(M.physical_device_name)
    FROM msdb..backupset B
        JOIN msdb..backupmediafamily M
            ON M.media_set_id = B.media_set_id
    WHERE B.database_name = @DBNAME
          AND B.backup_start_date >=
          (
              SELECT B.backup_start_date
              FROM msdb.dbo.backupset B
                  INNER JOIN msdb.dbo.backupmediafamily M
                      ON B.media_set_id = M.media_set_id
              WHERE M.physical_device_name = @Device_Name
                    AND B.database_name = @DBNAME
          )
    ORDER BY B.backup_start_date;

    /* Set last full date */
    SELECT @LASTFULL = MAX(backup_start_date)
    FROM #BackupHistory
    WHERE backup_type = 'D';


    /* need to know if no diffs or logs exist */
    IF (NOT EXISTS (SELECT * FROM #BackupHistory WHERE backup_type IN ( 'I' )))
    BEGIN
        SET @NoDiff = 1;
    END;
    IF (NOT EXISTS (SELECT * FROM #BackupHistory WHERE backup_type IN ( 'L' )))
    BEGIN
        SET @NoLogs = 1;
    END;


    -- IF another source is specified then we need to take the file name only from the physica_device_name
    -- split with XML, adding rownumber and taking top 1 reverse order
    IF @CustomBAKSource = 1
    BEGIN
        SET @Device_Name
            = @CustomBAKPath
              +
              (
                  SELECT TOP 1
                      ST.StringPart
                  FROM
                  (
                      SELECT ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS row_count,
                             x.i.value('.', 'VARCHAR(500)') AS StringPart
                      FROM
                          (
                              SELECT XMLEncoded =
                                     (
                                         SELECT @Device_Name AS [*] FOR XML PATH('')
                                     )
                          ) AS EncodeXML
                          CROSS APPLY
                          (
                              SELECT NewXML = CAST('<i>' + REPLACE(XMLEncoded, '\', '</i><i>') + '</i>' AS XML)
                          ) CastXML
                          CROSS APPLY NewXML.nodes('/i') x(i)
                  ) ST
                  ORDER BY ST.row_count DESC
              );
    END;

    IF (4 & @Options) = 4 --@singleuser = 1 
    BEGIN
        PRINT '/*** ' + QUOTENAME(@DBNAME) + ' SET SINGLE ***/';
        SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@DBNAME) + ' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;'; -- + CHAR(13)
        PRINT @SQL;
    END;
    PRINT '/*** ' + QUOTENAME(@DBNAME) + ' FULL RESTORE ***/';
    SET @SQL
        = 'Restore Database ' + QUOTENAME(@DBNAME) + ' FROM DISK = N''' + @Device_Name + '''' + CHAR(13) + 'WITH ';


    /* show last full for debug */
    IF @DEBUG = 1
    BEGIN
        SET @Message = '-- Last full date = ' + CAST(@LASTFULL AS NVARCHAR(50));
        PRINT @Message;
        SET @Message = '-- Recovery model = ' + CAST(@RecoveryID AS NVARCHAR(4)) + '[1=full,2=bulk,3=simple]';
        PRINT @Message;
    END;
	IF @STOPAT IS NOT NULL
		BEGIN
			IF @onlyLastDIFF = 1 or @onlyLastFull = 1
			BEGIN
			print '-- CANNOT USE STOPAT WITH FULL or DIFF ONLY, IGNORING STOPAT';
			END;
		END;

    /* assign bit values */
    IF @NoDiff = 1
    BEGIN
        SET @Options += 8;
        --PRINT '-- NO DIFFS';
    END;
    IF @NoLogs = 1
    BEGIN
        SET @Options += 16;
        --PRINT '-- NO LOGS';
    END;

/* setting recovery for full based on parameters and presence of diff/logs */	
IF @onlylastFull = 1
	BEGIN
		SET @recovery = @isrecovery;
		SET @Message = '-- Only last Full set';
	END
ELSE IF @onlylastdiff = 1
	BEGIN
		SET @recovery = @isNoRecovery;
		SET @Message = '-- Only Last Diff set';
		IF @NoDiff = 1 
			BEGIN
			SET @Message = '-- /* No diffs exist using last full only!  */';
			SET @Recovery = @isNoRecovery;
			END
		END
ELSE  IF @nologs = 1 and @nodiff = 1 -- no logs and no diffs 
	BEGIN
		SET @recovery = @isRecovery;
		SET @Message = '-- NO LOGS and NO DIFFS';
	END
ELSE IF  @nologs = 1 and @nodiff = 0 --no logs but diff 
	BEGIN
		SET @recovery = @isNoRecovery;
		SET @Message = '-- NO Logs,  DIFFS exist';

	END
ELSE IF @nodiff = 1 and @nologs = 0  --no diffs but logs exist
	BEGIN
		 SET @recovery = @isNoRecovery;
		 SET @Message = '-- NO DIFFS, Logs EXIST ';
		 
	END
ELSE IF @nodiff = 0 and @nologs = 0 --all files exist 
	BEGIN
		SET @Recovery = @isNoRecovery;
		SET @Message = '-- No options selected restoring all available';
	END
--at the end set NoRecovery is DR
IF @DRrecover = 1 
BEGIN
SET @recovery = @isNoRecovery;
END

  
  /*
 IF ((8 & @Options = 8) and (16 & @options = 0)) --no diffs, but logs exist so don't recover
    BEGIN
        SET @Recovery = @isNoRecovery;
        SET @Message = '-- NO DIFF! LOGS EXIST! ';
    END;

 IF ((8 & @Options = 8) AND (16 & @Options = 16)) --no diffs and no logs recover
    BEGIN
        SET @Recovery = @isRecovery;
        SET @Message = '-- NO DIFF! AND NO LOGS! ';
    END;
 IF (@DRRecover = 1)
        BEGIN
            SET @Recovery = @isNoRecovery;
            SET @Message = '-- DR NO RECOVERY';
        END;
IF ((1 & @options = 0) and (2 & @options = 0))  
	BEGIN
		SET @Message = '-- Applying all backup options'
	END
	*/

    IF @DEBUG = 1
    BEGIN
        PRINT @Message;
    END;

	/* Add the bitwise values to debug */
	--IF @DEBUG = 1 
		--BEGIN
			--SET @Message = (Select '-- Options bitwise Value = ' + CONVERT(VARCHAR(10),@Options));
			--Print @Message;
		--END

    /* TABLE variable for data files */
    IF OBJECT_ID('tempdb..#DataFiletable') IS NOT NULL
    BEGIN
        DROP TABLE #DataFiletable;
    END;


    /* create temp table with identity and row type*/

    CREATE TABLE #DataFileTable
    (
        row_id INT IDENTITY(1, 1),
        Fileid INT,
        typedesc VARCHAR(50),
        logicalname NVARCHAR(200)
    );
    INSERT INTO #DataFileTable
    (
        Fileid,
        typedesc,
        logicalname
    )
    SELECT file_id,
           type_desc,
           name
    FROM sys.master_files
    WHERE database_id = @DBID;


    /* get file count and loop through*/
    IF @WithMove = 1
    BEGIN
        --declare cursor variables
        DECLARE @fileid INT;
        DECLARE @typedesc VARCHAR(10);
        DECLARE @logicalname VARCHAR(50);

        SET @DataFileCount =
        (
            SELECT COUNT(row_id) FROM #DataFileTable WHERE typedesc = 'ROWS'
        );

        DECLARE db_master_files CURSOR FAST_FORWARD FOR
        SELECT Fileid,
               typedesc,
               logicalname
        FROM #DataFileTable
        ORDER BY Fileid ASC;

        OPEN db_master_files;
        FETCH NEXT FROM db_master_files
        INTO @fileid,
             @typedesc,
             @logicalname;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            --Iterate through data files 1= data, 2= log always, 3+ data always
            IF @typedesc = 'ROWS'
               AND @fileid = 1
            BEGIN
                SET @SQL
                    = @SQL + 'MOVE ''' + @logicalname + ''' To ''' + @TargetDataPath + @DBNAME + '.mdf'',' + CHAR(13);
            END;
            ELSE IF @typedesc = 'LOG'
            BEGIN
                SET @SQL
                    = @SQL + 'MOVE ''' + @logicalname + ''' To ''' + @TargetLogPath + @DBNAME + '_log.ldf'','
                      + CHAR(13);
            END;
            ELSE IF @typedesc = 'ROWS'
                    AND @fileid > 1
            BEGIN
                SET @NDFCount = @NDFCount + 1;
                SET @SQL
                    = @SQL + 'MOVE ''' + @logicalname + ''' To ''' + @TargetDataPath + @DBNAME + '_'
                      + CAST(@NDFCount AS NVARCHAR(1)) + '.ndf'',' + CHAR(13);
            /* Iterate NFF count */
            END;

            FETCH NEXT FROM db_master_files
            INTO @fileid,
                 @typedesc,
                 @logicalname;
        END;
        --put your toys away
        CLOSE db_master_files;
        DEALLOCATE db_master_files;
    END;


    --add stats and replace
    SET @SQL = @SQL + 'REPLACE, STATS = ' + CONVERT(NVARCHAR(3),@StatsValue) + ',';


    IF @DEBUG = 1 and @WithMove = 1
    BEGIN
        SET @Message
            = '-- Datafilecount = ' + CAST(@DataFileCount AS NVARCHAR(4)) + ' | NDFCount = '
              + CAST(@NDFCount AS NVARCHAR(4));
        PRINT @Message;
    END;


    SET @SQL = @SQL + @Recovery; -- + CHAR(13 ) 
    /* PRINT OUT THE FULL */
    PRINT @SQL;
    /* Reset Variables and counts */
    --SET @Recovery = 'RECOVERY;'
    SET @iDataFileCount = 1;
    SET @NDFCount = 1;

    --DELETE FROM #DataFileTable

    IF @Recovery = @isNoRecovery
    BEGIN
        /* Create the backup history table to count diffs and logs */

        IF @NoDiff = 0
           AND @onlyLastFull = 0
        BEGIN
            /* get last diff beyond last full*/
            SELECT @LASTDIFF = MAX(backup_start_date)
            FROM #BackupHistory
            WHERE backup_type = 'I'
                  AND backup_start_date > @LASTFULL;
        END;

        /* check diffs*/
        IF @NoDiff = 1
        BEGIN
            SET @LogChainStart = @LASTFULL;
        END;
        ELSE
        BEGIN
            SET @LogChainStart = @LASTDIFF;
            --assign last diff name
            SELECT @LASTDIFFNAME = physical_device_name
            FROM #BackupHistory
            WHERE dbname = @DBNAME
                  AND backup_type = 'I'
                  AND backup_start_date = @LASTDIFF;
        END;


        IF @CustomBAKSource = 1
        BEGIN
            SET @LASTDIFFNAME
                = @CustomBAKPath
                  +
                  (
                      SELECT TOP 1
                          ST.StringPart
                      FROM
                      (
                          SELECT ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS row_count,
                                 x.i.value('.', 'VARCHAR(500)') AS StringPart
                          FROM
                              (
                                  SELECT XMLEncoded =
                                         (
                                             SELECT @LASTDIFFNAME AS [*] FOR XML PATH('')
                                         )
                              ) AS EncodeXML
                              CROSS APPLY
                              (
                                  SELECT NewXML = CAST('<i>' + REPLACE(XMLEncoded, '\', '</i><i>') + '</i>' AS XML)
                              ) CastXML
                              CROSS APPLY NewXML.nodes('/i') x(i)
                      ) ST
                      ORDER BY ST.row_count DESC
                  );
        END;

        IF @NoLogs = 0
        BEGIN
            IF OBJECT_ID('tempdb..#LogBackupHistory') IS NOT NULL
                DROP TABLE #LogBackupHistory;


            CREATE TABLE #LogBackupHistory
            (
                id INT IDENTITY(1, 1),
                dbname VARCHAR(100),
                backup_start_date DATETIME,
                first_lsn NUMERIC(25, 0),
                Last_lsn NUMERIC(25, 0),
                database_backup_lsn NUMERIC(25, 0),
                physical_device_name VARCHAR(1000)
            );

/* using the identity, based on backup_start_date order, to run through backup chain order.
Need to change this to LSN
*/

            INSERT INTO #LogBackupHistory
            SELECT dbname,
                   backup_start_date,
                   first_lsn,
                   Last_lsn,
                   database_backup_lsn,
                   physical_device_name
            FROM #BackupHistory
            WHERE backup_type = 'L'
                  AND backup_start_date > @LogChainStart
                  AND dbname = @DBNAME
            ORDER BY backup_start_date;

           --if there are rows assign logcount variable, otherwise leave as 0
			if(exists(select 1 from #LogBackupHistory))
			BEGIN
			 SELECT @LOGCOUNT = MAX(id)
            FROM #LogBackupHistory;
			END
		--if there are no logs set nologs to 1
		if @LOGCOUNT = 0 set @nologs = 1

        END;

        /* CREATE DIFF BACKUP */
        IF ((@NoDiff = 0) AND (@onlyLastFull = 0))
        BEGIN
            PRINT '/*** ' + QUOTENAME(@DBNAME) + ' DIFFERENTIAL RESTORE ***/';
            SET @SQL
                = 'Restore Database ' + QUOTENAME(@DBNAME) + ' FROM DISK = N''' + @LASTDIFFNAME
                  + ''' WITH REPLACE, STATS = ' + CONVERT(NVARCHAR(3),@StatsValue) + ', '; -- + CHAR(13 )
        END;


        IF @onlyLastDIFF = 1
        BEGIN
            SET @Recovery = @isRecovery;
        END;
        ELSE IF @NoLogs = 1
        BEGIN
            SET @Recovery = @isRecovery;
        END;
        ELSE IF @RecoveryID = 3
        BEGIN
            SET @Recovery = @isRecovery;
        END;
       -- ELSE
        --    SET @Recovery = @isNoRecovery;

if @DRRecover = 1
BEGIN
	SET @Recovery = @isNoRecovery
END

        --only print if the variable changed. ie if last full only is not selected and diffs are present
        IF @NoDiff = 0
           AND @onlyLastFull = 0
        BEGIN
            SET @SQL = @SQL + @Recovery;
            PRINT @SQL;
        END;

        IF (@Recovery = @isNoRecovery)
           AND (@onlyLastDIFF = 0)
           AND (@RecoveryID = 1)
           AND (@onlyLastFull = 0)
        BEGIN
            /* transaction log cursor */
            PRINT '/* ' + QUOTENAME(@DBNAME) + ' TRANSACTION LOG RESTORES */';
            DECLARE LOGCursor CURSOR FAST_FORWARD FOR
            SELECT physical_device_name
            FROM #LogBackupHistory
            WHERE dbname = @DBNAME
            ORDER BY [id] ASC;

            IF @DEBUG = 1
            BEGIN
                SET @Message = '-- log backup count: ' + CAST(@LOGCOUNT AS NVARCHAR(8));
                PRINT @Message;
            END;

            OPEN LOGCursor;
            FETCH NEXT FROM LOGCursor
            INTO @LogPhysicalname;
            WHILE @@FETCH_STATUS = 0
            BEGIN

                --assign logphysicalname to logphysical, if customization occurs it happens after this initial assignment
                -- if no customization, we're good
                set @LogPhysical = @LogPhysicalname

                /* if a custom source - break up the device name and add path to file name only */
                --fix logphyciscal name SERVERNAME could be blank
                IF @CustomLOGSource = 1
                   OR @DBNameFolderLog = 1
                BEGIN

                    IF @CustomLOGSource = 1
                    BEGIN
                        SET @LogPhysical = @LogPhysical + @CustomLOGPath + '\';
                    END;

                    SET @LogPhysical = @CustomLOGPath;
                    IF @DBNameFolderLog = 1
                    BEGIN
                        SET @LogPhysical = @LogPhysical + @DBNAME + '\';
                    END;

                    SET @LogPhysical
                        = @LogPhysical
                          +
                          (
                              SELECT TOP 1
                                  ST.StringPart
                              FROM
                              (
                                  SELECT ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS row_count,
                                         x.i.value('.', 'VARCHAR(500)') AS StringPart
                                  FROM
                                      (
                                          SELECT XMLEncoded =
                                                 (
                                                     SELECT @LogPhysicalname AS [*] FOR XML PATH('')
                                                 )
                                      ) AS EncodeXML
                                      CROSS APPLY
                                      (
                                          SELECT NewXML = CAST('<i>' + REPLACE(XMLEncoded, '\', '</i><i>') + '</i>' AS XML)
                                      ) CastXML
                                      CROSS APPLY NewXML.nodes('/i') x(i)
                              ) ST
                              ORDER BY ST.row_count DESC
                          );

                END;


                IF @AppendUNCtoLogPath = 1
                BEGIN
                    SET @LogPhysical = '\\' + @SERVERNAME + '\' + REPLACE(@LogPhysicalname, ':', '$');
                END;


                -- if logphysical is null then assign cursor variable (no custom options have been selected)	
                IF @LogPhysical IS NULL
                BEGIN
                    SET @LogPhysical = @LogPhysicalname;
                END;

				
                IF @iCount < @LOGCOUNT - 1
                BEGIN
                    SET @SQL
                        = 'RESTORE LOG ' + QUOTENAME(@DBNAME) + ' FROM Disk =N''' + @LogPhysical + ''' WITH STATS = ' + CONVERT(NVARCHAR(3),@StatsValue) + ',';
						  IF @STOPAT IS NOT NULL
							BEGIN
							SET @SQL = @SQL + 'STOPAT=''' + CAST(@STOPAT as varchar(23)) + ''',';
							END;
						  SET @SQL = @SQL + 'NORECOVERY;';

                END;

                IF @iCount = @LOGCOUNT - 1
                BEGIN
                    SET @SQL
                        = 'RESTORE LOG ' + QUOTENAME(@DBNAME) + ' FROM DISK =N''' + @LogPhysical + ''' WITH STATS = ' + CONVERT(NVARCHAR(3),@StatsValue) + ',';
					 IF @STOPAT IS NOT NULL
							BEGIN
							SET @SQL = @SQL + 'STOPAT=''' + CAST(@STOPAT as varchar(23)) + ''',';
							END;

                    IF @DRRecover = 0
                    BEGIN
                        SET @SQL = @SQL + 'RECOVERY;'; --+ CHAR(10)
                    END;
                    ELSE
                    BEGIN
                        SET @SQL = @SQL + 'NORECOVERY;';
                    END;

                END;
                SET @iCount += 1;

                PRINT @SQL;

                FETCH NEXT FROM LOGCursor
                INTO @LogPhysicalname;
            END;
            CLOSE LOGCursor;
            DEALLOCATE LOGCursor;
        END;
    --only full backup while END
    END;
    --END full only
    IF (4 & @Options) = 4 --@singleuser = 1 
    BEGIN
        PRINT '/*** ' + QUOTENAME(@DBNAME) + ' SET MULTI ***/';
        SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@DBNAME) + ' SET MULTI_USER;'; --+ CHAR(10) 
        PRINT @SQL;
    END;

    --Carriage Return for readability
    PRINT CHAR(13);

    FETCH NEXT FROM DBSToRestore
    INTO @DBID,
         @DBNAME,
         @RecoveryID;
END;

CLOSE DBSToRestore;
DEALLOCATE DBSToRestore;












