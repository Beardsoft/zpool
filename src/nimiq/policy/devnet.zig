// This is a specific devnet policy that uses 8 batches per epoch
// instead of 720. In order to use this the albatross node needs to
// be patched as well, to make use of this.
// Using a smaller epoch allows to test a full epoch cycle within 8 minutes.
pub const genesis_number = 0;
pub const batch_size = 60;
pub const epoch_size = 480;
pub const batches_per_epoch = 8;
pub const collection_batches = 4;
pub const collection_size = 240;
pub const collections_per_epoch = 2;
pub const network_id = 6;
