const std = @import("std");
const Io = std.Io;

const pc = @import("pitchcorrect");

const usage =
    \\usage:
    \\  pitchcorrect tune <in.wav> <out.wav> [options]
    \\
    \\options:
    \\  --key <note>      主音。C, C#, Db, ... B      (default: C)
    \\  --scale <name>    major | minor | chromatic   (default: chromatic)
    \\  --amount <0..1>   補正の強さ。1.0 で完全吸着   (default: 1.0)
    \\  --speed <ms>      伸ばしている部分の追従の緩さ。
    \\                    0 で即座、大きいほど緩やか   (default: 0)
    \\                    ボーカルの標準は 10〜50
    \\                    音の乗り換えは常に速く追従する
    \\
;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var stdout_buffer: [64 * 1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const out = &stdout_file_writer.interface;
    defer out.flush() catch {};

    run(init.gpa, init.io, args) catch |err| {
        if (err == error.BadUsage) try out.writeAll(usage);
        return err;
    };
}

fn run(allocator: std.mem.Allocator, io: std.Io, args: []const []const u8) !void {
    if (args.len < 4) return error.BadUsage;
    if (!std.mem.eql(u8, args[1], "tune")) return error.BadUsage;

    const opts = try parseOptions(args[4..]);
    try cmdTune(allocator, io, args[2], args[3], opts);
}

fn parseRanged(value: []const u8, lo: f32, hi: f32) !f32 {
    const v = std.fmt.parseFloat(f32, value) catch return error.BadUsage;
    if (v < lo or v > hi) return error.BadUsage;
    return v;
}

fn parseOptions(args: []const []const u8) !pc.engine.Options {
    var opts = pc.engine.Options{};

    var i: usize = 0;
    while (i < args.len) : (i += 2) {
        if (i + 1 >= args.len) return error.BadUsage;
        const flag = args[i];
        const value = args[i + 1];

        if (std.mem.eql(u8, flag, "--key")) {
            opts.tuning.scale.root = pc.scale.parseNote(value) orelse return error.BadUsage;
        } else if (std.mem.eql(u8, flag, "--scale")) {
            opts.tuning.scale.degrees = pc.scale.parseScale(value) orelse return error.BadUsage;
        } else if (std.mem.eql(u8, flag, "--amount")) {
            opts.tuning.amount = try parseRanged(value, 0.0, 1.0);
        } else if (std.mem.eql(u8, flag, "--speed")) {
            opts.speed_ms = try parseRanged(value, 0.0, pc.engine.max_speed_ms);
        } else {
            return error.BadUsage;
        }
    }
    return opts;
}

fn cmdTune(
    allocator: std.mem.Allocator,
    io: std.Io,
    in_path: []const u8,
    out_path: []const u8,
    opts: pc.engine.Options,
) !void {
    var pcm: pc.wave.MonoPcm = undefined;
    try pc.wave.mono_wave_read(allocator, &pcm, in_path, io);
    defer allocator.free(pcm.s);

    var stats: pc.engine.Stats = .{};
    const tuned = try pc.engine.tune(allocator, pcm.s, @intCast(pcm.fs), opts, &stats);
    defer allocator.free(tuned);

    var tuned_pcm: pc.wave.MonoPcm = .{ .fs = pcm.fs, .bits = 16, .s = tuned };
    try pc.wave.mono_wave_write(&tuned_pcm, out_path, io);
}
