-- EVV Location Enhancements: federal compliance fields
-- Creates evv_record_location if missing (JPA-only installs), then adds compliance columns.

CREATE TABLE IF NOT EXISTS evv_record_location
(
    id
    UUID
    PRIMARY
    KEY
    DEFAULT
    gen_random_uuid
(
),
    evv_record_id BIGINT NOT NULL REFERENCES evv_record
(
    id
),
    role VARCHAR
(
    20
) NOT NULL,
    type VARCHAR
(
    20
) NOT NULL,
    latitude NUMERIC
(
    9,
    6
),
    longitude NUMERIC
(
    9,
    6
),
    accuracy_m NUMERIC
(
    6,
    2
),
    address_snapshot_json JSONB,
    no_gps_reason VARCHAR
(
    50
),
    manual_address VARCHAR
(
    500
),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now
(
)
    );

CREATE INDEX IF NOT EXISTS idx_evv_record_location_record_role
    ON evv_record_location (evv_record_id, role);

-- Add no_gps_reason column - stores why GPS could not be captured (federal EVV requirement)
ALTER TABLE evv_record_location
    ADD COLUMN IF NOT EXISTS no_gps_reason VARCHAR (50);

-- Add manual_address column - free-form address for MANUAL location type (community/facility visits)
ALTER TABLE evv_record_location
    ADD COLUMN IF NOT EXISTS manual_address VARCHAR (500);

-- Add caregiver_name snapshot to evv_record for immutable audit trail
ALTER TABLE evv_record
    ADD COLUMN IF NOT EXISTS caregiver_name VARCHAR (255);

-- Comments for documentation
COMMENT
ON COLUMN evv_record_location.no_gps_reason IS
    'Reason GPS location could not be captured; required when type != GPS per federal EVV regulations';
COMMENT
ON COLUMN evv_record_location.manual_address IS
    'Manually entered address for MANUAL location type (e.g. community or facility visits)';
COMMENT
ON COLUMN evv_record.caregiver_name IS
    'Snapshot of caregiver full name at time of visit; provides immutable audit trail independent of user record changes';
