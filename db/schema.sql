CREATE TABLE IF NOT EXISTS cursors(
    id INTEGER NOT NULL PRIMARY KEY,
    block_number UNSIGNED BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS epochs(
    number UNSIGNED BIGINT NOT NULL PRIMARY KEY,
    num_stakers INTEGER NOT NULL,
    balance UNSIGNED BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS stakers(
    address VARCHAR(44) NOT NULL,
    epoch_number UNSIGNED BIGINT NOT NULL,
    stake_balance UNSIGNED BIGINT NOT NULL,
    stake_percentage REAL NOT NULL,

    PRIMARY KEY (address, epoch_number),
    FOREIGN KEY(epoch_number) REFERENCES epochs(number)
);

CREATE TABLE IF NOT EXISTS rewards(
    epoch_number UNSIGNED BIGINT NOT NULL,
    collection_number UNSIGNED BIGINT NOT NULL,
    reward UNSIGNED BIGINT NOT NULL,

    PRIMARY KEY(epoch_number, collection_number),
    FOREIGN KEY(epoch_number) REFERENCES epochs(number)
);

CREATE TABLE IF NOT EXISTS transactions(
    hash VARCHAR(255) NOT NULL PRIMARY KEY,
    address VARCHAR(44) NOT NULL,
    amount UNSIGNED BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS payslips(
    collection_number UNSIGNED BIGINT NOT NULL,
    address VARCHAR(44) NOT NULL,
    amount UNSIGNED BIGINT NOT NULL,
    fee UNSIGNED BIGINT NOT NULL,
    tx_hash VARCHAR(255),

    PRIMARY KEY(collection_number, address),
    FOREIGN KEY(collection_number) REFERENCES rewards(collection_number),
    FOREIGN KEY(tx_hash) REFERENCES transactions(hash)
);

