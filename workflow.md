# WEFTLINE — MASTER ENGINEERING WORKFLOW

> **Document type:** Master implementation specification  
> **Project:** Weftline  
> **Category:** Durable Job and Workflow Execution Engine  
> **Architecture:** Modular Monolith  
> **Implementation status:** Not started  
> **Primary language:** Java 21  
> **Framework:** Spring Boot  
> **Build system:** Maven  
> **Source of truth:** PostgreSQL

---

# 1. PURPOSE OF THIS DOCUMENT

This document defines the complete engineering scope, architecture, implementation sequence, development rules and acceptance criteria for Weftline.

It is intended for:

- Human developers.
- AI coding agents.
- Code reviewers.
- Future contributors.

Any coding agent working on this repository MUST read this document before implementing or modifying project functionality.

This document is the primary implementation contract.

The objective is to build a reliable, persistent and concurrency-safe job execution and workflow orchestration engine.

The objective is NOT to create a simple background task executor or a CRUD application.

Every implementation decision should contribute to one or more of these engineering goals:

1. Durability.
2. Concurrency safety.
3. Failure recovery.
4. Execution reliability.
5. Workflow orchestration.
6. Scheduling fairness.
7. Observability.
8. Testability.

---

# 2. PROJECT DEFINITION

Weftline is a backend infrastructure system that allows applications to submit background jobs and multi-step workflows through REST APIs.

The system persists execution requests in PostgreSQL and executes them through managed worker processes.

It provides:

- Persistent job submission.
- Atomic job claiming.
- Concurrent worker execution.
- Job lifecycle management.
- Execution-attempt tracking.
- Automatic retries.
- Dead-letter handling.
- Worker leases and heartbeats.
- Expired-lease recovery.
- Fencing tokens.
- DAG-based workflow execution.
- Conditional workflow steps.
- Saga compensation.
- Tenant-fair scheduling.
- Append-only workflow execution history.
- Transactional outbox publishing.
- Operational monitoring.

Weftline should remain independently useful as a job execution engine even before workflow orchestration is implemented.

---

# 3. CORE ARCHITECTURAL DECISIONS

These decisions are established and must not be changed casually.

| Decision | Required approach |
|---|---|
| Architecture | Modular monolith |
| Language | Java 21 |
| Framework | Spring Boot |
| Build | Maven |
| Database | PostgreSQL |
| Persistence | Spring Data JPA and Spring JDBC where necessary |
| Schema management | Flyway |
| Job queue | PostgreSQL |
| Atomic claiming | SELECT FOR UPDATE SKIP LOCKED |
| Worker execution | Managed ExecutorService or Spring-managed executors |
| Reliability | At-least-once execution |
| Ownership | Leases, heartbeats and fencing tokens |
| Workflow model | Directed acyclic graph |
| Compensation | Saga-style compensation |
| Scheduling | Tenant-aware fair scheduling |
| Event history | Append-only workflow events |
| Event publishing | Transactional outbox |
| Message broker | Kafka, introduced in a later phase |
| Metrics | Micrometer |
| Health | Spring Boot Actuator |
| Integration tests | Testcontainers |
| Local infrastructure | Docker Compose (compose.yaml) |

## 3.1 PostgreSQL is the source of truth

PostgreSQL must own all authoritative execution state.

This includes:

- Jobs.
- Workflows.
- Workflow steps.
- Job attempts.
- Worker leases.
- Workflow events.
- Dead-letter records.
- Outbox messages.

The system must not rely on an in-memory queue as the authoritative source of pending jobs.

In-memory data structures may be used for local worker coordination, but losing them must not lose submitted work.

## 3.2 No Redis or RabbitMQ

Do not introduce Redis or RabbitMQ into Weftline.

PostgreSQL is the primary job coordination mechanism.

PostgreSQL `LISTEN/NOTIFY` may be introduced to wake idle workers in a later optimization, but it must never become the source of truth or the only mechanism for discovering pending jobs.

## 3.3 Kafka is a later-stage dependency

Kafka must not be introduced during the initial job engine implementation.

It is introduced only after:

- Job execution works.
- Job recovery works.
- Workflow execution works.
- Outbox records are persisted transactionally.
- Outbox publishing behavior is tested.

---

# 4. HIGH-LEVEL ARCHITECTURE

```text
                   CLIENT / API GATEWAY
                            |
                            | REST
                            v
                 +-----------------------+
                 |     Spring Boot       |
                 |                       |
                 |          api          |
                 |           |           |
                 |           v           |
                 |          job          |
                 |           |           |
                 |           v           |
                 |        workflow       |
                 |       /        \      |
                 |    graph       saga   |
                 |           |           |
                 |           v           |
                 |       execution      |
                 |    /       |      \   |
                 | scheduler worker recovery
                 |    leasing / fencing  |
                 |           |           |
                 |           v           |
                 |         retry         |
                 |           |           |
                 |           v           |
                 |         outbox        |
                 +-----------|-----------+
                             |
                             v
                        PostgreSQL
                             |
                             v
                       Outbox Relay
                             |
                             v
                           Kafka
```

## 4.1 Module responsibilities

### `api`

Responsible for:

- REST controllers.
- Request DTOs.
- Response DTOs.
- Input validation.
- HTTP exception mapping.
- API-level orchestration.
- API documentation.

Must not contain:

- SQL queries.
- Worker execution logic.
- Scheduling algorithms.
- Direct database entity manipulation from controllers.

### `job`

Responsible for:

- Job domain model.
- Job creation.
- Job submission.
- Job persistence.
- Job status transitions.
- Job idempotency.
- Job cancellation rules.
- Job retrieval.
- Job execution metadata.

### `workflow`

Responsible for:

- Workflow definitions.
- Workflow executions.
- Workflow steps.
- DAG representation.
- DAG validation.
- Dependency resolution.
- Conditional branches.
- Workflow state transitions.
- Saga compensation.
- Workflow event generation.

Sub-responsibilities:

- `workflow.graph`
- `workflow.saga`

### `execution`

Responsible for:

- Job scheduler.
- Job claiming.
- Worker pool.
- Worker lifecycle.
- Lease management.
- Heartbeats.
- Fencing tokens.
- Expired-lease recovery.
- Execution coordination.
- Graceful worker shutdown.
- Tenant-fair claiming.

Sub-responsibilities:

- `execution.scheduler`
- `execution.worker`
- `execution.leasing`
- `execution.recovery`

### `retry`

Responsible for:

- Retry policies.
- Maximum attempt configuration.
- Exponential backoff.
- Jitter.
- Next execution time.
- Permanent failure handling.
- Dead-letter processing.

### `outbox`

Responsible for:

- Outbox persistence.
- Event serialization.
- Event publication.
- Publication status.
- Retry of failed publication.
- Duplicate-safe event identification.

Do not create unnecessary modules for logging, metrics, configuration or analytics.

---

# 5. DEVELOPMENT RULES — STRICT

These rules apply to every implementation task.

## Rule 1: Follow the development phases

Implementation must follow the phases in Section 8.

Do not begin a later phase until the previous phase meets its acceptance criteria.

For example:

- Do not implement DAG workflows before the job engine works.
- Do not implement saga compensation before workflow execution works.
- Do not introduce Kafka before the transactional outbox is ready.
- Do not implement tenant fairness before basic job claiming is correct.

## Rule 2: Inspect before modifying

Before changing any code:

1. Inspect the existing project structure.
2. Read the relevant source files.
3. Read `README.md`.
4. Read this `workflow.md`.
5. Read `status.md` if it exists.
6. Identify the existing implementation and its tests.
7. Determine the smallest correct change.

Never assume that a feature is missing without inspecting the repository.

Never replace existing working code simply because a different implementation is preferred.

## Rule 3: Do not generate the entire project at once

Implement one coherent feature at a time.

Each implementation task must include:

- Purpose.
- Design decision.
- Files affected.
- Implementation.
- Tests.
- Verification.
- Documentation updates when necessary.

Do not generate hundreds of lines of unrelated code in one step.

## Rule 4: Preserve modular boundaries

Business logic must not be coupled to REST controllers, database implementation details or thread management.

Use clear separation between:

- Domain.
- Application services.
- Infrastructure.
- API.

Avoid circular dependencies between modules.

The `job` module must not directly control worker thread execution.

The `execution` module must coordinate execution using defined application-level interfaces.

The `workflow` module must own workflow dependency and transition rules.

## Rule 5: Do not overengineer

Do not introduce:

- Unnecessary design patterns.
- Generic frameworks for hypothetical future requirements.
- Premature microservices.
- Unnecessary interfaces for every class.
- Multiple message brokers.
- Unnecessary caching.
- Unnecessary abstractions around simple operations.

Use interfaces when they provide meaningful separation, testability or replaceable infrastructure boundaries.

## Rule 6: Database correctness is mandatory

Every database operation involving execution state must be designed with concurrency and transaction boundaries in mind.

Do not assume that Java-level synchronization protects a shared PostgreSQL database across multiple application instances.

Use database-level concurrency control where required.

## Rule 7: Never claim exactly-once execution

The engine provides at-least-once execution.

A job can execute again if a worker completes an external side effect but crashes before recording successful completion.

Job handlers should be idempotent where possible.

Document this behavior clearly.

## Rule 8: Test failure scenarios

A successful execution test is insufficient.

Test:

- Concurrent workers.
- Application restart.
- Worker crash.
- Lease expiration.
- Stale worker updates.
- Retry exhaustion.
- Database transaction failures.
- Duplicate submissions.
- Duplicate event delivery.

## Rule 9: Keep documentation synchronized

When architecture, APIs, database schemas or implementation decisions change:

- Update the relevant documentation.
- Update `status.md`.
- Update this workflow only when the approved project specification itself changes.

Do not silently change the architecture.

## Rule 10: Report honestly

Never claim that a test passed unless it was actually executed.

Never claim that a feature is complete when it is only partially implemented.

Clearly distinguish:

- Implemented.
- Tested.
- Partially implemented.
- Planned.
- Blocked.

---

# 6. REQUIRED ENGINEERING STANDARDS

## 6.1 Java standards

- Use Java 21.
- Prefer clear, readable code.
- Use records for suitable immutable DTOs.
- Use enums for controlled state values.
- Use meaningful class and method names.
- Avoid excessively large service classes.
- Use constructor injection.
- Avoid field injection.
- Handle exceptions explicitly.
- Use appropriate logging levels.
- Avoid logging credentials or sensitive data.
- Avoid unmanaged thread creation.
- Manage executors through Spring lifecycle mechanisms.
- Ensure worker threads shut down gracefully.

## 6.2 Spring Boot standards

- Use Spring Boot dependency injection.
- Use configuration properties for configurable values.
- Avoid hardcoded environment-specific settings.
- Separate controllers from application services.
- Use Jakarta Validation for request validation.
- Use centralized exception handling.
- Use Spring transactions at appropriate application boundaries.
- Use Actuator for health endpoints.
- Avoid exposing internal implementation details through API responses.

## 6.3 Maven standards

- Keep dependencies minimal.
- Use Spring Boot dependency management.
- Avoid unnecessary version overrides.
- Use Maven profiles only when useful.
- Configure test execution properly.
- Keep builds reproducible.
- Do not add a dependency merely because it is popular.

## 6.4 Database standards

- Use Flyway for schema migrations.
- Never rely on Hibernate schema auto-update in production-oriented configuration.
- Use explicit database constraints.
- Add indexes based on query patterns.
- Use transactions intentionally.
- Keep transactions short.
- Avoid holding row locks while executing long-running jobs.
- Use UTC for persisted timestamps.
- Use appropriate timestamp types.
- Avoid storing authoritative job state only in memory.

## 6.5 API standards

- Use consistent REST resource naming.
- Use request and response DTOs.
- Validate all incoming data.
- Use meaningful HTTP status codes.
- Return consistent error responses.
- Support pagination for potentially large result sets.
- Never expose database entities directly.
- Document API contracts.
- Implement idempotent submission semantics.

---

# 7. CORE DOMAIN MODEL

The following entities describe the intended domain. Their exact fields and relationships must be finalized during the relevant implementation phase.

## 7.1 Job

Represents a durable unit of background work.

Conceptual fields:

- `id`
- `tenant_id`
- `job_type`
- `payload`
- `status`
- `priority`
- `created_at`
- `updated_at`
- `scheduled_at`
- `available_at`
- `attempt_count`
- `max_attempts`
- `idempotency_key`
- `lease_owner`
- `lease_expires_at`
- `heartbeat_at`
- `fencing_token`
- `last_error`

## 7.2 Job Attempt

Represents an individual execution attempt for a job.

Conceptual fields:

- `id`
- `job_id`
- `attempt_number`
- `worker_id`
- `status`
- `started_at`
- `finished_at`
- `error_details`
- `fencing_token`

A job may have multiple attempts.

Never overwrite previous attempt history.

## 7.3 Workflow

Represents an execution containing multiple dependent steps.

Conceptual fields:

- `id`
- `tenant_id`
- `workflow_type`
- `status`
- `definition`
- `created_at`
- `started_at`
- `completed_at`
- `updated_at`

## 7.4 Workflow Step

Represents one executable node inside a workflow.

Conceptual fields:

- `id`
- `workflow_id`
- `step_key`
- `job_id`
- `status`
- `step_type`
- `configuration`
- `created_at`
- `started_at`
- `completed_at`

## 7.5 Workflow Dependency

Represents a dependency relationship between workflow steps.

Conceptual fields:

- `id`
- `workflow_id`
- `parent_step_id`
- `child_step_id`
- `dependency_type`

The workflow graph must be acyclic.

## 7.6 Workflow Event

Represents an immutable record of an important workflow transition or execution event.

Conceptual fields:

- `id`
- `workflow_id`
- `step_id`
- `event_type`
- `event_data`
- `occurred_at`
- `sequence_number`

Events must not be modified to rewrite execution history.

## 7.7 Dead Letter

Represents a job that has permanently exhausted its allowed execution attempts or cannot proceed under the configured failure policy.

Conceptual fields:

- `id`
- `job_id`
- `failure_reason`
- `attempt_count`
- `created_at`
- `resolved_at`
- `resolution_status`

## 7.8 Outbox Event

Represents an event that has been committed to PostgreSQL but has not necessarily been published to Kafka.

Conceptual fields:

- `id`
- `aggregate_type`
- `aggregate_id`
- `event_type`
- `payload`
- `created_at`
- `published_at`
- `status`
- `attempt_count`

The actual schema must use appropriate constraints, indexes and foreign keys.

Do not blindly implement these conceptual fields without considering query patterns, state transitions and transaction boundaries.

---

# 8. IMPLEMENTATION ROADMAP

The project must be implemented in the following order.

---

# PHASE 0 — PROJECT FOUNDATION

**Goal:** Establish a clean, reproducible Spring Boot project.

### Scope

- [ ] Inspect existing repository.
- [ ] Confirm Java 21 configuration.
- [ ] Confirm Spring Boot configuration.
- [ ] Confirm Maven build.
- [ ] Establish package structure.
- [ ] Configure application properties.
- [ ] Configure environment variables.
- [ ] Configure PostgreSQL connectivity.
- [ ] Integrate Flyway.
- [ ] Configure basic logging.
- [ ] Add initial database migration.
- [ ] Create Docker configuration (`compose.yaml` and `Dockerfile`).
- [ ] Create basic health endpoint.
- [ ] Configure basic unit testing.

### Expected structure

```text
weftline/
|
├── src/
│   ├── main/
│   │   ├── java/com/weftline/
│   │   │   ├── WeftlineApplication.java
│   │   │   ├── api/
│   │   │   ├── job/
│   │   │   ├── workflow/
│   │   │   ├── execution/
│   │   │   ├── retry/
│   │   │   └── outbox/
│   │   |
│   │   └── resources/
│   │       ├── application.yml
│   │       └── db/migration/
│   |
│   └── test/
|
├── compose.yaml
├── Dockerfile
├── pom.xml
├── README.md
├── workflow.md
└── status.md
```

This is a suggested initial structure. Adjust it only when there is a clear reason.

### Acceptance criteria

- [ ] Maven build succeeds.
- [ ] Spring Boot application starts.
- [ ] PostgreSQL connection succeeds.
- [ ] Flyway migration executes.
- [ ] Application health endpoint responds.
- [ ] Configuration does not depend on hardcoded credentials.
- [ ] Basic automated test passes.

**Do not implement job execution yet.**

---

# PHASE 1 — DURABLE JOB ENGINE

**Goal:** Build the first functioning version of Weftline.

This is the most important foundational phase.

### 1. Job persistence

- [ ] Define the Job domain model.
- [ ] Create the initial jobs database table.
- [ ] Configure Flyway migration.
- [ ] Add required indexes and constraints.
- [ ] Implement job persistence.
- [ ] Implement job retrieval.
- [ ] Implement job submission service.
- [ ] Implement request and response DTOs.
- [ ] Add input validation.

### 2. Job submission API

Initial endpoint:

`POST /api/v1/jobs`

Responsibilities:

- Validate incoming requests.
- Generate or accept a supported idempotency key.
- Persist the job.
- Return a job identifier.
- Return the initial job state.

The API must never report successful submission before the required database transaction commits.

### 3. Basic job state machine

Initial states:

```text
PENDING
   |
   v
RUNNING
   |
   +----> SUCCEEDED
   |
   +----> FAILED
```

Additional states can be introduced in later phases.

All state transitions must be validated.

Invalid transitions must be rejected.

### 4. Atomic job claiming

Implement PostgreSQL-based concurrent claiming.

Required technique:

`SELECT ... FOR UPDATE SKIP LOCKED`

The claiming process must:

1. Start a short database transaction.
2. Select eligible pending jobs.
3. Lock selected rows.
4. Skip rows already locked by other claimers.
5. Update selected jobs to their claimed/running ownership state.
6. Commit the transaction.
7. Return the claimed jobs to the worker execution layer.

Important:

- Do not execute business logic while holding database row locks.
- Do not hold a transaction open for the duration of a job.
- Do not assume one application instance.
- Do not use Java `synchronized` as the only concurrency mechanism.

### 5. Worker pool

- [ ] Create a managed worker pool.
- [ ] Configure worker count.
- [ ] Implement job dispatching.
- [ ] Implement a job handler abstraction.
- [ ] Implement handler registration.
- [ ] Execute jobs outside the claim transaction.
- [ ] Record execution results.
- [ ] Handle execution exceptions.
- [ ] Implement graceful shutdown.

Workers must execute supported job types through an explicit handler mechanism.

Do not use arbitrary Java reflection to execute untrusted class names or payloads.

### 6. Initial job status API

`GET /api/v1/jobs/{jobId}`

Must return:

- Job identifier.
- Job type.
- Current status.
- Creation timestamp.
- Execution timestamps where applicable.
- Attempt count.
- Last error summary where appropriate.

### Phase 1 acceptance criteria

- [ ] A job can be submitted through REST.
- [ ] The job is persisted in PostgreSQL.
- [ ] A worker can claim and execute it.
- [ ] Successful execution changes the job state.
- [ ] Failed execution is recorded.
- [ ] Multiple workers can claim jobs concurrently.
- [ ] Two valid workers cannot claim the same job simultaneously.
- [ ] Restarting the application does not erase pending jobs.
- [ ] Tests run against PostgreSQL.
- [ ] API documentation is available.

**Phase 1 is the first usable version of Weftline. Do not proceed until these conditions pass.**

---

# PHASE 2 — EXECUTION RELIABILITY

**Goal:** Make job execution resilient to failures.

### 1. Execution attempts

- [ ] Create the job attempts table.
- [ ] Record every attempt.
- [ ] Track attempt number.
- [ ] Record worker identity.
- [ ] Record start and finish timestamps.
- [ ] Preserve failure information.
- [ ] Separate job state from attempt state.

### 2. Retry mechanism

- [ ] Define retry policy.
- [ ] Configure maximum attempts.
- [ ] Implement exponential backoff.
- [ ] Implement jitter.
- [ ] Calculate next eligible execution time.
- [ ] Prevent retries before the configured time.
- [ ] Handle permanent failures.
- [ ] Record retry decisions.

Example:

```text
Attempt 1 -> Failed
       |
       v
Wait for backoff
       |
       v
Attempt 2 -> Failed
       |
       v
Wait for backoff
       |
       v
Attempt 3 -> Succeeded
```

Retry delays must be configurable.

Avoid retry storms.

### 3. Dead-letter handling

- [ ] Create dead-letter table.
- [ ] Move permanently failed jobs into dead-letter handling.
- [ ] Preserve failure details.
- [ ] Preserve attempt history.
- [ ] Implement dead-letter retrieval.
- [ ] Define controlled reprocessing behavior.

### 4. Leases and heartbeats

Each executing job must have an identifiable owner and an expiring lease.

Implement:

- [ ] Worker identity.
- [ ] Lease ownership.
- [ ] Lease expiration.
- [ ] Heartbeat timestamps.
- [ ] Periodic heartbeat updates.
- [ ] Lease renewal.
- [ ] Lease expiration detection.

### 5. Expired-lease recovery

- [ ] Find jobs whose leases have expired.
- [ ] Prevent stale owners from continuing to commit results.
- [ ] Recover eligible jobs.
- [ ] Record lease expiration in attempt history.
- [ ] Make recovered jobs eligible for another attempt according to the failure policy.

### 6. Fencing tokens

Implement monotonically increasing fencing tokens.

Every new execution ownership generation must receive a newer token.

All state-changing worker operations must verify the token against the currently valid ownership generation.

Example:

```text
Worker A claims job
Fencing token = 1

Worker A stops heartbeating

Lease expires

Worker B recovers job
Fencing token = 2

Worker A attempts to save its old result
       |
       v
Database rejects stale token 1

Worker B saves its valid result
       |
       v
Database accepts token 2
```

A fencing token must be enforced, not merely stored.

### 7. Job cancellation

- [ ] Define cancellation rules.
- [ ] Support cancellation of pending jobs.
- [ ] Define behavior for running jobs.
- [ ] Support cooperative cancellation where possible.
- [ ] Prevent cancellation from silently overwriting completed jobs.
- [ ] Record cancellation history.

### Phase 2 acceptance criteria

- [ ] Failed jobs retry according to policy.
- [ ] Retry delays are respected.
- [ ] Exhausted jobs enter dead-letter handling.
- [ ] Workers renew leases.
- [ ] Expired leases are detected.
- [ ] Expired jobs can be recovered.
- [ ] Stale workers cannot overwrite newer execution results.
- [ ] Attempt history is preserved.
- [ ] Cancellation follows documented state transitions.

---

# PHASE 3 — CONCURRENCY AND FAILURE TESTING

**Goal:** Prove that the job engine behaves correctly under realistic failure conditions.

This phase must not be treated as optional.

### Required tools

- JUnit 5.
- Testcontainers.
- PostgreSQL container.
- Mockito where appropriate.
- Spring Boot integration testing.

### Required tests

#### Test 1: Concurrent job claiming

Run multiple independent claimers against PostgreSQL.

Verify:

- No two valid claimers receive the same job ownership.
- Claimed jobs are not lost.
- Claim transactions do not remain open during execution.

#### Test 2: Worker crash

1. Submit a job.
2. Let a worker claim it.
3. Simulate the worker stopping unexpectedly.
4. Wait for lease expiration.
5. Allow recovery.
6. Verify the job can be executed again.

#### Test 3: Stale worker

1. Worker A claims a job.
2. Worker A loses its lease.
3. Worker B recovers the job.
4. Worker B obtains a newer fencing token.
5. Worker A attempts a state update.
6. Verify the stale update is rejected.

#### Test 4: Retry exhaustion

Verify that a job exceeding its maximum attempts reaches the dead-letter state.

#### Test 5: Duplicate submission

Submit multiple requests with the same tenant-scoped idempotency key.

Verify that the system follows its documented idempotency policy and does not create duplicate logical jobs.

#### Test 6: Application restart

- Submit pending jobs.
- Restart the application.
- Verify pending jobs remain available.
- Verify execution can resume.

### Load and stress scenarios

- [ ] 100 concurrent claimers or clients.
- [ ] Large batches of pending jobs.
- [ ] Multiple worker threads.
- [ ] Simulated database connection interruptions.
- [ ] Worker termination during execution.
- [ ] Repeated lease expiration.
- [ ] Concurrent cancellation and execution attempts.

The number 100 is an initial test scenario, not a claim that the system supports a particular production scale.

### Phase 3 acceptance criteria

- [ ] Integration tests use real PostgreSQL.
- [ ] Concurrent claiming is verified.
- [ ] Worker crash recovery is verified.
- [ ] Stale fencing-token updates are rejected.
- [ ] Duplicate submission behavior is verified.
- [ ] Restart recovery is verified.
- [ ] Test results are documented.

Do not move to workflow orchestration while foundational execution correctness remains unverified.

---

# PHASE 4 — WORKFLOW ENGINE

**Goal:** Extend individual jobs into dependency-based workflow execution.

A workflow is a collection of steps connected through a directed acyclic graph.

Each executable workflow step is backed by a job execution or an equivalent execution record with the same reliability guarantees.

### 1. Workflow definitions

- [ ] Define workflow model.
- [ ] Define workflow step model.
- [ ] Define dependency model.
- [ ] Define workflow creation API.
- [ ] Persist workflow definitions.
- [ ] Persist workflow executions.
- [ ] Validate incoming definitions.

### 2. DAG validation

- [ ] Represent steps as graph nodes.
- [ ] Represent dependencies as directed edges.
- [ ] Detect cycles.
- [ ] Reject invalid dependencies.
- [ ] Reject duplicate step identifiers.
- [ ] Reject references to missing steps.
- [ ] Implement topological ordering.

A valid workflow must be a directed acyclic graph.

### 3. Dependency-based execution

A step becomes READY only when all required parent steps have reached the required successful state.

Implement:

- [ ] WAITING state.
- [ ] READY state.
- [ ] Dependency evaluation.
- [ ] Parent-step completion tracking.
- [ ] Child-step activation.
- [ ] Workflow completion detection.
- [ ] Workflow failure detection.
- [ ] Recovery after restart.

Do not run a dependent step simply because it appears later in a submitted JSON array.

### 4. Conditional execution

- [ ] Support conditional transitions.
- [ ] Evaluate conditions using explicitly supported rules.
- [ ] Define behavior when conditions are false.
- [ ] Record skipped steps.
- [ ] Prevent arbitrary code execution through workflow definitions.

### 5. Workflow APIs

Initial endpoints:

```text
POST   /api/v1/workflows
GET    /api/v1/workflows/{workflowId}
GET    /api/v1/workflows/{workflowId}/steps
GET    /api/v1/workflows/{workflowId}/events
POST   /api/v1/workflows/{workflowId}/cancel
```

Request and response structures must be documented.

### 6. Workflow state machine

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

RUNNING or eligible PENDING
   |
   v
CANCELLED
```

Define precise transition rules.

A workflow must not be marked COMPLETED until all required steps have completed successfully or have been explicitly skipped according to valid workflow rules.

### 7. Workflow recovery

- [ ] Persist workflow execution progress.
- [ ] Recover interrupted workflow evaluation.
- [ ] Identify completed steps.
- [ ] Identify waiting steps.
- [ ] Re-evaluate dependencies safely.
- [ ] Avoid duplicate step scheduling.
- [ ] Maintain consistency between workflow and job states.

### Phase 4 acceptance criteria

- [ ] A workflow can be submitted.
- [ ] DAG validation rejects cycles.
- [ ] Dependencies are respected.
- [ ] Independent steps can execute concurrently.
- [ ] Failed steps produce the documented workflow behavior.
- [ ] Conditional execution works.
- [ ] Workflow state is persisted.
- [ ] Workflow execution resumes after restart.

---

# PHASE 5 — SAGA COMPENSATION

**Goal:** Support corrective operations for workflows that partially complete.

Saga compensation is not a database rollback.

It executes explicitly defined business operations to compensate for previously completed steps.

### Scope

- [ ] Define compensation configuration for steps.
- [ ] Define compensation state transitions.
- [ ] Track completed forward steps.
- [ ] Trigger compensation when required.
- [ ] Execute compensations in reverse completion/dependency order.
- [ ] Track individual compensation attempts.
- [ ] Retry failed compensation operations.
- [ ] Recover interrupted compensation.
- [ ] Record compensation events.
- [ ] Handle compensation exhaustion.
- [ ] Define manual intervention behavior.

Example:

```text
Forward execution:

Step 1: Create Account
          |
Step 2: Allocate Resources
          |
Step 3: Configure Service
          |
Step 4: Activate Service
          |
          X Permanent failure


Compensation:

Compensate Step 3
          |
Compensate Step 2
          |
Compensate Step 1
```

Compensation order must respect workflow dependency semantics.

For parallel branches, define a deterministic and safe compensation policy.

Do not assume that reversing an arbitrary list of submitted steps is correct.

### Important requirements

- Compensation operations may fail.
- Compensation operations may be retried.
- Compensation operations must be idempotent where possible.
- The workflow must preserve its original failure information.
- A workflow must distinguish forward execution failure from compensation failure.

### Phase 5 acceptance criteria

- [ ] Compensation is triggered under configured conditions.
- [ ] Compensation order is correct.
- [ ] Compensation failures are recorded.
- [ ] Compensation retries work.
- [ ] Interrupted compensation can resume.
- [ ] Final workflow state accurately reflects compensation outcome.

---

# PHASE 6 — TENANT-FAIR SCHEDULING

**Goal:** Prevent a single tenant from monopolizing worker capacity.

Basic FIFO scheduling is insufficient for this requirement.

Implement tenant-aware job selection.

### Scope

- [ ] Add tenant identity to jobs.
- [ ] Define tenant scheduling policy.
- [ ] Implement round-robin scheduling.
- [ ] Introduce optional tenant weights.
- [ ] Prevent starvation.
- [ ] Maintain concurrency safety.
- [ ] Ensure fairness across multiple scheduler instances.
- [ ] Add scheduling metrics.

Example:

```text
Tenant A: 100,000 pending jobs
Tenant B: 100 pending jobs
Tenant C: 50 pending jobs

Worker capacity is shared.

Expected:
B and C should continue receiving execution
opportunities while A has a large backlog.
```

The scheduling policy must define what fairness means.

Do not promise strict equal throughput when tenant weights or job durations differ.

### Acceptance criteria

- [ ] One tenant cannot indefinitely starve other eligible tenants.
- [ ] Tenant weights influence scheduling as documented.
- [ ] Concurrent schedulers preserve ownership correctness.
- [ ] Fairness tests cover highly uneven workloads.

---

# PHASE 7 — WORKFLOW EVENT HISTORY AND OUTBOX

**Goal:** Maintain durable workflow history and publish workflow events reliably.

## 7.1 Append-only workflow event history

- [ ] Define workflow event types.
- [ ] Persist state transition events.
- [ ] Preserve chronological ordering per workflow.
- [ ] Assign stable event identifiers.
- [ ] Prevent modification of historical events.
- [ ] Expose workflow history API.
- [ ] Support execution debugging using recorded events.

Workflow events should capture meaningful transitions, not every internal log statement.

The event history is a durable record of what happened.

It is not automatically a complete event-sourced architecture.

PostgreSQL domain tables remain authoritative for current state.

## 7.2 Transactional outbox

- [ ] Create outbox table.
- [ ] Persist an outbox record in the same transaction as the corresponding domain state change.
- [ ] Implement outbox polling.
- [ ] Implement Kafka publisher.
- [ ] Track publication attempts.
- [ ] Track publication success.
- [ ] Retry publication failures.
- [ ] Handle duplicate delivery.
- [ ] Configure stable event identifiers.
- [ ] Test application failure between database commit and event publication.

## 7.3 Kafka event contract

Initial topic:

`workflow.events`

Example event:

```json
{
  "eventId": "unique-event-id",
  "eventType": "WORKFLOW_COMPLETED",
  "workflowId": "workflow-id",
  "tenantId": "tenant-id",
  "occurredAt": "2026-11-15T12:00:00Z",
  "data": {}
}
```

The example is illustrative. Final event schemas must be versioned and documented.

Consumers must be able to handle duplicate delivery.

Do not claim that Kafka publishing is exactly once simply because an outbox is used.

### Acceptance criteria

- [ ] Workflow history is persisted.
- [ ] Domain state and outbox records commit atomically.
- [ ] Outbox records survive application restarts.
- [ ] Kafka events are eventually published.
- [ ] Failed publication is retried.
- [ ] Duplicate delivery is safely handled.
- [ ] Event contracts are documented.

---

# PHASE 8 — OBSERVABILITY AND PRODUCTION READINESS

**Goal:** Make the system understandable and diagnosable under real operating conditions.

### Logging

- [ ] Structured logging where appropriate.
- [ ] Job identifiers in execution logs.
- [ ] Workflow identifiers in workflow logs.
- [ ] Attempt identifiers in worker logs.
- [ ] Worker identifiers in execution logs.
- [ ] Correlation identifiers.
- [ ] Appropriate log levels.
- [ ] No sensitive payload or credential leakage.

### Metrics

Use Micrometer.

Expose metrics such as:

- Jobs submitted.
- Jobs completed.
- Jobs failed.
- Jobs currently running.
- Pending job count.
- Retry count.
- Dead-letter count.
- Execution duration.
- Queue waiting duration.
- Expired lease count.
- Worker utilization.
- Workflow completion count.
- Workflow failure count.
- Compensation failure count.
- Outbox publication failures.

Avoid unbounded metric labels such as arbitrary job IDs or user-provided values.

### Health

Use Spring Boot Actuator.

Implement meaningful health indicators for:

- Application availability.
- PostgreSQL connectivity.
- Kafka connectivity after Kafka integration.

### Graceful shutdown

- [ ] Stop accepting new work during shutdown.
- [ ] Stop new job claiming.
- [ ] Allow in-flight work a configured shutdown period.
- [ ] Handle unfinished work safely.
- [ ] Release or expire ownership safely.
- [ ] Ensure jobs can recover after restart.

### Performance testing

- [ ] Measure job submission throughput.
- [ ] Measure job claiming throughput.
- [ ] Measure execution latency.
- [ ] Measure queue waiting time.
- [ ] Measure database contention.
- [ ] Measure worker utilization.
- [ ] Document benchmark environment.
- [ ] Record limitations.

Never publish benchmark results without describing the machine, configuration, workload and test method.

---

# 9. API DESIGN CONTRACT

Initial API resources should be designed consistently.

## Jobs

```text
POST   /api/v1/jobs
GET    /api/v1/jobs/{jobId}
GET    /api/v1/jobs
POST   /api/v1/jobs/{jobId}/cancel
```

## Workflows

```text
POST   /api/v1/workflows
GET    /api/v1/workflows/{workflowId}
GET    /api/v1/workflows/{workflowId}/steps
GET    /api/v1/workflows/{workflowId}/events
POST   /api/v1/workflows/{workflowId}/cancel
```

## Dead letters

```text
GET    /api/v1/dead-letters
GET    /api/v1/dead-letters/{deadLetterId}
POST   /api/v1/dead-letters/{deadLetterId}/reprocess
```

These endpoints are the intended API surface, not permission to implement all endpoints in Phase 1.

Only introduce endpoints when their underlying functionality exists.

### API requirements

- Use versioned endpoints.
- Use DTOs.
- Validate requests.
- Return consistent error structures.
- Use appropriate HTTP status codes.
- Support pagination for list endpoints.
- Document idempotency behavior.
- Avoid exposing internal database details.

---

# 10. DATABASE AND TRANSACTION RULES

These requirements are mandatory.

## 10.1 Transaction boundaries

Database transactions should protect state transitions and related writes.

Examples:

- Job submission and idempotency record creation.
- Job claiming and ownership assignment.
- Attempt creation and job transition.
- Workflow state transition and workflow event insertion.
- Domain state update and outbox record insertion.

Do not keep transactions open while performing long-running job handlers or remote network calls.

## 10.2 Concurrent claiming

Claiming must be implemented using database-level concurrency control.

Use a short transaction that locks and updates eligible rows.

`SKIP LOCKED` allows multiple claimers to skip jobs already locked by another transaction.

Do not confuse atomic claiming with exactly-once execution.

## 10.3 Fencing

Every execution ownership generation must have a monotonically increasing fencing token.

State-changing operations must verify that the supplied token matches the current valid token.

Use conditional updates or equivalent transactionally safe mechanisms.

## 10.4 Indexing

Create indexes based on actual access patterns.

Potential access patterns include:

- Pending jobs ordered by eligibility.
- Jobs belonging to a tenant.
- Jobs by status.
- Jobs by scheduled execution time.
- Attempts by job.
- Workflows by tenant and status.
- Workflow steps by workflow and status.
- Unpublished outbox records.
- Dead-letter records by creation time.

Do not create indexes without considering write overhead and query requirements.

## 10.5 Migrations

Every schema change must be represented through Flyway migrations.

Never edit an already-applied migration as a routine way to change an existing database schema.

Create a new migration.

Do not use Hibernate automatic schema updates as the migration strategy.

---

# 11. SECURITY REQUIREMENTS

The engine is initially expected to receive requests from a trusted API gateway or controlled client environment.

It does not implement the full API-key and JWT management system belonging to the separate gateway project.

However, the engine must not expose unauthenticated public administration or execution endpoints.

Requirements:

- [ ] Define trusted service authentication.
- [ ] Protect internal operational endpoints.
- [ ] Validate incoming payloads.
- [ ] Limit payload size.
- [ ] Avoid arbitrary code execution from job definitions.
- [ ] Avoid unsafe Java deserialization.
- [ ] Protect database credentials.
- [ ] Avoid logging secrets.
- [ ] Define tenant isolation boundaries.
- [ ] Prevent one tenant from reading another tenant's jobs or workflows.

Gateway-signed requests may be introduced during integration with Project B. Until then, use an explicit development authentication strategy and document its limitations.

---

# 12. TESTING REQUIREMENTS

Testing must exist at multiple levels.

| Test type | Purpose |
|---|---|
| Unit tests | Validate domain logic and state transitions |
| Repository tests | Validate persistence and query behavior |
| Integration tests | Validate Spring and PostgreSQL interactions |
| Concurrency tests | Validate atomic claiming and ownership |
| Failure tests | Validate recovery and retries |
| API tests | Validate HTTP contracts |
| Workflow tests | Validate DAG and compensation behavior |
| Performance tests | Measure throughput and latency |

### Testing rules

- Do not mock PostgreSQL when testing PostgreSQL locking behavior.
- Use Testcontainers for database integration tests.
- Use deterministic test data.
- Avoid flaky tests based on arbitrary sleeps where synchronization mechanisms can be used.
- Test transaction rollback behavior.
- Test concurrent operations using independent transactions.
- Ensure tests clean up their data.
- Never claim that a test passed without running it.

---

# 13. DEFINITION OF DONE

A feature is complete only when all applicable conditions are satisfied.

- [ ] Requirements are implemented.
- [ ] Architecture boundaries are respected.
- [ ] Input validation exists.
- [ ] Error handling exists.
- [ ] Database changes have Flyway migrations.
- [ ] Relevant unit tests exist.
- [ ] Relevant integration tests exist.
- [ ] Concurrency or failure tests exist where applicable.
- [ ] Maven build succeeds.
- [ ] Existing tests still pass.
- [ ] API documentation is updated.
- [ ] README or technical documentation is updated when needed.
- [ ] `status.md` is updated.
- [ ] No temporary debugging code remains.
- [ ] No credentials or secrets are committed.

A feature must not be marked complete just because the application compiles.

---

# 14. CODING AGENT EXECUTION PROTOCOL

Every coding agent working on Weftline must follow this protocol.

## Before implementation

1. Read `README.md`.
2. Read `workflow.md`.
3. Read `status.md`.
4. Inspect the repository.
5. Identify the active development phase.
6. Inspect existing implementation and tests.
7. Identify dependencies and architectural constraints.
8. Present a concise implementation plan when the task is substantial.

## During implementation

1. Work only within the active phase unless explicitly instructed otherwise.
2. Implement small, logically complete changes.
3. Preserve existing working behavior.
4. Avoid unrelated refactoring.
5. Add tests alongside implementation.
6. Run relevant tests.
7. Inspect generated database migrations.
8. Check transaction boundaries.
9. Check concurrency implications.
10. Document important decisions.

## After implementation

The agent must report:

### 1. Work completed

List the actual features implemented.

### 2. Files changed

List created, modified and deleted files.

### 3. Architectural decisions

Explain important implementation decisions.

### 4. Tests executed

List the commands executed and their actual results.

### 5. Remaining issues

Identify incomplete functionality, known limitations and technical debt.

### 6. Next recommended task

Identify the smallest logical next task within the current phase.

### 7. Status update

Update `status.md` with the actual project state.

## Strict prohibitions

The coding agent MUST NOT:

- Implement all phases in a single operation.
- Skip acceptance criteria.
- Replace PostgreSQL with an in-memory queue.
- Introduce Redis or RabbitMQ.
- Introduce Kafka before Phase 7.
- Introduce DAG execution before Phase 4.
- Introduce saga compensation before Phase 5.
- Introduce tenant fairness before Phase 6.
- Claim exactly-once execution.
- Hold database locks during long-running jobs.
- Trust expired worker ownership.
- Bypass fencing checks.
- Silently change state machines.
- Silently modify API contracts.
- Delete database volumes or existing data to fix migration problems.
- Rewrite Flyway migration history without an explicit recovery plan.
- Add dependencies without explaining their purpose.
- Mark untested functionality as complete.
- Create unnecessary files or modules.
- Modify unrelated parts of the repository.

If a requirement is ambiguous or conflicts with the existing architecture, explain the conflict and ask for clarification rather than silently inventing a new design.

---

# 15. STATUS TRACKING

`status.md` is the current implementation progress record.

It must contain:

- Current development phase.
- Overall completion status.
- Completed features.
- In-progress features.
- Pending features.
- Tests passed.
- Tests failing.
- Known issues.
- Last completed milestone.
- Next recommended task.

Update it after every meaningful implementation milestone.

Do not use it as a replacement for this document.

`workflow.md` defines what should be built.

`status.md` records what has actually been built.

`README.md` explains the project to users and contributors.

---

# 16. FINAL PROJECT COMPLETION CRITERIA

Weftline's initial full scope is complete when:

### Job engine

- [ ] Persistent job submission.
- [ ] Concurrent PostgreSQL job claiming.
- [ ] Managed worker execution.
- [ ] Job state transitions.
- [ ] Execution attempt history.
- [ ] Idempotent submission.
- [ ] Retries and backoff.
- [ ] Dead-letter handling.
- [ ] Leases and heartbeats.
- [ ] Expired-lease recovery.
- [ ] Fencing token enforcement.
- [ ] Cancellation behavior.

### Workflow engine

- [ ] Workflow definitions.
- [ ] DAG validation.
- [ ] Dependency-based execution.
- [ ] Conditional steps.
- [ ] Workflow state management.
- [ ] Restart recovery.
- [ ] Saga compensation.
- [ ] Compensation failure recovery.

### Scheduling

- [ ] Tenant-aware job scheduling.
- [ ] Round-robin or equivalent fair selection.
- [ ] Weighted tenant scheduling.
- [ ] Fairness tests.

### Event infrastructure

- [ ] Append-only workflow history.
- [ ] Transactional outbox.
- [ ] Kafka event publishing.
- [ ] Duplicate-safe event handling.

### Production engineering

- [ ] Unit testing.
- [ ] PostgreSQL integration testing.
- [ ] Concurrency testing.
- [ ] Failure injection testing.
- [ ] Testcontainers.
- [ ] Docker Compose (`compose.yaml`).
- [ ] Actuator health endpoints.
- [ ] Micrometer metrics.
- [ ] Structured logging.
- [ ] Graceful shutdown.
- [ ] Performance benchmarks.
- [ ] Complete technical documentation.

---

# 17. FINAL ENGINEERING PRINCIPLE

Weftline should be developed as a serious backend infrastructure system.

The quality of the project will be measured by the correctness of its behavior under concurrency, failures, restarts and partial execution.

A simple feature implemented correctly is more valuable than an advanced feature implemented unreliably.

**Development priority:**

```text
CORRECTNESS
     |
     v
DURABILITY
     |
     v
CONCURRENCY SAFETY
     |
     v
FAILURE RECOVERY
     |
     v
WORKFLOW ORCHESTRATION
     |
     v
FAIR SCHEDULING
     |
     v
EVENT INFRASTRUCTURE
     |
     v
OBSERVABILITY AND PERFORMANCE
```

Do not optimize prematurely.

Do not expand scope unnecessarily.

Do not sacrifice correctness to finish features faster.

**Build Weftline incrementally. Verify every guarantee. Document every important engineering decision.**