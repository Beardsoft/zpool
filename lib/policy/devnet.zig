// This is a specific devnet policy that uses 4 batches per epoch
// instead of 720. In order to use this the albatross node needs to
// be patched as well, to make use of this.
// Using a smaller epoch allows to test a full epoch cycle within 4 minutes.
pub const genesis_number = 0;
pub const batch_size = 60;
pub const epoch_size = 240;
pub const batches_per_epoch = 4;
