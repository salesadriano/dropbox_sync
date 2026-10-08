---
name: supabase-postgres-best-practices
description: "Postgres best practices maintained by Supabase, valid for Postgres running anywhere. Load BEFORE writing or changing anything that lives in a Postgres database: creating or altering tables and columns, schema design, migrations and declarative schema files, RLS policies and the tests that verify them, indexes, triggers, database functions, queues and scheduled jobs (pg_cron, pgmq), vector search (pgvector), and pg_restore or data import. Also load it when diagnosing slow queries, high CPU, timeouts, EXPLAIN plans, connection exhaustion, locking, bloat, or rows visible to the wrong user or tenant. This is the default data-layer skill of this package and supports the DBA agent; it is not limited to performance work."
license: MIT
metadata:
  author: supabase
  version: "1.1.1"
  organization: Supabase
  source: supabase/agent-skills
---

# Supabase Postgres Best Practices

## Security Handoff

This skill does not replace security hardening.

- `references/security-rls-basics.md`, `references/security-rls-performance.md`, and `references/security-privileges.md` cover data-layer isolation. When the change also touches authentication, authorization, secrets, session/cookies, CSP/CORS, or API exposure, apply `security-best-practices` and `api-security-best-practices` as well.
- Never include real connection strings, credentials, service-role keys, tokens, or production data in examples, fixtures, migrations, diagrams, logs, or generated artifacts.
- Any change that alters which rows a tenant or user can read must be treated as a security change and validated with tests, not only reviewed.

## Scope Boundary

Use this skill for the data layer: schema, migrations, SQL, indexes, RLS, locking, pooling, and diagnostics.

Prefer [`clean-architecture`](../clean-architecture/SKILL.md) when the question is layer separation and where persistence belongs rather than how to model or query it. Integration tests against a real Postgres remain governed by [`protocolo-tdd`](../protocolo-tdd/SKILL.md), which requires Testcontainers with a real database and forbids mocking the data layer.


Comprehensive performance optimization guide for Postgres, maintained by Supabase. Contains rules across 8 categories, prioritized by impact to guide automated query optimization and schema design.

## When to Apply

Reference these guidelines when:
- Writing SQL queries or designing schemas
- Implementing indexes or query optimization
- Reviewing database performance issues
- Configuring connection pooling or scaling
- Optimizing for Postgres-specific features
- Working with Row-Level Security (RLS)

## Rule Categories by Priority

| Priority | Category | Impact | Prefix |
|----------|----------|--------|--------|
| 1 | Query Performance | CRITICAL | `query-` |
| 2 | Connection Management | CRITICAL | `conn-` |
| 3 | Security & RLS | CRITICAL | `security-` |
| 4 | Schema Design | HIGH | `schema-` |
| 5 | Concurrency & Locking | MEDIUM-HIGH | `lock-` |
| 6 | Data Access Patterns | MEDIUM | `data-` |
| 7 | Monitoring & Diagnostics | LOW-MEDIUM | `monitor-` |
| 8 | Advanced Features | LOW | `advanced-` |


## Quick Reference

Nao carregar o diretorio `references/` inteiro. Abrir apenas a regra necessaria (AGENTS.md item 37).

### 1. Query Performance (CRITICAL)

- [`query-composite-indexes`](references/query-composite-indexes.md) - Create Composite Indexes for Multi-Column Queries
- [`query-covering-indexes`](references/query-covering-indexes.md) - Use Covering Indexes to Avoid Table Lookups
- [`query-index-types`](references/query-index-types.md) - Choose the Right Index Type for Your Data
- [`query-missing-indexes`](references/query-missing-indexes.md) - Add Indexes on WHERE and JOIN Columns
- [`query-partial-indexes`](references/query-partial-indexes.md) - Use Partial Indexes for Filtered Queries

### 2. Connection Management (CRITICAL)

- [`conn-idle-timeout`](references/conn-idle-timeout.md) - Configure Idle Connection Timeouts
- [`conn-limits`](references/conn-limits.md) - Set Appropriate Connection Limits
- [`conn-pooling`](references/conn-pooling.md) - Use Connection Pooling for All Applications
- [`conn-prepared-statements`](references/conn-prepared-statements.md) - Use Prepared Statements Correctly with Pooling

### 3. Security & RLS (CRITICAL)

- [`security-privileges`](references/security-privileges.md) - Apply Principle of Least Privilege
- [`security-rls-basics`](references/security-rls-basics.md) - Enable Row Level Security for Multi-Tenant Data
- [`security-rls-performance`](references/security-rls-performance.md) - Optimize RLS Policies for Performance

### 4. Schema Design (HIGH)

- [`schema-constraints`](references/schema-constraints.md) - Add Constraints Safely in Migrations
- [`schema-data-types`](references/schema-data-types.md) - Choose Appropriate Data Types
- [`schema-foreign-key-indexes`](references/schema-foreign-key-indexes.md) - Index Foreign Key Columns
- [`schema-lowercase-identifiers`](references/schema-lowercase-identifiers.md) - Use Lowercase Identifiers for Compatibility
- [`schema-partitioning`](references/schema-partitioning.md) - Partition Large Tables for Better Performance
- [`schema-primary-keys`](references/schema-primary-keys.md) - Select Optimal Primary Key Strategy

### 5. Concurrency & Locking (MEDIUM-HIGH)

- [`lock-advisory`](references/lock-advisory.md) - Use Advisory Locks for Application-Level Locking
- [`lock-deadlock-prevention`](references/lock-deadlock-prevention.md) - Prevent Deadlocks with Consistent Lock Ordering
- [`lock-short-transactions`](references/lock-short-transactions.md) - Keep Transactions Short to Reduce Lock Contention
- [`lock-skip-locked`](references/lock-skip-locked.md) - Use SKIP LOCKED for Non-Blocking Queue Processing

### 6. Data Access Patterns (MEDIUM)

- [`data-batch-inserts`](references/data-batch-inserts.md) - Batch INSERT Statements for Bulk Data
- [`data-n-plus-one`](references/data-n-plus-one.md) - Eliminate N+1 Queries with Batch Loading
- [`data-pagination`](references/data-pagination.md) - Use Cursor-Based Pagination Instead of OFFSET
- [`data-upsert`](references/data-upsert.md) - Use UPSERT for Insert-or-Update Operations

### 7. Monitoring & Diagnostics (LOW-MEDIUM)

- [`monitor-explain-analyze`](references/monitor-explain-analyze.md) - Use EXPLAIN ANALYZE to Diagnose Slow Queries
- [`monitor-pg-stat-statements`](references/monitor-pg-stat-statements.md) - Enable pg_stat_statements for Query Analysis
- [`monitor-vacuum-analyze`](references/monitor-vacuum-analyze.md) - Maintain Table Statistics with VACUUM and ANALYZE

### 8. Advanced Features (LOW)

- [`advanced-full-text-search`](references/advanced-full-text-search.md) - Use tsvector for Full-Text Search
- [`advanced-jsonb-indexing`](references/advanced-jsonb-indexing.md) - Index JSONB Columns for Efficient Querying

## How to Use

Read individual rule files for detailed explanations and SQL examples:

Each rule file contains:
- Brief explanation of why it matters
- Incorrect SQL example with explanation
- Correct SQL example with explanation
- Optional EXPLAIN output or metrics
- Additional context and references
- Supabase-specific notes (when applicable)

## References

- https://www.postgresql.org/docs/current/
- https://supabase.com/docs
- https://wiki.postgresql.org/wiki/Performance_Optimization
- https://supabase.com/docs/guides/database/overview
- https://supabase.com/docs/guides/auth/row-level-security
