const std = @import("std");

pub const Scale = struct {
    root: u8,
    degrees: []const u8,
};

pub const major = [_]u8{ 0, 2, 4, 5, 7, 9, 11 };
pub const minor = [_]u8{ 0, 2, 3, 5, 7, 8, 10 };
pub const all = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 };

pub const chromatic = Scale{ .root = 0, .degrees = &all };

pub fn parseNote(name: []const u8) ?u8 {
    if (name.len == 0 or name.len > 2) return null;

    const letter: u8 = switch (std.ascii.toUpper(name[0])) {
        'C' => 0,
        'D' => 2,
        'E' => 4,
        'F' => 5,
        'G' => 7,
        'A' => 9,
        'B' => 11,
        else => return null,
    };
    if (name.len == 1) return letter;

    const accidental: i8 = switch (name[1]) {
        '#' => 1,
        'b', 'B' => -1,
        else => return null,
    };
    return @intCast(@mod(@as(i8, @intCast(letter)) + accidental, 12));
}

pub fn parseScale(name: []const u8) ?[]const u8 {
    if (std.ascii.eqlIgnoreCase(name, "major") or std.ascii.eqlIgnoreCase(name, "maj")) return &major;
    if (std.ascii.eqlIgnoreCase(name, "minor") or std.ascii.eqlIgnoreCase(name, "min")) return &minor;
    if (std.ascii.eqlIgnoreCase(name, "chromatic") or std.ascii.eqlIgnoreCase(name, "chrom")) return &all;
    return null;
}

pub const Tuning = struct {
    scale: Scale = chromatic,
    reference_hz: f32 = 440.0,
    amount: f32 = 1.0,
};

pub fn freqToSemitones(freq: f32, reference_hz: f32) f32 {
    return 12.0 * std.math.log2(freq / reference_hz);
}

pub fn semitonesToRatio(semitones: f32) f32 {
    return std.math.pow(f32, 2.0, semitones / 12.0);
}

const a_pitch_class: f32 = 9.0;

pub fn snapSemitones(semitones: f32, scale: Scale) f32 {
    if (scale.degrees.len == 0) return semitones;

    const root: f32 = @floatFromInt(scale.root);
    const rel = semitones + a_pitch_class - root;
    const octave = @floor(rel / 12.0);
    const within = rel - octave * 12.0;

    var best: f32 = @floatFromInt(scale.degrees[0]);
    var best_dist = @abs(within - best);
    for (scale.degrees[1..]) |d| {
        const cand: f32 = @floatFromInt(d);
        const dist = @abs(within - cand);
        if (dist < best_dist) {
            best = cand;
            best_dist = dist;
        }
    }

    const wrapped: f32 = @as(f32, @floatFromInt(scale.degrees[0])) + 12.0;
    if (@abs(within - wrapped) < best_dist) best = wrapped;

    return best + octave * 12.0 - a_pitch_class + root;
}
