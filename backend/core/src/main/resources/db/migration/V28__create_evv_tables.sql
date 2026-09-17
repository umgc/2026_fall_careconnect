CREATE TABLE evv_participant (
                                 id BIGSERIAL PRIMARY KEY,
                                 patient_name VARCHAR(200) NOT NULL,
                                 ma_number VARCHAR(64) NOT NULL UNIQUE,
                                 created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
                                 created_by VARCHAR(255) NOT NULL
);

CREATE TABLE evv_record (
                            id BIGSERIAL PRIMARY KEY,
                            participant_id BIGINT NOT NULL REFERENCES evv_participant(id),
                            service_type VARCHAR(128) NOT NULL,
                            individual_name VARCHAR(200) NOT NULL,
                            caregiver_id BIGINT NOT NULL REFERENCES users(id),
                            date_of_service DATE NOT NULL,
                            time_in TIMESTAMP WITH TIME ZONE NOT NULL,
                            time_out TIMESTAMP WITH TIME ZONE NOT NULL,
                            location_lat DOUBLE PRECISION,
                            location_lng DOUBLE PRECISION,
                            location_source VARCHAR(32),
                            status VARCHAR(32) NOT NULL DEFAULT 'DRAFT',
                            state_code VARCHAR(2) NOT NULL,
                            device_info JSONB,
                            created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
                            updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Immutable audit events (append-only)
CREATE TABLE evv_audit_event (
                                 id BIGSERIAL PRIMARY KEY,
                                 evv_record_id BIGINT NOT NULL REFERENCES evv_record(id),
                                 event_type VARCHAR(64) NOT NULL,
                                 event_time TIMESTAMP WITH TIME ZONE DEFAULT now(),
                                 actor_user_id BIGINT NOT NULL REFERENCES users(id),
                                 device_info JSONB,
                                 details JSONB
);

-- Outbox for state-specific integrations (transactional outbox)
CREATE TABLE evv_outbox (
                            id BIGSERIAL PRIMARY KEY,
                            evv_record_id BIGINT NOT NULL REFERENCES evv_record(id),
                            destination VARCHAR(64) NOT NULL,
                            payload JSONB NOT NULL,
                            status VARCHAR(32) NOT NULL DEFAULT 'READY',
                            attempts INT NOT NULL DEFAULT 0,
                            last_error TEXT,
                            created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
                            updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE INDEX idx_evv_record_state ON evv_record(state_code);
CREATE INDEX idx_outbox_status ON evv_outbox(status);
