ALTER TABLE call_sessions
    ADD COLUMN IF NOT EXISTS termination_sentiment_at TIMESTAMPTZ NULL,
    ADD COLUMN IF NOT EXISTS termination_summary_at TIMESTAMPTZ NULL,
    ADD COLUMN IF NOT EXISTS termination_recording_at TIMESTAMPTZ NULL,
    ADD COLUMN IF NOT EXISTS termination_meeting_at TIMESTAMPTZ NULL;

COMMENT
ON COLUMN call_sessions.termination_sentiment_at IS
    'UTC instant when SENTIMENT termination step was claim-fenced complete';
COMMENT
ON COLUMN call_sessions.termination_summary_at IS
    'UTC instant when SUMMARY termination step was claim-fenced complete';
COMMENT
ON COLUMN call_sessions.termination_recording_at IS
    'UTC instant when RECORDING termination step was claim-fenced complete';
COMMENT
ON COLUMN call_sessions.termination_meeting_at IS
    'UTC instant when MEETING termination step was claim-fenced complete';
