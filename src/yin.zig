const std = @import("std");

pub const Pitch = struct {
    period: f32,
    freq: f32,
    confidence: f32,
};

pub const Config = struct {
    sample_rate: u32 = 44100,
    min_freq: f32 = 70.0,
    max_freq: f32 = 1000.0,
    threshold: f32 = 0.15,
    min_rms: f32 = 0.003,
};

pub const Detector = struct {
    cfg: Config,
    tau_min: usize,
    tau_max: usize,
    cmnd: []f32,

    pub fn init(allocator: std.mem.Allocator, cfg: Config) !Detector {
        const sr: f32 = @floatFromInt(cfg.sample_rate);
        const tau_max: usize = @intFromFloat(@ceil(sr / cfg.min_freq));
        const tau_min = @max(2, @as(usize, @intFromFloat(@floor(sr / cfg.max_freq))));

        return .{
            .cfg = cfg,
            .tau_min = tau_min,
            .tau_max = tau_max,
            .cmnd = try allocator.alloc(f32, tau_max + 1),
        };
    }

    pub fn deinit(self: Detector, allocator: std.mem.Allocator) void {
        allocator.free(self.cmnd);
    }

    pub fn minWindow(self: Detector) usize {
        return self.tau_max * 2;
    }

    pub fn detect(self: *Detector, window: []const f32) ?Pitch {
        std.debug.assert(window.len >= self.minWindow());

        if (rms(window) < self.cfg.min_rms) return null;

        const w = window.len - self.tau_max;

        self.cmnd[0] = 1.0;
        var running_sum: f32 = 0.0;
        var tau: usize = 1;
        while (tau <= self.tau_max) : (tau += 1) {
            var sum: f32 = 0.0;
            for (window[0..w], window[tau..][0..w]) |a, b| {
                const delta = a - b;
                sum += delta * delta;
            }
            running_sum += sum;
            self.cmnd[tau] = if (running_sum > 0.0)
                sum * @as(f32, @floatFromInt(tau)) / running_sum
            else
                1.0;
        }

        const found = self.firstDipBelowThreshold() orelse return null;

        const refined = self.parabolicRefine(found);

        const sr: f32 = @floatFromInt(self.cfg.sample_rate);
        return .{
            .period = refined,
            .freq = sr / refined,
            .confidence = std.math.clamp(1.0 - self.cmnd[found], 0.0, 1.0),
        };
    }

    fn firstDipBelowThreshold(self: Detector) ?usize {
        var tau = self.tau_min;
        while (tau <= self.tau_max) : (tau += 1) {
            if (self.cmnd[tau] >= self.cfg.threshold) continue;

            while (tau + 1 <= self.tau_max and self.cmnd[tau + 1] < self.cmnd[tau]) {
                tau += 1;
            }
            return tau;
        }
        return null;
    }

    fn parabolicRefine(self: Detector, tau: usize) f32 {
        const t: f32 = @floatFromInt(tau);
        if (tau <= self.tau_min or tau + 1 > self.tau_max) return t;

        const s0 = self.cmnd[tau - 1];
        const s1 = self.cmnd[tau];
        const s2 = self.cmnd[tau + 1];

        const denom = 2.0 * (2.0 * s1 - s2 - s0);
        if (@abs(denom) < 1e-12) return t;

        const shift = (s2 - s0) / denom;
        if (@abs(shift) > 1.0) return t;
        return t + shift;
    }
};

fn rms(x: []const f32) f32 {
    var sum: f32 = 0.0;
    for (x) |v| sum += v * v;
    return @sqrt(sum / @as(f32, @floatFromInt(x.len)));
}
