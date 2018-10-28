-- Copyright 2018 Tanel Poder. All rights reserved. More info at http://tanelpoder.com
-- Licensed under the Apache License, Version 2.0. See LICENSE.txt for terms & conditions.

--------------------------------------------------------------------------------
--
-- Name:      sqlflame.sql
--
-- Purpose:   Demo script for displaying execution plan profile as a flame chart
-- 
-- Usage:     @sqlflame.sql <sqlid> <child#>
--            Note that you'll need to download Brendan Gregg's FlameGraph.pl  
--            https://github.com/brendangregg/FlameGraph
--
-- Author:    Tanel Poder - https://blog.tanelpoder.com 
-- 
-- Other:     This is an early version mostly meant as a proof of concept for
--            illustrating that a modern RDBMS SQL execution plan profile 
--            can be treated just like any code profile (FlameGraphs were
--            initially used for process stack profiling)
--
-- Credits:   Brendan Gregg invented and popularized FlameGraphs, if you want to
--            understand theri logic better, read the articles at:
--            http://www.brendangregg.com/flamegraphs.html          
--
--------------------------------------------------------------------------------

@@saveset

SET HEADING OFF LINESIZE 32767 PAGESIZE 0 TRIMSPOOL ON TRIMOUT ON LONG 9999999 VERIFY OFF LONGCHUNKSIZE 100000 FEEDBACK OFF APPINFO OFF
SET TERMOUT OFF
SET TIMING OFF

PROMPT
PROMPT -- SQLFlame 0.1 by Tanel Poder ( https://blog.tanelpoder.com )

WITH sq AS (
    SELECT /*+ MATERIALIZE */ 
        sp.id, sp.parent_id, sp.operation, sp.options
      , sp.object_owner, sp.object_name, ss.last_elapsed_time, ss.elapsed_time
    FROM v$sql_plan_statistics_all ss INNER JOIN 
         v$sql_plan sp 
      ON (
						sp.sql_id=ss.sql_id 
				AND sp.child_number=ss.child_number 
				AND sp.address=ss.address 
				AND sp.id=ss.id
      )
    AND sp.sql_id='&1'
    AND sp.child_number=&2
),  deltas AS (
    SELECT par.id, par.elapsed_time - SUM(chi.elapsed_time) self_elapsed_time
    FROM sq par LEFT OUTER JOIN 
         sq chi
      ON chi.parent_id = par.id
    GROUP BY par.id, par.elapsed_time
), combined AS (
    SELECT sq.id, sq.parent_id, sq.operation, sq.options
         , sq.object_owner, sq.object_name, sq.last_elapsed_time, sq.elapsed_time
         , NVL(deltas.self_elapsed_time, sq.elapsed_time) self_elapsed_time
    FROM 
        sq, deltas
    WHERE
        sq.id = deltas.id 
)
SELECT
    '0 - SELECT STATEMENT'||TRIM(SYS_CONNECT_BY_PATH(id||' - '||operation||NVL2(options,' '||options,NULL)||NVL2(object_owner||object_name, ' ['||object_owner||'.'||object_name||']', NULL), ';'))||' '||TRIM(ROUND(self_elapsed_time/1000))
FROM
    combined
CONNECT BY
    parent_id = PRIOR id 
    START WITH parent_id = 0
ORDER BY
    id ASC
.

spool sqlflame_stacks.txt
/
spool off

SET TERMOUT ON HEADING ON PAGESIZE 5000 LINESIZE 999 FEEDBACK ON 
SET TIMING ON

HOST flamegraph.pl --countname=Milliseconds --title="sql_id=&1" sqlflame_stacks.txt > sqlflame_&1..svg
HOST OPEN sqlflame_&1..svg

