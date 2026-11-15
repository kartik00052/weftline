CREATE TABLE jobs (
    id               UUID         PRIMARY KEY,
    tenant_id        VARCHAR(64)  NOT NULL,
    type             VARCHAR(128) NOT NULL,
    payload          JSONB        NOT NULL DEFAULT '{}'::jsonb,
    status           VARCHAR(32)  NOT NULL,
    priority         INT          NOT NULL DEFAULT 5,
    run_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    attempt_count    INT          NOT NULL DEFAULT 0,
    max_attempts     INT          NOT NULL DEFAULT 3,
    lease_owner      VARCHAR(128),
    lease_expires_at TIMESTAMPTZ,
    heartbeat_at     TIMESTAMPTZ,
    fencing_token    BIGINT       NOT NULL DEFAULT 0,
    idempotency_key  VARCHAR(128),
    last_error       TEXT,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT chk_jobs_status
        CHECK (status IN ('PENDING','RUNNING','SUCCEEDED','FAILED','DEAD_LETTERED','CANCELLED')),
    CONSTRAINT uq_jobs_tenant_idempotency UNIQUE (tenant_id, idempotency_key)
);

CREATE INDEX idx_jobs_claimable ON jobs (priority, run_at) WHERE status = 'PENDING';
CREATE INDEX idx_jobs_expired_leases ON jobs (lease_expires_at) WHERE status = 'RUNNING';