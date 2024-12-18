const std = @import("std");

pub const PolicyNetwork = enum {
    Unittest,
    Testnet,
    Devnet,
    Mainnet,
};

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Nimiq networks can have different constants altering core logic of the pool
    // we expose the 'policy' option to allow overwriting policy constants for the
    // correct ntwork.
    const policy_option = b.option(PolicyNetwork, "policy", "policy constants used for core logic");
    const selected_policy = policy_option orelse PolicyNetwork.Unittest;
    const network_policy_path = switch (selected_policy) {
        PolicyNetwork.Testnet => b.path("src/nimiq/policy/testnet.zig"),
        PolicyNetwork.Unittest => b.path("src/nimiq/policy/unittest.zig"),
        PolicyNetwork.Devnet => b.path("src/nimiq/policy/devnet.zig"),
        PolicyNetwork.Mainnet => b.path("src/nimiq/policy/mainnet.zig"),
    };

    // modules
    const mod_policy = b.addModule("policy", .{ .root_source_file = network_policy_path, .target = target, .optimize = optimize });
    const mod_base32 = b.dependency("base32", .{ .target = target, .optimize = optimize }).module("base32");
    const mod_toml = b.dependency("zig-toml", .{ .target = target, .optimize = optimize }).module("zig-toml");
    const mod_zbackoff = b.dependency("zbackoff", .{ .target = target, .optimize = optimize }).module("zbackoff");

    const exe = b.addExecutable(.{
        .name = "zpool",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("policy", mod_policy);
    exe.root_module.addImport("base32", mod_base32);
    exe.root_module.addImport("zig-toml", mod_toml);
    exe.root_module.addImport("zbackoff", mod_zbackoff);
    exe.linkSystemLibrary("sqlite3");
    exe.linkLibC();

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_unit_tests.root_module.addImport("policy", mod_policy);
    exe_unit_tests.root_module.addImport("base32", mod_base32);
    exe_unit_tests.root_module.addImport("zig-toml", mod_toml);
    exe_unit_tests.root_module.addImport("zbackoff", mod_zbackoff);
    exe_unit_tests.linkSystemLibrary("sqlite3");
    exe_unit_tests.linkLibC();

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
