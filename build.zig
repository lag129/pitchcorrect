const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("pitchcorrect", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    linkMiniaudio(b, mod, target);

    const exe = b.addExecutable(.{
        .name = "pitchcorrect",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pitchcorrect", .module = mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}

fn linkMiniaudio(b: *std.Build, mod: *std.Build.Module, target: std.Build.ResolvedTarget) void {
    const dep = b.dependency("miniaudio", .{});
    mod.link_libc = true;
    mod.addIncludePath(dep.path("."));
    mod.addCSourceFile(.{
        .file = dep.path("miniaudio.c"),
        .flags = &.{"-std=c99"},
    });

    switch (target.result.os.tag) {
        .macos => {
            mod.linkFramework("CoreFoundation", .{});
            mod.linkFramework("CoreAudio", .{});
            mod.linkFramework("AudioToolbox", .{});
        },
        .linux => {
            mod.linkSystemLibrary("pthread", .{});
            mod.linkSystemLibrary("m", .{});
            mod.linkSystemLibrary("dl", .{});
        },
        else => {},
    }
}
