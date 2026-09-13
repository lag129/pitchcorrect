const std = @import("std");

pub const Frame = struct {
    period: f32,
    ratio: f32,
};

const min_period: f32 = 16.0;

pub fn shift(gpa: std.mem.Allocator, input: []const f32, hop: usize, frames: []const Frame) ![]f32 {
    const n = input.len;
    const nf: f32 = @floatFromInt(n);

    const out = try gpa.alloc(f32, n);
    errdefer gpa.free(out);
    @memset(out, 0.0);

    const weight = try gpa.alloc(f32, n);
    defer gpa.free(weight);
    @memset(weight, 0.0);

    var marks: std.ArrayList(usize) = .empty;
    defer marks.deinit(gpa);

    var pos: f32 = 0.0;
    while (pos < nf) {
        const f = frameAt(frames, hop, pos);
        const center = snapToPeak(input, @intFromFloat(pos), @intFromFloat(f.period * 0.25));
        try marks.append(gpa, center);
        pos = @as(f32, @floatFromInt(center)) + f.period;
    }
    if (marks.items.len == 0) {
        @memcpy(out, input);
        return out;
    }

    var out_pos: f32 = @floatFromInt(marks.items[0]);
    var mi: usize = 0;
    while (out_pos < nf) {
        while (mi + 1 < marks.items.len and
            markDist(marks.items[mi + 1], out_pos) <= markDist(marks.items[mi], out_pos)) : (mi += 1)
        {}

        const f = frameAt(frames, hop, out_pos);
        const step: f32 = if (mi + 1 < marks.items.len)
            @floatFromInt(marks.items[mi + 1] - marks.items[mi])
        else
            f.period;

        const src_center: isize = @intCast(marks.items[mi]);
        const dst_center: isize = @intFromFloat(@round(out_pos));

        const half: isize = @intFromFloat(@max(1.0, step));
        const len: usize = @intCast(2 * half + 1);

        var k: usize = 0;
        while (k < len) : (k += 1) {
            const off = @as(isize, @intCast(k)) - half;
            const si = src_center + off;
            const di = dst_center + off;
            if (si < 0 or si >= n or di < 0 or di >= n) continue;
            const w = hann(k, len);
            out[@intCast(di)] += input[@intCast(si)] * w;
            weight[@intCast(di)] += w;
        }

        out_pos += step / f.ratio;
    }

    for (out, weight, input) |*o, w, dry| {
        if (w > 1e-4) {
            o.* /= w;
        } else {
            o.* = dry;
        }
    }
    return out;
}

fn frameAt(frames: []const Frame, hop: usize, pos: f32) Frame {
    if (frames.len == 0) return .{ .period = 256.0, .ratio = 1.0 };
    const idx = @min(frames.len - 1, @as(usize, @intFromFloat(@max(0.0, pos))) / hop);
    const f = frames[idx];
    return .{ .period = @max(min_period, f.period), .ratio = f.ratio };
}

fn markDist(mark: usize, pos: f32) f32 {
    return @abs(@as(f32, @floatFromInt(mark)) - pos);
}

fn snapToPeak(x: []const f32, center: usize, radius: usize) usize {
    if (x.len == 0) return 0;
    const lo = center -| radius;
    const hi = @min(x.len, center + radius + 1);
    if (lo >= hi) return @min(center, x.len - 1);

    var best = lo;
    var best_v = @abs(x[lo]);
    for (x[lo..hi], lo..) |v, i| {
        if (@abs(v) > best_v) {
            best_v = @abs(v);
            best = i;
        }
    }
    return best;
}

fn hann(k: usize, len: usize) f32 {
    if (len <= 1) return 1.0;
    const a: f32 = @floatFromInt(k);
    const b: f32 = @floatFromInt(len - 1);
    return 0.5 - 0.5 * @cos(2.0 * std.math.pi * a / b);
}
