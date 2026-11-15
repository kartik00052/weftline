# Weftline — Database Schema Specification

> **Document Type:** Database Schema & Data Model Specification  
> **Database Engine:** PostgreSQL 16+  
> **Migration Tool:** Flyway  
> **Status:** Schema Planned — Implementation Not Started (No migrations applied yet)  
> **Authoritative Specification:** [`workflow.md`](../workflow.md)

---

## 1. Schema Principles and Conventions

1. **PostgreSQL as Single Source of Truth:** All authoritative state (jobs, workflows, attempts, leases, and outbox messages) resides in PostgreSQL.
2. **Flyway Migrations:** All schema changes are managed via versioned Flyway migration scripts in `src/main/resources/db/migration/` (e.g., `V1__init_jobs.sql`). Hibernate auto-DDL is strictly prohibited.
3. **Timestamps:** All timestamp columns use `TIMESTAMPTZ` and store UTC values.
4. **Keys and Identifiers:** Primary keys use UUIDs or bigints with explicit constraints.
5. **Short Transactions:** DDL and DML operations must respect short transaction boundaries. Long-running tasks must never hold database locks.

---

## 2. Planned Tables Specification

The following tables represent the planned relational schema across development phases. None of these tables have been created yet.

### 2.1 `jobs` (Planned for Phase 1 & Phase 2)
Stores the durable units of background work.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | `UUID` | `PRIMARY KEY` | Unique job identifier |
| `tenant_id` | `VARCHAR(64)` | `NOT NULL` | Tenant owning the job |
| `job_type` | `VARCHAR(128)` | `NOT NULL` | Registered handler type |
| `payload` | `JSONB` / `TEXT` | `NOT NULL` | Job input arguments/payload |
| `status` | `VARCHAR(32)` | `NOT NULL` | `PENDING`, `RUNNING`, `SUCCEEDED`, `FAILED`, `CANCELLED` |
| `priority` | `INT` | `NOT NULL DEFAULT 0` | Execution priority |
| `created_at` | `TIMESTAMPTZ` | `NOT NULL` | Record creation timestamp |
| `updated_at` | `TIMESTAMPTZ` | `NOT NULL` | Last update timestamp |
| `scheduled_at` | `TIMESTAMPTZ` | `NOT NULL` | When the job was intended to run |
| `available_at` | `TIMESTAMPTZ` | `NOT NULL` | Next eligible execution time (backoff delay) |
| `attempt_count` | `INT` | `NOT NULL DEFAULT 0` | Number of execution attempts made |
| `max_attempts` | `INT` | `NOT NULL DEFAULT 3` | Maximum allowed attempts before dead-letter |
| `idempotency_key` | `VARCHAR(128)` | `NULL` | Tenant-scoped idempotency key |
| `lease_owner` | `VARCHAR(128)` | `NULL` | Worker ID currently holding the lease |
| `lease_expires_at`| `TIMESTAMPTZ` | `NULL` | Expiration time of current lease |
| `heartbeat_at` | `TIMESTAMPTZ` | `NULL` | Last heartbeat received from worker |
| `fencing_token` | `BIGINT` | `NOT NULL DEFAULT 0` | Monotonically increasing ownership token |
| `last_error` | `TEXT` | `NULL` | Summary of the most recent execution failure |

**Planned Indexes & Constraints:**
- `UNIQUE (tenant_id, idempotency_key)`: Ensures idempotent submission per tenant.
- `INDEX idx_jobs_claim`: `(status, available_at, priority DESC, scheduled_at ASC)` for fast `SKIP LOCKED` claiming.
- `INDEX idx_jobs_tenant`: `(tenant_id, status)` for tenant-aware scheduling and isolation.
- `INDEX idx_jobs_lease_recovery`: `(status, lease_expires_at)` where `status = 'RUNNING'`.

---

### 2.2 `job_attempts` (Planned for Phase 2)
Maintains an immutable historical record of every execution attempt for a job.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | `UUID` | `PRIMARY KEY` | Unique attempt identifier |
| `job_id` | `UUID` | `NOT NULL REFERENCES jobs(id)` | Associated job |
| `attempt_number` | `INT` | `NOT NULL` | Attempt counter (1, 2, 3...) |
| `worker_id` | `VARCHAR(128)` | `NOT NULL` | Worker node that performed the attempt |
| `status` | `VARCHAR(32)` | `NOT NULL` | `CLAIMED`, `EXECUTING`, `SUCCEEDED`, `FAILED`, `LEASE_EXPIRED` |
| `started_at` | `TIMESTAMPTZ` | `NOT NULL` | Attempt start timestamp |
| `finished_at` | `TIMESTAMPTZ` | `NULL` | Attempt completion timestamp |
| `error_details` | `TEXT` | `NULL` | Stack trace or failure reason |
| `fencing_token` | `BIGINT` | `NOT NULL` | Fencing token assigned to this attempt |

**Planned Indexes:**
- `INDEX idx_job_attempts_job_id`: `(job_id, attempt_number DESC)`

---

### 2.3 `dead_letters` (Planned for Phase 2)
Holds jobs that have permanently exhausted retry attempts or suffered unrecoverable failures.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | `UUID` | `PRIMARY KEY` | Unique dead-letter identifier |
| `job_id` | `UUID` | `NOT NULL REFERENCES jobs(id)` | Associated job |
| `failure_reason` | `TEXT` | `NOT NULL` | Final diagnostic failure message |
| `attempt_count` | `INT` | `NOT NULL` | Total attempts attempted prior to dead-letter |
| `created_at` | `TIMESTAMPTZ` | `NOT NULL` | When moved to dead-letter |
| `resolved_at` | `TIMESTAMPTZ` | `NULL` | When manually reprocessed or dismissed |
| `resolution_status` | `VARCHAR(32)` | `NULL` | Resolution outcome (`REPROCESSED`, `DISMISSED`) |

---

### 2.4 `workflows` (Planned for Phase 4)
Tracks the top-level lifecycle of multi-step workflow instances.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | `UUID` | `PRIMARY KEY` | Unique workflow identifier |
| `tenant_id` | `VARCHAR(64)` | `NOT NULL` | Owning tenant |
| `workflow_type` | `VARCHAR(128)` | `NOT NULL` | Registered workflow specification name |
| `status` | `VARCHAR(32)` | `NOT NULL` | `PENDING`, `RUNNING`, `COMPLETED`, `FAILED`, `COMPENSATING`, `COMPENSATED`, `CANCELLED` |
| `definition` | `JSONB` | `NOT NULL` | Complete DAG definition snapshot |
| `created_at` | `TIMESTAMPTZ` | `NOT NULL` | Creation timestamp |
| `started_at` | `TIMESTAMPTZ` | `NULL` | Workflow start timestamp |
| `completed_at` | `TIMESTAMPTZ` | `NULL` | Completion timestamp |
| `updated_at` | `TIMESTAMPTZ` | `NOT NULL` | Last state transition timestamp |

---

### 2.5 `workflow_steps` (Planned for Phase 4)
Represents executable step nodes within a workflow DAG.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | `UUID` | `PRIMARY KEY` | Unique step identifier |
| `workflow_id` | `UUID` | `NOT NULL REFERENCES workflows(id)` | Parent workflow |
| `step_key` | `VARCHAR(64)` | `NOT NULL` | Unique step key within the workflow |
| `job_id` | `UUID` | `NULL REFERENCES jobs(id)` | Underlying job backing this step execution |
| `status` | `VARCHAR(32)` | `NOT NULL` | `WAITING`, `READY`, `RUNNING`, `SUCCEEDED`, `FAILED`, `SKIPPED` |
| `step_type` | `VARCHAR(128)` | `NOT NULL` | Step handler identifier |
| `configuration` | `JSONB` | `NULL` | Step-specific execution configuration |
| `created_at` | `TIMESTAMPTZ` | `NOT NULL` | Step creation timestamp |
| `started_at` | `TIMESTAMPTZ` | `NULL` | Step execution start |
| `completed_at` | `TIMESTAMPTZ` | `NULL` | Step execution finish |

**Planned Constraints:**
- `UNIQUE (workflow_id, step_key)`

---

### 2.6 `workflow_dependencies` (Planned for Phase 4)
Defines directed edges between parent and child steps in the workflow DAG.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | `UUID` | `PRIMARY KEY` | Dependency edge identifier |
| `workflow_id` | `UUID` | `NOT NULL REFERENCES workflows(id)` | Parent workflow |
| `parent_step_id` | `UUID` | `NOT NULL REFERENCES workflow_steps(id)` | Dependency prerequisite step |
| `child_step_id` | `UUID` | `NOT NULL REFERENCES workflow_steps(id)` | Dependent step |
| `dependency_type`| `VARCHAR(32)` | `NOT NULL DEFAULT 'ON_SUCCESS'` | Required parent completion condition |

**Planned Constraints:**
- `UNIQUE (parent_step_id, child_step_id)`

---

### 2.7 `workflow_events` (Planned for Phase 7)
Append-only log of significant workflow state transitions and lifecycle milestones.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | `UUID` | `PRIMARY KEY` | Unique event identifier |
| `workflow_id` | `UUID` | `NOT NULL REFERENCES workflows(id)` | Workflow identifier |
| `step_id` | `UUID` | `NULL REFERENCES workflow_steps(id)` | Specific step if applicable |
| `event_type` | `VARCHAR(64)` | `NOT NULL` | E.g., `STEP_STARTED`, `STEP_COMPLETED`, `SAGA_TRIGGERED` |
| `event_data` | `JSONB` | `NOT NULL` | Structured event context |
| `occurred_at` | `TIMESTAMPTZ` | `NOT NULL` | Timestamp when event occurred |
| `sequence_number`| `BIGINT` | `NOT NULL` | Monotonically increasing sequence per workflow |

**Planned Constraints:**
- `UNIQUE (workflow_id, sequence_number)`

---

### 2.8 `outbox_events` (Planned for Phase 7)
Transactional outbox ensuring reliable event delivery to Kafka.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | `UUID` | `PRIMARY KEY` | Unique outbox event identifier |
| `aggregate_type` | `VARCHAR(64)` | `NOT NULL` | `JOB`, `WORKFLOW` |
| `aggregate_id` | `VARCHAR(64)` | `NOT NULL` | ID of aggregate producing event |
| `event_type` | `VARCHAR(64)` | `NOT NULL` | Canonical event name |
| `payload` | `JSONB` | `NOT NULL` | Serialized Kafka message payload |
| `created_at` | `TIMESTAMPTZ` | `NOT NULL` | Insertion timestamp (committed with domain write) |
| `published_at` | `TIMESTAMPTZ` | `NULL` | Timestamp when Kafka ACK received |
| `status` | `VARCHAR(32)` | `NOT NULL DEFAULT 'PENDING'` | `PENDING`, `PUBLISHED`, `FAILED` |
| `attempt_count` | `INT` | `NOT NULL DEFAULT 0` | Publication attempt counter |

**Planned Indexes:**
- `INDEX idx_outbox_pending`: `(status, created_at)` where `status = 'PENDING'`

---

## 3. Migration Roadmap and Status

| Migration File | Target Phase | Tables Introduced | Status |
|---|---|---|---|
| `V1__create_jobs.sql` | Phase 1 | `jobs` | **Not Created** |
| `V2__create_attempts_and_dead_letters.sql` | Phase 2 | `job_attempts`, `dead_letters` | **Not Created** |
| `V3__create_workflows_and_steps.sql` | Phase 4 | `workflows`, `workflow_steps`, `workflow_dependencies` | **Not Created** |
| `V4__create_events_and_outbox.sql` | Phase 7 | `workflow_events`, `outbox_events` | **Not Created** |

> **Note:** No Flyway migration scripts have been written or applied yet. The schema will be incrementally introduced starting in Phase 1.
