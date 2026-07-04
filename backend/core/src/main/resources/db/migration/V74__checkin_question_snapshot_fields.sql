ALTER TABLE check_in_questions
    ADD COLUMN IF NOT EXISTS prompt_snapshot TEXT;

ALTER TABLE check_in_questions
    ADD COLUMN IF NOT EXISTS type_snapshot VARCHAR(32);

UPDATE check_in_questions ciq
SET
    prompt_snapshot = q.prompt,
    type_snapshot = q.type
FROM questions q
WHERE q.id = ciq.question_id
  AND (ciq.prompt_snapshot IS NULL OR ciq.type_snapshot IS NULL);

ALTER TABLE check_in_questions
    ALTER COLUMN prompt_snapshot SET NOT NULL;

ALTER TABLE check_in_questions
    ALTER COLUMN type_snapshot SET NOT NULL;
