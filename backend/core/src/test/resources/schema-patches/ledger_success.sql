CREATE TABLE IF NOT EXISTS ledger_probe
(
    id
    INTEGER
    PRIMARY
    KEY,
    value_text
    VARCHAR
(
    40
) NOT NULL
    );
INSERT INTO ledger_probe (id, value_text)
VALUES (1, 'applied');
