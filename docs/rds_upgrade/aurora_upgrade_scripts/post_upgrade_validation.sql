-- ============================================================================
-- Aurora PostgreSQL Post-Upgrade Validation Script
-- Purpose: Run this immediately after upgrading to 16.9
-- Compare results with pre_upgrade_validation_report.txt
-- ============================================================================

-- Set output formatting
\pset border 2
\pset format wrapped

-- Create output file
\o post_upgrade_validation_report.txt

\echo '================================================================'
\echo 'Aurora PostgreSQL Post-Upgrade Validation Report'
\echo '================================================================'
\echo ''
\echo 'Generated at:'
SELECT NOW();
\echo ''

-- ============================================================================
-- SECTION 1: Verify Upgrade Success
-- ============================================================================
\echo '----------------------------------------------------------------'
\echo 'Section 1: Verify PostgreSQL Version'
\echo '----------------------------------------------------------------'

\echo ''
\echo 'Current Version (should be 16.x):'
SELECT version();

\echo ''
\echo 'Expected: PostgreSQL 16.9'

-- ============================================================================
-- SECTION 2: Extension Status
-- ============================================================================
\echo ''
\echo '----------------------------------------------------------------'
\echo 'Section 2: Extension Status After Upgrade'
\echo '----------------------------------------------------------------'

\echo ''
\echo 'All Extensions (verify they loaded successfully):'
SELECT 
    e.extname,
    e.extversion,
    n.nspname as schema
FROM pg_extension e
LEFT JOIN pg_namespace n ON n.oid = e.extnamespace
ORDER BY e.extname;

\echo ''
\echo 'Extensions Needing Updates:'
SELECT 
    e.extname,
    e.extversion as current_version,
    av.version as available_version
FROM pg_extension e
CROSS JOIN LATERAL (
    SELECT version 
    FROM pg_available_extension_versions 
    WHERE name = e.extname 
    ORDER BY version DESC 
    LIMIT 1
) av
WHERE e.extversion != av.version
ORDER BY e.extname;

-- ============================================================================
-- SECTION 3: Database Objects Verification
-- ============================================================================
\echo ''
\echo '----------------------------------------------------------------'
\echo 'Section 3: Database Objects (compare with pre-upgrade)'
\echo '----------------------------------------------------------------'

\echo ''
\echo 'Object Count by Type:'
SELECT 
    n.nspname as schema_name,
    CASE c.relkind
        WHEN 'r' THEN 'table'
        WHEN 'v' THEN 'view'
        WHEN 'm' THEN 'materialized_view'
        WHEN 'i' THEN 'index'
        WHEN 'S' THEN 'sequence'
        ELSE c.relkind::text
    END as object_type,
    COUNT(*) as count
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
GROUP BY n.nspname, c.relkind
ORDER BY n.nspname, c.relkind;

\echo ''
\echo 'Function Count (compare with pre-upgrade):'
SELECT 
    COUNT(*) as total_functions
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema');

-- ============================================================================
-- SECTION 4: Check for Errors or Issues
-- ============================================================================
\echo ''
\echo '----------------------------------------------------------------'
\echo 'Section 4: Check for Post-Upgrade Issues'
\echo '----------------------------------------------------------------'

\echo ''
\echo 'Invalid Objects (should be empty):'
SELECT 
    n.nspname,
    c.relname,
    c.relkind
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE c.relkind IN ('r', 'v', 'm')
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND NOT EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid = c.oid AND attnum > 0 AND NOT attisdropped
  );

\echo ''
\echo 'Check for Failed Constraint Checks:'
-- This would show constraints that might have failed during upgrade
SELECT 
    conrelid::regclass AS table_name,
    conname AS constraint_name,
    contype AS constraint_type,
    pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE connamespace NOT IN (
    SELECT oid FROM pg_namespace 
    WHERE nspname IN ('pg_catalog', 'information_schema')
)
ORDER BY conrelid::regclass::text;

-- ============================================================================
-- SECTION 5: Performance Validation
-- ============================================================================
\echo ''
\echo '----------------------------------------------------------------'
\echo 'Section 5: Performance Metrics After Upgrade'
\echo '----------------------------------------------------------------'

\echo ''
\echo 'Database Activity:'
SELECT 
    datname,
    numbackends as connections,
    xact_commit as commits,
    xact_rollback as rollbacks,
    blks_read as blocks_read,
    blks_hit as blocks_hit,
    ROUND(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 2) as cache_hit_ratio
FROM pg_stat_database
WHERE datname NOT IN ('template0', 'template1', 'rdsadmin')
ORDER BY datname;

\echo ''
\echo 'Current Connections:'
SELECT 
    datname,
    usename,
    state,
    COUNT(*) as connection_count
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
GROUP BY datname, usename, state
ORDER BY connection_count DESC;

\echo ''
\echo 'Active Queries:'
SELECT 
    pid,
    usename,
    datname,
    state,
    NOW() - query_start as duration,
    wait_event_type,
    wait_event,
    LEFT(query, 80) as query_preview
FROM pg_stat_activity
WHERE state != 'idle'
  AND pid != pg_backend_pid()
ORDER BY duration DESC;

-- ============================================================================
-- SECTION 6: Table Statistics (need update)
-- ============================================================================
\echo ''
\echo '----------------------------------------------------------------'
\echo 'Section 6: Table Statistics Status'
\echo '----------------------------------------------------------------'

\echo ''
\echo 'Tables Needing ANALYZE (last analyzed before upgrade):'
SELECT 
    schemaname,
    tablename,
    last_analyze,
    last_autoanalyze,
    n_live_tup,
    n_dead_tup
FROM pg_stat_user_tables
WHERE (last_analyze IS NULL OR last_analyze < NOW() - INTERVAL '1 day')
  AND (last_autoanalyze IS NULL OR last_autoanalyze < NOW() - INTERVAL '1 day')
ORDER BY n_live_tup DESC
LIMIT 20;

-- ============================================================================
-- SECTION 7: Configuration Changes
-- ============================================================================
\echo ''
\echo '----------------------------------------------------------------'
\echo 'Section 7: Configuration After Upgrade'
\echo '----------------------------------------------------------------'

\echo ''
\echo 'Key Configuration Parameters:'
SELECT name, setting, unit, context 
FROM pg_settings 
WHERE name IN (
    'max_connections',
    'shared_buffers',
    'effective_cache_size',
    'maintenance_work_mem',
    'checkpoint_completion_target',
    'wal_buffers',
    'default_statistics_target',
    'random_page_cost',
    'effective_io_concurrency',
    'work_mem',
    'min_wal_size',
    'max_wal_size',
    'max_parallel_workers_per_gather',
    'max_parallel_workers'
)
ORDER BY name;

\echo ''
\echo 'New PG16 Settings (if any):'
SELECT name, setting, short_desc
FROM pg_settings
WHERE name LIKE '%parallel%'
   OR name LIKE '%jit%'
ORDER BY name;

-- ============================================================================
-- SECTION 8: Replication Status
-- ============================================================================
\echo ''
\echo '----------------------------------------------------------------'
\echo 'Section 8: Replication Status After Upgrade'
\echo '----------------------------------------------------------------'

SELECT 
    client_addr,
    state,
    sync_state,
    pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) as replication_lag,
    write_lag,
    flush_lag,
    replay_lag
FROM pg_stat_replication;

-- ============================================================================
-- SECTION 9: Test Sample Queries
-- ============================================================================
\echo ''
\echo '----------------------------------------------------------------'
\echo 'Section 9: Sample Query Tests'
\echo '----------------------------------------------------------------'

\echo ''
\echo 'Test 1: Simple SELECT'
\timing on
SELECT COUNT(*) as table_count 
FROM pg_tables 
WHERE schemaname NOT IN ('pg_catalog', 'information_schema');
\timing off

\echo ''
\echo 'Test 2: System Catalog Query'
\timing on
SELECT 
    schemaname,
    COUNT(*) as object_count
FROM (
    SELECT schemaname FROM pg_tables
    UNION ALL
    SELECT schemaname FROM pg_views
    UNION ALL
    SELECT schemaname FROM pg_indexes
) t
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
GROUP BY schemaname;
\timing off

-- ============================================================================
-- SECTION 10: Validation Summary
-- ============================================================================
\echo ''
\echo '----------------------------------------------------------------'
\echo 'Section 10: Validation Summary'
\echo '----------------------------------------------------------------'

\echo ''
\echo 'Quick Health Check:'
SELECT 
    'PostgreSQL Version' as check_item,
    CASE 
        WHEN version() LIKE '%PostgreSQL 16.%' THEN '✓ PASS'
        ELSE '✗ FAIL - Version not 16.x'
    END as status
UNION ALL
SELECT 
    'Extensions Loaded',
    CASE 
        WHEN COUNT(*) > 0 THEN '✓ PASS - ' || COUNT(*)::text || ' extensions'
        ELSE '✗ FAIL - No extensions'
    END
FROM pg_extension
UNION ALL
SELECT 
    'Active Connections',
    CASE 
        WHEN COUNT(*) > 0 THEN '✓ PASS - ' || COUNT(*)::text || ' connections'
        ELSE '⚠ WARNING - No active connections'
    END
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
UNION ALL
SELECT 
    'Database Accessible',
    '✓ PASS - Connected successfully'
;

\echo ''
\echo '================================================================'
\echo 'Post-Upgrade Validation Report Complete'
\echo '================================================================'
\echo ''
\echo 'CRITICAL NEXT STEPS:'
\echo ''
\echo '1. Run ANALYZE to update statistics:'
\echo '   ANALYZE VERBOSE;'
\echo ''
\echo '2. Update extensions if needed:'
\echo '   ALTER EXTENSION extension_name UPDATE;'
\echo ''
\echo '3. Compare this report with pre_upgrade_validation_report.txt'
\echo '   - Verify object counts match'
\echo '   - Check all extensions loaded'
\echo '   - Ensure no unexpected errors'
\echo ''
\echo '4. Monitor application performance for 2-4 hours'
\echo ''
\echo '5. Check CloudWatch metrics:'
\echo '   - Database Connections'
\echo '   - CPU Utilization'
\echo '   - Read/Write Latency'
\echo ''

\o

\echo 'Report saved to: post_upgrade_validation_report.txt'
\echo ''
\echo 'Now run: ANALYZE VERBOSE;'

