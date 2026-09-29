package com.careconnect.ehr.reconciliation.support;

import java.util.ArrayDeque;
import java.util.Deque;
import java.util.concurrent.locks.Lock;

/**
 * Test-only plumbing that makes the in-memory fakes behave like a real database for the one property
 * that actually matters here: a lock taken inside {@code lockOrCreate} is held for the rest of the
 * enclosing "transaction" and released only when that transaction ends — exactly what a real
 * {@code SELECT ... FOR UPDATE} inside a real Postgres transaction gives you for free. A real
 * JDBC/JPA-backed implementation doesn't need this class at all; it gets the same guarantee from the
 * database and the framework's transaction manager. This exists purely so the contract tests can
 * prove {@link com.careconnect.ehr.reconciliation.RecencyWinsIdentityReconciler}'s concurrency
 * behavior under real thread interleaving without standing up a real database.
 */
public final class FakeTransactionSupport {

    private static final ThreadLocal<Deque<Lock>> HELD_LOCKS = ThreadLocal.withInitial(ArrayDeque::new);

    private FakeTransactionSupport() {
    }

    /** Acquires {@code lock} and registers it for release when {@link #endTransaction()} runs on this thread. */
    public static void acquireForTransaction(Lock lock) {
        lock.lock();
        HELD_LOCKS.get().push(lock);
    }

    /** Releases every lock acquired via {@link #acquireForTransaction} on this thread, in reverse order. */
    public static void endTransaction() {
        Deque<Lock> locks = HELD_LOCKS.get();
        while (!locks.isEmpty()) {
            locks.pop().unlock();
        }
    }
}
