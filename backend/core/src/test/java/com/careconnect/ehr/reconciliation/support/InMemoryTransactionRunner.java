package com.careconnect.ehr.reconciliation.support;

import com.careconnect.ehr.reconciliation.TransactionRunner;

public final class InMemoryTransactionRunner implements TransactionRunner {
    @Override
    public void runInTransaction(Runnable work) {
        try {
            work.run();
        } finally {
            FakeTransactionSupport.endTransaction();
        }
    }
}
