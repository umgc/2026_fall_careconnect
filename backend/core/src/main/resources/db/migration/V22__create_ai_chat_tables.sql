-- V22__create_ai_chat_tables.sql

-- Create patient_ai_config table
CREATE TABLE patient_ai_config (
    id BIGSERIAL PRIMARY KEY,
    patient_id BIGINT NOT NULL,
    ai_provider VARCHAR(20) NOT NULL CHECK (ai_provider IN ('OPENAI', 'DEEPSEEK')),
    openai_model VARCHAR(100),
    deepseek_model VARCHAR(100),
    max_tokens INTEGER NOT NULL DEFAULT 1000 CHECK (max_tokens >= 100 AND max_tokens <= 8000),
    temperature DECIMAL(3,2) NOT NULL DEFAULT 0.7 CHECK (temperature >= 0.0 AND temperature <= 2.0),
    conversation_history_limit INTEGER NOT NULL DEFAULT 20 CHECK (conversation_history_limit >= 5 AND conversation_history_limit <= 100),
    include_vitals_by_default BOOLEAN NOT NULL DEFAULT true,
    include_medications_by_default BOOLEAN NOT NULL DEFAULT true,
    include_notes_by_default BOOLEAN NOT NULL DEFAULT true,
    include_mood_pain_logs_by_default BOOLEAN NOT NULL DEFAULT true,
    include_allergies_by_default BOOLEAN NOT NULL DEFAULT true,
    is_active BOOLEAN NOT NULL DEFAULT true,
    system_prompt TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for patient_ai_config
CREATE INDEX idx_patient_ai_config_patient_id ON patient_ai_config(patient_id);
CREATE INDEX idx_patient_ai_config_active ON patient_ai_config(patient_id, is_active);

-- Create chat_conversations table
CREATE TABLE chat_conversations (
    id BIGSERIAL PRIMARY KEY,
    conversation_id VARCHAR(36) UNIQUE NOT NULL,
    patient_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    chat_type VARCHAR(50) NOT NULL DEFAULT 'GENERAL_SUPPORT' CHECK (chat_type IN ('MEDICAL_CONSULTATION', 'GENERAL_SUPPORT', 'MEDICATION_INQUIRY', 'MOOD_PAIN_SUPPORT', 'EMERGENCY_GUIDANCE', 'LIFESTYLE_ADVICE')),
    title VARCHAR(200),
    ai_provider_used VARCHAR(20) CHECK (ai_provider_used IN ('OPENAI', 'DEEPSEEK')),
    ai_model_used VARCHAR(100),
    total_tokens_used INTEGER DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for chat_conversations
CREATE INDEX idx_chat_conversations_conversation_id ON chat_conversations(conversation_id);
CREATE INDEX idx_chat_conversations_patient_id ON chat_conversations(patient_id);
CREATE INDEX idx_chat_conversations_user_id ON chat_conversations(user_id);
CREATE INDEX idx_chat_conversations_patient_active ON chat_conversations(patient_id, is_active);
CREATE INDEX idx_chat_conversations_updated_at ON chat_conversations(updated_at DESC);

-- Create chat_messages table
CREATE TABLE chat_messages (
    id BIGSERIAL PRIMARY KEY,
    conversation_id BIGINT NOT NULL REFERENCES chat_conversations(id) ON DELETE CASCADE,
    message_type VARCHAR(20) NOT NULL CHECK (message_type IN ('USER', 'ASSISTANT', 'SYSTEM')),
    content TEXT NOT NULL,
    tokens_used INTEGER,
    processing_time_ms BIGINT,
    temperature_used DECIMAL(3,2),
    context_included TEXT,
    ai_model_used VARCHAR(100),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for chat_messages
CREATE INDEX idx_chat_messages_conversation_id ON chat_messages(conversation_id);
CREATE INDEX idx_chat_messages_created_at ON chat_messages(conversation_id, created_at);

-- Add foreign key constraints (if tables exist)
-- Note: These might need to be adjusted based on your existing schema
-- ALTER TABLE patient_ai_config ADD CONSTRAINT fk_patient_ai_config_patient FOREIGN KEY (patient_id) REFERENCES patients(id);
-- ALTER TABLE chat_conversations ADD CONSTRAINT fk_chat_conversations_patient FOREIGN KEY (patient_id) REFERENCES patients(id);
-- ALTER TABLE chat_conversations ADD CONSTRAINT fk_chat_conversations_user FOREIGN KEY (user_id) REFERENCES users(id);

-- Create update triggers for updated_at columns
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_patient_ai_config_updated_at 
    BEFORE UPDATE ON patient_ai_config 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_chat_conversations_updated_at 
    BEFORE UPDATE ON chat_conversations 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
