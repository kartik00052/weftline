# Weftline — Testing Strategy and Verification Guide

> **Document Type:** Testing Strategy & Concurrency Verification Specification  
> **Testing Frameworks:** JUnit 5, Mockito, Testcontainers, Spring Boot Test  
> **Status:** Strategy Defined — Implementation Not Started (0 tests currently implemented)  
> **Authoritative Specification:** [`workflow.md`](../workflow.md)

---

## 1. Testing Philosophy

Weftline is a durable infrastructure engine whose primary value lies in its behavior under **failure, concurrency, and partial execution**. 

Key testing tenets:
- **Correctness under failure is prioritized over simple happy paths.**
- **Never mock PostgreSQL for concurrency or locking tests.** Mocks cannot validate `SKIP LOCKED`, row-level locks, transaction isolation, or database constraints.
- **Real infrastructure via Testcontainers:** All integration and concurrency tests must run against real PostgreSQL container instances.
- **Determinism over arbitrary sleeps:** Use countdown latches, synchronized test barriers, and condition polling rather than fragile `Thread.sleep()` calls.
- **Zero test pollution:** Every integration test must operate in an isolated database or cleanly manage its test data.

---

## 2. Test Hierarchy and Categorization

```text
+-------------------------------------------------------------+
|               Phase 3 & Phase 8: Benchmarks & Stress        |
|               (100+ concurrent claimers, load tests)        |
+-------------------------------------------------------------+
|               Concurrency & Failure Injection Tests         |
|         (Worker crash, lease expiry, stale worker fencing)  |
+-------------------------------------------------------------+
|               Integration Tests (Testcontainers)            |
|         (PostgreSQL SKIP LOCKED, Flyway migrations, JPA)    |
+-------------------------------------------------------------+
|               Unit Tests (Fast, Isolated)                   |
|         (DAG cycles, retry backoff formulas, DTO validation)|
+-------------------------------------------------------------+
```

### 2.1 Unit Tests
- **Scope:** Pure domain logic, state machines, math formulas, and input validation.
- **Examples:**
  - Validating exponential backoff and jitter calculations in the `retry` module.
  - DAG cycle detection and topological sorting in `workflow.graph`.
  - State machine transition rules (e.g., verifying invalid transitions throw exceptions).
  - REST request validation annotations and error translation.

### 2.2 Integration Tests (PostgreSQL via Testcontainers)
- **Scope:** Spring Data JPA repositories, Spring JDBC custom queries, and Flyway schema execution.
- **Infrastructure:** Real PostgreSQL 16 container spun up automatically using Testcontainers.
- **Key Scenarios:**
  - Flyway migration application from clean database state.
  - Verifying tenant-scoped idempotency unique constraints.
  - Atomic state updates within short transactional boundaries.

### 2.3 Concurrency & Atomic Claiming Tests (Phase 3)
- **Objective:** Prove that multiple independent worker threads or application instances cannot claim or execute the same job.
- **Scenario:**
  1. Insert a batch of 1,000 pending jobs.
  2. Spawn 20–50 concurrent worker threads executing `SELECT ... FOR UPDATE SKIP LOCKED`.
  3. Assert that every job is claimed exactly once across all workers.
  4. Assert that no two workers ever hold an active lease for the same job simultaneously.
  5. Assert that claim transactions commit immediately before job execution logic begins.

### 2.4 Failure Recovery and Fencing Tests (Phase 3)

#### Test A: Worker Crash & Expired-Lease Recovery
1. Worker A claims Job X and begins execution with a 5-second lease.
2. Worker A's heartbeat is abruptly terminated (simulating a crash or kill -9).
3. Wait for the lease to expire (`lease_expires_at < NOW()`).
4. Trigger the recovery scheduler.
5. Verify that Job X is safely recovered and reassigned to Worker B.
6. Verify that attempt history accurately records the lease expiration.

#### Test B: Stale Worker Fencing Enforcement
1. Worker A claims Job X (assigned `fencing_token = 1`).
2. Worker A pauses (simulating long GC pause or network partition).
3. Lease expires; recovery assigns Job X to Worker B with `fencing_token = 2`.
4. Worker B executes and completes Job X, committing with `fencing_token = 2`.
5. Worker A wakes up and attempts to commit its stale result with `fencing_token = 1`.
6. **Assert:** The database rejects Worker A's update due to token mismatch.
7. **Assert:** Worker B's result remains intact and uncorrupted.

#### Test C: Application Restart Recovery
1. Submit a set of pending and executing jobs.
2. Terminate the Spring Boot application context.
3. Restart the application against the same PostgreSQL database.
4. Verify that pending jobs remain durable and resume claiming without manual intervention.

---

## 3. Workflow Engine Verification (Phase 4 & Phase 5)

- **DAG Validation:**
  - Cycle detection: Definitions with circular dependencies (A -> B -> C -> A) must be rejected with descriptive validation errors.
  - Disconnected steps and multi-root DAGs: Verify valid execution order.
- **Dependency Execution:**
  - Steps only transition to `READY` when all parent dependencies reach `SUCCEEDED`.
  - Independent parallel steps execute concurrently across workers.
- **Saga Compensation (Phase 5):**
  - Inject a failure at Step 4 of a 4-step workflow.
  - Verify that compensation handlers for Step 3, Step 2, and Step 1 are triggered in exact reverse dependency order.
  - Verify compensation retries and failure handling.

---

## 4. Multi-Tenant Fairness Testing (Phase 6)

- **Scenario:**
  - Tenant A submits 10,000 jobs.
  - Tenant B submits 10 jobs.
- **Verification:**
  - Worker threads must not execute all 10,000 of Tenant A's jobs before starting Tenant B.
  - Tenant B's jobs must be claimed and executed promptly according to the fair scheduling policy.

---

## 5. Outbox & Kafka Verification (Phase 7)

- **Transactional Atomicity:** Verify that if the domain transaction rolls back, no outbox record is persisted.
- **Crash Between Commit and Publish:** Simulate application crash immediately after DB commit; verify that the outbox poller discovers and publishes the pending event upon restart.
- **Idempotent Consumption:** Verify that duplicate Kafka messages with the same event ID are safely handled by consumers.

---

## 6. Local Test Infrastructure Setup

Local testing can be executed against:
1. **Automated Test Suite:** Runs Testcontainers automatically (Docker daemon required).
2. **Local Development Service:** Started via `compose.yaml`:
   ```bash
   docker compose -f compose.yaml up -d
   ```

---

## 7. Current Testing Status

| Category | Planned Tests | Implemented Tests | Status |
|---|---|---|---|
| Unit Tests | State machines, DAG validation, Retry backoff | 0 | **Not Started** |
| Repository / DB Tests | JPA & JDBC queries, migrations | 0 | **Not Started** |
| Concurrency Tests | Concurrent claiming (`SKIP LOCKED`) | 0 | **Not Started** |
| Failure Tests | Crash recovery, fencing token rejection | 0 | **Not Started** |
| Workflow & Saga Tests | DAG execution, reverse compensation | 0 | **Not Started** |
| Fairness Tests | Multi-tenant fair claiming | 0 | **Not Started** |
| Outbox & Kafka Tests | Transactional outbox relay | 0 | **Not Started** |

> **Note:** No automated tests have been implemented yet. The test suite will be constructed incrementally starting in Phase 0.
