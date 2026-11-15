# Weftline — Architecture Specification

> **Document Type:** System Architecture Specification  
> **Project:** Weftline  
> **Status:** Architecture Defined — Implementation Not Started (Phase 0)  
> **Authoritative Specification:** [`workflow.md`](../workflow.md)

---

## 1. Overview and Architectural Style

Weftline is designed as a **modular monolith** running on **Java 21** and **Spring Boot**, with **PostgreSQL** serving as the authoritative single source of truth for all coordination, state transitions, and persistence.

The modular monolith style was chosen intentionally:
- It eliminates the operational and network complexity of microservices during early development.
- It enforces strict module separation through package-level boundaries and clear application-layer contracts.
- Modules may be split into separate deployable units in the future if scale warrants it, but no premature distribution is permitted.

Redis and RabbitMQ are explicitly excluded. PostgreSQL handles persistent queues, leasing, and state transitions directly via concurrency-safe relational operations.

---

## 2. Logical Module Structure

The application's business and infrastructure responsibilities are divided into six logical modules:

```text
                 Client / API Gateway
                         |
                         | REST
                         v
              +----------------------+
              |     Spring Boot      |
              |                      |
              |         api          |
              |          |           |
              |          v           |
              |         job          |
              |          |           |
              |          v           |
              |       workflow       |
              |      /       \       |
              |   graph      saga    |
              |          |           |
              |          v           |
              |      execution      |
              |   /      |       \   |
              |scheduler worker recovery
              |   leasing / fencing  |
              |          |           |
              |          v           |
              |        retry         |
              |          |           |
              |          v           |
              |        outbox -------+----> Kafka (Phase 7)
              +----------|-----------+
                         |
                         v
                    PostgreSQL
```

### Module Responsibilities

| Module | Core Responsibility | Must Not Contain |
|---|---|---|
| `api` | REST controllers, request/response DTOs, request validation, error translation. | Database entities, SQL queries, thread/worker pools. |
| `job` | Job domain model, creation, submission service, persistence, status transitions, idempotency keys, cancellation logic. | Direct worker execution or thread management. |
| `workflow` | Workflow definitions, execution state, DAG graph validation (`workflow.graph`), dependency resolution, conditional execution, saga compensation (`workflow.saga`). | Low-level thread pool execution logic. |
| `execution` | Job scheduler (`execution.scheduler`), worker pool (`execution.worker`), atomic job claiming, worker leases and heartbeats (`execution.leasing`), crash recovery (`execution.recovery`), tenant-fair scheduling. | Direct HTTP/API handling or external network clients. |
| `retry` | Retry policies, exponential backoff with jitter calculation, maximum attempt limits, dead-letter table routing. | Workflow DAG navigation. |
| `outbox` | Transactional outbox persistence, event serialization, polling relay, Kafka event distribution (introduced in Phase 7), duplicate-safe event identifiers. | Domain state transitions. |

---

## 3. Concurrency, Ownership, and Recovery Model

### 3.1 PostgreSQL as the Single Source of Truth
Authoritative job, workflow, attempt, and event state lives in PostgreSQL. In-memory queues or caches must never become the source of truth for pending work.

### 3.2 Atomic Job Claiming (`SKIP LOCKED`)
Multiple worker instances claim eligible jobs concurrently using PostgreSQL row-level locking:
```sql
SELECT id FROM jobs
WHERE status = 'PENDING' AND available_at <= NOW()
ORDER BY priority DESC, scheduled_at ASC
FOR UPDATE SKIP LOCKED
LIMIT :batchSize;
```
- **Transaction Boundaries:** Claiming runs in a short, dedicated database transaction. Once jobs are marked claimed/running with an assigned worker and lease, the transaction is committed immediately.
- **Locking Rule:** Business execution logic must **never** run while holding row locks.

### 3.3 Leases and Heartbeats
- When a worker claims a job, it is granted a time-bound lease (`lease_expires_at`).
- While actively working, the worker updates `heartbeat_at` and renews the lease at regular intervals.
- If a worker crashes or hangs, its lease expires. The recovery scheduler periodically identifies jobs with expired leases and makes them eligible for recovery.

### 3.4 Monotonically Increasing Fencing Tokens
To solve the stale worker problem (e.g., a slow worker pauses due to GC or network delay, loses its lease to another worker, and later tries to write its result):
- Every execution attempt is assigned a monotonically increasing `fencing_token`.
- State-changing database updates (marking success, failure, or updating intermediate state) verify that the worker's token matches the current active token.
- Stale updates from pre-empted workers are rejected by the database.

### 3.5 At-Least-Once Execution
Weftline guarantees **at-least-once** execution. Because a worker might finish work but crash before recording success, handlers must be designed to be idempotent wherever feasible. The engine does not promise "exactly-once" execution of external side effects.

---

## 4. Workflow Orchestration and Saga Compensation

### 4.1 Directed Acyclic Graph (DAG) Model
Workflows consist of distinct steps connected as a DAG:
- Definitions are validated on submission for cycles, unreachable nodes, and duplicate identifiers.
- A step transitions from `WAITING` to `READY` only when all dependency parent steps have succeeded.
- Independent parallel branches can be claimed and executed concurrently by workers.

### 4.2 State Machine
- **Workflow:** `PENDING` -> `RUNNING` -> `COMPLETED` | `FAILED` | `COMPENSATING` -> (`COMPENSATED` | `FAILED`) | `CANCELLED`
- **Workflow Step:** `WAITING` -> `READY` -> `RUNNING` -> `SUCCEEDED` | `FAILED` | `SKIPPED`
- **Job Attempt:** `CLAIMED` -> `EXECUTING` -> `SUCCEEDED` | `FAILED` | `LEASE_EXPIRED`

### 4.3 Saga Compensation
When a step permanently fails in a workflow configured for compensation:
- The workflow transitions to `COMPENSATING`.
- Compensating actions are executed in reverse dependency/completion order for previously succeeded steps.
- Compensation operations can be retried if transient failures occur; permanent compensation failures are recorded explicitly for manual inspection.

---

## 5. Multi-Tenant Fairness

To prevent any single tenant from saturating the worker pool:
- Jobs carry a `tenant_id`.
- The execution scheduler uses tenant-aware claiming (round-robin or weighted fair sharing).
- High-volume backlogs from one tenant cannot starve lower-volume tenants.

---

## 6. Event History and Transactional Outbox

- **Append-Only History:** All workflow transitions produce immutable `workflow_events` for auditing and replay.
- **Transactional Outbox:** To reliably publish events to Kafka without distributed transactions (2PC), outbox records are inserted into `outbox_events` within the **same** database transaction as the domain state transition.
- **Asynchronous Relay:** An outbox poller reads unpublished events and emits them to Kafka topic `workflow.events` (Phase 7).

---

## 7. Operational Observability

- **Metrics:** Micrometer instruments job execution duration, queue depth, lease expirations, worker utilization, and retry rates.
- **Health Checks:** Spring Boot Actuator exposes operational health endpoints (`/actuator/health`).
- **Local Infrastructure:** Docker Compose (`compose.yaml`) provides a reproducible local PostgreSQL 16 environment.

---

## 8. Implementation Status

| Component | Architecture Status | Implementation Status |
|---|---|---|
| Modular Monolith Foundation | Defined | **Not Started** (Phase 0) |
| Durable Job Engine & Concurrency | Defined | **Not Started** (Phase 1) |
| Leases, Heartbeats & Fencing | Defined | **Not Started** (Phase 2) |
| Concurrency & Failure Tests | Defined | **Not Started** (Phase 3) |
| DAG Workflow Orchestration | Defined | **Not Started** (Phase 4) |
| Saga Compensation | Defined | **Not Started** (Phase 5) |
| Tenant-Fair Scheduling | Defined | **Not Started** (Phase 6) |
| Outbox & Kafka Integration | Defined | **Not Started** (Phase 7) |
| Observability & Benchmarks | Defined | **Not Started** (Phase 8) |

> **Note:** This document describes the planned architecture. No production application modules, services, or entities have been implemented yet.
