# Weftline

**A Durable Job and Workflow Execution Engine**

Weftline is a Java-based backend infrastructure project designed to execute background jobs and multi-step workflows reliably.

It provides persistent job scheduling, concurrent worker execution, automatic retries, crash recovery, execution tracking and dependency-based workflow orchestration.

The primary goal is to explore and implement the engineering challenges behind reliable asynchronous execution systems using Java, Spring Boot, PostgreSQL and production-oriented backend practices.

> **Project status:** Initial development — architecture defined, implementation not yet started.

---

## 1. The Problem

Many backend applications need to perform operations that should not execute inside the lifecycle of an HTTP request.

Examples include:

- Generating large reports and exports.
- Processing uploaded files.
- Running data transformation pipelines.
- Sending notifications after business operations.
- Executing scheduled background tasks.
- Running multi-step provisioning and onboarding processes.
- Performing operations that depend on the successful completion of other operations.

Executing these operations directly inside an HTTP request introduces problems:

- Requests may time out.
- Application instances may restart.
- Tasks may fail halfway through execution.
- Multiple workers may accidentally execute the same job.
- Failed tasks may require manual intervention.
- One customer's workload may starve another customer's workload.
- Multi-step operations may leave partially completed results.

Weftline addresses these problems through persistent execution, controlled concurrency, failure recovery and workflow orchestration.

---

## 2. Project Objectives

The project aims to implement:

1. Persistent background job submission and execution.
2. Concurrent job claiming without duplicate ownership.
3. Configurable worker pools.
4. Job lifecycle and execution-attempt tracking.
5. Automatic retries with exponential backoff and jitter.
6. Dead-letter handling for permanently failed jobs.
7. Worker leases, heartbeats and expired-lease recovery.
8. Fencing tokens to prevent stale workers from overwriting newer results.
9. DAG-based workflow execution.
10. Conditional workflow steps.
11. Saga-style compensation for multi-step operations.
12. Tenant-aware fair job scheduling.
13. Append-only workflow execution history.
14. Transactional event publishing through an outbox.
15. Monitoring, integration testing and failure testing.

---

## 3. Architecture

Weftline follows a **modular monolith architecture**.

The application is initially deployed as one Spring Boot application. Its internal responsibilities are separated into well-defined modules with controlled dependencies.

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
              |        outbox -------+----> Kafka
              +----------|-----------+
                         |
                         v
                    PostgreSQL
```

### Logical modules

| Module | Responsibility |
|---|---|
| `api` | REST endpoints, request validation and response handling |
| `job` | Job creation, persistence, lifecycle and idempotent submission |
| `workflow` | Workflow definitions, DAG validation, dependencies, conditions and saga compensation |
| `execution` | Scheduling, claiming, worker pools, leases, heartbeats, fencing and recovery |
| `retry` | Retry policies, backoff, attempt limits and dead-letter handling |
| `outbox` | Reliable publication of committed workflow events to Kafka |

Metrics and health monitoring use shared Spring Boot Actuator and Micrometer configuration. They are not separate business modules.

The logical modules may initially live in one Maven application module using feature-oriented Java packages. Separate Maven modules should only be introduced when there is a concrete architectural reason.

---

## 4. Technology Stack

| Technology | Purpose |
|---|---|
| Java 21 | Primary programming language |
| Spring Boot | Application framework |
| Maven | Dependency and build management |
| Spring Data JPA | Persistence and repository abstractions |
| Hibernate | ORM |
| PostgreSQL | Durable storage and job coordination |
| Flyway | Database schema migrations |
| Spring JDBC | Specialized SQL and concurrency-safe claiming |
| Kafka | Workflow lifecycle event distribution |
| Micrometer | Application metrics |
| Spring Boot Actuator | Health and operational endpoints |
| JUnit 5 | Automated testing |
| Mockito | Unit testing |
| Testcontainers | Real PostgreSQL and Kafka integration tests |
| Docker | Reproducible local infrastructure |

### Infrastructure strategy

The first implementation requires only:

- Spring Boot
- PostgreSQL
- Flyway
- Docker

Kafka is introduced only after the core job and workflow execution mechanisms are reliable.

Redis and RabbitMQ are not required by this project.

PostgreSQL remains the source of truth for jobs, workflows, execution attempts and workflow history.

---

## 5. Core Features and Scope

### A. Durable Job Execution

- Submit background jobs through REST APIs.
- Persist jobs before execution.
- Claim jobs atomically using PostgreSQL.
- Execute jobs using managed worker threads.
- Track job status and execution attempts.
- Support configurable execution timeouts.
- Recover jobs after worker failures.
- Support job cancellation where execution state permits it.

### B. Reliability and Recovery

- Retry failed jobs according to configurable policies.
- Apply exponential backoff and jitter.
- Move permanently failed jobs to a dead-letter table.
- Assign leases to executing workers.
- Maintain leases through heartbeats.
- Detect expired leases.
- Recover jobs from expired leases.
- Use monotonically increasing fencing tokens.
- Reject stale worker updates.
- Design for at-least-once execution.

### C. Workflow Orchestration

- Create workflows containing multiple steps.
- Represent dependencies using a directed acyclic graph.
- Validate workflow definitions before execution.
- Execute steps only after their dependencies succeed.
- Support conditional execution.
- Track workflow and step states independently.
- Resume workflow execution after application restarts.
- Support workflow cancellation.

### D. Saga Compensation

- Allow workflow steps to define compensating actions.
- Execute compensation in reverse order when required.
- Track compensation states independently.
- Retry failed compensation operations.
- Recover interrupted compensation execution.
- Preserve execution history.

Compensation is a business-level corrective operation, not a guaranteed rollback of external side effects.

### E. Tenant-Fair Scheduling

- Associate jobs with tenants.
- Prevent one tenant from monopolizing worker capacity.
- Support weighted tenant scheduling.
- Implement round-robin or equivalent fair claiming.
- Test fairness under uneven workloads.

### F. Event History and Publishing

- Maintain append-only workflow execution events.
- Record meaningful state transitions.
- Persist outbox messages in the same transaction as the corresponding state changes.
- Publish committed events asynchronously to Kafka.
- Handle duplicate event delivery through stable event identifiers.

---

## 6. State Machines

### Workflow

```text
PENDING
   |
   v
RUNNING
   |
   +----> COMPLETED
   |
   +----> FAILED
   |
   +----> COMPENSATING
              |
              +----> COMPENSATED
              |
              +----> FAILED
```

Cancellation is a separately controlled transition to `CANCELLED`, subject to execution and compensation rules.

### Workflow Step

```text
WAITING
   |
   v
READY
   |
   v
RUNNING
   |
   +----> SUCCEEDED
   |
   +----> FAILED
   |
   +----> SKIPPED
```

### Job Attempt

```text
CLAIMED
   |
   v
EXECUTING
   |
   +----> SUCCEEDED
   |
   +----> FAILED
   |
   +----> LEASE_EXPIRED
```

Job lifecycle state and individual attempt state must remain separate.

---

## 7. Core Engineering Guarantees

Weftline is designed around the following guarantees:

**Persistent execution:** A submitted job is stored in PostgreSQL before it becomes eligible for execution.

**Concurrency-safe claiming:** Multiple workers can claim jobs concurrently without acquiring the same valid job ownership.

**At-least-once execution:** A job may execute more than once after failures. Handlers must therefore be idempotent where possible.

**Lease-based recovery:** Jobs owned by workers that stop heartbeating can become eligible for recovery after their leases expire.

**Fencing protection:** An older worker must not overwrite the result produced by a newer valid execution owner.

**Transactional state changes:** Related database changes must be committed atomically.

**Durable event publication:** Workflow events are published through an outbox so a committed database transition is not silently lost during a process crash.

**Explicit failure handling:** Retries, permanent failures, dead letters and compensation failures must be observable.

Weftline does not claim exactly-once execution of arbitrary external side effects.

---

## 8. Example Use Cases

### Background report generation

```text
Submit Report Job
       |
       v
Claim Job
       |
       v
Generate Report
       |
       v
Store Report
       |
       v
Mark Job Completed
```

### Data processing workflow

```text
Validate Data
      |
      v
Transform Data
      |
      v
Load Data
      |
      v
Notify User
```

Each step executes only when its dependencies have succeeded.

### Multi-step provisioning

```text
Create Account
      |
      v
Allocate Resources
      |
      v
Configure Service
      |
      v
Activate Account
```

If a later operation permanently fails, the workflow can execute compensating actions in reverse order.

---

## 9. Development Roadmap

Development is intentionally incremental.

| Phase | Scope |
|---|---|
| 1 | Persistent job submission, database schema, atomic claiming and worker execution |
| 2 | Retries, backoff, dead letters, leases, heartbeats, recovery and fencing |
| 3 | Concurrency testing, crash recovery and Testcontainers |
| 4 | Workflow DAGs, dependencies, conditions and state transitions |
| 5 | Saga compensation, tenant fairness and workflow event history |
| 6 | Transactional outbox and Kafka event publishing |
| 7 | Metrics, observability, performance testing and documentation |

No advanced phase should begin before its preceding phase passes its acceptance tests.

---

## 10. Testing Strategy

Weftline prioritizes correctness under failure rather than merely demonstrating successful execution.

Important scenarios include:

- Submit a job and verify database persistence.
- Run multiple workers and verify safe claiming.
- Execute multiple jobs concurrently.
- Kill a worker during execution.
- Verify expired-lease recovery.
- Verify stale workers cannot overwrite newer results.
- Verify retries follow configured backoff.
- Verify permanently failed jobs enter the dead-letter table.
- Verify workflow dependencies are respected.
- Verify compensation executes in reverse order.
- Verify tenant fairness under uneven workloads.
- Verify outbox events are eventually published.
- Verify duplicate event delivery does not corrupt consumers.

PostgreSQL integration tests should use Testcontainers rather than relying exclusively on mocks.

---

## 11. Non-Goals

The initial project will not implement:

- A general-purpose distributed microservices platform.
- Kubernetes orchestration.
- A custom database engine.
- A custom message broker.
- Redis-based job storage.
- RabbitMQ-based primary job execution.
- A visual workflow designer.
- A SaaS billing platform.
- Exactly-once execution of arbitrary external operations.
- A complete enterprise workflow platform.
- Unnecessary abstractions for hypothetical future features.

The priority is correctness, maintainability, reliability and demonstrable engineering depth.

---

## 12. Project Principles

1. PostgreSQL is the source of truth.
2. Persist before execute.
3. Separate domain logic from infrastructure logic.
4. Separate job, workflow, step and attempt states.
5. Treat every worker as potentially unreliable.
6. Never trust an expired execution owner.
7. Design for duplicate execution.
8. Keep database transactions short.
9. Never perform long-running business work while holding database row locks.
10. Test concurrency with real database instances.
11. Introduce infrastructure only when a feature requires it.
12. Prefer understandable implementations over unnecessary abstractions.

---

## 13. Project Vision

Weftline aims to demonstrate how a reliable asynchronous execution system can be designed and implemented using Java backend technologies.

The focus is not simply building a queue or executing background threads. It is understanding and solving the engineering problems of durable state, concurrent ownership, failure recovery, scheduling fairness, workflow dependencies and reliable event publication.

**Weftline — Reliable execution, from individual jobs to complex workflows.**