const std = @import("std");

const psola = @import("psola.zig");
const scale = @import("scale.zig");
const yin = @import("yin.zig");

pub const max_speed_ms: f32 = 400.0;

const onset_ms: f32 = 60.0;
const attack_ms: f32 = 80.0;

const Retune = struct {
    tuning: scale.Tuning,
    alpha_slow: f32,
    onset_frames: usize,
    attack_frames: usize,
    center_st: f32 = 0.0,
    off_count: usize = 0,
    attack_left: usize,

    fn init(tuning: scale.Tuning, speed_ms: f32, hop: usize, sample_rate: u32) Retune {
        const ms = std.math.clamp(speed_ms, 0.0, max_speed_ms);
        const hop_ms = 1000.0 * @as(f32, @floatFromInt(hop)) / @as(f32, @floatFromInt(sample_rate));
        const attack = @max(1, @as(usize, @intFromFloat(@round(attack_ms / hop_ms))));

        return .{
            .tuning = .{
                .scale = tuning.scale,
                .reference_hz = tuning.reference_hz,
                .amount = std.math.clamp(tuning.amount, 0.0, 1.0),
            },
            .alpha_slow = if (ms <= 0.0) 1.0 else 1.0 - @exp(-hop_ms / ms),
            .onset_frames = @max(1, @as(usize, @intFromFloat(@round(onset_ms / hop_ms)))),
            .attack_frames = attack,
            .attack_left = attack,
        };
    }

    fn noteStart(self: *Retune) void {
        self.off_count = 0;
        self.attack_left = self.attack_frames;
    }

    fn ratio(self: *Retune, freq: f32) f32 {
        if (freq <= 0.0) return 1.0;

        const current = scale.freqToSemitones(freq, self.tuning.reference_hz);
        if (self.noteOf(current) != self.noteOf(self.center_st)) {
            self.off_count += 1;
            if (self.off_count >= self.onset_frames) self.noteStart();
        } else {
            self.off_count = 0;
        }

        var alpha = self.alpha_slow;
        if (self.attack_left > 0) {
            self.attack_left -= 1;
            alpha = 1.0;
        }
        self.center_st += (current - self.center_st) * alpha;

        return self.correction();
    }

    fn noteOf(self: *const Retune, semitones: f32) i32 {
        return @intFromFloat(@round(scale.snapSemitones(semitones, self.tuning.scale)));
    }

    fn correction(self: *const Retune) f32 {
        const target = scale.snapSemitones(self.center_st, self.tuning.scale);

        return scale.semitonesToRatio((target - self.center_st) * self.tuning.amount);
    }
};

pub const Options = struct {
    tuning: scale.Tuning = .{},
    hop: usize = 512,
    window: usize = 2048,
    max_ratio: f32 = 2.0,
    speed_ms: f32 = 0.0,
};

pub const Stats = struct {
    frames: usize = 0,
    voiced: usize = 0,
};

pub fn tune(
    allocator: std.mem.Allocator,
    input: []const f32,
    sample_rate: u32,
    opts: Options,
    stats: ?*Stats,
) ![]f32 {
    var det = try yin.Detector.init(allocator, .{ .sample_rate = sample_rate });
    defer det.deinit(allocator);
    std.debug.assert(opts.window >= det.minWindow());

    const n_frames = if (input.len < opts.window) 0 else (input.len - opts.window) / opts.hop + 1;
    const frames = try allocator.alloc(psola.Frame, n_frames);
    defer allocator.free(frames);

    var retune = Retune.init(opts.tuning, opts.speed_ms, opts.hop, sample_rate);
    var last_period: f32 = @as(f32, @floatFromInt(sample_rate)) / 200.0;
    var voiced: usize = 0;

    for (frames, 0..) |*f, i| {
        const p = det.detect(input[i * opts.hop ..][0..opts.window]) orelse {
            retune.noteStart();
            f.* = .{ .period = last_period, .ratio = 1.0 };
            continue;
        };
        voiced += 1;
        last_period = p.period;

        const ratio = std.math.clamp(
            retune.ratio(p.freq),
            1.0 / opts.max_ratio,
            opts.max_ratio,
        );
        f.* = .{ .period = p.period, .ratio = ratio };
    }

    if (stats) |s| s.* = .{ .frames = n_frames, .voiced = voiced };

    return psola.shift(allocator, input, opts.hop, frames);
}
