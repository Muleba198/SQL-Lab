DROP TABLE IF EXISTS reservations;
DROP TABLE IF EXISTS lab_sessions;
DROP PROCEDURE IF EXISTS reserve_workstations(INT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS cancel_reservation(INT);

-- ---------------------------------------------------------------------
-- STEP 1: Create tables and add at least three sessions
-- ---------------------------------------------------------------------
CREATE TABLE lab_sessions (
    session_id              SERIAL PRIMARY KEY,
    session_name            VARCHAR(60) NOT NULL,
    available_workstations  INT NOT NULL CHECK (available_workstations >= 0)
);

CREATE TABLE reservations (
    reservation_id   SERIAL PRIMARY KEY,
    session_id       INT NOT NULL REFERENCES lab_sessions(session_id),
    lecturer         VARCHAR(60) NOT NULL,
    workstations     INT NOT NULL CHECK (workstations > 0),
    status           VARCHAR(20) NOT NULL DEFAULT 'RESERVED'
);

INSERT INTO lab_sessions (session_name, available_workstations) VALUES
    ('Monday 08:00 - Programming Lab', 30),
    ('Tuesday 10:00 - Networking Lab', 5),
    ('Wednesday 14:00 - Database Lab', 0);

SELECT * FROM lab_sessions ORDER BY session_id;

-- ---------------------------------------------------------------------
-- STEP 2: IF / ELSIF / ELSE - full, nearly full or enough workstations
-- ---------------------------------------------------------------------
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT session_name, available_workstations FROM lab_sessions ORDER BY session_id LOOP
        IF rec.available_workstations = 0 THEN
            RAISE NOTICE '% : FULL (% workstations)', rec.session_name, rec.available_workstations;
        ELSIF rec.available_workstations <= 5 THEN
            RAISE NOTICE '% : NEARLY FULL (% workstations)', rec.session_name, rec.available_workstations;
        ELSE
            RAISE NOTICE '% : ENOUGH WORKSTATIONS (% workstations)', rec.session_name, rec.available_workstations;
        END IF;
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- STEP 3: WHILE (preparation reminders) and numeric FOR (checks)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    counter INT := 1;
BEGIN
    WHILE counter <= 3 LOOP
        RAISE NOTICE 'Session preparation reminder %', counter;
        counter := counter + 1;
    END LOOP;

    FOR chk IN 1..3 LOOP
        RAISE NOTICE 'Workstation check %', chk;
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- STEP 4: reserve_workstations procedure
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE reserve_workstations(
    p_session_id INT,
    p_lecturer   VARCHAR,
    p_quantity   INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid number of workstations: % (must be greater than zero)', p_quantity;
    END IF;

    SELECT available_workstations INTO v_available
    FROM lab_sessions
    WHERE session_id = p_session_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session % does not exist', p_session_id;
    END IF;

    IF v_available >= p_quantity THEN
        UPDATE lab_sessions
        SET available_workstations = available_workstations - p_quantity
        WHERE session_id = p_session_id;

        INSERT INTO reservations (session_id, lecturer, workstations, status)
        VALUES (p_session_id, p_lecturer, p_quantity, 'RESERVED');

        RAISE NOTICE 'Reservation recorded: % reserved % workstation(s) in session %',
                     p_lecturer, p_quantity, p_session_id;
    ELSE
        RAISE NOTICE 'Reservation REJECTED: % requested % workstations but only % available',
                     p_lecturer, p_quantity, v_available;
    END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- STEP 5: Two valid reservations and one exceeding capacity
-- ---------------------------------------------------------------------
CALL reserve_workstations(1, 'Dr. Banda', 10);    -- valid (30 -> 20)
CALL reserve_workstations(2, 'Mr. Phiri', 2);     -- valid (5 -> 3)
CALL reserve_workstations(2, 'Ms. Mwansa', 10);   -- exceeds capacity (only 3 left)

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- ---------------------------------------------------------------------
-- STEP 6: cancel_reservation procedure (second call must not release again)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE cancel_reservation(p_reservation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_session_id INT;
    v_quantity   INT;
    v_status     VARCHAR(20);
BEGIN
    SELECT session_id, workstations, status
    INTO v_session_id, v_quantity, v_status
    FROM reservations
    WHERE reservation_id = p_reservation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Reservation % does not exist', p_reservation_id;
    ELSIF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Reservation % is already cancelled - workstations NOT released again', p_reservation_id;
    ELSE
        UPDATE reservations SET status = 'CANCELLED' WHERE reservation_id = p_reservation_id;
        UPDATE lab_sessions
        SET available_workstations = available_workstations + v_quantity
        WHERE session_id = v_session_id;
        RAISE NOTICE 'Reservation % cancelled - % workstation(s) released', p_reservation_id, v_quantity;
    END IF;
END;
$$;

CALL cancel_reservation(1);   -- first call: releases workstations
CALL cancel_reservation(1);   -- second call: must NOT release again

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- ---------------------------------------------------------------------
-- STEP 7: Explicit cursor - sessions with few workstations (5 or less)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    session_cursor CURSOR FOR
        SELECT session_name, available_workstations
        FROM lab_sessions
        WHERE available_workstations <= 5
        ORDER BY available_workstations, session_name;
    v_name  lab_sessions.session_name%TYPE;
    v_avail lab_sessions.available_workstations%TYPE;
BEGIN
    OPEN session_cursor;
    LOOP
        FETCH session_cursor INTO v_name, v_avail;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few workstations left: % (% available)', v_name, v_avail;
    END LOOP;
    CLOSE session_cursor;
END $$;

-- ---------------------------------------------------------------------
-- STEP 8: Request zero workstations - handled with an EXCEPTION block
-- ---------------------------------------------------------------------
DO $$
BEGIN
    CALL reserve_workstations(1, 'Dr. Zulu', 0);
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------
-- STEP 9: Final availability and reservation statuses
-- ---------------------------------------------------------------------
SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;
