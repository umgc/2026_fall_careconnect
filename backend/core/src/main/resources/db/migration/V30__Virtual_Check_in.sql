/* ---- VIRTUAL CHECK-IN: TABLES ---- */

CREATE TABLE IF NOT EXISTS questions (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  prompt     TEXT        NOT NULL,
  type       VARCHAR(32) NOT NULL,     -- TEXT | YES_NO | TRUE_FALSE | NUMBER
  required   BOOLEAN     NOT NULL DEFAULT FALSE,
  active     BOOLEAN     NOT NULL DEFAULT TRUE,
  ordinal    INTEGER     NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_questions_type
    CHECK (type IN ('TEXT','YES_NO','TRUE_FALSE','NUMBER'))
);

-- Fast lookups for “active” lists and ordered UIs
CREATE INDEX IF NOT EXISTS idx_questions_active_ordinal
  ON questions(active, ordinal);

/* Optionally avoid exact duplicates for (prompt, type)
   (Uncomment if you want to prevent repeated question rows)
-- ALTER TABLE questions
--   ADD CONSTRAINT uq_questions_prompt_type UNIQUE (prompt, type);
*/


/* ---------- CHECK-INS ---------- */
CREATE TABLE IF NOT EXISTS check_ins (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  patient_id  BIGINT      NOT NULL REFERENCES patient(id) ON UPDATE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  submitted_at TIMESTAMPTZ
);

-- Patient timeline queries
CREATE INDEX IF NOT EXISTS idx_check_ins_patient_created
  ON check_ins(patient_id, created_at DESC);


/* ---------- CHECK-IN ↔ QUESTIONS (snapshot at time of check-in) ----------
   Stores the *required* + *ordinal* as they were when the check-in was created.
   If you also need to lock down the original question type or prompt for auditing,
   add columns here (e.g., type_snapshot, prompt_snapshot).
*/
CREATE TABLE IF NOT EXISTS check_in_questions (
  check_in_id BIGINT NOT NULL REFERENCES check_ins(id)    ON DELETE CASCADE ON UPDATE CASCADE,
  question_id BIGINT NOT NULL REFERENCES questions(id)    ON UPDATE CASCADE,
  required    BOOLEAN NOT NULL,
  ordinal     INTEGER NOT NULL,
  PRIMARY KEY (check_in_id, question_id)
);

CREATE INDEX IF NOT EXISTS idx_check_in_questions_check_in
  ON check_in_questions(check_in_id);


/* ---------- ANSWERS (one per question per check-in) ----------
   Exactly one of value_text/value_boolean/value_number must be non-NULL.
   NOTE: This enforces “one value” but not “value type matches question.type”.
         If you need strict type enforcement, either:
           1) add `type_snapshot VARCHAR(32) NOT NULL` to check_in_questions and
              enforce with a trigger/check, or
           2) move type to answers and enforce directly here.
*/
CREATE TABLE IF NOT EXISTS answers (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  check_in_id  BIGINT NOT NULL REFERENCES check_ins(id)         ON DELETE CASCADE ON UPDATE CASCADE,
  question_id  BIGINT NOT NULL REFERENCES questions(id)         ON UPDATE CASCADE,

  value_text    TEXT,
  value_boolean BOOLEAN,
  value_number  NUMERIC(12,2),

  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- exactly one value column must be provided
  CONSTRAINT chk_answers_single_value CHECK (
    (CASE WHEN value_text    IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN value_boolean IS NOT NULL THEN 1 ELSE 0 END) +
    (CASE WHEN value_number  IS NOT NULL THEN 1 ELSE 0 END)
    = 1
  ),

  -- only one answer per (check_in, question)
  CONSTRAINT uq_answers_checkin_question UNIQUE (check_in_id, question_id),

  -- ensure (check_in_id, question_id) pair actually exists in the snapshot table
  CONSTRAINT fk_answers_selected_question
    FOREIGN KEY (check_in_id, question_id)
    REFERENCES check_in_questions(check_in_id, question_id)
    ON DELETE CASCADE ON UPDATE CASCADE
);

-- Speed up common answer queries by check-in
CREATE INDEX IF NOT EXISTS idx_answers_check_in
  ON answers(check_in_id);
