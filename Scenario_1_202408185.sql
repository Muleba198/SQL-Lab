DROP TABLE IF EXISTS book_loans;
DROP TABLE IF EXISTS books;
DROP PROCEDURE IF EXISTS borrow_book(INT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS return_book(INT);

-- ---------------------------------------------------------------------
-- STEP 1: Create tables and add at least three books
-- ---------------------------------------------------------------------
CREATE TABLE books (
    book_id          SERIAL PRIMARY KEY,
    title            VARCHAR(100) NOT NULL,
    available_copies INT NOT NULL CHECK (available_copies >= 0)
);

CREATE TABLE book_loans (
    loan_id        SERIAL PRIMARY KEY,
    book_id        INT NOT NULL REFERENCES books(book_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL CHECK (quantity > 0),
    loan_status    VARCHAR(20) NOT NULL DEFAULT 'BORROWED'
);

INSERT INTO books (title, available_copies) VALUES
    ('Database Systems', 10),
    ('Computer Networks', 2),
    ('Operating Systems', 0);

SELECT * FROM books ORDER BY book_id;

-- ---------------------------------------------------------------------
-- STEP 2: IF / ELSIF / ELSE - unavailable, low or sufficiently stocked
-- ---------------------------------------------------------------------
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT title, available_copies FROM books ORDER BY book_id LOOP
        IF rec.available_copies = 0 THEN
            RAISE NOTICE '% : UNAVAILABLE (% copies)', rec.title, rec.available_copies;
        ELSIF rec.available_copies <= 3 THEN
            RAISE NOTICE '% : LOW ON COPIES (% copies)', rec.title, rec.available_copies;
        ELSE
            RAISE NOTICE '% : SUFFICIENTLY STOCKED (% copies)', rec.title, rec.available_copies;
        END IF;
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- STEP 3: WHILE loop (overdue reminders) and numeric FOR loop (shelves)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    counter INT := 1;
BEGIN
    WHILE counter <= 3 LOOP
        RAISE NOTICE 'Overdue reminder number %', counter;
        counter := counter + 1;
    END LOOP;

    FOR shelf IN 1..3 LOOP
        RAISE NOTICE 'Library shelf number %', shelf;
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- STEP 4: borrow_book procedure
-- Checks copies, reduces stock and records a loan.
-- Invalid quantity raises an exception (handled in Step 8).
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE borrow_book(
    p_book_id        INT,
    p_student_number VARCHAR,
    p_quantity       INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be greater than zero)', p_quantity;
    END IF;

    SELECT available_copies INTO v_available
    FROM books
    WHERE book_id = p_book_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Book % does not exist', p_book_id;
    END IF;

    IF v_available >= p_quantity THEN
        UPDATE books
        SET available_copies = available_copies - p_quantity
        WHERE book_id = p_book_id;

        INSERT INTO book_loans (book_id, student_number, quantity, loan_status)
        VALUES (p_book_id, p_student_number, p_quantity, 'BORROWED');

        RAISE NOTICE 'Loan recorded: student % borrowed % copy(ies) of book %',
                     p_student_number, p_quantity, p_book_id;
    ELSE
        RAISE NOTICE 'Loan REJECTED: student % requested % copies but only % available',
                     p_student_number, p_quantity, v_available;
    END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- STEP 5: Two valid loans and one request exceeding available copies
-- ---------------------------------------------------------------------
CALL borrow_book(1, 'S1001', 2);   -- valid (10 -> 8)
CALL borrow_book(2, 'S1002', 1);   -- valid (2 -> 1)
CALL borrow_book(2, 'S1003', 5);   -- exceeds available copies (only 1 left)

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- ---------------------------------------------------------------------
-- STEP 6: return_book procedure (second call must not restore again)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE return_book(p_loan_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_book_id  INT;
    v_quantity INT;
    v_status   VARCHAR(20);
BEGIN
    SELECT book_id, quantity, loan_status
    INTO v_book_id, v_quantity, v_status
    FROM book_loans
    WHERE loan_id = p_loan_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Loan % does not exist', p_loan_id;
    ELSIF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Loan % was already returned - copies NOT restored again', p_loan_id;
    ELSE
        UPDATE book_loans SET loan_status = 'RETURNED' WHERE loan_id = p_loan_id;
        UPDATE books
        SET available_copies = available_copies + v_quantity
        WHERE book_id = v_book_id;
        RAISE NOTICE 'Loan % returned - % copy(ies) restored', p_loan_id, v_quantity;
    END IF;
END;
$$;

CALL return_book(1);   -- first call: restores copies
CALL return_book(1);   -- second call: must NOT restore copies again

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- ---------------------------------------------------------------------
-- STEP 7: Explicit cursor - books with few copies remaining (3 or less)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    book_cursor CURSOR FOR
        SELECT title, available_copies
        FROM books
        WHERE available_copies <= 3
        ORDER BY available_copies, title;
    v_title  books.title%TYPE;
    v_copies books.available_copies%TYPE;
BEGIN
    OPEN book_cursor;
    LOOP
        FETCH book_cursor INTO v_title, v_copies;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few copies left: % (% copies)', v_title, v_copies;
    END LOOP;
    CLOSE book_cursor;
END $$;

-- ---------------------------------------------------------------------
-- STEP 8: Borrow zero copies - handled with an EXCEPTION block
-- ---------------------------------------------------------------------
DO $$
BEGIN
    CALL borrow_book(1, 'S1004', 0);
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------
-- STEP 9: Final quantities and loan statuses
-- ---------------------------------------------------------------------
SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;