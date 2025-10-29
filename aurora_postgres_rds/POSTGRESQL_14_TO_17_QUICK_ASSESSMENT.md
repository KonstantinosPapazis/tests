# PostgreSQL 14 → 17: Quick Compatibility Assessment
## For Database Owners - 5 Minute Review

**Purpose:** Quick checklist to determine if your database can upgrade from PostgreSQL 14 to 17

---

## Critical Questions - Answer These First

### ✅ YES or ❌ NO - Mark each item:

| # | Question | Answer | Risk |
|---|----------|--------|------|
| 1 | Do you create tables **without** specifying a schema? (e.g., `CREATE TABLE mytable`) | ☐ YES / ☐ NO | 🔴 High |
| 2 | Do you have **custom backup scripts** using `pg_start_backup`? | ☐ YES / ☐ NO | 🔴 High |
| 3 | Do you use **database triggers**? | ☐ YES / ☐ NO | 🔴 High |
| 4 | Do you have the `old_snapshot_threshold` parameter configured? | ☐ YES / ☐ NO | 🔴 High |
| 5 | Do your queries use `INTERVAL` with the word `ago`? (e.g., `'3 days ago'`) | ☐ YES / ☐ NO | 🔴 High |
| 6 | Do you use `SET SESSION AUTHORIZATION` to switch users? | ☐ YES / ☐ NO | 🟡 Medium |
| 7 | Do you have **expression indexes** (indexes on functions)? | ☐ YES / ☐ NO | 🟡 Medium |
| 8 | Do you have **UNIQUE constraints** that allow NULL values? | ☐ YES / ☐ NO | 🟡 Medium |
| 9 | Do you use regular expressions in SQL? (~ operator) | ☐ YES / ☐ NO | 🟡 Medium |
| 10 | Are you close to your `max_connections` limit? | ☐ YES / ☐ NO | 🟡 Medium |

---

## Risk Assessment

### Count Your "YES" Answers by Risk Level:

**🔴 High Risk Items (Questions 1-5):** _____ YES answers
- **0 YES**: ✅ Low risk - proceed with confidence
- **1-2 YES**: ⚠️ Medium risk - code changes needed
- **3+ YES**: 🛑 High risk - significant work required

**🟡 Medium Risk Items (Questions 6-10):** _____ YES answers
- **0-2 YES**: ✅ Minor testing needed
- **3-4 YES**: ⚠️ Thorough testing required
- **5 YES**: ⚠️ Extended testing cycle needed

---

## If You Answered YES to Any High-Risk Question

### Question 1: Tables Without Schema

**Problem:** v15 removed default `CREATE` privilege on `public` schema

**Quick Check:**
```sql
-- Run this query:
SELECT count(*) 
FROM pg_tables 
WHERE schemaname = 'public' 
    AND tableowner = current_user;
```

**Impact:** Application may fail to create tables after upgrade

**Fix Required:** 
- Option A: Grant back old permissions: `GRANT CREATE ON SCHEMA public TO PUBLIC;`
- Option B: Update code to specify schema: `CREATE TABLE myschema.mytable`

---

### Question 2: Custom Backup Scripts

**Problem:** Exclusive backup mode removed in v15

**Quick Check:**
```bash
# Search your scripts:
grep -r "pg_start_backup" /path/to/scripts/
grep -r "exclusive" /path/to/scripts/
```

**Impact:** Backup scripts will fail

**Fix Required:** 
- Use non-exclusive mode: `pg_start_backup('label', false)`
- Or switch to AWS native snapshots (recommended)

---

### Question 3: Database Triggers

**Problem:** v16 requires `EXECUTE` privilege on trigger functions

**Quick Check:**
```sql
-- Run this query:
SELECT t.tgname, c.relname, p.proname
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_proc p ON t.tgfoid = p.oid
WHERE NOT t.tgisinternal;
```

**Impact:** Triggers may fail to fire

**Fix Required:**
```sql
-- Grant EXECUTE on each trigger function:
GRANT EXECUTE ON FUNCTION trigger_function_name() TO trigger_user;
```

---

### Question 4: old_snapshot_threshold

**Problem:** Parameter completely removed in v17

**Quick Check:**
```sql
-- Run this query:
SHOW old_snapshot_threshold;
```

**Impact:** Cluster won't start if parameter exists in config

**Fix Required:**
- Remove from `postgresql.conf`
- Remove from parameter group (Aurora)

---

### Question 5: INTERVAL with 'ago'

**Problem:** v17 restricts `ago` to end of interval only

**Quick Check:**
```bash
# Search your code:
grep -r "INTERVAL.*ago" /path/to/code/
```

**Examples:**
```sql
-- ❌ FAILS in v17:
SELECT INTERVAL '3 days ago 2 hours';

-- ✅ WORKS in v17:
SELECT INTERVAL '3 days 2 hours ago';
```

**Impact:** Queries will fail with syntax error

**Fix Required:** Move `ago` to end of all intervals

---

## Quick Compatibility Test Script

Run this in your **staging/test** database:

```sql
-- PostgreSQL 14 → 17 Quick Compatibility Test
-- Run this BEFORE upgrading

\echo '=== Testing PUBLIC Schema Permissions ==='
BEGIN;
CREATE TABLE test_public_perms (id INT);
-- If this succeeds, you have CREATE privilege on public schema
-- After v15 upgrade, this will FAIL unless you grant it back
ROLLBACK;

\echo '=== Testing Trigger Permissions ==='
-- Check if app users have EXECUTE on trigger functions
SELECT 
    p.proname as function,
    has_function_privilege('your_app_user', p.oid, 'EXECUTE') as has_execute
FROM pg_proc p
WHERE p.oid IN (SELECT tgfoid FROM pg_trigger WHERE NOT tgisinternal)
LIMIT 5;
-- If has_execute = false, you'll need to grant privileges

\echo '=== Testing Interval Syntax ==='
SELECT INTERVAL '3 days 2 hours ago';  -- This should work
-- If you have 'ago' in the middle, it will break in v17

\echo '=== Checking Extensions ==='
SELECT extname, extversion 
FROM pg_extension 
WHERE extname NOT IN ('plpgsql');
-- Verify all extensions have v17-compatible versions

\echo '=== Checking Connection Usage ==='
SELECT 
    max_conn,
    used,
    res_for_super,
    max_conn-used-res_for_super as available
FROM (
    SELECT 
        setting::int as max_conn,
        count(*) as used,
        5 as res_for_super  -- Approximate reserved connections
    FROM pg_stat_activity, pg_settings 
    WHERE pg_settings.name = 'max_connections'
    GROUP BY max_conn
) x;
-- If 'available' is low (<10), increase max_connections for reserved slots
```

---

## Immediate Actions Based on Results

### ✅ All Clear (No High-Risk YES answers)

**Recommendation:** Proceed to staging testing
- Run full test suite in staging
- Monitor performance
- Plan production upgrade

**Timeline:** 2-4 weeks

---

### ⚠️ Some Issues Found (1-2 High-Risk YES answers)

**Recommendation:** Address issues, then test

**Action Plan:**
1. Week 1: Identify and document all breaking changes
2. Week 2-3: Implement code fixes
3. Week 4: Staging testing
4. Week 5-6: Production upgrade

**Timeline:** 5-6 weeks

---

### 🛑 Major Issues (3+ High-Risk YES answers)

**Recommendation:** Significant preparation needed

**Action Plan:**
1. Month 1: Complete compatibility audit
2. Month 2: Code changes and fixes
3. Month 3: Comprehensive testing
4. Month 4: Production upgrade

**Timeline:** 3-4 months

---

## Next Steps

### 1. Share Results with Team

Forward this assessment to:
- [ ] Application developers
- [ ] Database administrators
- [ ] DevOps/Platform team
- [ ] Tech leads

### 2. Review Detailed Documentation

Read the complete breaking changes document:
- `POSTGRESQL_14_TO_17_BREAKING_CHANGES.md`

### 3. Schedule Testing

- [ ] Restore production snapshot to test cluster
- [ ] Run compatibility test script
- [ ] Execute application test suite
- [ ] Benchmark performance

### 4. Create Action Plan

Based on your risk level:
- **Low Risk:** Schedule upgrade within 1 month
- **Medium Risk:** Plan 2-3 month preparation
- **High Risk:** Allocate 3-4 months for changes

---

## Quick Reference: What Breaks Where

| Version Jump | Key Breaking Change | Impact |
|--------------|---------------------|--------|
| **14 → 15** | PUBLIC schema permissions | Cannot create tables |
| **14 → 15** | Exclusive backup removed | Backup scripts fail |
| **15 → 16** | Trigger EXECUTE privilege | Triggers don't fire |
| **15 → 16** | Query planner changes | Performance varies |
| **16 → 17** | old_snapshot_threshold removed | Config error |
| **16 → 17** | Interval ago restriction | Syntax errors |
| **16 → 17** | SET SESSION AUTHORIZATION | Behavior change |

---

## Decision Time

### Can We Upgrade?

**✅ YES - Proceed** if:
- 0-1 high-risk items
- Team has bandwidth
- Testing time available
- Rollback plan ready

**⚠️ MAYBE - With Work** if:
- 2-3 high-risk items
- Changes are understood
- Testing resources available
- 2-3 months timeline acceptable

**🛑 NO - Not Yet** if:
- 4+ high-risk items
- Changes not understood
- No testing capacity
- No rollback plan
- Business risk too high

---

## Contact for Help

**Questions about this assessment?**
- Database Team: #database-support
- Platform Engineering: platform-eng@company.com

**Need help with compatibility testing?**
- Schedule consultation with DBA team
- Request staging environment
- Ask for detailed audit

---

## Key Takeaway

**PostgreSQL 14 → 17 is a 3-major-version jump (14 → 15 → 16 → 17)**

Each version introduces breaking changes. **Don't upgrade without:**
1. ✅ Reviewing this assessment
2. ✅ Testing in staging
3. ✅ Having a rollback plan
4. ✅ Getting team buy-in

**The upgrade itself is straightforward with Blue/Green deployment, but application compatibility is critical.**

---

**Document:** Quick Assessment  
**Related:** Full breaking changes document  
**Version:** 1.0  
**Date:** October 2025

