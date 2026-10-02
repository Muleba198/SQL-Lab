DROP TABLE IF EXISTS allocations;
DROP TABLE IF EXISTS hostel_rooms;
DROP PROCEDURE IF EXISTS allocate_room(INT, VARCHAR);
DROP PROCEDURE IF EXISTS check_out(INT);

-- ---------------------------------------------------------------------
-- STEP 1: Create tables and add at least three rooms
-- ---------------------------------------------------------------------
CREATE TABLE hostel_rooms (
    room_id          SERIAL PRIMARY KEY,
    room_name        VARCHAR(20) NOT NULL,
    available_spaces INT NOT NULL CHECK (available_spaces >= 0)
);

CREATE TABLE allocations (
    allocation_id  SERIAL PRIMARY KEY,
    student_number VARCHAR(20) NOT NULL,
    room_id        INT NOT NULL REFERENCES hostel_rooms(room_id),
    status         VARCHAR(20) NOT NULL DEFAULT 'ALLOCATED'
);

INSERT INTO hostel_rooms (room_name, available_spaces) VALUES
    ('Room A101', 4),
    ('Room A102', 1),
    ('Room B201', 0);

SELECT * FROM hostel_rooms ORDER BY room_id;

-- ---------------------------------------------------------------------
-- STEP 2: IF / ELSIF / ELSE - full, one space left or several spaces
-- ---------------------------------------------------------------------
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT room_name, available_spaces FROM hostel_rooms ORDER BY room_id LOOP
        IF rec.available_spaces = 0 THEN
            RAISE NOTICE '% : FULL (% spaces)', rec.room_name, rec.available_spaces;
        ELSIF rec.available_spaces = 1 THEN
            RAISE NOTICE '% : ONE SPACE LEFT', rec.room_name;
        ELSE
            RAISE NOTICE '% : SEVERAL SPACES (% spaces)', rec.room_name, rec.available_spaces;
        END IF;
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- STEP 3: WHILE (inspection days) and numeric FOR (room checks)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    counter INT := 1;
BEGIN
    WHILE counter <= 3 LOOP
        RAISE NOTICE 'Hostel inspection day %', counter;
        counter := counter + 1;
    END LOOP;

    FOR chk IN 1..3 LOOP
        RAISE NOTICE 'Room check %', chk;
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- STEP 4: allocate_room procedure
-- Checks for a space, reduces availability by one, records allocation.
-- A blank student number raises an exception (handled in Step 8).
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE allocate_room(
    p_room_id        INT,
    p_student_number VARCHAR
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_student_number IS NULL OR TRIM(p_student_number) = '' THEN
        RAISE EXCEPTION 'Invalid input: student number cannot be blank';
    END IF;

    SELECT available_spaces INTO v_available
    FROM hostel_rooms
    WHERE room_id = p_room_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Room % does not exist', p_room_id;
    END IF;

    IF v_available >= 1 THEN
        UPDATE hostel_rooms
        SET available_spaces = available_spaces - 1
        WHERE room_id = p_room_id;

        INSERT INTO allocations (student_number, room_id, status)
        VALUES (TRIM(p_student_number), p_room_id, 'ALLOCATED');

        RAISE NOTICE 'Allocation recorded: student % allocated to room %',
                     TRIM(p_student_number), p_room_id;
    ELSE
        RAISE NOTICE 'Allocation REJECTED: room % is full (student %)',
                     p_room_id, p_student_number;
    END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- STEP 5: Two valid allocations and one allocation to a full room
-- ---------------------------------------------------------------------
CALL allocate_room(1, 'S2001');   -- valid (4 -> 3)
CALL allocate_room(2, 'S2002');   -- valid (1 -> 0)
CALL allocate_room(3, 'S2003');   -- room B201 is full

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- ---------------------------------------------------------------------
-- STEP 6: check_out procedure (second call must not free another space)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE check_out(p_allocation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_room_id INT;
    v_status  VARCHAR(20);
BEGIN
    SELECT room_id, status
    INTO v_room_id, v_status
    FROM allocations
    WHERE allocation_id = p_allocation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Allocation % does not exist', p_allocation_id;
    ELSIF v_status = 'COMPLETE' THEN
        RAISE NOTICE 'Allocation % already checked out - space NOT freed again', p_allocation_id;
    ELSE
        UPDATE allocations SET status = 'COMPLETE' WHERE allocation_id = p_allocation_id;
        UPDATE hostel_rooms
        SET available_spaces = available_spaces + 1
        WHERE room_id = v_room_id;
        RAISE NOTICE 'Allocation % checked out - 1 bed space released', p_allocation_id;
    END IF;
END;
$$;

CALL check_out(2);   -- first call: frees one space
CALL check_out(2);   -- second call: must NOT free another space

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- ---------------------------------------------------------------------
-- STEP 7: Explicit cursor - full or nearly full rooms (1 space or less)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    room_cursor CURSOR FOR
        SELECT room_name, available_spaces
        FROM hostel_rooms
        WHERE available_spaces <= 1
        ORDER BY available_spaces, room_name;
    v_name   hostel_rooms.room_name%TYPE;
    v_spaces hostel_rooms.available_spaces%TYPE;
BEGIN
    OPEN room_cursor;
    LOOP
        FETCH room_cursor INTO v_name, v_spaces;
        EXIT WHEN NOT FOUND;
        IF v_spaces = 0 THEN
            RAISE NOTICE '% is FULL', v_name;
        ELSE
            RAISE NOTICE '% is NEARLY FULL (% space left)', v_name, v_spaces;
        END IF;
    END LOOP;
    CLOSE room_cursor;
END $$;

-- ---------------------------------------------------------------------
-- STEP 8: Blank student number - handled with an EXCEPTION block
-- ---------------------------------------------------------------------
DO $$
BEGIN
    CALL allocate_room(1, '   ');
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------
-- STEP 9: Final available spaces and allocation statuses
-- ---------------------------------------------------------------------
SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;
