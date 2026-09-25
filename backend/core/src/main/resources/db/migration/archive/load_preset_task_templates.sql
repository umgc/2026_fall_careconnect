-- First, you'll need to create the templates table (not included in your original schema):
CREATE TABLE templates (
                           id BIGSERIAL PRIMARY KEY,
                           name VARCHAR(255),
                           description TEXT,
                           frequency VARCHAR(20),
                           task_interval INT,
                           do_count INT,
                           days_of_week VARCHAR(20),
                           time_of_day TIME,
                           icon INT,
                           notifications TEXT
);

-- Insert statements for PostgreSQL:
INSERT INTO templates (name, description, frequency, task_interval, do_count, days_of_week, time_of_day, icon, notifications)
VALUES('Medication', 'Medication schedules and dosages.', 'DAILY', -1, -1, null, '08:00', 58329, null);

INSERT INTO templates (name, description, frequency, task_interval, do_count, days_of_week, time_of_day, icon, notifications)
VALUES('Meals', 'Meal plans and nutritional information.', 'DAILY', -1, -1, null, '08:00', 57946, null);

INSERT INTO templates (name, description, frequency, task_interval, do_count, days_of_week, time_of_day, icon, notifications)
VALUES('Daily Walk', 'Managing daily walk schedules and tracking.', 'DAILY', -1, -1, null, '10:00', 57825, null);

INSERT INTO templates (name, description, frequency, task_interval, do_count, days_of_week, time_of_day, icon, notifications)
VALUES('Sleep', 'Manage sleep schedules', 'DAILY', -1, -1, null, '20:30', 57563, null);

INSERT INTO templates (name, description, frequency, task_interval, do_count, days_of_week, time_of_day, icon, notifications)
VALUES('Bathing', 'Manage bathing schedules and assistance.', 'DAILY', -1, -1, null, '08:00', 57551, null);

-- Patient insert (uncommented and corrected):
-- Note: You'll need to ensure user_id 10 exists in the users table first
INSERT INTO patient (first_name, last_name, email, phone, dob, user_id, relationship)
VALUES('Sandy', 'Test', 'test@test.com', '44344444444', '1990-09-01', 10, 'Patient-test');



-- "id": 1,
--         "firstName": "Sandy",
--         "lastName": "Test",
--         "email": "test@test.com",
--         "phone": "4434444444",
--         "dob": "01/09/1990",
--         "address": {
--             "line1": "Here",
--             "line2": "tets",
--             "city": "test",
--             "state": "te",
--             "zip": "22222"
--         },
--         "user": {
--             "id": 5,
--             "name": null,
--             "email": "test@test.com",
--             "password": "$2a$10$/GSLSsYyWRq4XCm8uCpAaeaLEMbhqdX3QMWoFeDl.Vlu9R1.EH1vC",
--             "passwordHash": "$2a$10$/GSLSsYyWRq4XCm8uCpAaeaLEMbhqdX3QMWoFeDl.Vlu9R1.EH1vC",
--             "role": "PATIENT",
--             "isVerified": false,
--             "verificationToken": "2fe84312-9aa0-475d-a685-3198fe162637",
--             "createdAt": "2025-07-25T23:45:20.000+00:00",
--             "lastLogin": null,
--             "profileImageUrl": null,
--             "status": "ACTIVE",
--             "active": true
--         },
--         "relationship": "Patient-test"