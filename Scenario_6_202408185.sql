DROP TABLE IF EXISTS bookings;
DROP TABLE IF EXISTS events;
DROP PROCEDURE IF EXISTS book_seats(INT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS cancel_booking(INT);

-- ---------------------------------------------------------------------
-- STEP 1: Create tables and add at least three events
-- ---------------------------------------------------------------------
CREATE TABLE events (
    event_id        SERIAL PRIMARY KEY,
    event_name      VARCHAR(80) NOT NULL,
    available_seats INT NOT NULL CHECK (available_seats >= 0)
);

CREATE TABLE bookings (
    booking_id     SERIAL PRIMARY KEY,
    event_id       INT NOT NULL REFERENCES events(event_id),
    student_number VARCHAR(20) NOT NULL,
    seats          INT NOT NULL CHECK (seats > 0),
    status         VARCHAR(20) NOT NULL DEFAULT 'BOOKED'
);

INSERT INTO events (event_name, available_seats) VALUES
    ('Graduation Gala', 100),
    ('Career Fair', 8),
    ('Sports Day Finals', 0);

SELECT * FROM events ORDER BY event_id;

-- ---------------------------------------------------------------------
-- STEP 2: IF / ELSIF / ELSE - full, nearly full or plenty of seats
-- ---------------------------------------------------------------------
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT event_name, available_seats FROM events ORDER BY event_id LOOP
        IF rec.available_seats = 0 THEN
            RAISE NOTICE '% : FULL (% seats)', rec.event_name, rec.available_seats;
        ELSIF rec.available_seats <= 10 THEN
            RAISE NOTICE '% : NEARLY FULL (% seats)', rec.event_name, rec.available_seats;
        ELSE
            RAISE NOTICE '% : PLENTY OF SEATS (% seats)', rec.event_name, rec.available_seats;
        END IF;
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- STEP 3: WHILE (booking reminder days) and numeric FOR (entrance checks)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    counter INT := 1;
BEGIN
    WHILE counter <= 3 LOOP
        RAISE NOTICE 'Booking reminder day %', counter;
        counter := counter + 1;
    END LOOP;

    FOR chk IN 1..3 LOOP
        RAISE NOTICE 'Entrance check %', chk;
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- STEP 4: book_seats procedure
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE book_seats(
    p_event_id       INT,
    p_student_number VARCHAR,
    p_seats          INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_seats IS NULL OR p_seats <= 0 THEN
        RAISE EXCEPTION 'Invalid number of seats: % (must be greater than zero)', p_seats;
    END IF;

    SELECT available_seats INTO v_available
    FROM events
    WHERE event_id = p_event_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Event % does not exist', p_event_id;
    END IF;

    IF v_available >= p_seats THEN
        UPDATE events
        SET available_seats = available_seats - p_seats
        WHERE event_id = p_event_id;

        INSERT INTO bookings (event_id, student_number, seats, status)
        VALUES (p_event_id, p_student_number, p_seats, 'BOOKED');

        RAISE NOTICE 'Booking recorded: student % booked % seat(s) for event %',
                     p_student_number, p_seats, p_event_id;
    ELSE
        RAISE NOTICE 'Booking REJECTED: student % requested % seats but only % remain',
                     p_student_number, p_seats, v_available;
    END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- STEP 5: Two valid bookings and one exceeding the remaining seats
-- ---------------------------------------------------------------------
CALL book_seats(1, 'S3001', 4);    -- valid (100 -> 96)
CALL book_seats(2, 'S3002', 3);    -- valid (8 -> 5)
CALL book_seats(2, 'S3003', 10);   -- exceeds remaining seats (only 5 left)

SELECT * FROM events ORDER BY event_id;
SELECT * FROM bookings ORDER BY booking_id;

-- ---------------------------------------------------------------------
-- STEP 6: cancel_booking procedure (second call must not release again)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE cancel_booking(p_booking_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_event_id INT;
    v_seats    INT;
    v_status   VARCHAR(20);
BEGIN
    SELECT event_id, seats, status
    INTO v_event_id, v_seats, v_status
    FROM bookings
    WHERE booking_id = p_booking_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Booking % does not exist', p_booking_id;
    ELSIF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Booking % is already cancelled - seats NOT released again', p_booking_id;
    ELSE
        UPDATE bookings SET status = 'CANCELLED' WHERE booking_id = p_booking_id;
        UPDATE events
        SET available_seats = available_seats + v_seats
        WHERE event_id = v_event_id;
        RAISE NOTICE 'Booking % cancelled - % seat(s) released', p_booking_id, v_seats;
    END IF;
END;
$$;

CALL cancel_booking(1);   -- first call: releases seats
CALL cancel_booking(1);   -- second call: must NOT release seats again

SELECT * FROM events ORDER BY event_id;
SELECT * FROM bookings ORDER BY booking_id;

-- ---------------------------------------------------------------------
-- STEP 7: Explicit cursor - full or nearly full events (10 seats or less)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    event_cursor CURSOR FOR
        SELECT event_name, available_seats
        FROM events
        WHERE available_seats <= 10
        ORDER BY available_seats, event_name;
    v_name  events.event_name%TYPE;
    v_seats events.available_seats%TYPE;
BEGIN
    OPEN event_cursor;
    LOOP
        FETCH event_cursor INTO v_name, v_seats;
        EXIT WHEN NOT FOUND;
        IF v_seats = 0 THEN
            RAISE NOTICE '% is FULL', v_name;
        ELSE
            RAISE NOTICE '% is NEARLY FULL (% seats left)', v_name, v_seats;
        END IF;
    END LOOP;
    CLOSE event_cursor;
END $$;

-- ---------------------------------------------------------------------
-- STEP 8: Book zero seats - handled with an EXCEPTION block
-- ---------------------------------------------------------------------
DO $$
BEGIN
    CALL book_seats(1, 'S3004', 0);
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------
-- STEP 9: Final seat availability and booking statuses
-- ---------------------------------------------------------------------
SELECT * FROM events ORDER BY event_id;
SELECT * FROM bookings ORDER BY booking_id;