# DynamicBuildRestore
T-SQL script to build restore scripts for all, or one, databases on an available instance. 
This only creates the commands, it does not run them. You will need to cut and paste the results from the source to the target instance.

This currently only uses MSDB data, so no pointing to a directory.

This is great for re-seeding Log Shipping on an instance with many DBs.


## CUSTOMIZABLE VARIABLE DESCRIPTIONS ##

**@onlyLastFull**
0 - use last full + 
1 - only use last full only. Ignores all other subsequent backups in the chain (diff + logs)

**@onlyLastDIFF**
0 - use last diff +
1 - Only use last diff. Ignores all other subsequent backups in the chain (logs)

**@DRRecover**
0 - use With RECOVERY
1 - use with NORECOVERY

**@singleuser**
0 - default
1 - Sets DB to single user mode, and attempts to reset to multi after

**@WithMove**
0 - No moving of physical data/log files
1 - WITH MOVE DATA/LOG files

**@TargetDataPath** - Value of data file path used only when @WithMove is set to 1

**@TargetLogPath** - Value of log file path used only when @WithMove is set to 1

**@SingleDB**
0 - Get all DB restores built
1 - Only 1 DB restore built

**@SingleDBName** - The single DB you want to create restore script for. Only used with @SingleDB is set to 1

**@CustomBAKSource**
0 - No change to file path
1 - Removes file names from backup source string

**@CustomBAKPath** - Appends path to backup file names. Only used when @CustomBAKSource is set to 1

**@AppendUNCtoLogPath**
0 - No change to LOG File path
1 - Uses UNC to replace drive letter with source @@servername. Only usefull if logs are backed up to drive letter.

**@CustomLOGSource**
0 - No change to LOG path
1 - Change LOG path (separates log trn name from location, to be used with @CustomLOGPath variable)

**@CustomLOGPath** - Path used to append to LOG filename. Only used when @CustomLOGSource is set to 1

**@DBNameFolderLog**
0 - Don't add DBname to log path
1 - Append Databse name to @CustomLogPath


**@Debug**
0 - Don't show internal information
1 - Show internal information
 