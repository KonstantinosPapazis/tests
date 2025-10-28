Here are the breaking changes you should be aware of when upgrading PostgreSQL from version 13.20 to 15.10. These include new incompatibilities, deprecated features, and behaviors that may impact existing applications and extensions.​

Major Breaking Changes
ABI compatibility for extensions: PostgreSQL 15.9 (and thus 15.10) briefly introduced an ABI break for extensions that use ResultRelInfo, causing binary incompatibility with major extensions like timescaledb, requiring a rebuild. This was restored to previous size in 15.10, but you may need to check extensions and possibly rebuild them if you skipped intermediate patches.​

ALTER {ROLE|DATABASE} SET role behavior: CVE-2024-10978 security fix in 15.9 changed how settings for roles and databases are applied for non-interactive sources. 15.10 restored prior functionality after breaking many expected use cases for automation or environment variable-based config​.

Logical replication slot restart_lsn: Before 15.10, certain logical replication restarts could result in the restart_lsn going backwards, potentially breaking replication clients or automation.​

Partitioned tables and transition triggers: Upgrading from older 13.x saw crashes if both AFTER UPDATE and AFTER DELETE triggers using transition tables were present due to incorrect requirements handling.​

libpq quoting API: Changes in escape functions (PQescapeLiteral, PQescapeIdentifier) now properly honor length parameters and handle invalid encoding differently—could break legacy code using these incorrectly.​

Extension & Feature Deprecations
Major upgrades from 13 to 15 will break or remove some old extensions, and require updating PostGIS and other dependencies before upgrading, especially on managed/cloud platforms.​

Certain features and flags are retired or replaced (this especially applies for cloud and vendor distributions; check with your provider for third party extension compatibility).​

Security Fixes with Potential Side Effects
CVE-2024-10976, CVE-2024-10977, CVE-2024-10978, CVE-2024-10979 brought strengthened safeties against privilege escalation or configuration errors, but also reverted or altered expected behavior around role and environment-based settings, requiring config review on upgrade.​

Miscellaneous Changes
New extensions and UDFs introduced in vendor builds (set_user, ldap2pg, pgAgent, barman), as well as changes to extension loading and authentication auditing, could impact startup scripts or application boot logic.​

Partitioned table dynamic partitioning behavior improved for COPY and EDB*Loader, with potential to break scripts relying on now-invalid state.​

Recommendations
Review release notes for each minor and major version for full deprecation or incompatibility lists, including vendor-specific changes for Oracle compatibility mods, cloud automated extension management, and more.​

Before upgrading, audit your extensions (especially Timescaledb, PostGIS, pgaudit, dblink, etc.), triggers (especially in partitioned tables), logic that relies on role/database config inheritance, and all automation dependent on libpq client behavior or logical replication.​

Consult the official PostgreSQL release notes if you need full changelogs or details for each step


------
When upgrading PostgreSQL from 13 to 15, several extension compatibility issues must be considered, especially if using managed platforms like Azure, AWS, or Google Cloud.​

Unsupported Extensions
The following extensions are not supported for in-place major upgrades (must be dropped prior to upgrade and recreated afterward; otherwise, the upgrade will fail):

timescaledb

dblink

orafce

postgres_fdw

pg_partman

pgaudit (Azure-specific restriction)

Platforms like Azure and Cloud SQL for PostgreSQL block major upgrades if these extensions are present.​

PostGIS and Dependency Handling
PostGIS needs to be upgraded alongside PostgreSQL, and mismatches in PostGIS versions or dependent schemas (postgis_raster, postgis_sfcgal, etc.) can break spatial functionality or abort upgrades.​

Old unsupported PostGIS versions (e.g., 2.5) are likely incompatible with PostgreSQL 15 and must be upgraded to newer releases.​

Extension Version Compatibility
Extension versions do not automatically upgrade; manual steps are needed to install compatible versions (especially for extensions compiled with C libraries—binary incompatibility occurs across major PostgreSQL releases).​

Failure to manually update extensions leads to errors such as application failures, missing functionality, or lost data.​

Vendor and Cloud Platform Restrictions
Managed platforms (AWS, Azure, Google Cloud) can further restrict which extensions are installable after an upgrade, using parameters like rds.allowed_extensions (AWS) or azure.extensions (Azure).​

If unsupported extensions are present, the upgrade is aborted with a clear error pointing to the incompatibility.​

Recommendations
Before upgrading, use SQL queries to list all installed extensions and their versions:
SELECT oid, extname, extversion FROM pg_extension;​

Remove any unsupported extensions, update all required ones to the latest compatible versions, and test database logic and application behavior thoroughly before committing to production.​

These compatibility checks and procedures are critical for a successful upgrade from 13 to 15, especially for databases relying heavily on extensions and custom modules.​

-----