# PostgreSQL Breaking Changes: Version 14 → 17
## Compatibility Guide for Database Owners

**Document Version:** 1.0  
**Last Updated:** October 2025  
**Source:** PostgreSQL Official Release Notes  
**Purpose:** Pre-upgrade compatibility assessment

---

## Executive Summary

This document outlines **breaking changes, incompatibilities, and deprecated features** when upgrading from PostgreSQL 14 to PostgreSQL 17. Database owners should review these changes to assess application compatibility before upgrading.

### Upgrade Path
```
PostgreSQL 14 → 15 → 16 → 17
```

Each major version introduces breaking changes that must be reviewed.

### Risk Assessment Quick Reference

| Change Category | Risk Level | Action Required |
|----------------|------------|-----------------|
| **Removed Features** | 🔴 High | Code changes needed |
| **Changed Behavior** | 🟡 Medium | Testing required |
| **Security Restrictions** | 🟡 Medium | Permission review |
| **Performance Changes** | 🟢 Low | Monitoring recommended |
| **Deprecated Features** | 🟡 Medium | Plan migration |

---

## Table of Contents

1. [PostgreSQL 14 → 15 Breaking Changes](#postgresql-14--15-breaking-changes)
2. [PostgreSQL 15 → 16 Breaking Changes](#postgresql-15--16-breaking-changes)
3. [PostgreSQL 16 → 17 Breaking Changes](#postgresql-16--17-breaking-changes)
4. [Critical Changes Summary](#critical-changes-summary)
5. [Pre-Upgrade Checklist](#pre-upgrade-checklist)
6. [Testing Recommendations](#testing-recommendations)

---

## PostgreSQL 14 → 15 Breaking Changes

### 🔴 High Impact Changes

#### 1. PUBLIC Schema Permissions Revoked

**What Changed:**
- Users no longer have `CREATE` privilege on the `public` schema by default
- This is a **major security change**

**Impact:**
```sql
-- This will FAIL in v15 (worked in v14):
CREATE TABLE my_table (id INT);  -- Error: permission denied for schema public

-- Applications creating temporary objects may fail
CREATE TEMP TABLE temp_data AS SELECT ...;
```

**Who's Affected:**
- Applications that create tables without specifying schema
- Users who rely on default `CREATE` permissions
- ETL processes that create temporary objects

**Fix:**
```sql
-- Option 1: Grant CREATE back (restores old behavior)
GRANT CREATE ON SCHEMA public TO PUBLIC;

-- Option 2: Specify schema explicitly
CREATE TABLE myschema.my_table (id INT);

-- Option 3: Use specific roles
GRANT CREATE ON SCHEMA public TO app_user;
```

**Migration Strategy:**
1. Review all `CREATE TABLE`, `CREATE VIEW`, `CREATE FUNCTION` statements
2. Test with restricted permissions in staging
3. Decide: restore old behavior or update code

---

#### 2. Exclusive Backup Mode Removed

**What Changed:**
- `pg_start_backup(exclusive => true)` removed
- Only non-exclusive backup mode supported

**Impact:**
```sql
-- This will FAIL in v15:
SELECT pg_start_backup('backup', true);  -- Error: exclusive mode not supported
```

**Who's Affected:**
- Custom backup scripts using exclusive mode
- Third-party backup tools not updated for v15

**Fix:**
```sql
-- Use non-exclusive mode:
SELECT pg_start_backup('backup', false);

-- Or use AWS native backups (recommended for Aurora)
```

**Migration Strategy:**
1. Audit all backup scripts
2. Update to non-exclusive mode or use AWS snapshots
3. Test backup/restore procedures before upgrade

---

#### 3. UNIQUE Constraint Behavior with NULLs

**What Changed:**
- Multiple `NULL` values in `UNIQUE` columns now handled differently
- More SQL-standard compliant behavior

**Impact:**
```sql
CREATE TABLE test (
    id INT,
    email VARCHAR UNIQUE
);

-- v14: Multiple NULLs allowed
INSERT INTO test VALUES (1, NULL);  -- OK
INSERT INTO test VALUES (2, NULL);  -- OK

-- v15: Behavior may differ based on constraint definition
```

**Who's Affected:**
- Tables with `UNIQUE` constraints that allow `NULL`
- Applications relying on old `NULL` handling

**Fix:**
- Review all `UNIQUE` constraints
- Test data insertion patterns
- May need to use `UNIQUE NULLS NOT DISTINCT` for old behavior

---

### 🟡 Medium Impact Changes

#### 4. Regular Expression Parsing Stricter

**What Changed:**
- More strict regex pattern validation
- Some previously accepted patterns may fail

**Impact:**
```sql
-- Some regex patterns that worked in v14 may fail in v15
SELECT 'text' ~ 'invalid[regex';  -- May raise error
```

**Who's Affected:**
- Applications using complex regex patterns
- Data validation rules using regex

**Fix:**
- Audit all regex usage in SQL
- Test regex patterns in staging
- Update invalid patterns

---

#### 5. to_timestamp() / to_date() More Strict

**What Changed:**
- Stricter input validation
- Previously accepted invalid dates may now fail

**Impact:**
```sql
-- May fail in v15 (was lenient in v14):
SELECT to_date('2023-02-30', 'YYYY-MM-DD');  -- Invalid date
SELECT to_timestamp('25:00:00', 'HH24:MI:SS');  -- Invalid time
```

**Who's Affected:**
- ETL processes with date conversion
- Applications with flexible date inputs

**Fix:**
- Validate input data before conversion
- Add error handling for date functions
- Test all date/time conversions

---

## PostgreSQL 15 → 16 Breaking Changes

### 🔴 High Impact Changes

#### 1. EXECUTE Privilege Required for Trigger Functions

**What Changed:**
- Trigger functions now require explicit `EXECUTE` privilege
- Previously worked without explicit permission

**Impact:**
```sql
-- Trigger creation may fail if user lacks EXECUTE privilege
CREATE TRIGGER my_trigger
    BEFORE INSERT ON my_table
    FOR EACH ROW EXECUTE FUNCTION my_trigger_function();
-- Error: permission denied for function my_trigger_function
```

**Who's Affected:**
- Applications with triggers
- Users who create triggers but don't own the trigger function

**Fix:**
```sql
-- Grant EXECUTE privilege:
GRANT EXECUTE ON FUNCTION my_trigger_function() TO app_user;
```

**Migration Strategy:**
1. Audit all triggers and their functions
2. Grant necessary `EXECUTE` privileges
3. Test trigger functionality after upgrade

---

#### 2. System Catalog Changes

**What Changed:**
- `pg_stat_*` views have new columns
- Some monitoring queries may break

**Impact:**
```sql
-- Queries with SELECT * from system views may fail
SELECT * FROM pg_stat_activity;  -- New columns added

-- Column count mismatches in application code
```

**Who's Affected:**
- Monitoring tools querying system catalogs
- Applications with hardcoded column positions
- Backup/restore scripts

**Fix:**
- Use explicit column names instead of `SELECT *`
- Update monitoring queries
- Test all admin scripts

---

### 🟡 Medium Impact Changes

#### 3. Query Planner Improvements

**What Changed:**
- Significant query planner enhancements
- Execution plans may change

**Impact:**
- Query performance may improve or degrade
- Different index usage
- Memory usage changes

**Who's Affected:**
- Performance-critical queries
- Applications with query timeouts
- Optimized database schemas

**Fix:**
- Benchmark critical queries before/after
- Update statistics: `ANALYZE`
- Review execution plans: `EXPLAIN ANALYZE`
- Consider reindexing

---

#### 4. Parallel Query Enhancements

**What Changed:**
- Better parallel query support
- More operations can run in parallel

**Impact:**
- Higher CPU usage for some queries
- Better performance for large datasets
- Different resource consumption patterns

**Who's Affected:**
- Data warehouse workloads
- Batch processing jobs
- Reporting queries

**Fix:**
- Monitor CPU usage after upgrade
- Adjust `max_parallel_workers` if needed
- Test parallel query behavior

---

## PostgreSQL 16 → 17 Breaking Changes

### 🔴 High Impact Changes

#### 1. old_snapshot_threshold Parameter Removed

**What Changed:**
- `old_snapshot_threshold` server variable completely removed
- Feature that allowed vacuum to cause "snapshot too old" errors

**Impact:**
```sql
-- This parameter no longer exists:
SHOW old_snapshot_threshold;  -- Error: unrecognized configuration parameter
```

**Who's Affected:**
- Databases using `old_snapshot_threshold` for long-running queries
- Applications relying on this behavior
- Custom vacuum strategies

**Fix:**
- Remove parameter from `postgresql.conf`
- Adjust long-running query handling
- Review vacuum policies

---

#### 2. db_user_namespace Feature Removed

**What Changed:**
- Feature simulating per-database users removed
- Rarely used feature eliminated

**Impact:**
```sql
-- db_user_namespace no longer available
-- Users can no longer be scoped to specific databases using this feature
```

**Who's Affected:**
- Rare: Only if explicitly using `db_user_namespace`
- Multi-tenant applications with per-database users

**Fix:**
- Migrate to standard PostgreSQL role management
- Use separate databases with different roles
- Implement application-level user scoping

---

#### 3. SET SESSION AUTHORIZATION Behavior Change

**What Changed:**
- Behavior based on session user's **current** superuser status
- Previously based on connection-time status

**Impact:**
```sql
-- Behavior change when switching authorization:
SET SESSION AUTHORIZATION 'new_user';
-- Now checks current superuser status, not original connection status
```

**Who's Affected:**
- Applications using `SET SESSION AUTHORIZATION`
- Security-sensitive session management
- Connection poolers with authorization switching

**Fix:**
- Review all `SET SESSION AUTHORIZATION` usage
- Test authorization switching behavior
- Update security assumptions

---

#### 4. Interval Syntax Restrictions

**What Changed:**
- `ago` keyword now restricted to end of interval only
- Empty interval units cannot appear multiple times

**Impact:**
```sql
-- This may FAIL in v17:
SELECT INTERVAL '3 days ago 2 hours';  -- Error: 'ago' must be at end

-- This works:
SELECT INTERVAL '3 days 2 hours ago';  -- OK

-- This may fail:
SELECT INTERVAL '1 day day';  -- Error: duplicate unit
```

**Who's Affected:**
- Applications with dynamic interval construction
- Date/time calculations
- Reporting queries

**Fix:**
- Audit all `INTERVAL` usage
- Update interval syntax
- Test date arithmetic

---

#### 5. Maintenance Operation Security Changes

**What Changed:**
- Functions in expression indexes and materialized views require specified search path
- Prevents unsafe access during maintenance operations

**Impact:**
```sql
-- Expression indexes and materialized views must have explicit search path
CREATE INDEX idx ON table ((my_function(column)));
-- my_function must have search_path set during creation

-- Affects: ANALYZE, CLUSTER, REFRESH MATERIALIZED VIEW, REINDEX, VACUUM
```

**Who's Affected:**
- Databases with expression indexes
- Materialized views using functions
- Maintenance procedures

**Fix:**
```sql
-- Set search path when creating functions:
CREATE FUNCTION my_function(x INT) RETURNS INT
    LANGUAGE SQL
    SET search_path = public
AS $$
    SELECT x + 1;
$$;
```

---

### 🟡 Medium Impact Changes

#### 6. Windows: fsync_writethrough Removed

**What Changed:**
- `wal_sync_method = 'fsync_writethrough'` removed on Windows
- Functionally equivalent to `fsync`

**Impact:**
```sql
-- This setting no longer valid on Windows:
SET wal_sync_method = 'fsync_writethrough';  -- Error on Windows
```

**Who's Affected:**
- **Aurora PostgreSQL on Windows** (rare - Aurora is primarily Linux)
- Windows-based PostgreSQL installations

**Fix:**
```sql
-- Use fsync instead:
SET wal_sync_method = 'fsync';
```

---

#### 7. WAL File Name Function Changes

**What Changed:**
- Adjustments to file boundary handling in WAL functions
- May affect backup/replication tools

**Impact:**
- WAL-related functions return slightly different results
- Custom backup scripts may need updates

**Who's Affected:**
- Custom backup solutions
- WAL archiving scripts
- Replication management tools

**Fix:**
- Test backup/restore procedures
- Update WAL processing scripts
- Verify replication functionality

---

## AWS Aurora PostgreSQL Specific Changes

### RDS Reserved Connection Slots

**Introduced in:** PostgreSQL 16.5, 15.9, 14.14, 13.17

**What Changed:**
- Some connection slots now reserved for `rds_reserved` role
- Granted to Amazon RDS administrative users

**Impact:**
```sql
-- Effective max_connections reduced by reserved slots
-- Parameter: rds.rds_reserved_connections

-- Example:
-- max_connections = 100
-- rds.rds_reserved_connections = 2
-- Available to applications: 98
```

**Who's Affected:**
- Applications close to `max_connections` limit
- Connection pool configurations

**Fix:**
```sql
-- Option 1: Increase max_connections
ALTER SYSTEM SET max_connections = 105;

-- Option 2: Adjust application connection pools
-- Reduce pool size by reserved connection count

-- Option 3: Monitor connection usage
SELECT count(*) FROM pg_stat_activity;
```

---

### Extension Compatibility

**Key Extensions to Check:**

```sql
-- Check current extensions:
SELECT extname, extversion FROM pg_extension ORDER BY extname;

-- Known compatibility issues:
-- - TimescaleDB: ABI changes in some versions
-- - PostGIS: Verify version compatibility
-- - pg_cron: Updated to 1.6+ for v16
-- - orafce: Updated to 4.14+ for v16
```

**Action Required:**
1. List all installed extensions
2. Check compatibility for target PostgreSQL version
3. Plan extension updates
4. Test extension functionality

---

## Critical Changes Summary

### Must Review Before Upgrade

| Change | Versions | Risk | Action |
|--------|----------|------|--------|
| PUBLIC schema permissions | 14→15 | 🔴 High | Test app permissions |
| Exclusive backup removed | 14→15 | 🔴 High | Update backup scripts |
| Trigger EXECUTE privilege | 15→16 | 🔴 High | Grant privileges |
| old_snapshot_threshold removed | 16→17 | 🔴 High | Remove from config |
| Interval syntax restrictions | 16→17 | 🔴 High | Audit INTERVAL usage |
| SET SESSION AUTHORIZATION | 16→17 | 🟡 Medium | Test authorization |
| Query planner changes | All | 🟡 Medium | Benchmark performance |
| System catalog changes | All | 🟡 Medium | Update monitoring |

---

## Pre-Upgrade Checklist

### Phase 1: Discovery (Before Testing)

```markdown
**Code Review:**
- [ ] Search codebase for PUBLIC schema usage
- [ ] Find all CREATE TABLE/VIEW/FUNCTION without schema
- [ ] Identify all trigger functions
- [ ] Locate regex usage in SQL
- [ ] Find date/time conversion functions
- [ ] Search for INTERVAL usage
- [ ] Check for SET SESSION AUTHORIZATION

**Configuration Review:**
- [ ] List all custom PostgreSQL parameters
- [ ] Identify use of old_snapshot_threshold
- [ ] Check wal_sync_method settings
- [ ] Review max_connections configuration

**Database Objects:**
- [ ] List all triggers and their functions
- [ ] Inventory all expression indexes
- [ ] List all materialized views
- [ ] Check for UNIQUE constraints with NULLs
- [ ] Review all custom functions and search paths

**Extensions:**
- [ ] List installed extensions and versions
- [ ] Check compatibility for target version
- [ ] Plan extension upgrade path

**Backup/Monitoring:**
- [ ] Review custom backup scripts
- [ ] Check monitoring queries on system catalogs
- [ ] Verify admin tool compatibility
```

---

### Phase 2: Testing (Staging Environment)

```markdown
**Functional Testing:**
- [ ] Test all CRUD operations
- [ ] Verify trigger functionality
- [ ] Test date/time conversions with edge cases
- [ ] Validate regex patterns
- [ ] Test interval calculations
- [ ] Verify session authorization switching

**Permission Testing:**
- [ ] Test table creation in public schema
- [ ] Verify trigger creation permissions
- [ ] Test function execution permissions
- [ ] Check role and privilege grants

**Performance Testing:**
- [ ] Run EXPLAIN ANALYZE on critical queries
- [ ] Compare execution plans v14 vs v17
- [ ] Benchmark query response times
- [ ] Monitor resource usage (CPU, memory, I/O)
- [ ] Test parallel query performance

**Integration Testing:**
- [ ] Test backup/restore procedures
- [ ] Verify monitoring tool functionality
- [ ] Test application connection pooling
- [ ] Verify extension functionality
- [ ] Test replication (if applicable)

**Data Validation:**
- [ ] Run ANALYZE on all tables
- [ ] Check data integrity constraints
- [ ] Verify foreign key relationships
- [ ] Test CHECK constraints
```

---

### Phase 3: Validation SQL Queries

Run these queries to identify potential issues:

#### Check for PUBLIC Schema Usage
```sql
-- Find objects in public schema
SELECT schemaname, tablename, tableowner
FROM pg_tables
WHERE schemaname = 'public';

-- Find functions in public schema
SELECT n.nspname as schema, p.proname as function
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public';
```

#### Check Triggers and Permissions
```sql
-- List all triggers and their functions
SELECT
    t.tgname as trigger_name,
    c.relname as table_name,
    p.proname as function_name,
    pg_get_userbyid(p.proowner) as function_owner
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_proc p ON t.tgfoid = p.oid
WHERE NOT t.tgisinternal
ORDER BY table_name, trigger_name;

-- Check EXECUTE privileges on trigger functions
SELECT
    n.nspname as schema,
    p.proname as function,
    pg_get_userbyid(p.proowner) as owner,
    has_function_privilege('app_user', p.oid, 'EXECUTE') as has_execute
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE p.oid IN (SELECT tgfoid FROM pg_trigger WHERE NOT tgisinternal);
```

#### Check Expression Indexes
```sql
-- Find expression indexes
SELECT
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE indexdef LIKE '%(%(%';  -- Heuristic for expression indexes
```

#### Check UNIQUE Constraints with NULLs
```sql
-- Find UNIQUE constraints that might be affected
SELECT
    tc.table_schema,
    tc.table_name,
    tc.constraint_name,
    kcu.column_name,
    c.is_nullable
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
    AND tc.table_schema = kcu.table_schema
JOIN information_schema.columns c
    ON kcu.table_name = c.table_name
    AND kcu.column_name = c.column_name
    AND kcu.table_schema = c.table_schema
WHERE tc.constraint_type = 'UNIQUE'
    AND c.is_nullable = 'YES';
```

#### Check for Interval Usage
```sql
-- Find stored procedures with INTERVAL
SELECT
    n.nspname as schema,
    p.proname as function,
    pg_get_functiondef(p.oid) as definition
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE pg_get_functiondef(p.oid) ILIKE '%INTERVAL%'
    AND n.nspname NOT IN ('pg_catalog', 'information_schema');
```

#### Check Extensions
```sql
-- List extensions and versions
SELECT
    extname as extension,
    extversion as current_version,
    (SELECT default_version 
     FROM pg_available_extensions 
     WHERE name = extname) as available_version
FROM pg_extension
ORDER BY extname;
```

---

## Testing Recommendations

### Test Environment Strategy

#### 1. Restore Production Snapshot to Staging

```bash
# Restore from production snapshot to test cluster
aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier test-pg17-upgrade \
  --snapshot-identifier prod-latest-snapshot \
  --engine aurora-postgresql \
  --engine-version 17.1

# Test upgrade on this cluster
```

#### 2. Run Compatibility Tests

```sql
-- Test script example
BEGIN;

-- Test 1: PUBLIC schema permissions
CREATE TABLE test_public_schema (id INT);
-- Expected: Should fail without explicit grant

-- Test 2: Trigger permissions
CREATE TRIGGER test_trigger
    BEFORE INSERT ON my_table
    FOR EACH ROW EXECUTE FUNCTION my_function();
-- Expected: Check if EXECUTE privilege needed

-- Test 3: Interval syntax
SELECT INTERVAL '3 days 2 hours ago';
-- Expected: Verify syntax is accepted

ROLLBACK;
```

#### 3. Performance Baseline

```sql
-- Before upgrade: capture baselines
CREATE TABLE performance_baseline AS
SELECT
    query,
    mean_exec_time,
    stddev_exec_time,
    calls
FROM pg_stat_statements
WHERE mean_exec_time > 100  -- Queries > 100ms
ORDER BY mean_exec_time DESC
LIMIT 100;

-- After upgrade: compare
SELECT
    b.query,
    b.mean_exec_time as before_ms,
    s.mean_exec_time as after_ms,
    ((s.mean_exec_time - b.mean_exec_time) / b.mean_exec_time * 100) as pct_change
FROM performance_baseline b
JOIN pg_stat_statements s ON b.query = s.query
WHERE abs((s.mean_exec_time - b.mean_exec_time) / b.mean_exec_time) > 0.20  -- 20% change
ORDER BY abs(pct_change) DESC;
```

---

## Application Code Audit Queries

### Search Your Codebase for These Patterns

#### 1. Schema-less Table Creation
```bash
# Search application code
grep -r "CREATE TABLE" ./src/ | grep -v "CREATE TABLE [a-z_]*\."
grep -r "CREATE TEMP" ./src/
```

#### 2. Backup Script References
```bash
# Find backup scripts
grep -r "pg_start_backup" ./scripts/
grep -r "exclusive" ./scripts/
```

#### 3. Interval Usage
```bash
# Find interval usage in code
grep -r "INTERVAL.*ago" ./src/
grep -r "INTERVAL" ./src/ | grep -v "// "
```

#### 4. Regex Usage
```bash
# Find regex in SQL
grep -r "~" ./src/ | grep -E "(SELECT|WHERE|HAVING)"
grep -r "!~" ./src/
grep -r "SIMILAR TO" ./src/
```

---

## Decision Matrix: Can We Upgrade?

### Green Light ✅ (Low Risk)

Upgrade can proceed if:
- [ ] No use of removed features
- [ ] All code reviewed and tested
- [ ] Performance benchmarks acceptable
- [ ] All extensions compatible
- [ ] Backup/restore procedures validated
- [ ] Rollback plan documented
- [ ] Stakeholders informed

### Yellow Light 🟡 (Medium Risk - Mitigation Needed)

Proceed with caution if:
- [ ] Some code changes required (but identified)
- [ ] Performance changes acceptable (after tuning)
- [ ] Extension updates available
- [ ] Additional testing time allocated
- [ ] Staged rollout plan in place

### Red Light 🔴 (High Risk - Do Not Upgrade Yet)

Delay upgrade if:
- [ ] Critical features removed without workaround
- [ ] Extensions incompatible with no update available
- [ ] Significant performance degradation in testing
- [ ] Insufficient testing completed
- [ ] No rollback plan
- [ ] Breaking changes not understood or addressed

---

## References

### Official Documentation

- [PostgreSQL 15 Release Notes](https://www.postgresql.org/docs/15/release-15.html)
- [PostgreSQL 16 Release Notes](https://www.postgresql.org/docs/16/release-16.html)
- [PostgreSQL 17 Release Notes](https://www.postgresql.org/docs/17/release-17.html)
- [AWS Aurora PostgreSQL Release Notes](https://docs.aws.amazon.com/AmazonRDS/latest/PostgreSQLReleaseNotes/)

### Upgrade Guides

- [PostgreSQL Upgrade Guide](https://www.postgresql.org/docs/current/upgrading.html)
- [AWS Aurora PostgreSQL Upgrades](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/USER_UpgradeDBInstance.PostgreSQL.html)

### Tools

- [pg_upgrade Documentation](https://www.postgresql.org/docs/current/pgupgrade.html)
- [why-upgrade.depesz.com](https://why-upgrade.depesz.com/) - Interactive version comparison

---

## Support and Questions

**For Technical Questions:**
- Database Team: #database-support
- Platform Engineering: platform-engineering@yourcompany.com

**For Business Impact:**
- Application Owners: Review with your tech lead
- Product Managers: Assess feature impact

**Emergency Contacts:**
- On-Call DBA: PagerDuty "Database Team"
- Platform Escalation: Check runbook

---

## Document Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | Oct 2025 | Initial version covering PostgreSQL 14 → 17 breaking changes |

---

## Approval Sign-off

**Before upgrading to PostgreSQL 17, this document should be:**

- [ ] Reviewed by Database Administrator
- [ ] Reviewed by Application Tech Leads
- [ ] Reviewed by Platform Engineering
- [ ] All breaking changes assessed
- [ ] Compatibility testing completed
- [ ] Risk mitigation plans documented

**Prepared by:** Platform Engineering Team  
**Reviewed by:** ___________________________  
**Date:** ___________________________

