
------------------READ BEFORE RUNNING--------------------------------------
/* Restore [PIMCO_Consolidated] database, 
   Import raw data as [Raw_Data] tabel into [PIMCO_Consolidated] database, and then run scripts below
   - Make sure raw data column names are same as select statement in 00 session
   - All date-related columns are dynamic variables align with current period data, no need to change date or column name mannually
   - If any cash desk missed after checking with fund list in the current cycle, the rest of script will stop running
   - Dynamic SQL query including variable@ needs to be run starting from DECLARE statement of variables
   - Temp tables will be deleted automatically if disconnect from data engine 
     (temp tables: ##Month_Total, ##Month, ##Percentage, ##MonthName, ##MonthNamePercent, ##Temp1, ##Temp2, ##Temp3, ##Temp4, ##Temp5)
   - In 08 session, when create tables for each file group, need to change file group number and refresh Excel model to generate multiple workbooks
*/

/* 00
	- Convert data types of raw data into correct format
	- Create [Clean_Data] table to contain cleaned data
*/

DROP TABLE IF EXISTS Clean_Data;

---- Create table for correct data type ----
CREATE TABLE Clean_Data (			
						 Price_Date			      DATE           
						,Fund_Type				  NVARCHAR(255)
						,Fund_Name			      NVARCHAR(255)
						,Share_Class			  NVARCHAR(255)
						,Fund					  NUMERIC(10,0)
						,Cash_Desk				  NUMERIC(10,0)
						,Account				  NUMERIC(10,0)
					    ,Social_Code              NUMERIC(10,0)
					    ,Social_Code_Description  NVARCHAR(255)
					    ,Regline1                 NVARCHAR(255)
					    ,Regline2                 NVARCHAR(255)
					    ,Total_Shares             FLOAT
					    ,Total_Assets             FLOAT
					    ,Price                    FLOAT
	                    )

---- Insert [Raw_Data] into [Clean_Data] table in correct data types ----
INSERT INTO Clean_Data (
                        Price_Date
                       ,Fund_Type
					   ,Fund_Name
					   ,Share_Class
					   ,Fund 
                       ,Cash_Desk
					   ,Account
					   ,Social_Code
					   ,Social_Code_Description
					   ,Regline1
					   ,Regline2
					   ,Total_Shares
					   ,Total_Assets
					   ,Price
					   )
SELECT  CAST(PRICE_DATE AS DATE)						AS Price_Date
	   ,CAST(FDNAME3 AS NVARCHAR(255))					AS Fund_Type
	   ,CAST(FUND_NAME AS NVARCHAR(255))			    AS Fund_Name
	   ,CAST(SHARE_CLASS AS NVARCHAR(255))			    AS Share_Class
	   ,CAST(FUND AS NUMERIC(10,0))						AS Fund 
	   ,CAST(CASH_DESK AS NUMERIC(10,0))				AS Cash_Desk
	   ,CAST(ACCOUNT AS NUMERIC(10,0))					AS Account
	   ,CAST(SOCIALCODE AS NUMERIC(10,0))				AS Social_Code
	   ,CAST(SOCIALCODE_DESCRIPTION AS NVARCHAR(255))   AS Social_Code_Description
	   ,CAST(REGLINE1 AS NVARCHAR(255))					AS Regline1
	   ,CAST(REGLINE2 AS NVARCHAR(255))					AS Regline2
	   ,CAST(TOTAL_SHARES AS FLOAT)						AS Total_Shares
	   ,CAST(TOTAL_ASSETS AS FLOAT)						AS Total_Assets
	   ,CAST(PRICE AS FLOAT)							AS Price
FROM  Raw_Data

/* 01
	- Select only the funds that are flagged as "Yes" for testing (assume "Active" for all entries)

	- Create table [In_Scope_Data] which contains all columns and rows in [Clean_Data], and appends "Active" column

	- Over-write "Cash Desk" values 4141 to 4142, 4121 to 4122, and 4778 to 4758

*/	   
DROP TABLE IF EXISTS In_Scope_Data;

SELECT Price_Date
      ,Fund_Type
      ,Fund_Name
      ,Share_Class
      ,Fund
      ,CASE WHEN Cash_Desk = '4141' THEN '4142'
			WHEN Cash_Desk = '4121' THEN '4122'
			WHEN Cash_Desk = '4778' THEN '4758'
			--WHEN UPPER(FUND_NAME) LIKE '%PIMCO ESG INCOME%' THEN '14756' -- March Cycle update for PIMS
			ELSE Cash_Desk END AS Cash_Desk
      ,Account
      ,Social_Code
      ,Social_Code_Description
      ,Regline1
      ,Regline2
      ,Total_Shares
      ,Total_Assets
      ,Price
	  ,'Yes' AS Active
INTO In_Scope_Data
FROM Clean_Data
WHERE Fund_Type IN ('ESVT','PVIT') OR (Fund_Type = 'ITVL' AND Cash_Desk = '14751')


/* 01 Check Raw Data with Current and Prior Cycle Fund List

    - Import current cycle fund list as [Fund_List_Current] table

	- Add [Fund_List_Current] into prior fund list table [00_Fund_List_InScope]
	
	- Check current cycle fund list: 
	  If cash desk in the current cycle fund list but not in the clean data, label in Check_Current and select the cash desks in the warning table
	  If all cash desks in the fund list exist in the clean data, no cash desk selected

	- Check prior cycle fund list: (current and previous Clean Data)
	  If cash desk exists in both one year prior and current, labeled as "Continued";
	  If only exists in current cycle, labeled as "New";
	  If only exists in prior year, labeled as "Discontinued"
	  Select cash desks that are New or Discontinued in the warning table

*/	   

---- Create Fund list table (if not exists)
--CREATE TABLE [00_Fund_List_InScope] (	
--                       CashDesk#                NUMERIC(10,0)
--						,Cycle_Date			      DATE
--						,Fund_Type                NVARCHAR(255)
--						,CashDesk_RawData	      NUMERIC(10,0)
--						,Count_CD				  NUMERIC(10,0)
--					    ,Total_Shares             FLOAT
--						,CashDesk_FundList	      NUMERIC(10,0)
--						,Check_Current            NVARCHAR(255)
--						,Check_Prior              NVARCHAR(255)
--	                    )


---- If current cycle fund list has not been added, append into previous fund list 

IF NOT EXISTS 
         (SELECT Cycle_Date 
		  FROM [00_Fund_List_InScope], [In_Scope_Data]
		  GROUP BY Cycle_Date
		  HAVING Cycle_Date = MAX(Price_Date))
BEGIN

	---- Check if cash desk in the raw data match with fund list scope in the current cycle
	INSERT INTO [00_Fund_List_InScope] 
	            (        CashDesk#                
						,Cycle_Date			      
						,Fund_Type                
						,CashDesk_RawData	      
						,Count_CD				  
					    ,Total_Shares             
						,CashDesk_FundList	      
						,Check_Current)  
	SELECT   ROW_NUMBER() OVER(ORDER BY ISD.Fund_Type ASC)  AS CashDesk# 
			,'2021-12-31'                               AS Price_Date    -- change for every period, max date for cash desk may not equal to current period 
			,ISD.Fund_Type				                AS Fund_Type
			,ISD.Cash_Desk                               AS CashDesk_RawData
			,COUNT(ISD.Cash_Desk)                        AS Count_CD
			,SUM(ISD.Total_Shares)                       AS Total_Shares 
			,FL.PIMCO_ID                                AS CashDesk_FundList
			,CASE WHEN ISD.Cash_Desk IS NULL THEN 'Not in raw data, but in scope' 
				  WHEN FL.PIMCO_ID  IS NULL THEN 'Not in scope, but in raw data'
				  ELSE 'Cash desk is in scope and in raw data' END AS Check_Current
	FROM  In_Scope_Data AS ISD
		  FULL OUTER JOIN [Fund_List_Current] AS FL
		  ON ISD.Cash_Desk = FL.PIMCO_ID
	GROUP BY ISD.Cash_Desk, FL.PIMCO_ID, ISD.Fund_Type

END

-- check result of updated inscope fund list
SELECT * FROM [00_Fund_List_InScope] ORDER BY Cycle_Date DESC, CashDesk# ASC 

------------- Check Current Cycle ----------------
---- If find cash desk 'Not in raw data, but in scope' (CashDesk_Rawdata is null), raise error message and stop execution

-- Declare current cycle variables
DECLARE @ErrorMsg NVARCHAR(400)
DECLARE @CurrentCycleDate DATE

SELECT @CurrentCycleDate = MAX(Price_Date) FROM In_Scope_Data

PRINT @CurrentCycleDate 


IF EXISTS (
      SELECT CashDesk_FundList FROM [00_Fund_List_InScope] WHERE CashDesk_RawData IS NULL AND Cycle_Date = @CurrentCycleDate)
BEGIN  
      SET  @ErrorMsg = 'Cash desk missing from raw data, all execution paused' 
	  SELECT @ErrorMsg AS  IfCashDeskMissing, CashDesk_FundList AS Missing_CashDesk 
			 FROM [00_Fund_List_InScope] 
			 WHERE CashDesk_RawData IS NULL AND Cycle_Date = @CurrentCycleDate
	  --SET NOEXEC ON
      RETURN 	
END
ELSE IF NOT EXISTS (
      SELECT CashDesk_FundList FROM [00_Fund_List_InScope] WHERE CashDesk_RawData IS NULL AND Cycle_Date = @CurrentCycleDate)
BEGIN
      SET     @ErrorMsg = 'All in-scope cash desks exist in raw data, please continue'
      SELECT  @ErrorMsg AS IfCashDeskMissing
      RETURN 
END



------------- Check Prior Cycle ----------------
---- If cash desk exists in both one year prior and current, labeled as "Continued";
---- If only exists in current cycle, labeled as "New";
---- If only exists in prior year, labeled as "Discontinued"
---- Select cash desks that are New or Discontinued

-- Declare one year prior date variables
DECLARE @CurrentCycleDate2 DATE,
        @PriorCycleDate    DATE,
        @PriorCycleTable   NVARCHAR(MAX) = '';

SELECT @CurrentCycleDate2 = MAX(Price_Date) FROM Clean_Data
SELECT @PriorCycleDate = DATEADD(YEAR,-1,MAX(Price_Date)) FROM Clean_Data
SELECT @PriorCycleTable  = '[dbo].[00_Export_Current @ ' + CONVERT(NVARCHAR(4),YEAR(@PriorCycleDate)) + '.'+ CONVERT(NVARCHAR(2),MONTH(@PriorCycleDate)) + ']'

PRINT @CurrentCycleDate2
PRINT @PriorCycleDate
PRINT @PriorCycleTable

-- Flag as New/Continued/Discontinued by comparing current and one year prior cycle cash desk list, output New/Discontinued cash desks
--(WIP: Current and prior date need to be fix)
EXEC('
SELECT *
FROM (
    SELECT DISTINCT CD.Fund_Type
       ,'+@CurrentCycleDate2+' AS Current_CycleDate
	   ,'+@PriorCycleDate+'    AS PriorYear_CycleDate
       , CD.Cash_Desk AS Current_CD
	   , PC.[Cash Desk] AS PriorYear_CD
	   , CASE WHEN CD.Cash_Desk IS NOT NULL AND  PC.[Cash Desk] IS NOT NULL THEN ''Continued''
	          WHEN CD.Cash_Desk IS NULL AND  PC.[Cash Desk] IS NOT NULL THEN ''Discontinued''
			  ELSE ''New'' END AS Check_Prior
    FROM In_Scope_Data CD
    FULL OUTER JOIN '+@PriorCycleTable+' PC
    ON CD.Cash_Desk = PC.[Cash Desk] 
	) a
WHERE Check_Prior != ''Continued''
ORDER BY Fund_Type ASC, Check_Prior ASC
')


/*  02
	- Compute the total shares held of all funds under the same "Cash Desk" code in each of
	  the past 12 months.
	  
	- In other words, the new table [Monthly_Shares] contains a "Cash Desk" column and
	  12 "Monthly Total" columns; for each distinct "Cash Desk" code, shares held in each month is stored.
*/

DROP TABLE IF EXISTS Monthly_Shares;

---- Add "Year_Month_Total" column for pivot table----
ALTER TABLE In_Scope_Data 
ADD Year_Month_Total 
AS (CAST(YEAR(Price_Date) AS VARCHAR(4)) + '_' + FORMAT(Price_Date, 'MM') + '_Total')

---- Create variable to get list of "YearMonth" column for pivot table----
DECLARE 
     @MonthTotal                 NVARCHAR(MAX) = ''
	,@MonthTotalIsNull           NVARCHAR(MAX) = ''
	,@SQL1                       NVARCHAR(MAX) = ''

SELECT 
     @MonthTotal += QUOTENAME(Year_Month_Total) + ','
	,@MonthTotalIsNull += 'ISNULL(' + QUOTENAME(Year_Month_Total) + ',0)' + 'AS' + QUOTENAME(Year_Month_Total) + ','
FROM 
    (
	 SELECT Year_Month_Total
     FROM In_Scope_Data
     GROUP BY Year_Month_Total
    ) AS a
ORDER BY Year_Month_Total ASC 

SET @MonthTotal       = LEFT(@MonthTotal, LEN(@MonthTotal) - 1)
SET @MonthTotalIsNull = LEFT(@MonthTotalIsNull, LEN(@MonthTotalIsNull) - 1)

-- Store variables into global temp table --
DROP TABLE IF EXISTS ##Month_Total
SELECT @MonthTotal AS Ym_Total, @MonthTotalIsNull AS Ym_Total_Isnull 
INTO ##Month_Total

PRINT @MonthTotal
PRINT @MonthTotalIsNull

---- Dynamic pivot table to calculate total shares for each month ----
SET @SQL1 =' 
            SELECT Fund_Type
	              ,Cash_Desk
	              ,'+ @MonthTotalIsNull +'
            INTO Monthly_Shares
            FROM
                (SELECT Fund_Type
	            ,Cash_Desk
	            ,Total_Shares
	            ,Year_Month_Total
                FROM In_Scope_Data
                ) AS PivotData
        PIVOT
            (
			 SUM(Total_Shares)
             FOR Year_Month_Total IN ('+ @MonthTotal +')
            ) AS PivotResult
			'

EXECUTE SP_EXECUTESQL @SQL1


/* 03
	- Store the total shares held for each distinct Account# in each month,
	  as well as the total monthly shares held for the Account's respective "Cash Desk".
	
	- This is for the purpose of future computation.
*/

DROP TABLE IF EXISTS Breakdown_Acct;

---- Add "YearMonth" column for pivot table----
ALTER TABLE In_Scope_Data 
ADD Year_Month 
AS (CAST(YEAR(Price_Date) AS VARCHAR(4))+ '_'+ FORMAT(Price_Date, 'MM'))

---- Get list of YearMonth column for pivot table----
DECLARE 
     @Month             NVARCHAR(MAX) = ''
	,@MonthIsNull       NVARCHAR(MAX) = ''
	,@MonthTotal        NVARCHAR(MAX) = ''
	,@SQL2              NVARCHAR(MAX) = ''

SELECT 
     @Month += QUOTENAME(Year_Month) + ','
	,@MonthIsNull += 'ISNULL(' + QUOTENAME(Year_Month) +',0)' + 'AS' + QUOTENAME(Year_Month) + ','
FROM 
    (
	 SELECT Year_Month
     FROM In_Scope_Data
     GROUP BY Year_Month
    ) AS a
ORDER BY Year_Month ASC


SET @Month = LEFT(@Month, LEN(@Month) - 1)
SET @MonthIsNull = LEFT(@MonthIsNull, LEN(@MonthIsNull) - 1)

-- Extract variable from temp table--
SELECT @MonthTotal = Ym_Total FROM ##Month_Total

-- Store variable into global temp table --
DROP TABLE IF EXISTS  ##Month
SELECT @Month AS YM, @MonthIsNull AS YM_IsNull 
INTO   ##Month

PRINT  @Month
PRINT  @MonthIsNull
PRINT  @MonthTotal

---- Dynamic pivot table to calculate total shares for each account in each month----
SET @SQL2 =' 
            SELECT Cash_Desk
                  ,Social_Code
                  ,Account
	              ,'+ @MonthIsNull +'
	              ,'+ @MonthTotal +'
            INTO Breakdown_Acct
            FROM
                (SELECT ISD.Cash_Desk
                       ,Social_Code
                       ,Account
					   ,Total_Shares
	                   ,Year_Month
	                   ,'+ @MonthTotal +'
                 FROM In_Scope_Data AS ISD
                      LEFT JOIN Monthly_Shares AS MS
                      ON ISD.Cash_Desk = MS.Cash_Desk
                ) AS PivotData
        PIVOT
            (
             SUM(Total_Shares)
             FOR Year_Month IN ('+ @Month +')
            ) AS PivotResult
			'
        

EXECUTE SP_EXECUTESQL @SQL2;

/* 04	  

	- Seperate public accounts from Omnibus accounts, and creates [Omnibus_Override_Acct] that flags all omnibus accounts.
	  Public accounts are excluded when computing percentages, but omnibus accounts are included.

	- For accounts which charge to both a non-omnibus social code and an omnibus social code,
	  be sure not to flag the values associated with the omnibus into public,
	  but rather include them with the account when calculating >5% shareholder threshold.
*/
DROP TABLE IF EXISTS Omnibus_Override_Acct
DROP TABLE IF EXISTS ##Temp1;

SELECT  Cash_Desk
	   ,Account
	   ,COUNT(Social_Code) AS Social_Code_Count
INTO    ##Temp1
FROM   (
        SELECT DISTINCT Account
             ,Social_Code
	         ,Cash_Desk
        FROM In_Scope_Data
	    ) AS a
GROUP BY Cash_Desk, Account


---- If Social_Code_Count > 1 AND (Social_Code = '9' OR Social_Code = '995'), then this account has to be omnibus ----
---- If total rows = social code count, then entire account is omnibus and flag these into public ----
---- When "Omnibus_Override" = 1, it means the account is still needed to calculate the percentage ----

SELECT  temp.Cash_Desk
       ,temp.Account  
	   ,Social_Code_Count
	   ,Social_Code_Count_9_995
	   ,CASE WHEN Social_Code_Count = Social_Code_Count_9_995 THEN 0
			 ELSE 1 END AS Omnibus_Override
INTO    Omnibus_Override_Acct
FROM   (
	    SELECT BA.Cash_Desk
              ,BA.Account
	          ,Social_Code_Count
              ,SUM(CASE WHEN Social_Code_Count > 1 AND (Social_Code = '9' OR Social_Code = '995')
	               THEN 1
			       ELSE 0
			       END) AS Social_Code_Count_9_995
        FROM   Breakdown_Acct AS BA
               LEFT JOIN ##Temp1
                    ON   BA.Cash_Desk = ##Temp1.Cash_Desk
                    AND  BA.Account = ##Temp1.Account
        GROUP BY BA.Cash_Desk, BA.Account, Social_Code_Count) AS temp
WHERE Social_Code_Count > 1 AND Social_Code_Count_9_995 > 0
ORDER BY temp.Cash_Desk, Account


/* 05
	- Count number of accounts in each active cash desk.
	
	- Active is because Breakdown_Acct comes from In_Scope_Data, which is filtered by Active='Yes'.
*/

DROP TABLE IF EXISTS Acct_Count_for_Active_CashDesk


SELECT Cash_Desk 
      ,COUNT(Account) AS Number_Of_Accounts
INTO   Acct_Count_for_Active_CashDesk 
FROM  (
       SELECT DISTINCT Cash_Desk, Account 
	   FROM Breakdown_Acct) AS a
GROUP BY Cash_Desk
ORDER BY Number_Of_Accounts ASC


/*
   FOR MARCH UPDATE ONLY (more accounts)
   - Divide accounts into file groups, seperate PIMS and PAPS fund type first (or other names depend on cycle), 
     each file group can contain no more than 60,000 accounts and 20 cash desks.
   - Create [File_Group_Partition]
   IF NOT MARCH, '1' AS File_Group for each fund type
*/

DROP TABLE IF EXISTS File_Group_Partition; 

---- Create table ----
CREATE TABLE File_Group_Partition 
       (
        RowID                             INT IDENTITY(1,1)                NOT NULL
	   ,Fund_Type                         NVARCHAR(MAX)                    NOT NULL
       ,Cash_Desk                         NUMERIC(10,0)                    NOT NULL
	   ,Number_Of_Accounts                NUMERIC(10,0)                    NOT NULL DEFAULT 1
	   ,Cum_Num_Accounts                  NUMERIC(10,0)                    NULL DEFAULT 0
	   ,Number_of_CashDesk                NUMERIC(10,0)                    NOT NULL DEFAULT 1
	   ,File_Group                        INT                              NULL   
       )

---- Insert distinct cash desks and respective sum of accounts ----
INSERT INTO File_Group_Partition (Fund_Type, Cash_Desk, Number_Of_Accounts)
SELECT      Fund_Type
           ,ACAC.Cash_Desk
	       ,Number_Of_Accounts
FROM        Acct_Count_for_Active_CashDesk AS ACAC
            LEFT JOIN In_Scope_Data AS ISD 
	             ON ACAC.Cash_Desk = ISD.Cash_Desk
GROUP BY Fund_Type, ACAC.Cash_Desk, Number_Of_Accounts

---- Assign file group ID base on three criterias ----
-- Declare variables
DECLARE @Cur               AS INT
       ,@Max               AS INT
	   ,@MaxCashDesk       AS INT
	   ,@MaxRunTotal       AS NUMERIC(10,0)
       ,@RunTotal          AS NUMERIC(10,0)
	   ,@GroupID           AS INT
	   ,@CashDeskCount     AS INT
	   ,@LastName          AS NVARCHAR(MAX)
	   ,@CurName           AS NVARCHAR(MAX);

-- Set initial variables
SELECT  @Cur = MIN(RowID)
       ,@Max = MAX(RowID)
       ,@MaxCashDesk = 20
	   ,@MaxRunTotal = 60000
	   ,@GroupID = 1
	   ,@RunTotal = 0
	   ,@CashDeskCount = 0
FROM   File_Group_Partition

-- Assign default fund type to variable 
SELECT @LastName = FGP.Fund_Type 
FROM   File_Group_Partition AS FGP 
WHERE  FGP.RowID = @Cur

-- Loop through each row
WHILE  @Cur <= @Max + 1
BEGIN
       
       -- Get current row values
       SELECT  @RunTotal = @RunTotal + FGP.Cum_Num_Accounts
	          ,@CashDeskCount = @CashDeskCount + 1
			  ,@CurName = FGP.Fund_Type 
	   FROM    File_Group_Partition AS FGP 
	   WHERE   FGP.RowID = @Cur
       
	   -- Start loop if three criterias are satisfied
       IF @RunTotal >= @MaxRunTotal OR @CashDeskCount > @MaxCashDesk OR @LastName <> @CurName
       BEGIN
              
              -- Reset values and increment group id
            SELECT @RunTotal = FGP.Cum_Num_Accounts
			      ,@CashDeskCount = 1
			      ,@GroupID = @GroupID + 1 
			FROM File_Group_Partition AS FGP 
			WHERE RowID = @Cur

       END

       -- Update values in [File_Group_Partition] table for each row
       UPDATE FGP
       SET    FGP.Cum_Num_Accounts = @RunTotal
	         ,FGP.Number_of_CashDesk = @CashDeskCount
			 ,FGP.File_Group = @GroupID
       FROM File_Group_Partition AS FGP
       WHERE FGP.RowID = @Cur

       -- Increment current row id and update current fund type name
       PRINT CAST( @Cur AS NVARCHAR(MAX))
       SELECT @Cur = @Cur + 1, @LastName = @CurName
END 


SELECT * FROM File_Group_Partition


/* 06
	
	- Use [Tracking_Prior @ YYYY.MM] that matches same period as current period.  
	  i.e. If update at 2021.03, use [Tracking_Prior @ 2021.03] which refers one year prior tracking records.

	- DO NOT TRACK Omnibus Accounts (Social Code 9 or 995) no matter Flag_%Threshold and Flag_PreviouslyTracked
	- If account books value to a non-omnibus social code and an omnibus social code at the same time,
	  Do not flag values as omnibus because want to include in the calculation
	- Flag account if ownership percentage surpasses 5% threshold
	- Flag account if funds were checked in the previous cycle 
	  (only need to check at the date exactly one year prior (i.e. if valuation 12.31.15, check at 12.31.14)

*/

DROP TABLE IF EXISTS OWNERSHIP_CONSOLIDATION
DROP TABLE IF EXISTS Tracking_Prior
DROP TABLE IF EXISTS ##Temp2
DROP TABLE IF EXISTS ##Temp3
DROP TABLE IF EXISTS ##Percentage

DECLARE   @Month                     AS NVARCHAR(MAX) = '',
		  @PriorTableName            AS NVARCHAR(MAX) = '',
		  @SQL0                      AS NVARCHAR(MAX) = '';

-- Load month varibles from temp table
SELECT @Month = YM FROM ##Month

-- Select [Tracking_Prior @ xxxx.xx] table that aligns with current period
SELECT @PriorTableName = '[dbo].[00_Tracking_Prior @ ' + REPLACE(REPLACE(RIGHT(@Month,8), '_', '.'),']','') +']'

PRINT @PriorTableName

-- Create [Tracking_Prior] to store matched table values
SET @SQL0 = 'SELECT *
             INTO Tracking_Prior
			 FROM '+@PriorTableName+'';

EXECUTE SP_EXECUTESQL @SQL0;

---- Create [Flag_Omnibus] to flag omnibus accounts ----
---- Only override [Flag_Omnibus] when Omnibus_Override = 1 ----

DECLARE  @Month    AS NVARCHAR(MAX) = '',
	     @SQL3     AS NVARCHAR(MAX) = '';

SELECT @Month = [YM] FROM ##Month

PRINT  @Month
------------------
SET @SQL3 =' 
  SELECT BA.Cash_Desk
        ,BA.Account
	    ,Social_Code
        ,'+ @Month +'
	    ,CASE WHEN Social_Code IN (''9'', ''995'') AND ISNULL(Omnibus_Override, 0) <> 1 THEN 1
         ELSE 0 END AS Flag_Omnibus
  INTO  ##Temp2
  FROM  Breakdown_Acct AS BA
        LEFT JOIN Omnibus_Override_Acct AS OOA
        ON BA.Cash_Desk = OOA.Cash_Desk
        AND BA.Account = OOA.Account
  ORDER BY BA.Cash_Desk ASC, BA.Account ASC';

EXECUTE SP_EXECUTESQL @SQL3;


---- Calculate Ownership Percentages for each account ----

DECLARE @Month                     AS NVARCHAR(MAX) = '',
	    @MonthTotal                AS NVARCHAR(MAX) = '',
	    @SumMonth                  AS NVARCHAR(MAX) = '',
	    @Division                  AS NVARCHAR(MAX) ='',
	    @PercentMonth              AS NVARCHAR(MAX) ='',
	    @PercentCase               AS NVARCHAR(MAX) ='',
	    @SQL4                      AS NVARCHAR(MAX) = '';

-- Load month varibles from temp table
SELECT @MonthTotal = Ym_Total FROM ##Month_Total
SELECT @Month = YM FROM ##Month

-- Define dynamic varible calculatios
SELECT @SumMonth += 'SUM(' + QUOTENAME(Year_Month)+ +') AS '+ QUOTENAME(Year_Month) + ','
	  -- Divide shares of each account by monthly total shares to calculate ownership percentage --
	  ,@Division += 'ISNULL('+ QUOTENAME(Year_Month)+'/NULLIF('+ QUOTENAME(Year_Month_Total) + ',0),0) AS ' + QUOTENAME(Year_Month +'%') + ','
	  ,@PercentMonth +=  QUOTENAME(Year_Month +'%') + ','
	  ,@PercentCase += QUOTENAME(Year_Month +'%') + '>=0.05 OR ' 	
FROM 
   (SELECT Year_Month_Total, Year_Month
    FROM In_Scope_Data
    GROUP BY Year_Month_Total, Year_Month
   ) AS a
ORDER BY Year_Month_Total ASC ;

SET @SumMonth = LEFT(@SumMonth, LEN(@SumMonth) - 1)
SET @Division = LEFT(@Division, LEN(@Division) - 1)
SET @PercentMonth = LEFT(@PercentMonth, LEN(@PercentMonth) - 1)
SET @PercentCase = LEFT(@PercentCase, LEN(@PercentCase) -3);

PRINT @SumMonth
PRINT @Division;
PRINT @PercentMonth;
PRINT @PercentCase;
PRINT @MonthTotal
PRINT @Month

-- Store variables in to temp table--
SELECT @Division AS Division, @PercentMonth AS PercentMonth, @PercentCase AS PercentCase 
INTO ##Percentage

-- Create [##Temp3] to calculate monthly shares percentage for each account
SET @SQL4 =' 
    SELECT Cash_Desk
          ,Account
	      ,'+ @Month +'
	      ,'+ @PercentMonth +'
	      ,Flag_Omnibus
    INTO  ##Temp3
    FROM
       (
        SELECT Cash_Desk
              ,Account
	         ,'+ @Month +'
	         ,'+ @Division +'
	         ,Flag_Omnibus
        FROM 
		    (SELECT temp.Cash_Desk
				   ,Account
				   ,'+ @SumMonth +' 
				   ,'+ @MonthTotal +'
				   ,Flag_Omnibus
		     FROM ##Temp2 AS temp
		          LEFT JOIN Monthly_Shares AS MS
		          ON temp.Cash_Desk = MS.Cash_Desk
		     GROUP BY temp.Cash_Desk, Account, Flag_Omnibus, '+ @MonthTotal + '
		    ) AS a
       ) AS b';

EXECUTE SP_EXECUTESQL @SQL4;

---- Final flag: create [OWNERSHIP_CONSOLIDATION] "Track_InScope" to record flagged accounts ----

---- DO NOT TRACK OMNIBUS ACCOUNTS no matter Flag_%Threshold and Flag_PreviouslyTracked----
---- Flag account if ownership percentage surpasses 5% threshold ----
---- Flag account if checked in the previous cycle excluding omnibus ----
---- Final Flag: 1 = Track; 0 = Do Not Track---- 

DECLARE 
    @Month            AS NVARCHAR(MAX) = '',
	@PercentMonth     AS NVARCHAR(MAX) ='',
	@PercentCase      AS NVARCHAR(MAX) ='',
	@SQL5             AS NVARCHAR(MAX) = '';

SELECT @Month = YM FROM ##Month
SELECT @PercentMonth = PercentMonth FROM ##Percentage
SELECT @PercentCase = PercentCase FROM ##Percentage

PRINT @PercentMonth
PRINT @PercentCase
PRINT @Month

-- Create [OWNERSHIP_CONSOLIDATION] to flag accounts if criterias are met
-- If not MARCH update, select '1' AS File_Group, no need to join File_Group_Partition
SET @SQL5 = '
SELECT Cash_Desk
      ,Account
	  ,'+ @Month +'
	  ,'+ @PercentMonth +'
	  ,Flag_Omnibus
	  ,Flag_Percent_Threshold
	  ,Flag_PreviouslyTracked
	  ,CASE When Flag_Omnibus = 1 Then 0 
			When Flag_Percent_Threshold = 1 Then 1 
			When Flag_PreviouslyTracked = 1 Then 1 
	   Else 0 End as Track_InScope  /* Final flag for reporting */
	  ,File_Group
INTO  OWNERSHIP_CONSOLIDATION
FROM 
    (SELECT temp.Cash_Desk
           ,Account
	       ,'+ @Month +'
	       ,'+ @PercentMonth +'
	       ,Flag_Omnibus
	       ,CASE WHEN '+ @PercentCase +' THEN 1 ELSE 0 END AS Flag_Percent_Threshold
	       ,CASE WHEN TP.Fund <> '''' THEN 1 ELSE 0 END AS Flag_PreviouslyTracked
	       ,File_Group  
     FROM ##Temp3 AS temp
	      LEFT JOIN Tracking_Prior AS TP
		       ON temp.Cash_Desk = TP.Fund
		       AND temp.Account = TP.Account_Number
	      LEFT JOIN File_Group_Partition AS FGP
	           ON temp.Cash_Desk = FGP.Cash_Desk) AS a';

EXECUTE SP_EXECUTESQL @SQL5;


  /*  07
	- Create table [Distinct_Account_Names], which contains all unique Cash Desk, Account#, Account Name and File Group.
*/

DROP TABLE IF EXISTS Distinct_Account_Names


SELECT DISTINCT  ISD.Cash_Desk
	            ,ISD.Account
	            ,ISD.Regline1 AS Account_Name
	            ,File_Group
INTO Distinct_Account_Names
FROM In_Scope_Data AS ISD
	 LEFT JOIN OWNERSHIP_CONSOLIDATION AS OC
	      ON ISD.Cash_Desk = OC.Cash_Desk


/*   08
	- Create tables for Ownership Excel workbook, one file group at a time
	- Refresh Power Pivot in excel after uploading one group, save as multiple excel workbooks
*/

---- Delete table after uploading one group ----

DROP TABLE IF EXISTS OWNERSHIP_CONSOLIDATION_Group
DROP TABLE IF EXISTS Cash_Desk
DROP TABLE IF EXISTS AccountNames
DROP TABLE IF EXISTS ##Temp4
DROP TABLE IF EXISTS ##MonthName
DROP TABLE IF EXISTS ##MonthNamePercent

---- 1 Upload Cash Desk ----
SELECT Cash_Desk AS [Cash Desk]   
INTO   Cash_Desk
FROM   File_Group_Partition
WHERE  File_Group = '2'  /*change group number*/

---- 2 Upload Account Names ----
SELECT Cash_Desk AS [Cash Desk]   
      ,Account
      ,Account_Name AS [Account Name]   
INTO   AccountNames
FROM   Distinct_Account_Names
WHERE  File_Group = '2'  /*change group number*/

---- 3 Upload Ownership Consolidation ----
---- Need to change column names to match Ownership Excel, to enable correct refreshing in Power Query

-- Create month names that align with Ownership Excel

CREATE TABLE ##Temp4 (Price_Date DATETIME, MonthName VARCHAR(10))

INSERT INTO ##Temp4
SELECT   Price_Date, 
         LEFT(DATENAME(MONTH, Price_Date),3) AS MonthName
FROM     In_Scope_Data
GROUP BY LEFT(DATENAME(month, Price_Date ),3), Price_Date
ORDER BY Price_Date ASC

-- Change first month in past year to 'PY_' to avoid duplication with current month
UPDATE  ##Temp4
SET MonthName ='PY_' + MonthName
WHERE Price_Date IN 
     (SELECT TOP 1 Price_Date
      FROM ##Temp4   
      ORDER BY Price_Date ASC) 

-- Store month names into temp table
SELECT * INTO ##MonthName FROM ##Temp4 ORDER BY Price_Date ASC 

-- Create month names % that align with Ownership Excel
SELECT MonthName + '%' AS MonthNamePercent, Price_Date
INTO ##MonthNamePercent
FROM ##MonthName  
ORDER BY Price_Date ASC

-- Verify column names to upload
SELECT MonthName FROM ##MonthName ORDER BY Price_Date ASC
SELECT MonthNamePercent FROM ##MonthNamePercent ORDER BY Price_Date ASC

-- Declare variables to be used in dynamic query
DECLARE 
          @Month                   AS NVARCHAR(MAX) = '',
	      @PercentMonth            AS NVARCHAR(MAX) ='',
		  @MonthName_ASFLOAT       AS NVARCHAR(MAX) ='',
		  @MonthNamePercent_ASFLOAT AS NVARCHAR(MAX) ='',
	      @SQL6                    AS NVARCHAR(MAX) = '';

-- Load variables from temp table
SELECT @Month = YM FROM ##Month
SELECT @PercentMonth = PercentMonth FROM ##Percentage
SELECT @MonthName_ASFLOAT += MonthName + ' FLOAT, ' FROM  ##MonthName  ORDER BY Price_Date ASC
SELECT @MonthNamePercent_ASFLOAT += QUOTENAME(MonthNamePercent) + ' FLOAT, ' FROM  ##MonthNamePercent  ORDER BY Price_Date ASC

SET @MonthName_ASFLOAT= LEFT(@MonthName_ASFLOAT, LEN(@MonthName_ASFLOAT) - 1)
SET @MonthNamePercent_ASFLOAT= LEFT(@MonthNamePercent_ASFLOAT, LEN(@MonthNamePercent_ASFLOAT) - 1)

PRINT @PercentMonth
PRINT @Month
PRINT @MonthName_ASFLOAT
PRINT @MonthNamePercent_ASFLOAT;

-- Upload subtable into OWNERSHIP_CONSOLIDATION_Group table, and refresh in Ownership Excel one file group at a time
SET @SQL6 = '


CREATE TABLE OWNERSHIP_CONSOLIDATION_Group
      (
       [Cash Desk]                       NUMERIC(10,0)
	  ,Account                           NUMERIC(10,0)
	  ,'+ @MonthName_ASFLOAT +' 
	  ,'+ @MonthNamePercent_ASFLOAT +' 
	  ,Flag_Omnibus                      INT
	  ,[Flag_%Threshold]                 INT
      ,Flag_PreviouslyTracked            INT
      ,Track_InScope	                 INT
	  )

INSERT INTO OWNERSHIP_CONSOLIDATION_Group
SELECT Cash_Desk AS [Cash Desk]  
	  ,Account   
      ,'+ @Month +' 
      ,'+ @PercentMonth +'   
      ,Flag_Omnibus
      ,Flag_Percent_Threshold AS [Flag_%Threshold]
      ,Flag_PreviouslyTracked
      ,Track_InScope	 
FROM OWNERSHIP_CONSOLIDATION
WHERE File_Group = ''2'' '; /*change group number*/

EXECUTE SP_EXECUTESQL @SQL6;


/*   09
	  Control test
	  - Compare results of queries with the File_Group_Partition table in session 05
	  - Export OWNERSHIP_CONSOLIDATION into Excel, compare with raw data using pivot table aggregation
*/

---- The below three queries are supposed to return the same row number or count ----
SELECT DISTINCT Cash_Desk, Account
FROM   In_Scope_Data
--FROM   Clean_Data

SELECT COUNT(*)
FROM   OWNERSHIP_CONSOLIDATION

SELECT DISTINCT Cash_Desk, Account
FROM   OWNERSHIP_CONSOLIDATION

---- Check account number and disctinct Cash Desk number in each file ----
SELECT File_Group, COUNT(Account), COUNT(DISTINCT Cash_Desk)
FROM   OWNERSHIP_CONSOLIDATION
GROUP BY File_Group
ORDER BY File_Group


/* 10 
     Database BackUp  */

DECLARE @Month                    NVARCHAR(MAX) = '',
        @RawTableName             NVARCHAR(MAX) = '',
        @ExCurTableName           NVARCHAR(MAX) = '',
		@CleanDataTableName       NVARCHAR(MAX) = '',
		@InScopeDataTableName     NVARCHAR(MAX) = '',
		@MonthlySharesTableName   NVARCHAR(MAX) = '',
		@BreakdownAcctTableName   NVARCHAR(MAX) = '',
		@OmnibusTableName         NVARCHAR(MAX) = '',
		@AcctCountTableName       NVARCHAR(MAX) = '',
		@FileGroupTableName       NVARCHAR(MAX) = '',
		@OwnershipTableName       NVARCHAR(MAX) = '',
		@DistinctAcctTableName    NVARCHAR(MAX) = '',
        @PercentMonth             NVARCHAR(MAX) = '';
	
---- Load variables from temp table ----
SELECT @Month = YM FROM ##Month
SELECT @PercentMonth = PercentMonth FROM ##Percentage

---- Set backup table names ----
SET @RawTableName = '[dbo].[00_Raw_Data @ ' + REPLACE(REPLACE(RIGHT(@Month,8), '_', '.'),']','') +']'
SET @ExCurTableName = '[dbo].[00_Export_Current @ ' + REPLACE(REPLACE(RIGHT(@Month,8), '_', '.'),']','') +']'

SET @CleanDataTableName = '[dbo].[Clean_Data_' + REPLACE(REPLACE(RIGHT(@Month,8), '_', '.'),']','') +']'
SET @InScopeDataTableName = '[dbo].[In_Scope_Data_' + REPLACE(REPLACE(RIGHT(@Month,8), '_', '.'),']','') +']'
SET @MonthlySharesTableName = '[dbo].[Monthly_Shares_' + REPLACE(REPLACE(RIGHT(@Month,8), '_', '.'),']','') +']'
SET @BreakdownAcctTableName = '[dbo].[Breakdown_Acct_' + REPLACE(REPLACE(RIGHT(@Month,8), '_', '.'),']','') +']'
SET @OmnibusTableName = '[dbo].[Omnibus_Override_Acct_' + REPLACE(REPLACE(RIGHT(@Month,8), '_', '.'),']','') +']'
SET @AcctCountTableName = '[dbo].[Acct_Count_for_Active_CashDesk_' + REPLACE(REPLACE(RIGHT(@Month,8), '_', '.'),']','') +']'
SET @FileGroupTableName = '[dbo].[File_Group_Partition_' + REPLACE(REPLACE(RIGHT(@Month,8), '_', '.'),']','') +']'
SET @OwnershipTableName = '[dbo].[OWNERSHIP_CONSOLIDATION_' + REPLACE(REPLACE(RIGHT(@Month,8), '_', '.'),']','') +']'
SET @DistinctAcctTableName = '[dbo].[Distinct_Account_Names_' + REPLACE(REPLACE(RIGHT(@Month,8), '_', '.'),']','') +']'


PRINT @Month
PRINT @RawTableName
PRINT @ExCurTableName
PRINT @OwnershipTableName
PRINT @PercentMonth;

---- 1 Backup raw data ----
EXEC('
     SELECT * 
     INTO '+@RawTableName+' 
     FROM Raw_Data')

---- 2 Backup tracked accounts in ownership consolidation----
EXEC('
     SELECT  Cash_Desk
	        ,Account
            ,'+@Month+'
            ,'+@PercentMonth+'
            ,Flag_Omnibus
            ,Flag_Percent_Threshold
            ,Flag_PreviouslyTracked
            ,Track_InScope
	        ,File_Group
     INTO  '+@ExCurTableName+' 
     FROM   OWNERSHIP_CONSOLIDATION
     WHERE  Track_InScope = 1
     ORDER BY File_Group')

---- 3 Backup current period tables used in processing ----
EXEC('
     SELECT  *
     INTO  '+@CleanDataTableName+' 
     FROM   Clean_Data
     ')

EXEC('
     SELECT  *
     INTO  '+@InScopeDataTableName+' 
     FROM  In_Scope_Data
     ')

EXEC('
     SELECT  *
     INTO  '+@MonthlySharesTableName+' 
     FROM  Monthly_Shares
     ')

EXEC('
     SELECT  *
     INTO  '+@BreakdownAcctTableName+' 
     FROM  Breakdown_Acct
     ')

EXEC('
     SELECT  *
     INTO  '+@OmnibusTableName+' 
     FROM  Omnibus_Override_Acct
     ')

EXEC('
     SELECT  *
     INTO  '+@AcctCountTableName+' 
     FROM  Acct_Count_for_Active_CashDesk
     ')

EXEC('
     SELECT  *
     INTO  '+@FileGroupTableName+' 
     FROM  File_Group_Partition
     ')

EXEC('
     SELECT  Cash_Desk
	        ,Account
            ,'+@Month+'
            ,'+@PercentMonth+'
            ,Flag_Omnibus
            ,Flag_Percent_Threshold
            ,Flag_PreviouslyTracked
            ,Track_InScope
	        ,File_Group
     INTO  '+@OwnershipTableName+' 
     FROM   OWNERSHIP_CONSOLIDATION
     ORDER BY Cash_Desk ASC, Account ASC')

EXEC('
     SELECT  *
     INTO  '+@DistinctAcctTableName+' 
     FROM  Distinct_Account_Names
     ')


---- 4 Backup Tracking Current table as Tracking Prior for next year ----

  -- Method1: mannually upload to Tracking Current table from excel by clicking 'Save to database' in "Currently Tracked" hidden tab

  -- Method2: calculate sum of shares from OWNERSHIP_CONSOLIDATION table for each pair of cash desk & account 

  -- Can apply both and cross validate two methods 

------------------------------------  ----------------------------------------------------------
---- Method 1 (For Validation purpose, compare Tracking_Current_Excel and Tracking_Current if needed) ----
DROP TABLE IF EXISTS Tracking_Current_Excel

CREATE TABLE Tracking_Current_Excel (			
						 Date			      DATE           
						,Fund				  FLOAT
						,[Account Number]	  NVARCHAR(255)
						,Name			      NVARCHAR(255)
					    ,Shares               MONEY
	                    )
------------------------------------  
---- Method 2 ----------------------
DROP TABLE IF EXISTS Tracking_Current
DROP TABLE IF EXISTS ##Temp5

-- Create [Tracking_Current] table from ownership consolidation table, sum shares by cash desk & account 
SELECT 
	     OC.Cash_Desk AS Fund
		,OC.Account   AS Account_Number
		,Regline1     AS Name
		,SUM(Total_Shares) AS Shares
INTO    ##Temp5
FROM    OWNERSHIP_CONSOLIDATION AS OC
	LEFT JOIN In_Scope_Data AS ISD
	     ON OC.Cash_Desk = ISD.Cash_Desk
	     AND OC.Account = ISD.Account
WHERE  Track_InScope = 1
GROUP BY OC.Cash_Desk,  OC.Account, Regline1

---- If cash desk & account has duplicated fund names, concate as one column, then get sum of shares for each pair of cash desk & account 
-- Declare variables used in [Tracking_Current] table
DECLARE @CurrentDate     DATE,
       	@PriorTableName2 NVARCHAR(MAX) = '';

-- Add "Date" column and set values as current period
SELECT @CurrentDate = DATEADD(YEAR, 0, MAX(Price_Date)) FROM In_Scope_Data
-- Upload Tracking_Prior table name as next year for future use
SELECT @PriorTableName2 = '[dbo].[00_Tracking_Prior @ ' + CAST(YEAR(DATEADD(YEAR, 1, MAX(Price_Date))) AS NVARCHAR(4))
                           + '.' + CAST(FORMAT(MAX(Price_Date), 'MM') AS NVARCHAR(2)) +']'  FROM In_Scope_Data

PRINT @CurrentDate
PRINT @PriorTableName2

-- Concate duplicated fund name, and upload into [Tracking_Current] table
SELECT a.*
INTO   Tracking_Current
FROM
    (SELECT @CurrentDate AS Date, Fund, Account_Number, LEFT(pre_trimmed.Name , LEN(pre_trimmed.Name)-1) AS Name, SUM(Shares) AS Shares
     FROM   ##Temp5 AS extern   
     CROSS  APPLY
         (
            SELECT Name + ','
            FROM   ##Temp5 AS intern
			WHERE  extern.Fund = intern.Fund
			FOR    XML PATH('')
		 )  AS  pre_trimmed (Name)
	 GROUP BY Fund, Account_Number, pre_trimmed.Name
    ) AS a


-- Copy [Tracking_Current] table as [Tracking_Prior @ xxxx.xx] for next year 
EXEC('
     SELECT * 
     INTO '+ @PriorTableName2 +'
     FROM  Tracking_Current')


/* Final Step 
   - Clean up current period tables used in processing */
   
DROP TABLE IF EXISTS 
           Raw_Data
		  ,Clean_Data
	      ,Tracking_Prior
		  ,In_Scope_Data
		  ,Monthly_Shares
		  ,Breakdown_Acct
		  ,Omnibus_Override_Acct
		  ,Acct_Count_for_Active_CashDesk
		  ,File_Group_Partition
		  ,OWNERSHIP_CONSOLIDATION
		  ,Distinct_Account_Names
		  ,Tracking_Current
		  ,Cash_Desk
		  ,AccountNames
		  ,OWNERSHIP_CONSOLIDATION_Group
		  ,Tracking_Current_Excel
		  ,Fund_List_Current


		  