CREATE TABLE ledger_failure_probe
(
    id INTEGER PRIMARY KEY
);
INSERT INTO table_that_does_not_exist (id)
VALUES (1);
