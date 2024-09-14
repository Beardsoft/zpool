CREATE TABLE IF NOT EXISTS cursors(
    id INTEGER NOT NULL PRIMARY KEY,
    block_number INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS statuses(
    id INTEGER NOT NULL PRIMARY KEY,
    status TEXT NOT NULL
);

INSERT INTO statuses(id, status) VALUES 
    (0, "NOT_ELECTED"),
    (1, "NO_STAKERS"),
    (2, "RETIRED"),
    (3, "INACTIVE"),
    (4, "ERROR"),
    (5, "IN_PROGRESS"),
    (6, "COMPLETED"),
    (7, "PENDING"),
    (8, "OUT_FOR_PAYMENT"),
    (9, "AWAITING_CONFIRMATION");

CREATE TABLE IF NOT EXISTS epochs(
    number INTEGER NOT NULL PRIMARY KEY,
    num_stakers INTEGER NOT NULL,
    balance INTEGER NOT NULL,
    status_id INTEGER NOT NULL,

    FOREIGN KEY(status_id) REFERENCES statuses(id)
);

CREATE TABLE IF NOT EXISTS stakers(
    address TEXT NOT NULL,
    epoch_number INTEGER NOT NULL,
    stake_balance INTEGER NOT NULL,
    stake_percentage REAL NOT NULL,

    PRIMARY KEY (address, epoch_number),
    FOREIGN KEY(epoch_number) REFERENCES epochs(number)
);

CREATE TABLE IF NOT EXISTS rewards(
    epoch_number INTEGER NOT NULL,
    collection_number INTEGER NOT NULL,
    reward INTEGER NOT NULL,
    pool_fee INTEGER NOT NULL,

    PRIMARY KEY(epoch_number, collection_number),
    FOREIGN KEY(epoch_number) REFERENCES epochs(number)
);

CREATE TABLE IF NOT EXISTS transactions(
    hash TEXT NOT NULL PRIMARY KEY,
    address TEXT NOT NULL,
    amount INTEGER NOT NULL,
    status_id INTEGER NOT NULL,

    FOREIGN KEY(status_id) REFERENCES statuses(id)
);

CREATE TABLE IF NOT EXISTS payslips(
    collection_number INTEGER NOT NULL,
    address TEXT NOT NULL,
    amount INTEGER NOT NULL,
    status_id NOT NULL,
    tx_hash TEXT,

    PRIMARY KEY(collection_number, address),
    FOREIGN KEY(collection_number) REFERENCES rewards(collection_number),
    FOREIGN KEY(status_id) REFERENCES statuses(id),
    FOREIGN KEY(tx_hash) REFERENCES transactions(hash)
);

