const std = @import("std");
const c = @import("c.zig").c;

pub const sample_rate: u32 = 44100;

pub const Error = error{
    OpenFailed,
    DecodeFailed,
    EncodeFailed,
    WriteFailed,
};

pub const Audio = struct {
    samples: []f32,
    sample_rate: u32,

    pub fn deinit(self: Audio, gpa: std.mem.Allocator) void {
        gpa.free(self.samples);
    }

    pub fn duration(self: Audio) f32 {
        return @as(f32, @floatFromInt(self.samples.len)) /
            @as(f32, @floatFromInt(self.sample_rate));
    }
};

pub fn load(gpa: std.mem.Allocator, path: [:0]const u8) !Audio {
    var config = c.ma_decoder_config_init(c.ma_format_f32, 1, sample_rate);
    config.channelMixMode = c.ma_channel_mix_mode_simple;

    var decoder: c.ma_decoder = undefined;
    if (c.ma_decoder_init_file(path.ptr, &config, &decoder) != c.MA_SUCCESS) {
        return Error.OpenFailed;
    }
    defer _ = c.ma_decoder_uninit(&decoder);

    var total_frames: c.ma_uint64 = 0;
    if (c.ma_decoder_get_length_in_pcm_frames(&decoder, &total_frames) != c.MA_SUCCESS) {
        return Error.DecodeFailed;
    }
    if (total_frames == 0) return Error.DecodeFailed;

    const samples = try gpa.alloc(f32, @intCast(total_frames));
    errdefer gpa.free(samples);

    var frames_read: c.ma_uint64 = 0;
    const result = c.ma_decoder_read_pcm_frames(&decoder, samples.ptr, total_frames, &frames_read);
    if (result != c.MA_SUCCESS and result != c.MA_AT_END) {
        return Error.DecodeFailed;
    }

    return .{
        .samples = try gpa.realloc(samples, @intCast(frames_read)),
        .sample_rate = sample_rate,
    };
}

pub fn save(path: [:0]const u8, samples: []const f32, sr: u32) !void {
    const config = c.ma_encoder_config_init(c.ma_encoding_format_wav, c.ma_format_f32, 1, sr);

    var encoder: c.ma_encoder = undefined;
    if (c.ma_encoder_init_file(path.ptr, &config, &encoder) != c.MA_SUCCESS) {
        return Error.EncodeFailed;
    }
    defer c.ma_encoder_uninit(&encoder);

    var written: c.ma_uint64 = 0;
    if (c.ma_encoder_write_pcm_frames(&encoder, samples.ptr, samples.len, &written) != c.MA_SUCCESS) {
        return Error.WriteFailed;
    }
    if (written != samples.len) return Error.WriteFailed;
}
