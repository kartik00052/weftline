package com.weftline.workflow.domain;

public enum WorkflowStatus {
    PENDING, RUNNING, COMPLETED, FAILED, COMPENSATING, COMPENSATED, CANCELLED
}