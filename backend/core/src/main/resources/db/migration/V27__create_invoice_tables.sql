BEGIN;

-- =========================
-- DROP existing objects (order matters)
-- =========================
DROP TABLE IF EXISTS invoice_recommended_actions CASCADE;
DROP TABLE IF EXISTS invoice_history_entries CASCADE;
DROP TABLE IF EXISTS invoice_service_lines CASCADE;
DROP TABLE IF EXISTS invoices CASCADE;

-- =========================
-- CREATE tables
-- =========================
CREATE TABLE invoices (
                          id                      varchar(64) PRIMARY KEY,
                          invoice_number          varchar(64) NOT NULL DEFAULT '',

    -- provider snapshot
                          provider_name           varchar(255) NOT NULL DEFAULT '',
                          provider_address        varchar(512) NOT NULL DEFAULT '',
                          provider_phone          varchar(64)  NOT NULL DEFAULT '',
                          provider_email          varchar(255),

    -- patient snapshot
                          patient_name            varchar(255) NOT NULL DEFAULT '',
                          patient_address         varchar(512),
                          patient_account_no      varchar(128),
                          patient_billing_address varchar(512),

    -- dates
                          statement_date          timestamptz NOT NULL,
                          due_date                timestamptz NOT NULL,
                          paid_date               timestamptz,

    -- status and flags
                          payment_status          varchar(32) NOT NULL,
                          billed_to_insurance     boolean NOT NULL DEFAULT false,

    -- amounts
                          total_charges           numeric(18,2),
                          total_adjustments       numeric(18,2),
                          total_total             numeric(18,2),
                          amount_due              numeric(18,2),

    -- payment references
                          payment_link            varchar(1024),
                          qr_code_url             varchar(1024),
                          payment_notes           text,

    -- supported methods stored as CSV (e.g., 'card,ach,check')
                          supported_methods       varchar(1024),

    -- check payable snapshot
                          check_name              varchar(255),
                          check_address           varchar(512),
                          check_reference         varchar(255),

    -- ai summary
                          ai_summary              text,

    -- audit and doc link
                          created_by              varchar(255),
                          updated_by              varchar(255),
                          document_link           varchar(1024),

                          created_at              timestamptz NOT NULL,
                          updated_at              timestamptz NOT NULL
);

CREATE TABLE invoice_service_lines (
                                       id                      bigserial PRIMARY KEY,
                                       invoice_id              varchar(64) NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
                                       description             varchar(1024),
                                       service_code            varchar(128),
                                       service_date            timestamptz,
                                       charge                  numeric(18,2),
                                       patient_balance         numeric(18,2),
                                       insurance_adjustments   numeric(18,2)
);

CREATE TABLE invoice_history_entries (
                                         id                      bigserial PRIMARY KEY,
                                         invoice_id              varchar(64) NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
                                         version                 int NOT NULL,
                                         changes                 text NOT NULL,
                                         user_id                 varchar(128) NOT NULL,
                                         action                  varchar(128) NOT NULL,
                                         details                 text NOT NULL,
                                         timestamp               timestamptz NOT NULL
);

CREATE TABLE invoice_recommended_actions (
                                             id                      bigserial PRIMARY KEY,
                                             invoice_id              varchar(64) NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
                                             action_text             varchar(512) NOT NULL
);

-- =========================
-- INDEXES
-- =========================
CREATE INDEX idx_invoices_due_date            ON invoices(due_date);
CREATE INDEX idx_invoices_statement_date      ON invoices(statement_date);
CREATE INDEX idx_invoices_payment_status      ON invoices(payment_status);
CREATE INDEX idx_invoices_amount_due          ON invoices(amount_due);
CREATE INDEX idx_invoices_provider_name       ON invoices(provider_name);
CREATE INDEX idx_invoices_patient_name        ON invoices(patient_name);

CREATE INDEX idx_service_lines_invoice_id     ON invoice_service_lines(invoice_id);
CREATE INDEX idx_history_invoice_id           ON invoice_history_entries(invoice_id);
CREATE INDEX idx_actions_invoice_id           ON invoice_recommended_actions(invoice_id);

-- Optional unique invoice number
 CREATE UNIQUE INDEX uq_invoices_invoice_number ON invoices(invoice_number);

CREATE TABLE IF NOT EXISTS invoice_payments (
                                                id                  VARCHAR(36) PRIMARY KEY,
    invoice_id          VARCHAR(36) NOT NULL,
    confirmation_number VARCHAR(100),
    payment_date        TIMESTAMP WITH TIME ZONE NOT NULL,
                                      method_key          VARCHAR(40) NOT NULL,
    amount_paid         NUMERIC(12,2) NOT NULL,
    plan_enabled        BOOLEAN NOT NULL DEFAULT FALSE,
    plan_months         INT,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_by          VARCHAR(100),

    CONSTRAINT fk_invoice_payments_invoice
    FOREIGN KEY (invoice_id) REFERENCES invoices(id)
                                  ON DELETE CASCADE
    );

CREATE INDEX IF NOT EXISTS idx_invoice_payments_invoice ON invoice_payments(invoice_id);
CREATE INDEX IF NOT EXISTS idx_invoice_payments_date ON invoice_payments(payment_date);