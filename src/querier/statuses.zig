pub const Status = enum(u8) {
    NotElected,
    InProgress,
    Retired,
    InActive,
    Error,
    Completed,
    Pending,
    OutForPayment,
};
