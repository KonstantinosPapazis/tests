-- ============================================================================
-- Aurora PostgreSQL Pre-Upgrade Validation Script
-- Purpose: Run this before upgrading from 13.20 to 16.9
-- Save output for comparison with post-upgrade results
-- ============================================================================

-- Set output formatting
\pset border 2
\pset format wrapped

-- Create output file
\o pre_upgrade_validation_report.txt

\echo '================================================================'
\echo 'Aurora PostgreSQL Pre-Upgrade Validation Report'
\echo '================================================================'
\echo ''
\echo 'Generated at:'
SELECT NOW();
\echo ''

-- ============================================================================
-- SECTION 1: Database Version and Configuration
-- ============================================================================
\echo '----------------------------------------------------------------'
\echo 'Section 1: Current Database Version'
\echo '----------------------------------------------------------------'

SELECT version();

\echo ''
\echo 'Database Configuration:'
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
    'max_wal_size'
)
ORDER BY name;

-- ============================================================================
-- SECTION 2: Database Inventory
-- ============================================================================
\echo ''
\echo '----------------------------------------------------------------'
\echo 'Section 2: Database Inventory'
\echo '----------------------------------------------------------------'

\echo ''
\echo 'All Databases:'
SELECT 
    datname,
    pg_size_pretty(pg_database_size(datname)) as size,
    datcollate,
    datctype
FROM pg_database
ORDER BY datname;

\echo ''
\echo 'All Schemas:'
SELECT 
    nspname,
    nspowner::regrole as owner
FROM pg_namespace 
WHERE nspname NOT LIKE 'pg_%' 
  AND nspname != 'information_schema'
ORDER BY nspname;

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
        WHEN 't' THEN 'toast_table'
        ELSE c.relkind::text
    END as object_type,
    COUNT(*) as count
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
GROUP BY n.nspname, c.relkind
ORDER BY n.nspname, c.relkind;

-- ============================================================================
-- SECTION 3: Extensions
-- ============================================================================
\echo ''
\echo '----------------------------------------------------------------'
\echo 'Section 3: Extensions'
\echo '----------------------------------------------------------------'

\echo ''
\echo 'Installed Extensions:'
SELECT 
    e.extname,
    e.extversion,
    n.nspname as schema,
    c.description
FROM pg_extension e
LEFT JOIN pg_namespace n ON n.oid = e.extnamespace
LEFT JOIN pg_description c ON c.objoid = e.oid
ORDER BY e.extname;

\echo ''
\echo 'Available Extension Versions:'
SELECT 
    name,
    default_version,
    installed_version,
    comment
FROM pg_available_extensions
WHERE installed_version IS NOT NULL
ORDER BY name;

-- ============================================================================
-- SECTION 4: Functions and Procedures
-- ============================================================================
\echo ''
\echo '----------------------------------------------------------------'
\echo 'Section 4: Functions and Procedures'
\echo '----------------------------------------------------------------'

\echo ''
\echo 'User-Defined Functions:'
SELECT 
    n.nspname as schema_name,
    p.proname as function_name,
    pg_get_function_identity_arguments(p.oid) as arguments,
    l.lanname as language,
    CASE p.provolatile
        WHEN 'i' THEN 'IMMUTABLE'
        WHEN 's' THEN 'STABLE'
        WHEN 'v' THEN 'VOLATILE'
    END as volatility
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
JOIN pg_language l ON p.prolang = l.oid
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY n.nspname, p.proname;

\echo ''
\echo 'Functions by Language:'
SELECT 
    l.lanname as language,
    COUNT(*) as count
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
JOIN pg_language l ON p.prolang = l.oid
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
GROUP BY l.lanname
ORDER BY count DESC;

-- ============================================================================
-- SECTION 5: Triggers
-- ============================================================================
\echo ''
\echo '----------------------------------------------------------------'
\echo 'Section 5: Triggers'
\echo '----------------------------------------------------------------'

SELECT 
    n.nspname as schema_name,
    c.relname as table_name,
    t.tgname as trigger_name,
    p.proname as function_name,
    CASE 
        WHEN t.tgtype & 2 = 2 THEN 'BEFORE'
        WHEN t.tgtype & 64 = 64 THEN 'INSTEAD OF'
        ELSE 'AFTER'
    END as timing,
    CASE 
        WHEN t.tgtype & 4 = 4 THEN 'INSERT'
        WHEN t.tgtype & 8 = 8 THEN 'DELETE'
        WHEN t.tgtype & 16 = 16 THEN 'UPDATE'
        ELSE 'OTHER'
    END as event
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
JOIN pg_proc p ON t.tgfoid = p.oid
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND NOT t.tgisinternal
ORDER BY n.nspname, c.relname, t.tgname;

-- ============================================================================
-- SECTION 6: Compatibility Checks
-- ============================================================================
\echo ''
\echo '----------------------------------------------------------------'
\echo 'Section 6: Compatibility Checks'
\echo '----------------------------------------------------------------'

\echo ''
\echo 'Check for tables with OIDs (deprecated):'
SELECT 
    n.nspname,
    c.relname 
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE c.relhasoids 
  AND n.nspname NOT IN ('pg_catalog', 'information_schema');

\echo ''
\echo 'Check for Python 2 functions (PL/Python):'
SELECT 
    n.nspname,
    p.proname,
    'Python 2 not supported in PG 14+' as warning
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
JOIN pg_language l ON p.prolang = l.oid
WHERE l.lanname IN ('plpythonu', 'plpython2u')
  AND n.nspname NOT IN ('pg_catalog', 'information_schema');

\echo ''
\echo 'Check for deprecated data types:'
SELECT 
    n.nspname,
    c.relname,
    a.attname,
    t.typname
FROM pg_attribute a
JOIN pg_class c ON a.attrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
JOIN pg_type t ON a.atttypid = t.oid
WHERE t.typname IN ('abstime', 'reltime', 'tinterval')
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND a.attnum > 0
  AND NOT a.attisdropped;

-- ============================================================================
-- SECTION 7: Indexes and Constraints
-- ============================================================================
\echo ''
\echo '----------------------------------------------------------------'
\echo 'Section 7: Indexes and Constraints'
\echo '----------------------------------------------------------------'

\echo ''
\echo 'Index Count by Schema:'
SELECT 
    schemaname,
    COUNT(*) as index_count
FROM pg_indexes
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
GROUP BY schemaname
ORDER BY schemaname;

\echo ''
\echo 'Foreign Key Constraints:'
SELECT 
    tc.table_schema,
    tc.table_name,
    tc.constraint_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
  AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY tc.table_schema, tc.table_name;

-- ============================================================================
-- SECTION 8: Table Statistics
-- ============================================================================
\echo ''
\echo '----------------------------------------------------------------'
\echo 'Section 8: Table Statistics'
\echo '----------------------------------------------------------------'

\echo ''
\echo 'Largest Tables:'
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) AS index_size
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 20;

\echo ''
\echo 'Table Statistics (for performance comparison):'
SELECT 
    schemaname,
    tablename,
    n_tup_ins as inserts,
    n_tup_upd as updates,
    n_tup_del as deletes,
    n_live_tup as live_tuples,
    n_dead_tup as dead_tuples,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
ORDER BY schemaname, tablename;

-- ============================================================================
-- SECTION 9: Performance Metrics
-- ============================================================================
\echo ''
\echo '----------------------------------------------------------------'
\echo 'Section 9: Current Performance Metrics'
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
    application_name,
    client_addr,
    state,
    COUNT(*) as connection_count
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
GROUP BY datname, usename, application_name, client_addr, state
ORDER BY connection_count DESC;

\echo ''
\echo 'Long Running Queries (> 1 minute):'
SELECT 
    pid,
    usename,
    datname,
    state,
    NOW() - query_start as duration,
    LEFT(query, 100) as query_preview
FROM pg_stat_activity
WHERE state != 'idle'
  AND NOW() - query_start > INTERVAL '1 minute'
  AND pid != pg_backend_pid()
ORDER BY duration DESC;

-- ============================================================================
-- SECTION 10: Replication Status (if applicable)
-- ============================================================================
\echo ''
\echo '----------------------------------------------------------------'
\echo 'Section 10: Replication Status'
\echo '----------------------------------------------------------------'

SELECT 
    client_addr,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    sync_priority,
    pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) as replication_lag
FROM pg_stat_replication;

-- ============================================================================
-- SECTION 11: Permissions Check
-- ============================================================================
\echo ''
\echo '----------------------------------------------------------------'
\echo 'Section 11: Schema Permissions'
\echo '----------------------------------------------------------------'

\echo ''
\echo 'PUBLIC Schema Permissions (will change in PG 15):'
SELECT 
    nspname,
    nspacl
FROM pg_namespace
WHERE nspname = 'public';

\echo ''
\echo 'Role List:'
SELECT 
    rolname,
    rolsuper,
    rolinherit,
    rolcreaterole,
    rolcreatedb,
    rolcanlogin,
    rolconnlimit
FROM pg_roles
WHERE rolname NOT LIKE 'pg_%'
  AND rolname NOT IN ('rdsadmin', 'rdsrepladmin')
ORDER BY rolname;

-- ============================================================================
-- SECTION 12: Custom Summary
-- ============================================================================
\echo ''
\echo '----------------------------------------------------------------'
\echo 'Section 12: Summary'
\echo '----------------------------------------------------------------'

\echo ''
\echo 'Database Summary:'
SELECT 
    'Total Databases' as metric,
    COUNT(*)::text as value
FROM pg_database
UNION ALL
SELECT 
    'Total Schemas',
    COUNT(*)::text
FROM pg_namespace 
WHERE nspname NOT LIKE 'pg_%' AND nspname != 'information_schema'
UNION ALL
SELECT 
    'Total Tables',
    COUNT(*)::text
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
UNION ALL
SELECT 
    'Total Indexes',
    COUNT(*)::text
FROM pg_indexes
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
UNION ALL
SELECT 
    'Total Functions',
    COUNT(*)::text
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
UNION ALL
SELECT 
    'Total Extensions',
    COUNT(*)::text
FROM pg_extension
WHERE extname NOT IN ('plpgsql')
UNION ALL
SELECT 
    'Total Triggers',
    COUNT(*)::text
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND NOT t.tgisinternal;

\echo ''
\echo '================================================================'
\echo 'Pre-Upgrade Validation Report Complete'
\echo '================================================================'
\echo ''
\echo 'Next Steps:'
\echo '1. Review this report for any warnings or deprecated features'
\echo '2. Save this file for comparison with post-upgrade validation'
\echo '3. Address any Python 2, deprecated data types, or OID issues'
\echo '4. Proceed with test environment upgrade'
\echo ''

\o

-- Return to normal output
\echo 'Report saved to: pre_upgrade_validation_report.txt'

